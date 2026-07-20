// borgd: the borg-pi5's own process.
//
// One binary, no runtime to install: it owns mode state, the health registry and the
// status page, talks MQTT to everything else, and survives every piece of hardware
// being absent (README.md's stability principle).
//
// Diagnostics go to stderr, results to stdout, and systemd captures both. There is no
// logging framework here on purpose: `journalctl --user -u borgd` is the log.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	mqtt "github.com/eclipse/paho.mqtt.golang"
)

const defaultConfigPath = "/srv/borg/app/shared/borg.yaml"

type Borgd struct {
	cfg     *Config
	modes   *Modes
	health  *Registry
	mixer   *Mixer
	speaker *Speaker
	env     *EnvHistory
	events  *Events
	envPub  *Coalescer
	tuner   *Tuner
	lowPass *LowPass
	panel   *Panel
	client  mqtt.Client

	mu      sync.Mutex
	lastEnv time.Time // when the ESP last said anything, for the esp capability
}

func main() {
	configPath := flag.String("config", defaultConfigPath, "path to borg.yaml")
	checkOnly := flag.Bool("check", false, "validate the config and exit")
	flag.Parse()

	cfg, err := LoadConfig(*configPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%v\n", err)
		os.Exit(2)
	}
	if *checkOnly {
		fmt.Printf("%s ok: broker %s:%d\n", *configPath, cfg.Broker.Host, cfg.Broker.Port)
		return
	}

	a := &Borgd{cfg: cfg, modes: NewModes(time.Now), health: NewRegistry(time.Now)}
	a.mixer = NewMixer(time.Now)
	a.speaker = NewSpeaker(a.mixer, cfg.Audio.Piper, cfg.Audio.Voice)
	a.env = NewEnvHistory(cfg.Environment.HistoryHours,
		time.Duration(cfg.Environment.SampleIntervalS)*time.Second, time.Now)
	a.events = NewEvents(time.Now)
	// A retained snapshot at most every 10s: the history only grows once a minute, so
	// this is about not writing a retained message per ESP reading.
	a.envPub = NewCoalescer(10*time.Second, time.Now)
	a.tuner = NewTuner(time.Now)
	a.panel = NewPanel()
	a.lowPass = NewLowPass(cfg.Adsb.LowPassFt, cfg.Adsb.LowPassKM,
		time.Duration(cfg.Adsb.LowPassCooldownS)*time.Second, time.Now)
	a.registerCapabilities()

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	go a.serveHTTP(ctx)
	go a.skyLoop(ctx)

	if err := a.connect(); err != nil {
		// Not fatal by design: the status page still answers and says the broker is
		// missing, which is more useful than a dead unit and an empty journal.
		fmt.Fprintf(os.Stderr, "mqtt: %v (retrying in the background)\n", err)
	}

	a.run(ctx)
}

// registerCapabilities builds the registry from the config. A capability switched off
// in borg.yaml reports `disabled` rather than `missing`: not wanted, versus wanted but
// broken.
func (a *Borgd) registerCapabilities() {
	enabled := a.cfg.Capabilities.Enabled()
	a.health.Register("clock", ClockProbe(execRunner, time.Now), true)
	a.health.Register("sdr", SDRProbe(execRunner), enabled["sdr"])
	a.health.Register("speaker", SpeakerProbe(execRunner, a.speaker), enabled["speaker"])
	a.health.Register("mic", MicrophoneProbe(execRunner), enabled["microphone"])
	a.health.Register("camera", CameraProbe(fileExists), enabled["camera"])
	a.health.Register("esp", FreshnessProbe(a.lastEnvSeen, time.Now, 5*time.Minute,
		"no data from the ESP yet"), enabled["esp"])
	a.health.Register("broker", a.brokerProbe(), true)
	// Always ok while this process is running: its whole purpose is to overwrite the
	// retained "missing" the last will leaves behind after a crash.
	a.health.Register(CapabilityBorgd, func() (State, string) { return StateOK, "" }, true)
}

func (a *Borgd) lastEnvSeen() time.Time {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.lastEnv
}

func (a *Borgd) brokerProbe() Probe {
	return func() (State, string) {
		if a.client != nil && a.client.IsConnected() {
			return StateOK, ""
		}
		return StateMissing, "not connected to the broker"
	}
}

// --- MQTT -----------------------------------------------------------------------

func (a *Borgd) connect() error {
	opts := mqtt.NewClientOptions().
		AddBroker(fmt.Sprintf("tcp://%s:%d", a.cfg.Broker.Host, a.cfg.Broker.Port)).
		SetClientID("borgd").
		SetUsername("borgd").
		SetPassword(a.cfg.Broker.Password).
		SetCleanSession(true).
		SetAutoReconnect(true).
		SetConnectRetry(true).
		SetConnectRetryInterval(10 * time.Second).
		SetMaxReconnectInterval(60 * time.Second)

	// The LWT lands on borgd's own capability topic, per the contract: that is
	// what lets a client tell "borgd down" from "all quiet". The aggregate stays
	// whatever it last was, which is honest, since nobody is updating it any more.
	lwt, _ := json.Marshal(CapabilityPayload(string(StateMissing), "borgd offline",
		Timestamp(time.Now())))
	opts.SetWill(HealthTopic(CapabilityBorgd), string(lwt), QoSState, true)

	opts.OnConnect = func(c mqtt.Client) {
		fmt.Fprintln(os.Stderr, "mqtt: connected")
		for _, topic := range Subscriptions {
			if token := c.Subscribe(topic, QoSState, a.onMessage); token.Wait() && token.Error() != nil {
				fmt.Fprintf(os.Stderr, "mqtt: subscribe %s: %v\n", topic, token.Error())
			}
		}
		a.publishAllModes()
		a.publishHealth()
		// Retained snapshots go out on connect too: a broker that was restarted has
		// forgotten them, and a client subscribing right now would otherwise see an
		// empty history until the next reading.
		a.publishEnvRecent()
		a.publish(TopicEventRecent, a.events.Payload(), true)
		a.publish(TopicKnob, KnobPayload(a.panel.Knob()), true)
	}
	opts.OnConnectionLost = func(_ mqtt.Client, err error) {
		fmt.Fprintf(os.Stderr, "mqtt: connection lost: %v\n", err)
	}

	a.client = mqtt.NewClient(opts)
	token := a.client.Connect()
	if !token.WaitTimeout(10*time.Second) || token.Error() != nil {
		return fmt.Errorf("connecting to %s:%d: %w", a.cfg.Broker.Host, a.cfg.Broker.Port, token.Error())
	}
	return nil
}

func (a *Borgd) publish(topic string, payload any, retained bool) {
	if a.client == nil || !a.client.IsConnected() {
		return
	}
	data, err := json.Marshal(payload)
	if err != nil {
		fmt.Fprintf(os.Stderr, "encode %s: %v\n", topic, err)
		return
	}
	a.client.Publish(topic, QoSState, retained, data)
}

func (a *Borgd) publishMode(mode Mode) {
	s := a.modes.Get(mode)
	a.publish(ModeTopic(mode), Envelope(map[string]any{
		"submode": s.Submode, "chan": nilIfEmpty(s.Chan), "pinned": s.Pinned, "since": s.Since,
	}), true)
}

func (a *Borgd) publishAllModes() {
	for _, mode := range AllModes {
		a.publishMode(mode)
	}
	focus := a.modes.Focus()
	a.publish(TopicModeFocus, Envelope(map[string]any{"focus": nilIfEmpty(string(focus))}), true)
}

func (a *Borgd) publishHealth() {
	for _, c := range a.health.All() {
		a.publish(HealthTopic(c.Name), Envelope(map[string]any{
			"state": string(c.State), "reason": c.Reason, "since": c.Since,
		}), true)
	}
	a.publish(TopicHealth, Envelope(map[string]any{
		"state": string(a.health.Aggregate()), "summary": a.health.Summary(),
		"ts": Timestamp(time.Now()),
	}), true)
}

func nilIfEmpty(s string) any {
	if s == "" {
		return nil
	}
	return s
}

// onMessage dispatches an incoming message. Nothing in here may panic the process: a
// malformed payload from any client is a log line, not an outage.
func (a *Borgd) onMessage(_ mqtt.Client, msg mqtt.Message) {
	defer func() {
		if r := recover(); r != nil {
			fmt.Fprintf(os.Stderr, "handling %s: %v\n", msg.Topic(), r)
		}
	}()

	topic := msg.Topic()
	switch {
	case strings.HasPrefix(topic, "balkon/cmd/mode/"):
		a.handleModeCommand(topic, msg.Payload())
	case topic == TopicCmdFocus:
		a.handleFocus(msg.Payload())
	case topic == TopicCmdBrightness:
		a.handleLevel(topic, msg.Payload(), func(v int) { a.setBrightness(v) })
	case topic == TopicCmdVolume:
		a.handleLevel(topic, msg.Payload(), func(v int) { a.setVolume(v) })
	case strings.HasPrefix(topic, "balkon/input/"):
		a.handleInput(topic, msg.Payload())
	case strings.HasPrefix(topic, "balkon/env/"):
		a.mu.Lock()
		a.lastEnv = time.Now()
		a.mu.Unlock()
		a.handleEnv(topic, msg.Payload())
	case topic == "balkon/presence":
		a.mu.Lock()
		a.lastEnv = time.Now()
		a.mu.Unlock()
	}
}

func (a *Borgd) handleModeCommand(topic string, payload []byte) {
	mode := Mode(strings.TrimPrefix(topic, "balkon/cmd/mode/"))
	var cmd struct {
		Submode string `json:"submode"`
		Chan    string `json:"chan"`
	}
	if err := json.Unmarshal(payload, &cmd); err != nil {
		fmt.Fprintf(os.Stderr, "%s: bad payload: %v\n", topic, err)
		return
	}
	changed, err := a.modes.Apply(mode, cmd.Submode, cmd.Chan)
	if err != nil {
		// A refused command is worth a line: it means a client and borgd
		// disagree about what exists, which is a contract drift worth noticing.
		fmt.Fprintf(os.Stderr, "%s refused: %v\n", topic, err)
		return
	}
	for _, m := range changed {
		a.publishMode(m)
		a.applyTuner(m)
		if m == Lumen {
			a.applyLumen()
		}
	}
}

// applyTuner turns a mode change into a tuner claim. The mode machine has already
// enforced that COMMS and SIGINT cannot both run; this decides which decoder that
// actually means, and announces the antenna length when the band changes, since the
// whip is a manual compromise the unit can only ask about (docs/build-notes.md).
func (a *Borgd) applyTuner(mode Mode) {
	state := a.modes.Get(mode)
	consumer, wants := ConsumerForMode(mode, state.Submode)
	if !wants {
		if _, ok := ConsumerForMode(mode, "adsb"); ok || mode == Comms || mode == Sigint {
			for _, c := range []Consumer{ConsumerListening, ConsumerAdsb, ConsumerIsm,
				ConsumerAprs, ConsumerRadiosonde, ConsumerSpectrum} {
				a.tuner.Release(c)
			}
		}
		return
	}

	band := state.Submode
	claim, changed, err := a.tuner.Request(Claim{Consumer: consumer, Band: band})
	if err != nil {
		fmt.Fprintf(os.Stderr, "tuner: %v\n", err)
		return
	}
	if !changed {
		return
	}
	fmt.Fprintf(os.Stderr, "tuner: %s (%s)\n", claim.Consumer, claim.Band)
	if cm, ok := a.cfg.Audio.AntennaCM[band]; ok {
		a.speaker.Announce(AntennaHint(strings.ToUpper(band), cm))
	}
}

// skyLoop republishes the ADS-B picture while ADS-B holds the tuner.
//
// Once a second, which is what the contract promises and what makes the app's radar
// look alive. When the tuner belongs to somebody else the loop idles rather than
// publishing a stale sky: an old snapshot pretending to be current is worse than an
// obviously empty one.
func (a *Borgd) skyLoop(ctx context.Context) {
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			if a.tuner.Current().Consumer != ConsumerAdsb {
				continue
			}
			snap, err := ReadSnapshot(a.cfg.Adsb.AircraftJSON)
			if err != nil {
				// readsb not up yet, or the container is restarting. The sdr
				// capability already says so; no need for a line every second.
				continue
			}
			sky := BuildSky(snap, a.cfg.Location.Latitude, a.cfg.Location.Longitude,
				a.cfg.Adsb.MaxRangeKM)
			a.publish(TopicAdsbAircraft, SkyPayload(sky, time.Now()), true)

			for _, hit := range a.lowPass.Check(sky) {
				a.RecordEvent(CategoryAircraft, hit.EventText())
			}
		}
	}
}

// handleLevel reads the {"value":n} shape both level commands share.
func (a *Borgd) handleLevel(topic string, payload []byte, apply func(int)) {
	var cmd struct {
		Value *int `json:"value"`
	}
	if err := json.Unmarshal(payload, &cmd); err != nil || cmd.Value == nil {
		fmt.Fprintf(os.Stderr, "%s: expected {\"value\":n}, got %q\n", topic, payload)
		return
	}
	apply(*cmd.Value)
}

// setBrightness is the one path to the light's brightness, whether the command came
// from the app, the panel's encoder or a mode change.
func (a *Borgd) setBrightness(value int) {
	a.panel.SetBrightness(value)
	a.publishWLED(WLEDBrightness(a.panel.Brightness()))
}

func (a *Borgd) setVolume(value int) {
	a.panel.SetVolume(value)
	v := a.panel.Volume()
	// wpctl talks to the same PipeWire session borgd plays through, so this is
	// the volume everything hears, not a per-stream one.
	if out, err := execRunner("wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@",
		fmt.Sprintf("%d%%", v)); err != nil {
		fmt.Fprintf(os.Stderr, "volume: %v: %s\n", err, strings.TrimSpace(out))
	}
}

// publishWLED sends a command to the light. WLED speaks its own API and is the only
// device borgd talks to in a foreign dialect, which is why the translation lives
// in wled.go and this only ships the result.
func (a *Borgd) publishWLED(cmd WLEDCommand) {
	data, err := cmd.Encode()
	if err != nil {
		fmt.Fprintf(os.Stderr, "wled: %v\n", err)
		return
	}
	if a.client == nil || !a.client.IsConnected() {
		return
	}
	a.client.Publish(WLEDAPITopic(), QoSState, false, data)
}

// applyLumen pushes a LUMEN submode to the light. Every other mode is borgd's
// own business; this one has a device of its own that has to be told.
func (a *Borgd) applyLumen() {
	state := a.modes.Get(Lumen)
	cmd, err := WLEDForSubmode(state.Submode, a.panel.Brightness())
	if err != nil {
		fmt.Fprintf(os.Stderr, "wled: %v\n", err)
		return
	}
	a.publishWLED(cmd)
}

// handleInput turns a panel event into its effect and carries it out. The panel is a
// dumb device by design (decision 2026-07-20): it reports what happened, this decides
// what it means.
func (a *Borgd) handleInput(topic string, payload []byte) {
	var raw map[string]any
	if err := json.Unmarshal(payload, &raw); err != nil {
		fmt.Fprintf(os.Stderr, "%s: bad payload: %v\n", topic, err)
		return
	}
	action, ok := ParseInputTopic(topic, raw)
	if !ok {
		return
	}

	effect := a.panel.Handle(action, a.modes)
	switch {
	case effect.Focus != nil:
		if a.modes.SetFocus(*effect.Focus) {
			a.publish(TopicModeFocus, Envelope(map[string]any{
				"focus": string(*effect.Focus)}), true)
		}
	case effect.Unpin != nil:
		if a.modes.Pin(*effect.Unpin, false) {
			a.publishMode(*effect.Unpin)
		}
	case effect.SetSubmode != nil:
		c := effect.SetSubmode
		changed, err := a.modes.Apply(c.Mode, c.Submode, c.Chan)
		if err != nil {
			fmt.Fprintf(os.Stderr, "panel: %v\n", err)
			return
		}
		for _, m := range changed {
			a.publishMode(m)
			a.applyTuner(m)
			if m == Lumen {
				a.applyLumen()
			}
		}
	case effect.Brightness != nil:
		a.setBrightness(*effect.Brightness)
	case effect.Volume != nil:
		a.setVolume(*effect.Volume)
	case effect.KnobTarget != nil:
		a.publish(TopicKnob, KnobPayload(*effect.KnobTarget), true)
	}
}

// envFields maps the ESP's per-value topics onto the history's fields. ESPHome
// publishes a plain number, not JSON, which is why this path does not go through the
// envelope decoder.
var envFields = map[string]string{
	"balkon/env/temperature": "t",
	"balkon/env/humidity":    "h",
	"balkon/env/pressure":    "p",
}

func (a *Borgd) handleEnv(topic string, payload []byte) {
	field, ok := envFields[topic]
	if !ok {
		return // env/recent is ours; anything else is not a reading
	}
	value, err := strconv.ParseFloat(strings.TrimSpace(string(payload)), 64)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s: not a number: %q\n", topic, payload)
		return
	}
	a.env.Observe(field, value)
	if a.env.Commit(a.clockOK()) {
		a.envPub.Touch()
	}
}

// clockOK gates every timestamped write. Before the first NTP sync the Pi thinks it is
// 1970, and a history stamped that way is worse than a gap.
func (a *Borgd) clockOK() bool {
	if !PlausibleTime(time.Now()) {
		return false
	}
	c, ok := a.health.Get("clock")
	return ok && c.State == StateOK
}

func (a *Borgd) publishEnvRecent() {
	a.publish(TopicEnvRecent, a.env.Payload(), true)
}

// RecordEvent adds an event to the retained ring and publishes it. This ring is what
// the app diffs to raise notifications, so an entry that never lands is a notification
// the user never gets: it publishes immediately rather than waiting for a coalescer.
func (a *Borgd) RecordEvent(category EventCategory, text string) {
	if !a.events.Add(category, text, a.clockOK()) {
		fmt.Fprintf(os.Stderr, "event dropped (clock not synced): %s %s\n", category, text)
		return
	}
	a.publish(TopicEventRecent, a.events.Payload(), true)
}

func (a *Borgd) handleFocus(payload []byte) {
	var cmd struct {
		Focus string `json:"focus"`
	}
	if err := json.Unmarshal(payload, &cmd); err != nil {
		return
	}
	if a.modes.SetFocus(Mode(cmd.Focus)) {
		a.publish(TopicModeFocus, Envelope(map[string]any{"focus": nilIfEmpty(cmd.Focus)}), true)
	}
}

// --- HTTP -----------------------------------------------------------------------

func (a *Borgd) serveHTTP(ctx context.Context) {
	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		fmt.Fprint(w, StatusPage(a.health, a.modes, a.cfg.Broker.Host, a.systemInfo()))
	})
	mux.HandleFunc("/health.json", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if err := json.NewEncoder(w).Encode(BuildHealthJSON(a.health, a.modes)); err != nil {
			fmt.Fprintf(os.Stderr, "health.json: %v\n", err)
		}
	})

	srv := &http.Server{
		Addr:              fmt.Sprintf(":%d", a.cfg.HTTP.Port),
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}
	go func() {
		<-ctx.Done()
		shutdown, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		_ = srv.Shutdown(shutdown)
	}()

	fmt.Fprintf(os.Stderr, "http: listening on :%d\n", a.cfg.HTTP.Port)
	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		// Losing the status page must not take the unit down; MQTT still works.
		fmt.Fprintf(os.Stderr, "http: %v\n", err)
	}
}

func (a *Borgd) systemInfo() map[string]string {
	claim := a.tuner.Current()
	tuner := string(claim.Consumer)
	if claim.Band != "" {
		tuner += " (" + claim.Band + ")"
	}
	if waiting := a.tuner.Waiting(); len(waiting) > 0 {
		parts := make([]string, 0, len(waiting))
		for _, c := range waiting {
			parts = append(parts, string(c))
		}
		tuner += ", waiting: " + strings.Join(parts, ", ")
	}
	return map[string]string{
		"broker": fmt.Sprintf("%s:%d", a.cfg.Broker.Host, a.cfg.Broker.Port),
		"build":  buildVersion(),
		// "why is there no ADS-B right now" has to be answerable at a glance.
		"tuner": tuner,
	}
}

// --- main loop --------------------------------------------------------------------

func (a *Borgd) run(ctx context.Context) {
	interval := time.Duration(a.cfg.Health.ProbeIntervalS) * time.Second
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	a.health.ProbeAll()
	a.publishHealth()
	fmt.Fprintf(os.Stderr, "borgd: up, probing every %s\n", interval)

	// "Borg online" once the sound card has actually shown up: the user session and
	// the USB card are not necessarily ready when this process is.
	go func() {
		if waitForSound(execRunner, 10, 3*time.Second) {
			a.speaker.Announce(BootAnnouncement)
		}
	}()

	for {
		select {
		case <-ctx.Done():
			fmt.Fprintln(os.Stderr, "borgd: shutting down")
			if a.client != nil && a.client.IsConnected() {
				a.publish(TopicHealth, Envelope(map[string]any{
					"state": string(StateMissing), "summary": "borgd stopped",
					"ts": Timestamp(time.Now()),
				}), true)
				a.client.Disconnect(500)
			}
			return
		case <-ticker.C:
			// The history is committed from the message path too, but a quiet ESP
			// still needs the cadence to advance once a reading exists.
			if a.env.Commit(a.clockOK()) {
				a.envPub.Touch()
			}
			if a.envPub.Due() {
				a.publishEnvRecent()
			}
			if changed := a.health.ProbeAll(); len(changed) > 0 {
				for _, name := range changed {
					if c, ok := a.health.Get(name); ok {
						fmt.Fprintf(os.Stderr, "health: %s -> %s %s\n", name, c.State, c.Reason)
					}
				}
				a.publishHealth()
			}
		}
	}
}

// buildVersion is stamped at build time (-ldflags -X main.version=...), so the status
// page can say which tree is running, the same question the app answers with rNNN.
var version = "dev"

func buildVersion() string { return version }
