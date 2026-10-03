"""Synthesize an original, mathematically periodic low-key cosmic ambience."""

from pathlib import Path
import wave

import numpy as np


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets/effects/cosmic_presence_loop_candidate.wav"
RATE = 44100
DURATION = 12
COUNT = RATE * DURATION


def circular_air() -> np.ndarray:
    rng = np.random.default_rng(2503)
    bins = np.fft.rfftfreq(COUNT, 1 / RATE)
    spectrum = rng.normal(size=len(bins)) + 1j * rng.normal(size=len(bins))
    # Broad distant air, with little energy near the bass notes or above speech.
    shape = (bins / 260) ** 2 / (1 + (bins / 260) ** 2)
    shape *= 1 / (1 + (bins / 1050) ** 4)
    spectrum *= shape
    spectrum[0] = 0
    air = np.fft.irfft(spectrum, n=COUNT)
    return air / np.sqrt(np.mean(air * air))


def main() -> None:
    t = np.arange(COUNT, dtype=np.float64) / RATE
    cycle = 2 * np.pi * t / DURATION
    slow = 0.75 + 0.17 * np.sin(cycle + 0.6) + 0.08 * np.sin(2 * cycle - 0.3)
    body = (
        0.085 * np.sin(2 * np.pi * 48 * t + 0.2)
        + 0.044 * np.sin(2 * np.pi * 73 * t + 1.2)
        + 0.026 * np.sin(2 * np.pi * 96 * t + 2.0)
    ) * slow
    distant_pulse = 0.024 * np.sin(2 * np.pi * 36 * t + 0.7) * (0.5 + 0.5 * np.cos(3 * cycle)) ** 6
    air = circular_air() * (0.012 + 0.004 * np.cos(cycle - 0.5))
    signal = body + distant_pulse + air
    peak = np.max(np.abs(signal))
    if peak >= 0.8:
        raise ValueError(f"Unexpected peak {peak:.3f}")
    pcm = np.rint(np.clip(signal, -1, 1) * 32767).astype("<i2")
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUTPUT), "wb") as writer:
        writer.setnchannels(1)
        writer.setsampwidth(2)
        writer.setframerate(RATE)
        writer.writeframes(pcm.tobytes())
    seam = abs(int(pcm[0]) - int(pcm[-1])) / 32768
    print(f"Wrote {OUTPUT.relative_to(ROOT)}: {DURATION}s mono 44.1kHz PCM; peak={peak:.3f}, seam={seam:.5f}")


if __name__ == "__main__":
    main()
