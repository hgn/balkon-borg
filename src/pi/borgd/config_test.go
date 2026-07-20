package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const minimalConfig = `
broker:
  password: secret
location:
  latitude: 48.1
  longitude: 11.5
`

func TestDefaultsFillTheGaps(t *testing.T) {
	cfg, err := ParseConfig([]byte(minimalConfig))
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Broker.Host != "borg-pi" || cfg.Broker.Port != 1883 {
		t.Errorf("broker defaults not applied: %+v", cfg.Broker)
	}
	if cfg.HTTP.Port != 80 {
		t.Errorf("http port default not applied: %d", cfg.HTTP.Port)
	}
	if cfg.Health.ProbeIntervalS != 30 {
		t.Errorf("probe interval default not applied: %d", cfg.Health.ProbeIntervalS)
	}
}

// The point of validating at all: a typo must not be silently ignored.
func TestAnUnknownKeyIsAnError(t *testing.T) {
	_, err := ParseConfig([]byte(minimalConfig + "\nbrokr:\n  host: nope\n"))
	if err == nil {
		t.Fatal("expected an unknown key to be refused")
	}
	if !strings.Contains(err.Error(), "brokr") {
		t.Errorf("the error should name the offending key, got %v", err)
	}
}

func TestAMissingPasswordIsRefused(t *testing.T) {
	_, err := ParseConfig([]byte("broker:\n  host: x\nlocation:\n  latitude: 0\n  longitude: 0\n"))
	if err == nil || !strings.Contains(err.Error(), "password") {
		t.Fatalf("expected a complaint about the missing password, got %v", err)
	}
}

func TestOutOfRangeCoordinatesAreRefused(t *testing.T) {
	_, err := ParseConfig([]byte("broker:\n  password: x\nlocation:\n  latitude: 120\n  longitude: 0\n"))
	if err == nil || !strings.Contains(err.Error(), "latitude") {
		t.Fatalf("expected a complaint about the latitude, got %v", err)
	}
}

// Hysteresis pointing the wrong way would flap the effect on and off forever.
func TestInvertedHysteresisIsRefused(t *testing.T) {
	yaml := minimalConfig + "\nenvironment:\n  condensation_on_pct: 80\n  condensation_off_pct: 90\n"
	_, err := ParseConfig([]byte(yaml))
	if err == nil || !strings.Contains(err.Error(), "condensation") {
		t.Fatalf("expected a complaint about the thresholds, got %v", err)
	}
}

// The real file has to stay loadable: it is shipped, and a broken one means no borgd.
func TestTheShippedConfigIsValid(t *testing.T) {
	path := filepath.Join("..", "..", "shared", "borg.yaml")
	if _, err := os.Stat(path); err != nil {
		t.Skipf("shared/borg.yaml not present: %v", err)
	}
	cfg, err := LoadConfig(path)
	if err != nil {
		t.Fatalf("the shipped borg.yaml does not load: %v", err)
	}
	if cfg.Broker.Password == "" {
		t.Error("the shipped config must carry the broker password")
	}
	if cfg.Adsb.MaxRangeKM <= 0 {
		t.Error("the radar range must be positive")
	}
}

func TestMissingFileIsNamed(t *testing.T) {
	_, err := LoadConfig("/nonexistent/borg.yaml")
	if err == nil || !strings.Contains(err.Error(), "borg.yaml") {
		t.Fatalf("the error should name the file, got %v", err)
	}
}
