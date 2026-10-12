#!/usr/bin/env python3
"""Render original replacements for the menu hover/select cues and the block drop cue.

Run: python tools/generate_core_cues.py
Writes deterministic 44.1 kHz mono 16-bit PCM WAVs to assets/effects, named by
AudioConfig hover_file / click_file / drop_file (Bontago-eq0). No samples are used.

- ui_hover.wav: a quiet, very short D6 tick; replaces button_hover_pcm.wav,
  which started on a non-zero sample (a click of its own).
- ui_select.wav: a soft rising D5 -> A5 pluck, the same tactile family as the
  lobby cues (tools/generate_lobby_ui_cues.py); replaces select.wav.
- block_release.wav: a short woody tock built from quickly damped inharmonic
  body modes over a filtered-noise knock. It replaces block_placed.wav, whose
  sustained ~1 kHz -> 516 Hz tone read as a sharp, off-key note over the music.
"""

from pathlib import Path
import wave

import numpy as np


RATE = 44100
DEST = Path(__file__).resolve().parents[1] / "assets" / "effects"


def clock(seconds: float) -> np.ndarray:
    return np.arange(round(seconds * RATE), dtype=np.float64) / RATE


def band_noise(rng: np.random.Generator, n: int, low_hz: float, high_hz: float) -> np.ndarray:
    # White noise shaped in the frequency domain to a soft low/high band.
    f = np.fft.rfftfreq(n, 1.0 / RATE)
    response = (1.0 - np.exp(-(f / low_hz) ** 4)) * np.exp(-(f / high_hz) ** 4)
    noise = np.fft.irfft(np.fft.rfft(rng.standard_normal(n)) * response, n)
    return noise / max(float(np.std(noise)), 1e-9)


def pluck(rng: np.random.Generator, hz: float, seconds: float, decay_s: float) -> np.ndarray:
    # Damped body tone (slight upper partials) with a 3 ms noise attack.
    t = clock(seconds)
    ph = 2.0 * np.pi * hz * t
    tonal = 0.6 * np.sin(ph) + 0.18 * np.sin(2.0 * ph + 0.2) + 0.06 * np.sin(3.01 * ph + 0.4)
    attack = 0.22 * band_noise(rng, t.size, 900.0, 6000.0) * np.exp(-t / 0.003)
    return tonal * np.exp(-t / decay_s) + attack


def place(total_s: float, parts) -> np.ndarray:
    out = np.zeros(round(total_s * RATE))
    for start_s, part in parts:
        i = round(start_s * RATE)
        out[i:i + part.size] += part[:out.size - i]
    return out


def ui_hover() -> np.ndarray:
    rng = np.random.default_rng(4301)
    return pluck(rng, 1174.66, 0.040, 0.007)


def ui_select() -> np.ndarray:
    rng = np.random.default_rng(4302)
    return place(0.16, ((0.0, pluck(rng, 587.33, 0.10, 0.025)),
                        (0.045, pluck(rng, 880.0, 0.115, 0.030))))


def block_release() -> np.ndarray:
    t = clock(0.16)
    rng = np.random.default_rng(4303)
    modes = ((210.0, 1.0, 0.030), (447.0, 0.55, 0.018), (731.0, 0.30, 0.011), (1190.0, 0.12, 0.006))
    body = sum(a * np.sin(2.0 * np.pi * f * t + 0.5 * k) * np.exp(-t / d) for k, (f, a, d) in enumerate(modes))
    knock = band_noise(rng, t.size, 250.0, 2600.0) * np.exp(-t / 0.006)
    return 0.8 * body + 0.45 * knock


def save(filename: str, samples: np.ndarray, peak_dbfs: float = None) -> None:
    # Gameplay cues match the bundled effects: loudest 300 ms (or the whole
    # cue when shorter) at -16 dBFS RMS, peak capped at -1 dBFS. UI cues take
    # an explicit peak like the lobby cue family.
    samples = samples - samples.mean()
    if peak_dbfs is None:
        window = min(round(RATE * 0.3), samples.size)
        energy = np.cumsum(np.r_[0.0, samples * samples])
        loudest = np.sqrt(np.max((energy[window:] - energy[:-window]) / window))
        gain = min(10 ** (-16 / 20) / loudest, 10 ** (-1 / 20) / np.max(np.abs(samples)))
    else:
        gain = 10 ** (peak_dbfs / 20) / np.max(np.abs(samples))
    # Short edge ramps so no cue starts or stops on a non-zero sample (click).
    ramp_in = min(round(0.0008 * RATE), samples.size)
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
    print(f"{filename}: {samples.size / RATE:.3f}s")


def main() -> None:
    DEST.mkdir(parents=True, exist_ok=True)
    save("ui_hover.wav", ui_hover(), peak_dbfs=-9.0)
    save("ui_select.wav", ui_select(), peak_dbfs=-6.0)
    save("block_release.wav", block_release())


if __name__ == "__main__":
    main()
