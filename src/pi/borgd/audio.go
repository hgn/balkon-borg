// Playback: the part that actually makes noise, and the only part of M2 that cannot be
// tested without a sound card.
//
// Deliberately thin. Everything worth reasoning about (who may play, what resumes) is
// in mixer.go and tested; here we shell out to PipeWire's tools and to Piper, and treat
// every failure as a degraded speaker rather than an error anybody has to handle.
package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

// Speaker plays sound through PipeWire. It is safe to call from several goroutines:
// the mixer decides who may play, this serialises the actual processes.
type Speaker struct {
	mu      sync.Mutex
	mixer   *Mixer
	voice   string // Piper voice model (.onnx), empty if TTS is unavailable
	piper   string // path to the piper binary
	playing *exec.Cmd
}

func NewSpeaker(mixer *Mixer, piperPath, voicePath string) *Speaker {
	return &Speaker{mixer: mixer, piper: piperPath, voice: voicePath}
}

// Available reports whether text-to-speech can work at all. A unit with no voice model
// is not broken, it is quiet: everything else keeps running.
func (s *Speaker) Available() bool {
	if s.piper == "" || s.voice == "" {
		return false
	}
	_, err := os.Stat(s.voice)
	return err == nil
}

// Say synthesizes text and plays it, claiming the speaker as `src` and handing it back
// afterwards (so the radio resumes on its own).
//
// Blocks until the speech is over, which is what makes "announce, then resume" work
// without a queue: callers run it in their own goroutine.
func (s *Speaker) Say(src Source, text string) error {
	grant := s.mixer.Claim(src)
	if !grant.Granted {
		return fmt.Errorf("not speaking: %s", grant.Reason)
	}
	defer func() {
		if resume, ok := s.mixer.Release(src); ok {
			fmt.Fprintf(os.Stderr, "audio: resuming %s\n", resume)
		}
	}()

	if !s.Available() {
		return fmt.Errorf("no voice model available")
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	// piper writes a wav to stdout, pw-play reads it from stdin. Two small processes
	// beat a temporary file that has to be cleaned up on every error path.
	piper := exec.Command(s.piper, "--model", s.voice, "--output_file", "-")
	piper.Stdin = strings.NewReader(text)
	play := exec.Command("pw-play", "-")
	pipe, err := piper.StdoutPipe()
	if err != nil {
		return fmt.Errorf("piper stdout: %w", err)
	}
	play.Stdin = pipe
	play.Stderr = os.Stderr
	piper.Stderr = os.Stderr

	if err := piper.Start(); err != nil {
		return fmt.Errorf("starting piper: %w", err)
	}
	if err := play.Start(); err != nil {
		_ = piper.Process.Kill()
		return fmt.Errorf("starting pw-play: %w", err)
	}
	s.playing = play

	if err := piper.Wait(); err != nil {
		return fmt.Errorf("piper: %w", err)
	}
	if err := play.Wait(); err != nil {
		return fmt.Errorf("pw-play: %w", err)
	}
	s.playing = nil
	return nil
}

// PlayFile plays a wav (the talk-down message from the phone, U21).
func (s *Speaker) PlayFile(src Source, path string) error {
	grant := s.mixer.Claim(src)
	if !grant.Granted {
		return fmt.Errorf("not playing %s: %s", filepath.Base(path), grant.Reason)
	}
	defer s.mixer.Release(src)

	s.mu.Lock()
	defer s.mu.Unlock()

	cmd := exec.Command("pw-play", path)
	cmd.Stderr = os.Stderr
	s.playing = cmd
	err := cmd.Run()
	s.playing = nil
	if err != nil {
		return fmt.Errorf("playing %s: %w", path, err)
	}
	return nil
}

// Announce is the fire-and-forget form used from the message path: an announcement must
// never block MQTT handling, and a failed announcement is a log line, not an outage.
func (s *Speaker) Announce(text string) {
	go func() {
		if err := s.Say(SourceAnnouncement, text); err != nil {
			fmt.Fprintf(os.Stderr, "audio: %v\n", err)
		}
	}()
}

// SpeakerProbe reports on the whole chain rather than just the card: a sound device
// with no working TTS still plays talk-down and the alarm, so that is `degraded`, not
// `missing`.
func SpeakerProbe(run commandRunner, speaker *Speaker) Probe {
	device := SoundProbe(run)
	return func() (State, string) {
		if state, reason := device(); state != StateOK {
			return state, reason
		}
		if speaker == nil || !speaker.Available() {
			return StateDegraded, "no Piper voice model, announcements are silent"
		}
		return StateOK, ""
	}
}

// BootAnnouncement is what the unit says when it comes up, once the speaker exists.
// Short on purpose: it runs at every cold start, including at six in the morning.
const BootAnnouncement = "Borg online"

// AntennaHint tells the user how far to extend the whip for a band (build-notes.md:
// the antenna is a manual compromise, the mode switch retunes the tuner, not the
// hardware). Lengths come from the band table in the config, not from here.
func AntennaHint(band string, cm int) string {
	return fmt.Sprintf("Antenne für %s auf %d Zentimeter ausfahren", band, cm)
}

// waitForSound gives PipeWire a moment after boot before the first announcement: the
// user session and the USB card are not necessarily up when borgd is.
func waitForSound(run commandRunner, attempts int, delay time.Duration) bool {
	probe := SoundProbe(run)
	for i := 0; i < attempts; i++ {
		if state, _ := probe(); state == StateOK {
			return true
		}
		time.Sleep(delay)
	}
	return false
}
