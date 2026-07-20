// Hardware probes: the only place that touches the machine directly.
//
// Every probe answers with a state and a reason and never returns an error, because
// absent hardware is a valid state (README.md's stability principle). A probe is
// cheap and runs every health.probe_interval_s seconds, so plugging the SDR in later
// brings it back without a restart.
package main

import (
	"os"
	"os/exec"
	"strings"
	"time"
)

// commandRunner is the seam tests replace; nothing here shells out directly.
type commandRunner func(name string, args ...string) (string, error)

func execRunner(name string, args ...string) (string, error) {
	// Foreign tool output is parsed below, so pin the locale: otherwise a German
	// system shifts number and date formats under us.
	cmd := exec.Command(name, args...)
	cmd.Env = append(os.Environ(), "LC_ALL=C")
	out, err := cmd.CombinedOutput()
	return string(out), err
}

// ClockProbe reports whether NTP has synced. Until it has, timestamped persistence is
// gated: a gap in the bird log is a gap, a log full of 1970 is corruption.
func ClockProbe(run commandRunner) Probe {
	return func() (State, string) {
		out, err := run("timedatectl", "show", "-p", "NTPSynchronized", "--value")
		if err != nil {
			return StateDegraded, "timedatectl unavailable"
		}
		if strings.TrimSpace(out) == "yes" {
			return StateOK, ""
		}
		return StateDegraded, "waiting for the first NTP sync"
	}
}

// SDRProbe uses rtl_test, which exits after listing devices when given -t.
func SDRProbe(run commandRunner) Probe {
	return func() (State, string) {
		out, err := run("rtl_test", "-t")
		text := strings.ToLower(out)
		switch {
		case strings.Contains(text, "no supported devices found"):
			return StateMissing, "no RTL-SDR attached"
		case strings.Contains(text, "usb_claim_interface error"):
			// The classic one: the DVB driver grabbed the stick despite the blacklist.
			return StateDegraded, "device busy, another driver holds it"
		case err != nil && !strings.Contains(text, "found"):
			return StateMissing, "rtl_test failed"
		default:
			return StateOK, ""
		}
	}
}

// SoundProbe looks for a playback device. A Pi with no speaker attached is a valid,
// running system.
func SoundProbe(run commandRunner) Probe {
	return func() (State, string) {
		out, err := run("aplay", "-l")
		if err != nil || !strings.Contains(out, "card ") {
			return StateMissing, "no playback device"
		}
		return StateOK, ""
	}
}

func MicrophoneProbe(run commandRunner) Probe {
	return func() (State, string) {
		out, err := run("arecord", "-l")
		if err != nil || !strings.Contains(out, "card ") {
			return StateMissing, "no capture device"
		}
		return StateOK, ""
	}
}

// CameraProbe checks the device node rather than opening the camera: opening it while
// Frigate holds it would be both rude and misleading.
func CameraProbe(exists func(string) bool) Probe {
	return func() (State, string) {
		if exists("/dev/video0") {
			return StateOK, ""
		}
		return StateMissing, "no camera device node"
	}
}

// FreshnessProbe reports on data that is supposed to keep arriving: the ESP's sensors,
// a decoder's output. Silence past the deadline is degraded, not missing, because the
// source existed once.
func FreshnessProbe(last func() time.Time, now func() time.Time, maxAge time.Duration,
	whenNever string) Probe {
	return func() (State, string) {
		t := last()
		if t.IsZero() {
			return StateMissing, whenNever
		}
		if age := now().Sub(t); age > maxAge {
			return StateDegraded, "no data for " + age.Truncate(time.Second).String()
		}
		return StateOK, ""
	}
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}
