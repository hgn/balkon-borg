// borg-arbiter: the borg-pi5's own process.
//
// One binary, no runtime to install: it owns mode state, the health registry and the
// status page, talks MQTT to everything else, and survives every piece of hardware
// being absent (README.md's stability principle).
//
// Diagnostics go to stderr, results to stdout, and systemd captures both. There is no
// logging framework here on purpose: `journalctl --user -u borg-arbiter` is the log.
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

type Arbiter struct {
	cfg     *Config
	modes   *Modes
	health  *Registry
	mixer   *Mixer
	speaker *Speaker
	env     *EnvHistory
	events  *Events
	envPub  *Coalescer
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

	a := &Arbiter{cfg: cfg, modes: NewModes(time.Now), health: NewRegistry(time.Now)}
	a.mixer = NewMixer(time.Now)
	a.speaker = NewSpeaker(a.mixer, cfg.Audio.Piper, cfg.Audio.Voice)
	a.env = NewEnvHistory(cfg.Environment.HistoryHours,
		time.Duration(cfg.Environment.SampleIntervalS)*time.Second, time.Now)
	a.events = NewEvents(time.Now)
	// A retained snapshot at most every 10s: the history only grows once a minute, so
	// this is about not writing a retained message per ESP reading.
	a.envPub = NewCoalescer(10*time.Second, time.Now)
	a.registerCapabilities()

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	go a.serveHTTP(ctx)

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
func (a *Arbiter) registerCapabilities() {
	enabled := a.cfg.Capabilities.Enabled()
	a.health.Register("clock", ClockProbe(execRunner), true)
	a.health.Register("sdr", SDRProbe(execRunner), enabled["sdr"])
	a.health.Register("speaker", SpeakerProbe(execRunner, a.speaker), enabled["speaker"])
	a.health.Register("mic", MicrophoneProbe(execRunner), enabled["microphone"])
	a.health.Register("camera", CameraProbe(fileExists), enabled["camera"])
	a.health.Register("esp", FreshnessProbe(a.lastEnvSeen, time.Now, 5*time.Minute,
		"no data from the ESP yet"), enabled["esp"])
	a.health.Register("broker", a.brokerProbe(), true)
	// Always ok while this process is running: its whole purpose is to overwrite the
	// retained "missing" the last will leaves behind after a crash.
	a.health.Register(CapabilityArbiter, func() (State, string) { return StateOK, "" }, true)
}

func (a *Arbiter) lastEnvSeen() time.Time {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.lastEnv
}

func (a *Arbiter) brokerProbe() Probe {
	return func() (State, string) {
		if a.client != nil && a.client.IsConnected() {
			return StateOK, ""
		}
		return StateMissing, "not connected to the broker"
	}
}

// --- MQTT -----------------------------------------------------------------------

func (a *Arbiter) connect() error {
	opts := mqtt.NewClientOptions().
		AddBroker(fmt.Sprintf("tcp://%s:%d", a.cfg.Broker.Host, a.cfg.Broker.Port)).
		SetClientID("borg-arbiter").
		SetUsername("arbiter").
		SetPassword(a.cfg.Broker.Password).
		SetCleanSession(true).
		SetAutoReconnect(true).
		SetConnectRetry(true).
		SetConnectRetryInterval(10 * time.Second).
		SetMaxReconnectInterval(60 * time.Second)

	// The LWT lands on the arbiter's own capability topic, per the contract: that is
	// what lets a client tell "arbiter down" from "all quiet". The aggregate stays
	// whatever it last was, which is honest, since nobody is updating it any more.
	lwt, _ := json.Marshal(CapabilityPayload(string(StateMissing), "arbiter offline",
		Timestamp(time.Now())))
	opts.SetWill(HealthTopic(CapabilityArbiter), string(lwt), QoSState, true)

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

func (a *Arbiter) publish(topic string, payload any, retained bool) {
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

func (a *Arbiter) publishMode(mode Mode) {
	s := a.modes.Get(mode)
	a.publish(ModeTopic(mode), Envelope(map[string]any{
		"submode": s.Submode, "chan": nilIfEmpty(s.Chan), "pinned": s.Pinned, "since": s.Since,
	}), true)
}

func (a *Arbiter) publishAllModes() {
	for _, mode := range AllModes {
		a.publishMode(mode)
	}
	focus := a.modes.Focus()
	a.publish(TopicModeFocus, Envelope(map[string]any{"focus": nilIfEmpty(string(focus))}), true)
}

func (a *Arbiter) publishHealth() {
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
func (a *Arbiter) onMessage(_ mqtt.Client, msg mqtt.Message) {
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

func (a *Arbiter) handleModeCommand(topic string, payload []byte) {
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
		// A refused command is worth a line: it means a client and the arbiter
		// disagree about what exists, which is a contract drift worth noticing.
		fmt.Fprintf(os.Stderr, "%s refused: %v\n", topic, err)
		return
	}
	for _, m := range changed {
		a.publishMode(m)
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

func (a *Arbiter) handleEnv(topic string, payload []byte) {
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
func (a *Arbiter) clockOK() bool {
	c, ok := a.health.Get("clock")
	return ok && c.State == StateOK
}

func (a *Arbiter) publishEnvRecent() {
	a.publish(TopicEnvRecent, a.env.Payload(), true)
}

// RecordEvent adds an event to the retained ring and publishes it. This ring is what
// the app diffs to raise notifications, so an entry that never lands is a notification
// the user never gets: it publishes immediately rather than waiting for a coalescer.
func (a *Arbiter) RecordEvent(category EventCategory, text string) {
	if !a.events.Add(category, text, a.clockOK()) {
		fmt.Fprintf(os.Stderr, "event dropped (clock not synced): %s %s\n", category, text)
		return
	}
	a.publish(TopicEventRecent, a.events.Payload(), true)
}

func (a *Arbiter) handleFocus(payload []byte) {
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

func (a *Arbiter) serveHTTP(ctx context.Context) {
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

func (a *Arbiter) systemInfo() map[string]string {
	return map[string]string{
		"broker": fmt.Sprintf("%s:%d", a.cfg.Broker.Host, a.cfg.Broker.Port),
		"build":  buildVersion(),
	}
}

// --- main loop --------------------------------------------------------------------

func (a *Arbiter) run(ctx context.Context) {
	interval := time.Duration(a.cfg.Health.ProbeIntervalS) * time.Second
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	a.health.ProbeAll()
	a.publishHealth()
	fmt.Fprintf(os.Stderr, "arbiter: up, probing every %s\n", interval)

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
			fmt.Fprintln(os.Stderr, "arbiter: shutting down")
			if a.client != nil && a.client.IsConnected() {
				a.publish(TopicHealth, Envelope(map[string]any{
					"state": string(StateMissing), "summary": "arbiter stopped",
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
