#!/usr/bin/env python3
"""Measure (and optionally normalise) Stackfall audio loudness. Stdlib only.

  python tools/measure_audio.py [paths...]            # table: peak / RMS / short-window RMS
  python tools/measure_audio.py --normalize --target-rms -18 assets/effects/*.wav

Measures .wav (PCM 8/16/24/32-bit and 32/64-bit float). .ogg/.mp3 are decoded
through ffmpeg when it is on PATH, otherwise reported as "skipped".
Normalisation rescales the PCM (8/16/24/32-bit, float) in place (same format/rate/channels) so the
loudest WINDOW_S-second RMS window hits --target-rms, then caps the sample
peak at --peak-cap. Originals stay recoverable through git.
"""
import argparse, array, math, shutil, struct, subprocess, sys, wave
from pathlib import Path

WINDOW_S = 0.3
DEFAULT_PATHS = ["assets/effects", "assets/ui", "assets/music"]
AUDIO_EXT = {".wav", ".mp3", ".ogg"}


def db(x):
    return -math.inf if x <= 0 else 20.0 * math.log10(x)


def read_wav_float(path):
    """Return (channels, rate, [float samples interleaved in -1..1], fmt info)."""
    raw = Path(path).read_bytes()
    # Parse manually so WAVE_FORMAT_IEEE_FLOAT (3) and EXTENSIBLE work.
    if raw[:4] != b"RIFF" or raw[8:12] != b"WAVE":
        raise ValueError("not RIFF/WAVE")
    pos, fmt, data = 12, None, None
    while pos + 8 <= len(raw):
        cid, size = raw[pos:pos + 4], struct.unpack("<I", raw[pos + 4:pos + 8])[0]
        body = raw[pos + 8:pos + 8 + size]
        if cid == b"fmt ":
            fmt = struct.unpack("<HHIIHH", body[:16])
            if fmt[0] == 0xFFFE and len(body) >= 26:
                fmt = (struct.unpack("<H", body[24:26])[0],) + fmt[1:]
        elif cid == b"data":
            data = (pos + 8, size)
        pos += 8 + size + (size & 1)
    if fmt is None or data is None:
        raise ValueError("missing fmt/data")
    tag, ch, rate, _, _, bits = fmt
    body = raw[data[0]:data[0] + data[1]]
    if tag == 1:
        if bits == 8:
            s = [(b - 128) / 128.0 for b in body]
        elif bits == 16:
            a = array.array("h"); a.frombytes(body[:len(body) // 2 * 2]); s = [v / 32768.0 for v in a]
        elif bits == 24:
            n = len(body) // 3
            s = [int.from_bytes(body[i * 3:i * 3 + 3], "little", signed=True) / 8388608.0 for i in range(n)]
        elif bits == 32:
            a = array.array("i"); a.frombytes(body[:len(body) // 4 * 4]); s = [v / 2147483648.0 for v in a]
        else:
            raise ValueError("unsupported PCM bits %d" % bits)
    elif tag == 3:
        a = array.array("f" if bits == 32 else "d"); a.frombytes(body[:len(body) // (bits // 8) * (bits // 8)]); s = list(a)
    else:
        raise ValueError("unsupported wav format tag %d" % tag)
    return ch, rate, s, (tag, bits, raw, data)


def decode_ffmpeg(path):
    out = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le", "-ac", "1", "-ar", "44100", "-"],
                         capture_output=True, check=True).stdout
    a = array.array("f"); a.frombytes(out[:len(out) // 4 * 4])
    return 1, 44100, list(a)


def stats(ch, rate, s):
    if not s:
        return None
    peak = max(max(s), -min(s))
    rms = math.sqrt(sum(v * v for v in s) / len(s))
    frames = len(s) // ch
    win = max(1, int(WINDOW_S * rate)) * ch
    if len(s) <= win:
        wmax = rms
    else:
        hop = max(1, win // 4)
        wmax = 0.0
        sq = [v * v for v in s]
        acc = sum(sq[:win])
        wmax = acc
        i = 0
        while i + hop + win <= len(sq):
            acc += sum(sq[i + win:i + win + hop]) - sum(sq[i:i + hop])
            wmax = max(wmax, acc)
            i += hop
        wmax = math.sqrt(max(wmax, 0.0) / win)
    return peak, rms, wmax, frames / rate


def normalize_wav(path, target_rms_db, peak_cap_db):
    ch, rate, s, (tag, bits, raw, data) = read_wav_float(path)
    st = stats(ch, rate, s)
    if st is None or st[2] <= 0:
        return None
    peak, _, wmax, _ = st
    gain = 10 ** (target_rms_db / 20.0) / wmax
    gain = min(gain, 10 ** (peak_cap_db / 20.0) / peak)
    off, size = data
    body = raw[off:off + size]
    if tag == 1 and bits == 16:
        a = array.array("h"); a.frombytes(body[:len(body) // 2 * 2])
        out = array.array("h", [max(-32768, min(32767, round(v * gain))) for v in a])
    elif tag == 1 and bits == 8:
        out = bytes(max(0, min(255, round((b - 128) * gain + 128))) for b in body)
    elif tag == 1 and bits == 24:
        n = len(body) // 3
        out = bytearray()
        for i in range(n):
            v = int.from_bytes(body[i * 3:i * 3 + 3], "little", signed=True)
            v = max(-8388608, min(8388607, round(v * gain)))
            out += v.to_bytes(3, "little", signed=True)
    elif tag == 1 and bits == 32:
        a = array.array("i"); a.frombytes(body[:len(body) // 4 * 4])
        out = array.array("i", [max(-2147483648, min(2147483647, round(v * gain))) for v in a])
    elif tag == 3 and bits in (32, 64):
        a = array.array("f" if bits == 32 else "d"); a.frombytes(body[:len(body) // (bits // 8) * (bits // 8)])
        out = array.array(a.typecode, [v * gain for v in a])
    else:
        raise ValueError("unsupported format for normalise (%s)" % path)
    nb = out.tobytes() if isinstance(out, array.array) else bytes(out)
    new = raw[:off] + nb + raw[off + len(nb):]
    Path(path).write_bytes(new)
    return 20 * math.log10(gain)


def collect(paths):
    files = []
    for p in paths:
        p = Path(p)
        if p.is_dir():
            files += sorted(f for f in p.rglob("*") if f.suffix.lower() in AUDIO_EXT)
        elif p.exists():
            files.append(p)
    return files


def measure(path):
    ext = path.suffix.lower()
    if ext == ".wav":
        ch, rate, s, _ = read_wav_float(path)
    elif shutil.which("ffmpeg"):
        ch, rate, s = decode_ffmpeg(path)
    else:
        return None
    return stats(ch, rate, s)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="*")
    ap.add_argument("--normalize", action="store_true")
    ap.add_argument("--target-rms", type=float, default=-18.0, help="dBFS short-window (%.1fs) max RMS" % WINDOW_S)
    ap.add_argument("--peak-cap", type=float, default=-1.0, help="dBFS sample-peak ceiling")
    args = ap.parse_args()
    files = collect(args.paths or DEFAULT_PATHS)
    print("%-44s %8s %8s %9s %7s" % ("file", "peak", "rms", "win-rms", "dur_s"))
    for f in files:
        try:
            if args.normalize:
                if f.suffix.lower() != ".wav":
                    print("%-44s skipped (not .wav)" % f.as_posix()); continue
                g = normalize_wav(f, args.target_rms, args.peak_cap)
                note = "  gain %+.1f dB" % g if g is not None else "  silent"
            else:
                note = ""
            st = measure(f)
        except Exception as e:  # noqa
            print("%-44s error: %s" % (f.as_posix(), e)); continue
        if st is None:
            print("%-44s skipped (no ffmpeg)" % f.as_posix()); continue
        print("%-44s %8.1f %8.1f %9.1f %7.2f%s" % (f.as_posix(), db(st[0]), db(st[1]), db(st[2]), st[3], note))


if __name__ == "__main__":
    sys.exit(main())
