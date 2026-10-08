"""Synthesize placeholder beacon-claim tension audio (loop, interrupt sting, rival-broken cue).

Original procedural audio, stdlib only, deterministic (fixed seed). Output is normalised
through tools/measure_audio.py with the project convention (-18 dBFS window RMS, -1 dBFS peak).
"""

from pathlib import Path
import importlib.util
import math
import random
import struct
import wave


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "assets/effects"
RATE = 44100
SEED = 114
TWO_PI = 2.0 * math.pi
TARGET_RMS_DB = -18.0
PEAK_CAP_DB = -1.0

LOOP_SECONDS = 8.0
BEAT_PERIOD = 1.0  # divides LOOP_SECONDS so the pulse is seamless
DRONE_HZ = (55.0, 82.5, 110.25)  # integer cycles in the 8 s loop (multiples of 1/8 Hz)
SHIMMER_HZ = (880.0, 1318.5, 1760.25, 2637.0)
STING_SECONDS = 1.0
BROKEN_SECONDS = 0.6


def thump(local: float, freq: float, decay: float) -> float:
    if local < 0.0:
        return 0.0
    return math.sin(TWO_PI * freq * local) * math.exp(-decay * local) * min(1.0, local / 0.004)


def loop_sample(t: float, noise: float) -> float:
    phase = t / LOOP_SECONDS
    drone = sum(math.sin(TWO_PI * f * t + i) * (0.5 / (i + 1)) for i, f in enumerate(DRONE_HZ))
    drone *= 0.75 + 0.25 * math.sin(TWO_PI * phase * 2.0)
    beat = t % BEAT_PERIOD
    pulse = thump(beat, 48.0, 14.0) + 0.7 * thump(beat - 0.27, 42.0, 16.0)
    # Swell is zero at both loop ends (sin^2), peaking mid-loop, so the shimmer rises then falls seamlessly.
    swell = math.sin(math.pi * phase) ** 2
    shimmer = sum(math.sin(TWO_PI * f * t + 1.7 * i) * 0.12 for i, f in enumerate(SHIMMER_HZ))
    shimmer *= swell * (0.6 + 0.4 * math.sin(TWO_PI * 6.0 * t))
    return drone * 0.55 + pulse * 0.9 + shimmer * 0.5 + noise * 0.02


def sting_sample(t: float, noise: float) -> float:
    cut = min(1.0, max(0.0, (STING_SECONDS - t) / 0.03))
    glide = 440.0 * math.exp(-1.6 * t)  # descending
    value = 0.0
    for detune in (1.0, 1.013, 0.987):
        value += math.sin(TWO_PI * glide * detune * t + 3.0 * math.sin(TWO_PI * 5.0 * t)) * 0.3
    value *= math.exp(-2.2 * t) * min(1.0, t / 0.005)
    value += 1.2 * thump(t, 60.0, 9.0)
    value += noise * 0.06 * math.exp(-30.0 * t)
    return math.tanh(value * 1.1) * cut


def broken_sample(t: float, noise: float) -> float:
    notes = ((0.00, 659.25), (0.10, 880.0), (0.20, 1318.5))
    value = 0.0
    for start, freq in notes:
        local = t - start
        if local < 0.0:
            continue
        env = min(1.0, local / 0.006) * math.exp(-4.5 * local)
        value += env * (math.sin(TWO_PI * freq * local) + 0.25 * math.sin(TWO_PI * freq * 2.0 * local)) * 0.4
    cut = min(1.0, max(0.0, (BROKEN_SECONDS - t) / 0.05))
    return math.tanh(value) * cut


def write_wav(path: Path, seconds: float, fn) -> None:
    rng = random.Random(SEED)
    pcm = bytearray()
    for frame in range(round(RATE * seconds)):
        value = max(-1.0, min(1.0, fn(frame / RATE, rng.uniform(-1.0, 1.0))))
        pcm.extend(struct.pack("<h", round(value * 32767)))
    with wave.open(str(path), "wb") as writer:
        writer.setnchannels(1)
        writer.setsampwidth(2)
        writer.setframerate(RATE)
        writer.writeframes(bytes(pcm))


def normalize(path: Path) -> None:
    spec = importlib.util.spec_from_file_location("measure_audio", ROOT / "tools/measure_audio.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.normalize_wav(path, TARGET_RMS_DB, PEAK_CAP_DB)


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for name, seconds, fn in (
        ("claim_tension_loop", LOOP_SECONDS, loop_sample),
        ("claim_interrupt_sting", STING_SECONDS, sting_sample),
        ("claim_rival_broken", BROKEN_SECONDS, broken_sample),
    ):
        path = OUT_DIR / f"{name}.wav"
        write_wav(path, seconds, fn)
        normalize(path)
        print(f"Wrote {path.relative_to(ROOT)}: {seconds:.2f}s, mono 44.1kHz 16-bit PCM")


if __name__ == "__main__":
    main()
