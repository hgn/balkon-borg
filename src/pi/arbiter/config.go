// Runtime configuration, read from shared/borg.yaml and validated at startup.
//
// A typo fails here, naming the field, rather than surfacing as odd behaviour at three
// in the morning. Validation is explicit rather than tag-driven: there are a dozen
// fields, and a plain function that says what is wrong beats a framework.
package main

import (
	"bytes"
	"fmt"
	"os"

	"gopkg.in/yaml.v3"
)

type Config struct {
	Broker       Broker       `yaml:"broker"`
	HTTP         HTTPConfig   `yaml:"http"`
	Paths        Paths        `yaml:"paths"`
	Location     Location     `yaml:"location"`
	Adsb         Adsb         `yaml:"adsb"`
	Environment  Environment  `yaml:"environment"`
	Health       HealthConfig `yaml:"health"`
	Capabilities Capabilities `yaml:"capabilities"`
}

// BrokerUsers are the accounts the ACL distinguishes. They share one password: the
// separation exists so the broker can enforce who may write what, not to keep secrets
// from each other.
var BrokerUsers = []string{"arbiter", "app", "esp"}

type Broker struct {
	Host     string `yaml:"host"`
	Port     int    `yaml:"port"`
	Password string `yaml:"password"`
}

type HTTPConfig struct {
	Port int `yaml:"port"`
}

type Paths struct {
	Root      string `yaml:"root"`
	Media     string `yaml:"media"`
	Clips     string `yaml:"clips"`
	Timelapse string `yaml:"timelapse"`
	Apk       string `yaml:"apk"`
}

type Location struct {
	Latitude  float64 `yaml:"latitude"`
	Longitude float64 `yaml:"longitude"`
	AltitudeM float64 `yaml:"altitude_m"`
}

type Adsb struct {
	MaxRangeKM float64 `yaml:"max_range_km"`
	LowPassFt  float64 `yaml:"low_pass_ft"`
}

type Environment struct {
	SampleIntervalS    int     `yaml:"sample_interval_s"`
	HistoryHours       int     `yaml:"history_hours"`
	CondensationOnPct  float64 `yaml:"condensation_on_pct"`
	CondensationOffPct float64 `yaml:"condensation_off_pct"`
}

type HealthConfig struct {
	ProbeIntervalS int `yaml:"probe_interval_s"`
}

type Capabilities struct {
	SDR        bool `yaml:"sdr"`
	Camera     bool `yaml:"camera"`
	Microphone bool `yaml:"microphone"`
	Speaker    bool `yaml:"speaker"`
	ESP        bool `yaml:"esp"`
}

// Enabled maps capability names to their switch, so the registry can be built from the
// config without a switch statement per capability.
func (c Capabilities) Enabled() map[string]bool {
	return map[string]bool{
		"sdr":        c.SDR,
		"camera":     c.Camera,
		"microphone": c.Microphone,
		"speaker":    c.Speaker,
		"esp":        c.ESP,
	}
}

// LoadConfig reads and validates the file. KnownFields makes an unknown key an error:
// a typo must not be silently ignored, which is the whole point of validating at all.
func LoadConfig(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("reading config: %w", err)
	}
	return ParseConfig(data)
}

func ParseConfig(data []byte) (*Config, error) {
	var cfg Config
	dec := yaml.NewDecoder(bytes.NewReader(data))
	dec.KnownFields(true)
	if err := dec.Decode(&cfg); err != nil {
		return nil, fmt.Errorf("borg.yaml: %w", err)
	}
	cfg.applyDefaults()
	if err := cfg.validate(); err != nil {
		return nil, fmt.Errorf("borg.yaml: %w", err)
	}
	return &cfg, nil
}

func (c *Config) applyDefaults() {
	if c.Broker.Host == "" {
		c.Broker.Host = "borg-pi"
	}
	if c.Broker.Port == 0 {
		c.Broker.Port = 1883
	}
	if c.HTTP.Port == 0 {
		c.HTTP.Port = 80
	}
	if c.Health.ProbeIntervalS == 0 {
		c.Health.ProbeIntervalS = 30
	}
	if c.Environment.SampleIntervalS == 0 {
		c.Environment.SampleIntervalS = 60
	}
	if c.Environment.HistoryHours == 0 {
		c.Environment.HistoryHours = 24
	}
	if c.Adsb.MaxRangeKM == 0 {
		c.Adsb.MaxRangeKM = 50
	}
	// Paths default to the layout provisioning creates, so a minimal config is a
	// working config and only deviations have to be written down.
	if c.Paths.Root == "" {
		c.Paths.Root = "/srv/borg"
	}
	if c.Paths.Media == "" {
		c.Paths.Media = c.Paths.Root + "/media"
	}
	if c.Paths.Clips == "" {
		c.Paths.Clips = c.Paths.Root + "/clips"
	}
	if c.Paths.Timelapse == "" {
		c.Paths.Timelapse = c.Paths.Media + "/timelapse"
	}
	if c.Paths.Apk == "" {
		c.Paths.Apk = c.Paths.Root + "/apk"
	}
}

func (c *Config) validate() error {
	if c.Broker.Password == "" {
		return fmt.Errorf("broker.password is empty; every client needs it to connect")
	}
	if c.Location.Latitude < -90 || c.Location.Latitude > 90 {
		return fmt.Errorf("location.latitude %v is out of range", c.Location.Latitude)
	}
	if c.Location.Longitude < -180 || c.Location.Longitude > 180 {
		return fmt.Errorf("location.longitude %v is out of range", c.Location.Longitude)
	}
	// A threshold that switches off above where it switches on would flap forever.
	if c.Environment.CondensationOffPct > c.Environment.CondensationOnPct {
		return fmt.Errorf("environment.condensation_off_pct (%v) is above condensation_on_pct (%v)",
			c.Environment.CondensationOffPct, c.Environment.CondensationOnPct)
	}
	if c.Paths.Root == "" {
		return fmt.Errorf("paths.root is empty")
	}
	return nil
}
