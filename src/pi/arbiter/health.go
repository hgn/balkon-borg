// The capability health registry.
//
// The stability principle in one file: the system runs with any subset of hardware
// present, and what is absent is reported rather than fatal. Every capability carries a
// state, a reason and a since-timestamp, because "camera missing since 14:02" is
// actionable and "camera missing" is not.
//
// No MQTT and no hardware in here: probes are injected, so the whole thing is testable
// without a Pi. main.go wires the real probes in and publishes the payloads.
package main

import (
	"fmt"
	"sort"
	"sync"
	"time"
)

type State string

const (
	StateOK       State = "ok"
	StateDegraded State = "degraded"
	StateMissing  State = "missing"
	StateDisabled State = "disabled"
)

// severity decides the worst-of aggregate. Disabled is deliberately harmless: the user
// switched it off, so it must not colour the summary.
func severity(s State) int {
	switch s {
	case StateDegraded:
		return 1
	case StateMissing:
		return 2
	default:
		return 0
	}
}

type Capability struct {
	Name   string `json:"-"`
	State  State  `json:"state"`
	Reason string `json:"reason"`
	Since  string `json:"since"`
}

// Probe answers what a capability's state is right now, and why. A probe that panics is
// caught by the registry and turned into degraded: the line between "the SDR is
// unhappy" and "the unit is dead".
type Probe func() (State, string)

type Registry struct {
	mu     sync.Mutex
	now    func() time.Time
	caps   map[string]Capability
	probes map[string]Probe
	order  []string
}

func NewRegistry(now func() time.Time) *Registry {
	if now == nil {
		now = time.Now
	}
	return &Registry{now: now, caps: map[string]Capability{}, probes: map[string]Probe{}}
}

// Register adds a capability. A disabled one is never probed and reports as such, which
// is the difference between "not wanted" and "wanted but broken".
func (r *Registry) Register(name string, probe Probe, enabled bool) {
	r.mu.Lock()
	defer r.mu.Unlock()

	state, reason := StateOK, ""
	if !enabled {
		state, reason = StateDisabled, "disabled in borg.yaml"
	}
	if _, seen := r.caps[name]; !seen {
		r.order = append(r.order, name)
	}
	r.caps[name] = Capability{name, state, reason, Timestamp(r.now())}
	if enabled && probe != nil {
		r.probes[name] = probe
	}
}

// Set updates a capability and reports whether anything actually changed. Since only
// moves when the state moves, so it answers "how long has it been like this" rather
// than "when was it last looked at".
func (r *Registry) Set(name string, state State, reason string) bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.set(name, state, reason)
}

func (r *Registry) set(name string, state State, reason string) bool {
	current, existed := r.caps[name]
	if existed && current.State == state && current.Reason == reason {
		return false
	}
	since := current.Since
	if !existed || current.State != state {
		since = Timestamp(r.now())
	}
	if !existed {
		r.order = append(r.order, name)
	}
	r.caps[name] = Capability{name, state, reason, since}
	return true
}

// ProbeAll runs every enabled probe and returns the names whose state changed, so the
// caller republishes only those.
func (r *Registry) ProbeAll() []string {
	r.mu.Lock()
	probes := make(map[string]Probe, len(r.probes))
	for name, p := range r.probes {
		probes[name] = p
	}
	r.mu.Unlock()

	var changed []string
	for _, name := range r.names() {
		probe, ok := probes[name]
		if !ok {
			continue
		}
		state, reason := runProbe(probe)
		if r.Set(name, state, reason) {
			changed = append(changed, name)
		}
	}
	return changed
}

// runProbe isolates a misbehaving probe: a panic here would otherwise take down the
// whole arbiter over one unhappy piece of hardware.
func runProbe(probe Probe) (state State, reason string) {
	defer func() {
		if r := recover(); r != nil {
			state, reason = StateDegraded, fmt.Sprintf("probe panicked: %v", r)
		}
	}()
	return probe()
}

func (r *Registry) names() []string {
	r.mu.Lock()
	defer r.mu.Unlock()
	out := append([]string(nil), r.order...)
	sort.Strings(out)
	return out
}

func (r *Registry) Get(name string) (Capability, bool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	c, ok := r.caps[name]
	return c, ok
}

// All returns the capabilities in a stable order, so the status page does not shuffle
// between reloads.
func (r *Registry) All() []Capability {
	r.mu.Lock()
	defer r.mu.Unlock()
	out := make([]Capability, 0, len(r.caps))
	for _, c := range r.caps {
		out = append(out, c)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out
}

// Aggregate is the worst-of summary the app's header dot shows.
func (r *Registry) Aggregate() State {
	worst := StateOK
	for _, c := range r.All() {
		if severity(c.State) > severity(worst) {
			worst = c.State
		}
	}
	return worst
}

// Summary is one line for the aggregate topic and the status page header.
func (r *Registry) Summary() string {
	var problems []string
	ok := 0
	for _, c := range r.All() {
		if severity(c.State) > 0 {
			problems = append(problems, c.Name)
		} else if c.State == StateOK {
			ok++
		}
	}
	if len(problems) == 0 {
		return fmt.Sprintf("%d capabilities ok", ok)
	}
	return fmt.Sprintf("%d degraded or missing: %s", len(problems), join(problems, ", "))
}

func join(items []string, sep string) string {
	out := ""
	for i, s := range items {
		if i > 0 {
			out += sep
		}
		out += s
	}
	return out
}
