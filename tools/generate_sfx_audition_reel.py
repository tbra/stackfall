"""Build an unprocessed listening reel from the bundled effect WAV files."""

from __future__ import annotations

import hashlib
from pathlib import Path
import wave


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs/audio_review"
NAMES = ("boing", "creak", "rocket", "bomb", "volcano", "quake2", "propeller")
GAP_SECONDS = 0.75


def timestamp(frames: int, rate: int) -> str:
    seconds = frames / rate
    minutes, remainder = divmod(seconds, 60)
    return f"{int(minutes):02d}:{remainder:06.3f}"


def main() -> None:
    clips = []
    expected_format = None
    for name in NAMES:
        source = ROOT / "assets/effects" / f"{name}.wav"
        with wave.open(str(source), "rb") as reader:
            audio_format = (reader.getnchannels(), reader.getsampwidth(), reader.getframerate(), reader.getcomptype())
            if expected_format is None:
                expected_format = audio_format
            if audio_format != expected_format:
                raise ValueError(f"Incompatible WAV format: {source}")
            frames = reader.readframes(reader.getnframes())
            clips.append((source, reader.getnframes(), frames))

    channels, sample_width, rate, _ = expected_format
    gap_frames = round(rate * GAP_SECONDS)
    silence = bytes(gap_frames * channels * sample_width)
    OUT.mkdir(parents=True, exist_ok=True)
    reel = OUT / "sfx_audition_reel.wav"
    rows = []
    cursor = 0
    with wave.open(str(reel), "wb") as writer:
        writer.setnchannels(channels)
        writer.setsampwidth(sample_width)
        writer.setframerate(rate)
        for index, (source, frame_count, pcm) in enumerate(clips, start=1):
            start = cursor
            writer.writeframes(pcm)
            cursor += frame_count
            digest = hashlib.sha256(pcm).hexdigest()
            rows.append((index, source.relative_to(ROOT).as_posix(), timestamp(start, rate), timestamp(cursor, rate), digest))
            if index < len(clips):
                writer.writeframes(silence)
                cursor += gap_frames

    with wave.open(str(reel), "rb") as reader:
        reel_pcm = reader.readframes(reader.getnframes())
    offset = 0
    for index, (_, frame_count, pcm) in enumerate(clips):
        byte_count = frame_count * channels * sample_width
        if reel_pcm[offset : offset + byte_count] != pcm:
            raise AssertionError(f"Clip {index + 1} differs from source PCM")
        offset += byte_count
        if index < len(clips) - 1:
            if reel_pcm[offset : offset + len(silence)] != silence:
                raise AssertionError(f"Gap after clip {index + 1} is not silent")
            offset += len(silence)
    if offset != len(reel_pcm):
        raise AssertionError("Unexpected audio after final clip")

    lines = [
        "# SFX audition reel",
        "",
        "Listen to [sfx_audition_reel.wav](sfx_audition_reel.wav) in the order below. Each cue is copied byte for byte from its source WAV; only 0.75 seconds of digital silence is added between cues. No gain, compression, fades, or resampling are applied.",
        "",
        f"Format: {channels} channel, {rate} Hz, {sample_width * 8} bit PCM. Total duration: {timestamp(cursor, rate)}.",
        "",
        "| # | Source cue | Start | End | Source PCM SHA-256 |",
        "| --- | --- | --- | --- | --- |",
    ]
    lines.extend(f"| {number} | `{source}` | {start} | {end} | `{digest}` |" for number, source, start, end, digest in rows)
    lines.extend([
        "",
        "## Listening notes",
        "",
        "Check the attack, tail, loudness balance, and whether each cue reads as its intended event at normal gameplay volume. In particular, audition boing and creak with a gift claim; the special rocket, bomb, volcano, quake, and propeller cues are candidates awaiting live wiring. Log any cue requiring revision in Beads before integration.",
        "",
        "This sheet verifies digital integrity only. A person still needs to listen to the WAV and judge the sound.",
        "",
    ])
    (OUT / "SFX_AUDITION.md").write_text("\n".join(lines), encoding="utf-8")
    print(f"Wrote {reel.relative_to(ROOT)} ({timestamp(cursor, rate)}) and timestamp sheet; all seven PCM segments and six silence gaps verified.")


if __name__ == "__main__":
    main()
