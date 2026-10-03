"""Synthesize a short, original gift arrival chime without external samples."""

from pathlib import Path
import math
import struct
import wave


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets/effects/gift_spawn_candidate.wav"
RATE = 44100
DURATION = 1.35
NOTES = ((0.00, 523.25, 0.34, 0.37), (0.16, 659.25, 0.34, 0.34), (0.33, 783.99, 0.58, 0.33), (0.51, 1046.50, 0.70, 0.28))


def sample(time: float) -> float:
    value = 0.0
    for start, frequency, length, volume in NOTES:
        local = time - start
        if not 0 <= local < length:
            continue
        attack = min(1.0, local / 0.009)
        release = min(1.0, (length - local) / 0.12)
        envelope = attack * release * math.exp(-2.1 * local / length)
        # A soft bell-like upper partial gives the cue a hand-crafted toy quality.
        tone = math.sin(2 * math.pi * frequency * local)
        tone += 0.23 * math.sin(2 * math.pi * frequency * 2.01 * local)
        tone += 0.10 * math.sin(2 * math.pi * frequency * 3.93 * local)
        value += volume * envelope * tone
    return math.tanh(value * 0.88) * 0.75


def main() -> None:
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    pcm = bytearray()
    for frame in range(round(RATE * DURATION)):
        value = max(-1.0, min(1.0, sample(frame / RATE)))
        pcm.extend(struct.pack("<h", round(value * 32767)))
    with wave.open(str(OUTPUT), "wb") as writer:
        writer.setnchannels(1)
        writer.setsampwidth(2)
        writer.setframerate(RATE)
        writer.writeframes(pcm)
    print(f"Wrote {OUTPUT.relative_to(ROOT)}: {DURATION:.2f}s, mono 44.1kHz 16-bit PCM")


if __name__ == "__main__":
    main()
