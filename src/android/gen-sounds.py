#!/usr/bin/env python3
"""Generate the app's R2D2-style UI sounds as WAV assets.

Synthesized from scratch (sine chirps, ring modulation, noise bursts) so the
set is license-free, internally consistent and reproducible: same seed, same
bytes. Sound grammar mirrors the haptics grammar (see src/android/README.md);
any file can be replaced by dropping a same-named WAV into the output dir.
"""

import argparse
import math
import random
import struct
import sys
import wave
from pathlib import Path

RATE = 44100
PEAK = 0.7  # headroom; the app plays these at reduced volume anyway


def env(i: int, n: int, attack_s: float = 0.005, decay_pow: float = 2.2) -> float:
    """Fast attack, exponential-ish decay — the 'droid blip' envelope."""
    t = i / RATE
    a = min(1.0, t / attack_s)
    d = (1.0 - i / n) ** decay_pow
    return a * d


def chirp(dur: float, f0: float, f1: float, *, ring: float = 0.0,
          vibrato: float = 0.0, decay_pow: float = 2.2) -> list[float]:
    """One sine sweep f0 -> f1 with optional ring modulation and vibrato."""
    n = int(dur * RATE)
    out: list[float] = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        frac = i / n
        f = f0 + (f1 - f0) * frac
        if vibrato:
            f *= 1.0 + 0.04 * math.sin(2.0 * math.pi * vibrato * t)
        phase += 2.0 * math.pi * f / RATE
        s = math.sin(phase)
        if ring:
            s *= 1.0 + 0.35 * math.sin(2.0 * math.pi * ring * t)
        out.append(s * env(i, n, decay_pow=decay_pow))
    return out


def click(dur: float, rng: random.Random) -> list[float]:
    """Short filtered-noise burst (walkie-talkie key click)."""
    n = int(dur * RATE)
    out: list[float] = []
    prev = 0.0
    for i in range(n):
        prev = 0.6 * prev + 0.4 * rng.uniform(-1.0, 1.0)  # crude low-pass
        out.append(prev * env(i, n, attack_s=0.001, decay_pow=3.0))
    return out


def silence(dur: float) -> list[float]:
    return [0.0] * int(dur * RATE)


def write_wav(path: Path, samples: list[float]) -> None:
    peak = max((abs(s) for s in samples), default=1.0)
    scale = PEAK / peak if peak > 0 else 0.0
    frames = b"".join(
        struct.pack("<h", int(max(-1.0, min(1.0, s * scale)) * 32767))
        for s in samples
    )
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(frames)
    print(f"{path}  {len(samples) / RATE * 1000:5.0f} ms", file=sys.stderr)


def build_set(out: Path, seed: int) -> None:
    rng = random.Random(seed)
    out.mkdir(parents=True, exist_ok=True)

    # Selection blips: single short chirp, alternating direction/register.
    for i in range(5):
        f0 = rng.uniform(900, 1600)
        f1 = f0 * rng.choice((1.35, 0.72))
        write_wav(out / f"blip-{i + 1}.wav",
                  chirp(rng.uniform(0.055, 0.09), f0, f1, ring=rng.uniform(0, 60)))

    # Confirm chirps (state echo): two quick ascending beeps — "happy droid".
    for i in range(3):
        base = rng.uniform(1000, 1400)
        s = chirp(0.07, base, base * 1.25, ring=40)
        s += silence(0.03)
        s += chirp(0.09, base * 1.4, base * 1.9, ring=40)
        write_wav(out / f"chirp-{i + 1}.wav", s)

    # SENTRY power-up / power-down: longer sweeps with wobble.
    write_wav(out / "power-up.wav",
              chirp(0.35, 320, 1250, vibrato=9, ring=30, decay_pow=1.4))
    write_wav(out / "power-down.wav",
              chirp(0.35, 1250, 300, vibrato=9, ring=30, decay_pow=1.4))

    # Push-to-talk: key click down, two-tone "roger" on send.
    write_wav(out / "ptt-click.wav", click(0.045, rng))
    roger = chirp(0.08, 1100, 1100, decay_pow=1.8)
    roger += silence(0.02)
    roger += chirp(0.10, 1500, 1500, decay_pow=1.8)
    write_wav(out / "ptt-roger.wav", roger)

    # Sad blips (errors): descending glissando with tremolo — dejected droid.
    for i in range(2):
        f0 = rng.uniform(900, 1100)
        write_wav(out / f"sad-{i + 1}.wav",
                  chirp(0.32, f0, f0 * 0.45, vibrato=12, ring=25, decay_pow=1.6))

    # Easter-egg twitter: a burst of excited babble (6-9 random chirplets).
    for i in range(2):
        s: list[float] = []
        for _ in range(rng.randint(6, 9)):
            f0 = rng.uniform(800, 2200)
            f1 = f0 * rng.choice((1.5, 0.65, 1.25))
            s += chirp(rng.uniform(0.05, 0.1), f0, f1, ring=rng.uniform(20, 70))
            s += silence(rng.uniform(0.01, 0.04))
        write_wav(out / f"twitter-{i + 1}.wav", s)


def main() -> int:
    parser = argparse.ArgumentParser(description="generate the UI sound set")
    parser.add_argument("--out", type=Path,
                        default=Path(__file__).parent / "app/assets/audio/ui",
                        help="output directory (default: app/assets/audio/ui)")
    parser.add_argument("--seed", type=int, default=42,
                        help="RNG seed; same seed reproduces the same set")
    args = parser.parse_args()
    build_set(args.out, args.seed)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
