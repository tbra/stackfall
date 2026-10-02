#!/usr/bin/env python3
"""Render three original Stackfall effect cues from deterministic synthesis.

Usage: python tools/generate_sfx_cues.py
No recordings, samples, or network dependencies are used. The output is
44.1 kHz mono 16-bit PCM for the existing AudioConfig filenames.
"""

from pathlib import Path
import wave

import numpy as np


RATE = 44100
ROOT = Path(__file__).resolve().parents[1] / "assets" / "effects"
RNG = np.random.default_rng(20261002)


def timebase(seconds: float) -> np.ndarray:
    return np.arange(round(RATE * seconds), dtype=np.float64) / RATE


def phase_of(frequency: np.ndarray) -> np.ndarray:
    return 2.0 * np.pi * np.cumsum(frequency) / RATE


def lowpass(signal: np.ndarray, width: int) -> np.ndarray:
    kernel = np.ones(width, dtype=np.float64) / width
    return np.convolve(signal, kernel, mode="same")


def boing() -> np.ndarray:
    t = timebase(0.72)
    # A stretched spring: swift descending bend, small upward rebound,
    # and a ceramic click at the point of contact.
    frequency = 225.0 + 415.0 * np.exp(-t * 15.0) + 30.0 * np.sin(2 * np.pi * 8.0 * t) * np.exp(-t * 7.0)
    phase = phase_of(frequency)
    body = np.sin(phase) + 0.28 * np.sin(2 * phase) + 0.10 * np.sin(3 * phase)
    envelope = (1.0 - np.exp(-t * 180.0)) * np.exp(-t * 6.5)
    click = lowpass(RNG.standard_normal(len(t)), 7) * np.exp(-t * 95.0)
    return 0.86 * envelope * body + 0.28 * click


def creak() -> np.ndarray:
    t = timebase(1.15)
    # Stick-slip friction: discrete slips whose rate sweeps through two rubs
    # (slow-fast-slow), each slip ringing a few damped wood resonances. The
    # audible pulse train is what makes a creak read as wood, not a hum.
    rate = 22.0 + 46.0 * np.exp(-((t - 0.30) / 0.13) ** 2) + 34.0 * np.exp(-((t - 0.78) / 0.16) ** 2)
    jitter = 1.0 + 0.18 * lowpass(RNG.standard_normal(len(t)), 400) * 20.0
    slip_phase = np.cumsum(rate * np.clip(jitter, 0.6, 1.4)) / RATE
    slips = np.zeros(len(t))
    slip_at = np.flatnonzero(np.diff(np.floor(slip_phase)) > 0) + 1
    slips[slip_at] = 0.55 + 0.45 * RNG.random(slip_at.size)
    k = timebase(0.045)
    ring = (np.sin(2 * np.pi * 185.0 * k) * np.exp(-k * 70.0)
            + 0.55 * np.sin(2 * np.pi * 430.0 * k) * np.exp(-k * 110.0)
            + 0.30 * np.sin(2 * np.pi * 1150.0 * k) * np.exp(-k * 190.0))
    body = np.convolve(slips, ring)[: len(t)]
    rub = np.exp(-((t - 0.30) / 0.20) ** 2) + 0.8 * np.exp(-((t - 0.78) / 0.22) ** 2)
    grain = lowpass(RNG.standard_normal(len(t)), 9) * 0.08
    return rub * (body + grain)


def rocket() -> np.ndarray:
    t = timebase(1.28)
    rise = np.clip(t / 0.40, 0.0, 1.0)
    tail = np.clip((1.28 - t) / 0.42, 0.0, 1.0)
    envelope = np.sin(0.5 * np.pi * rise) * np.sin(0.5 * np.pi * tail)
    noise = RNG.standard_normal(len(t))
    rumble = lowpass(noise, 90)
    hiss = noise - lowpass(noise, 8)
    frequency = 78.0 + 480.0 * (t / 1.28) ** 1.7
    phase = phase_of(frequency)
    whistle = np.sin(phase) + 0.17 * np.sin(2 * phase)
    return envelope * (1.9 * rumble + 0.12 * hiss + 0.34 * whistle)


def write_cue(name: str, samples: np.ndarray) -> None:
    # Match the bundled effects' approximate -16 dBFS 300 ms window RMS.
    # A -1 dBFS peak cap preserves transient headroom if that target cannot
    # be reached without clipping.
    window = round(0.3 * RATE)
    square = samples * samples
    energy = np.cumsum(np.r_[0.0, square])
    max_window_rms = np.sqrt(np.max((energy[window:] - energy[:-window]) / window))
    target = 10.0 ** (-16.0 / 20.0)
    peak_cap = 10.0 ** (-1.0 / 20.0)
    gain = min(target / max_window_rms, peak_cap / np.max(np.abs(samples)))
    # Short edge ramps so no cue starts or stops on a non-zero sample (click).
    ramp_in = min(round(0.001 * RATE), len(samples))
    ramp_out = min(round(0.008 * RATE), len(samples))
    samples = samples.copy()
    samples[:ramp_in] *= np.linspace(0.0, 1.0, ramp_in)
    samples[-ramp_out:] *= np.linspace(1.0, 0.0, ramp_out)
    pcm = np.rint(np.clip(samples * gain, -1.0, 1.0) * 32767.0).astype("<i2")
    path = ROOT / name
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(pcm.tobytes())
    print(f"{path.relative_to(ROOT.parent.parent)}: {len(samples) / RATE:.2f}s")


def main() -> None:
    ROOT.mkdir(parents=True, exist_ok=True)
    write_cue("boing.wav", boing())
    write_cue("creak.wav", creak())
    write_cue("rocket.wav", rocket())


if __name__ == "__main__":
    main()
