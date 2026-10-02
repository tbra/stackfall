#!/usr/bin/env python3
"""Render four original Stackfall special-effect cues, with no source samples.

Run: python tools/generate_special_sfx.py
Produces deterministic 44.1 kHz mono 16-bit PCM WAV files matching the
existing AudioConfig filenames. This creates assets; it changes no hooks.
"""

from pathlib import Path
import wave

import numpy as np


RATE = 44100
DEST = Path(__file__).resolve().parents[1] / "assets" / "effects"


def clock(seconds: float) -> np.ndarray:
    return np.arange(round(seconds * RATE), dtype=np.float64) / RATE


def phase(frequency: np.ndarray) -> np.ndarray:
    return np.cumsum(frequency) * (2.0 * np.pi / RATE)


def smooth(noise: np.ndarray, width: int) -> np.ndarray:
    # A box filter is predictable across NumPy versions and gives the
    # low, tactile noise body used throughout this pack.
    return np.convolve(noise, np.ones(width) / width, mode="same")


def bump(t: np.ndarray, center: float, width: float) -> np.ndarray:
    return np.exp(-((t - center) / width) ** 2)


def bomb() -> np.ndarray:
    t = clock(1.05)
    rng = np.random.default_rng(4201)
    noise = rng.standard_normal(t.size)
    attack = np.exp(-t * 44.0)
    low = smooth(noise, 80)
    air = smooth(noise, 5) - smooth(noise, 32)
    falling = np.sin(phase(125.0 + 105.0 * np.exp(-t * 10.0)))
    body = (1.0 - np.exp(-t * 220.0)) * np.exp(-t * 4.3)
    debris = sum(0.16 * bump(t, at, 0.014) * smooth(noise, 3) for at in (0.13, 0.25, 0.37))
    return 0.40 * attack * noise + body * (1.4 * low + 0.40 * falling + 0.17 * air) + debris


def volcano() -> np.ndarray:
    t = clock(1.62)
    rng = np.random.default_rng(4202)
    noise = rng.standard_normal(t.size)
    swell = 0.78 * bump(t, 0.43, 0.30) + bump(t, 0.97, 0.38)
    fade = (1.0 - np.exp(-t * 60.0)) * (1.0 - np.exp(-(1.62 - t) * 14.0))
    rumble = smooth(noise, 95)
    sizzle = noise - smooth(noise, 7)
    lava = np.sin(phase(70.0 + 22.0 * np.sin(2.0 * np.pi * 2.7 * t)))
    pops = sum(0.28 * bump(t, at, 0.018) * sizzle for at in (0.19, 0.54, 0.68, 1.03, 1.25))
    return fade * swell * (1.85 * rumble + 0.19 * sizzle + 0.23 * lava) + pops


def quake() -> np.ndarray:
    t = clock(1.88)
    rng = np.random.default_rng(4203)
    noise = rng.standard_normal(t.size)
    waves = bump(t, 0.24, 0.18) + 0.85 * bump(t, 0.76, 0.22) + 0.70 * bump(t, 1.28, 0.25)
    low = smooth(noise, 145)
    grit = smooth(noise, 11)
    sub = np.sin(phase(43.0 + 8.0 * np.sin(2.0 * np.pi * 0.9 * t)))
    end = 1.0 - np.exp(-(1.88 - t) * 12.0)
    return waves * end * (2.2 * low + 0.33 * grit + 0.22 * sub)


def propeller() -> np.ndarray:
    t = clock(1.37)
    rng = np.random.default_rng(4204)
    noise = rng.standard_normal(t.size)
    spin_hz = 6.0 + 23.0 * (1.0 - np.exp(-t * 3.8))
    blade_phase = phase(spin_hz)
    chop = np.maximum(np.sin(blade_phase), 0.0) ** 6
    wind = smooth(noise, 17) + 0.22 * (noise - smooth(noise, 6))
    motor = np.sin(phase(115.0 + 185.0 * (1.0 - np.exp(-t * 2.9))))
    fade_in = 1.0 - np.exp(-t * 13.0)
    fade_out = 1.0 - np.exp(-(1.37 - t) * 13.0)
    return fade_in * fade_out * (0.58 * chop * wind + 0.27 * motor + 0.10 * wind)


def save(filename: str, samples: np.ndarray) -> None:
    # Match the current bundled effects' loudest 300 ms window target. Keep
    # at least 1 dB peak headroom; the cap wins for very spiky cues.
    window = round(RATE * 0.3)
    energy = np.cumsum(np.r_[0.0, samples * samples])
    loudest = np.sqrt(np.max((energy[window:] - energy[:-window]) / window))
    gain = min(10 ** (-16 / 20) / loudest, 10 ** (-1 / 20) / np.max(np.abs(samples)))
    # Short edge ramps so no cue starts or stops on a non-zero sample (click).
    ramp_in = min(round(0.001 * RATE), samples.size)
    ramp_out = min(round(0.008 * RATE), samples.size)
    samples = samples.copy()
    samples[:ramp_in] *= np.linspace(0.0, 1.0, ramp_in)
    samples[-ramp_out:] *= np.linspace(1.0, 0.0, ramp_out)
    pcm = np.rint(np.clip(samples * gain, -1, 1) * 32767).astype("<i2")
    with wave.open(str(DEST / filename), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(pcm.tobytes())
    print(f"{filename}: {samples.size / RATE:.2f}s")


def main() -> None:
    DEST.mkdir(parents=True, exist_ok=True)
    for name, synth in (("bomb.wav", bomb), ("volcano.wav", volcano),
                        ("quake2.wav", quake), ("propeller.wav", propeller)):
        save(name, synth())


if __name__ == "__main__":
    main()
