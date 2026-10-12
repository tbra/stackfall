#!/usr/bin/env python3
"""Render the original Stackfall special-effect cues, with no source samples.

Run: python tools/generate_special_sfx.py
Produces deterministic 44.1 kHz mono 16-bit PCM WAV files named by
AudioConfig.special_cue_files. The first four (bomb, volcano, quake2,
propeller) are the 2026-10-02 pack and render byte-identically; the rest were
added for Bontago-eq0 (one activation cue per special).
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


def resonate(signal: np.ndarray, center, q: float) -> np.ndarray:
    # Two-pole band-pass (RBJ, constant 0 dB peak). `center` may be a scalar
    # or a per-sample array, so noise can take a moving pitch.
    centers = np.broadcast_to(np.asarray(center, dtype=np.float64), signal.shape)
    w = 2.0 * np.pi * np.clip(centers, 20.0, RATE * 0.45) / RATE
    alpha = np.sin(w) / (2.0 * q)
    a0 = 1.0 + alpha
    b0 = (alpha / a0).tolist()
    a1 = (-2.0 * np.cos(w) / a0).tolist()
    a2 = ((1.0 - alpha) / a0).tolist()
    x = signal.tolist()
    out = [0.0] * len(x)
    x1 = x2 = y1 = y2 = 0.0
    for i, x0 in enumerate(x):
        y0 = b0[i] * (x0 - x2) - a1[i] * y1 - a2[i] * y2
        out[i] = y0
        x2, x1, y2, y1 = x1, x0, y1, y0
    return np.array(out)


def since(t: np.ndarray, at: float):
    # Local time after `at` (0 before it) and the matching on/off mask.
    return np.maximum(t - at, 0.0), (t >= at).astype(np.float64)


def chirp(t: np.ndarray, at: float, f0: float, f1: float, dur: float, decay: float) -> np.ndarray:
    # A short sine whose pitch glides f0 -> f1 over `dur`, starting at `at`.
    local, on = since(t, at)
    freq = f0 + (f1 - f0) * np.clip(local / dur, 0.0, 1.0)
    return on * np.sin(phase(freq * on)) * np.exp(-local * decay) * (1.0 - np.exp(-local * 900.0))


def ticks(t: np.ndarray, times, width: float, source: np.ndarray, gains=None) -> np.ndarray:
    # Very short bursts of `source` centred on each time (crackle, rattle, sparks).
    out = np.zeros_like(t)
    for i, at in enumerate(times):
        out += (1.0 if gains is None else gains[i]) * bump(t, at, width)
    return out * source


def anvil() -> np.ndarray:
    # Struck steel: inharmonic bar partials (one pair detuned so it beats)
    # over a heavy landing thump.
    t = clock(1.40)
    rng = np.random.default_rng(4205)
    noise = rng.standard_normal(t.size)
    partials = ((196.0, 1.0, 3.0), (197.6, 0.5, 3.0), (523.0, 0.55, 4.4),
                (871.0, 0.40, 5.6), (1394.0, 0.28, 7.5), (2187.0, 0.16, 10.0))
    ring = sum(a * np.sin(2.0 * np.pi * f * t + 0.7 * k) * np.exp(-t * d)
               for k, (f, a, d) in enumerate(partials))
    strike = (noise - smooth(noise, 4)) * np.exp(-t * 95.0)
    thump = smooth(noise, 120) * np.exp(-t * 9.0)
    knock = np.sin(phase(58.0 + 45.0 * np.exp(-t * 20.0))) * np.exp(-t * 7.0)
    return 0.55 * ring + 0.55 * strike + 2.2 * thump + 0.5 * knock


def black_hole() -> np.ndarray:
    # A swirling pitch dive that collapses into a sub implosion.
    t = clock(1.70)
    rng = np.random.default_rng(4206)
    noise = rng.standard_normal(t.size)
    dive = 55.0 + 845.0 * np.exp(-t * 2.6)
    tone = np.sin(phase(dive)) + 0.4 * np.sin(phase(dive * 1.5))
    swirl = resonate(noise, 150.0 + 2250.0 * np.exp(-t * 2.2), 3.0)
    wobble = 0.5 + 0.5 * np.sin(phase(9.0 - 6.0 * t / 1.70))
    env = (1.0 - np.exp(-t * 6.0)) * (1.0 - np.exp(-(1.70 - t) * 5.0))
    implode = bump(t, 1.22, 0.16) * (np.sin(2.0 * np.pi * 38.0 * t) + 1.6 * smooth(noise, 140))
    return env * (0.45 * tone + 0.8 * swirl * wobble) + 0.9 * implode


def cat() -> np.ndarray:
    # A synthetic mi-a-ow: a harmonic voice whose pitch arcs up and down
    # while two formants slide from an i through an a to a u.
    t = clock(0.85)
    rng = np.random.default_rng(4207)
    noise = rng.standard_normal(t.size)
    f0 = np.interp(t, (0.0, 0.12, 0.30, 0.55, 0.85), (430.0, 640.0, 720.0, 560.0, 380.0))
    f0 = f0 * (1.0 + 0.012 * np.sin(2.0 * np.pi * 5.5 * t))
    f1 = np.interp(t, (0.0, 0.25, 0.60, 0.85), (520.0, 950.0, 820.0, 560.0))
    f2 = np.interp(t, (0.0, 0.25, 0.60, 0.85), (2300.0, 1500.0, 1150.0, 900.0))
    base = phase(f0)
    voice = np.zeros_like(t)
    for k in range(1, 14):
        fk = k * f0
        weight = np.exp(-((fk - f1) / 200.0) ** 2) + 0.7 * np.exp(-((fk - f2) / 300.0) ** 2) + 0.04
        voice += weight * np.sin(k * base) / k ** 0.5
    breath = 0.04 * (noise - smooth(noise, 3))
    env = (1.0 - np.exp(-t * 28.0)) * np.clip((0.85 - t) / 0.32, 0.0, 1.0) ** 1.5
    return env * (voice + breath)


def freeze() -> np.ndarray:
    # A glassy tink, a frost hiss, ice-crackle ticks thinning out and a high
    # crystalline shimmer that fades last.
    t = clock(1.30)
    rng = np.random.default_rng(4208)
    noise = rng.standard_normal(t.size)
    bright = noise - smooth(noise, 3)
    tink = np.sin(2.0 * np.pi * 1568.0 * t) * np.exp(-t * 11.0) + 0.5 * np.sin(2.0 * np.pi * 4186.0 * t) * np.exp(-t * 16.0)
    hiss = (noise - smooth(noise, 5)) * bump(t, 0.24, 0.17)
    crackle_at = np.sort(rng.uniform(0.02, 0.95, 38))
    crackle = ticks(t, crackle_at, 0.0016, bright, 0.4 * np.exp(-crackle_at * 1.8))
    shimmer = np.zeros_like(t)
    for k, (f, a, on) in enumerate(((2637.0, 0.30, 0.05), (3520.0, 0.24, 0.12),
                                    (4186.0, 0.20, 0.20), (5274.0, 0.14, 0.28))):
        local, gate = since(t, on)
        sway = 0.75 + 0.25 * np.sin(2.0 * np.pi * (3.0 + k) * t)
        shimmer += a * gate * (1.0 - np.exp(-local * 20.0)) * sway * np.sin(2.0 * np.pi * f * t + rng.uniform(0.0, 6.28))
    tail = np.exp(-t * 2.4) * (1.0 - np.exp(-(1.30 - t) * 20.0))
    return 0.45 * tink + 0.35 * hiss + crackle + shimmer * tail


def glue() -> np.ndarray:
    # Gloop: two resonant squelches of thick low noise and three rising bubble pops.
    t = clock(0.95)
    rng = np.random.default_rng(4209)
    noise = rng.standard_normal(t.size)
    squelch_env = bump(t, 0.17, 0.11) + 0.75 * bump(t, 0.50, 0.13)
    squelch = resonate(smooth(noise, 9), 260.0 + 620.0 * bump(t, 0.20, 0.14) + 380.0 * bump(t, 0.52, 0.14), 4.0)
    bubbles = (chirp(t, 0.09, 170.0, 520.0, 0.06, 26.0) + 0.8 * chirp(t, 0.36, 210.0, 600.0, 0.05, 30.0)
               + 0.65 * chirp(t, 0.66, 150.0, 470.0, 0.07, 24.0))
    end = 1.0 - np.exp(-(0.95 - t) * 30.0)
    return end * (3.0 * squelch_env * squelch + 0.55 * bubbles)


def jumping_bean() -> np.ndarray:
    # Four springy hops, each a wooden tick plus a wobbling boing pitched a
    # little higher than the last, with a seed rattle between hops.
    t = clock(1.15)
    rng = np.random.default_rng(4210)
    noise = rng.standard_normal(t.size)
    out = np.zeros_like(t)
    for i, at in enumerate((0.0, 0.33, 0.60, 0.82)):
        local, on = since(t, at)
        base = 260.0 * 1.12 ** i
        spring = base * (1.0 + 0.55 * np.exp(-local * 16.0)) * (1.0 + 0.07 * np.sin(2.0 * np.pi * 21.0 * local))
        boing = on * np.sin(phase(spring * on)) * np.exp(-local * 9.0) * (1.0 - np.exp(-local * 700.0))
        tick = on * np.exp(-local * 140.0) * noise
        out += (0.9 - 0.1 * i) * (boing + 0.35 * resonate(tick, 1900.0, 7.0))
    rattle = 0.22 * ticks(t, rng.uniform(0.05, 1.0, 26), 0.0015, noise - smooth(noise, 3))
    return out + rattle


def magnet() -> np.ndarray:
    # Electric hum winding up an octave, a rising vwoom and stray sparks.
    t = clock(1.35)
    rng = np.random.default_rng(4211)
    noise = rng.standard_normal(t.size)
    hum = np.tanh(3.5 * np.sin(phase(70.0 * 2.0 ** (t / 1.35))))
    pulse = 0.55 + 0.45 * np.sin(phase(12.0 + 14.0 * t / 1.35))
    vwoom = np.sin(phase(220.0 + 660.0 * (t / 1.35) ** 1.6))
    sparks = 0.35 * ticks(t, rng.uniform(0.1, 1.25, 16), 0.0012, noise - smooth(noise, 3))
    env = (1.0 - np.exp(-t * 10.0)) * (1.0 - np.exp(-(1.35 - t) * 11.0))
    return env * (0.5 * hum * pulse + 0.3 * vwoom) + sparks


def paintball() -> np.ndarray:
    # A wet splat: bright pop, a falling resonant smear, a soft thump and
    # droplets landing after it.
    t = clock(0.80)
    rng = np.random.default_rng(4212)
    noise = rng.standard_normal(t.size)
    pop = (noise - smooth(noise, 3)) * np.exp(-t * 130.0)
    smear = resonate(noise, 380.0 + 900.0 * np.exp(-t * 9.0), 1.6) * np.exp(-t * 13.0) * (1.0 - np.exp(-t * 600.0))
    thump = smooth(noise, 60) * np.exp(-t * 24.0)
    drops = sum(0.30 * (0.85 ** i) * chirp(t, at, 1100.0, 2300.0, 0.025, 70.0)
                for i, at in enumerate(np.sort(rng.uniform(0.12, 0.62, 6))))
    return 0.18 * pop + 1.4 * smear + 1.8 * thump + drops


def stackfall() -> np.ndarray:
    # A falling-object whistle, then a cascade of wooden block clacks.
    t = clock(1.70)
    rng = np.random.default_rng(4213)
    noise = rng.standard_normal(t.size)
    whistle_hz = 1800.0 * (500.0 / 1800.0) ** np.clip(t / 0.9, 0.0, 1.0)
    whistle_hz = whistle_hz * (1.0 + 0.01 * np.sin(2.0 * np.pi * 6.0 * t))
    whistle = np.sin(phase(whistle_hz)) * (1.0 - np.exp(-t * 8.0)) * np.clip((0.95 - t) / 0.08, 0.0, 1.0)
    cascade = np.zeros_like(t)
    for i, at in enumerate(np.sort(rng.uniform(0.86, 1.55, 14))):
        local, on = since(t, at)
        hit = on * np.exp(-local * 70.0) * noise
        cascade += (1.0 - 0.04 * i) * resonate(hit, rng.uniform(650.0, 1400.0), 9.0)
        if i % 3 == 0:
            cascade += 1.2 * on * np.exp(-local * 32.0) * smooth(noise, 70)
    return 0.32 * whistle + cascade


def rocket_blast() -> np.ndarray:
    # Rocket detonation (its trigger is the impact, not the launch): an
    # ignition whoosh rising into a bright crack, a boom and crackle sparks.
    t = clock(1.10)
    rng = np.random.default_rng(4214)
    noise = rng.standard_normal(t.size)
    hit = 0.16
    rise = np.clip(t / hit, 0.0, 1.0)
    whoosh = resonate(noise, 600.0 + 3200.0 * rise, 2.0) * rise ** 2 * (t < hit)
    local, on = since(t, hit)
    crack = on * (noise - smooth(noise, 4)) * np.exp(-local * 60.0)
    boom_body = 1.3 * smooth(noise, 70) + 0.35 * np.sin(phase(70.0 + 120.0 * np.exp(-local * 12.0)))
    boom = on * (1.0 - np.exp(-local * 260.0)) * np.exp(-local * 5.2) * boom_body
    sparks = 0.18 * ticks(t, rng.uniform(0.30, 0.85, 12), 0.0018, noise - smooth(noise, 3))
    return 0.35 * whoosh + 0.45 * crack + boom + sparks


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
                        ("quake2.wav", quake), ("propeller.wav", propeller),
                        ("anvil.wav", anvil), ("black_hole.wav", black_hole),
                        ("cat.wav", cat), ("freeze.wav", freeze), ("glue.wav", glue),
                        ("jumping_bean.wav", jumping_bean), ("magnet.wav", magnet),
                        ("paintball.wav", paintball), ("stackfall.wav", stackfall),
                        ("rocket_blast.wav", rocket_blast)):
        save(name, synth())


if __name__ == "__main__":
    main()
