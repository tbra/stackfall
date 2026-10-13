#!/usr/bin/env python3
"""Second round of original gift / drop cues (Bontago-eq0 owner feedback 2026-10-12).

Run: python tools/generate_gift_cues_v2.py
Writes deterministic 44.1 kHz mono 16-bit PCM WAVs to assets/effects. No samples.

Owner feedback on round one: the new drop, Bomb, Rocket and Paintball cues were
disliked (two candidates each here, "_a" wired by default; Bomb, Rocket and
Paintball were rebuilt again in round three, see below); Earthquake and Magnet
need a sound for their whole active window (seamless loops); Glue needs a sound
when a glued block hits something; the Jumping Bean needs a sound per hop.

Loops are built so the last sample flows into the first: noise is synthesised in
the frequency domain (an inverse FFT is periodic over its length) and every
oscillator and modulator completes a whole number of cycles per loop.
"""

from pathlib import Path
import wave

import numpy as np

from generate_special_sfx import RATE, DEST, bump, chirp, clock, phase, resonate, save, since, smooth, ticks


def drive(x: np.ndarray, amount: float) -> np.ndarray:
    # Soft saturation: fattens a cartoon boom without hard clipping.
    return np.tanh(amount * x) / np.tanh(amount)


def norm(x: np.ndarray) -> np.ndarray:
    peak = float(np.max(np.abs(x)))
    return x / peak if peak > 0.0 else x


def circular_noise(rng: np.random.Generator, n: int, low_hz: float, high_hz: float, tilt: float = 0.0) -> np.ndarray:
    # Band-limited noise that repeats exactly every n samples. `tilt` > 0 darkens
    # it (amplitude ~ f^-tilt), 1.0 is close to brown noise.
    f = np.fft.rfftfreq(n, 1.0 / RATE)
    shape = (1.0 - np.exp(-(f / max(low_hz, 1.0)) ** 2)) * np.exp(-(f / high_hz) ** 2)
    shape[1:] *= f[1:] ** -tilt
    shape[0] = 0.0
    spectrum = shape * np.exp(1j * rng.uniform(0.0, 2.0 * np.pi, f.size))
    return norm(np.fft.irfft(spectrum, n))


def whole_hz(hz: float, seconds: float) -> float:
    # Nearest frequency with a whole number of cycles in `seconds` (seamless loops).
    return max(round(hz * seconds), 1) / seconds


# --- Block drop (released piece) ----------------------------------------------

def block_drop_a() -> np.ndarray:
    # Soft airy "fwip": a quick downward band-passed air sweep with a hint of
    # low thump. No pitch, so it can never clash with the music.
    t = clock(0.18)
    rng = np.random.default_rng(4401)
    noise = rng.standard_normal(t.size)
    sweep = resonate(noise, 600.0 + 2600.0 * np.exp(-t * 32.0), 1.4) * np.exp(-t * 26.0) * (1.0 - np.exp(-t * 300.0))
    thump = smooth(noise, 90) * np.exp(-t * 40.0)
    return sweep + 1.6 * thump


def block_drop_b() -> np.ndarray:
    # A soft, low, rounded "plop": a short pitch drop with a felt-like attack.
    t = clock(0.16)
    rng = np.random.default_rng(4402)
    noise = rng.standard_normal(t.size)
    body = np.sin(phase(150.0 + 170.0 * np.exp(-t * 38.0))) * np.exp(-t * 22.0) * (1.0 - np.exp(-t * 500.0))
    felt = smooth(noise, 14) * np.exp(-t * 90.0)
    return body + 0.5 * felt


# --- Explosion / splat building blocks (round three) -------------------------------
# Owner feedback on round two: Bomb and Rocket "should sound more like explosions",
# Paintball "should have more of a splat sound". Round three is built the way a real
# blast sounds rather than from tones: white noise through a low-pass whose cutoff
# falls from bright to dull within a fraction of a second (the fireball's roar), a
# sub-bass thump, a turbulent rolling rumble and sparse debris crackle. The splat is
# a broadband wet slap, a low-mid thwack and a dense spray of tiny droplet grains.


def lowpass(signal: np.ndarray, cutoff, poles: int = 2) -> np.ndarray:
    # Cascaded one-pole low-pass; `cutoff` (Hz) may be a per-sample array.
    cut = np.broadcast_to(np.asarray(cutoff, dtype=np.float64), signal.shape)
    alpha = (1.0 - np.exp(-2.0 * np.pi * np.clip(cut, 5.0, RATE * 0.45) / RATE)).tolist()
    out = signal.tolist()
    for _ in range(poles):
        y = 0.0
        for i, x in enumerate(out):
            y += alpha[i] * (x - y)
            out[i] = y
    return np.array(out)


def band(signal: np.ndarray, low_hz, high_hz, poles: int = 2) -> np.ndarray:
    return lowpass(signal, high_hz, poles) - lowpass(signal, low_hz, poles)


def brown(rng: np.random.Generator, n: int) -> np.ndarray:
    # Integrated white noise with its drift removed: a deep, rolling rumble source.
    walk = np.cumsum(rng.standard_normal(n))
    walk -= lowpass(walk, 15.0, 1)
    return norm(walk)


def crackle(t: np.ndarray, rng: np.random.Generator, start: float, end: float, count: int,
            bright_hz: float, decay_s: float) -> np.ndarray:
    # Sparse debris/fire crackle: short filtered noise grains whose density and level
    # thin out over [start, end].
    out = np.zeros_like(t)
    times = start + (end - start) * rng.random(count) ** 1.8
    grain = round(0.006 * RATE)
    for at in times:
        i = round(at * RATE)
        if i + grain >= t.size:
            continue
        g = rng.standard_normal(grain) * np.exp(-np.arange(grain) / (grain * 0.25))
        out[i:i + grain] += g * np.exp(-(at - start) / decay_s) * rng.uniform(0.4, 1.0)
    return lowpass(out, bright_hz, 1)


def explosion(t: np.ndarray, rng: np.random.Generator, bright_hz: float, roar_s: float,
              sub_hz: float, sub_s: float, rumble_s: float, crackle_count: int) -> np.ndarray:
    noise = rng.standard_normal(t.size)
    attack = 1.0 - np.exp(-t / 0.0015)
    crack = (noise - lowpass(noise, 1500.0, 1)) * np.exp(-t / 0.004)
    cutoff = 160.0 + bright_hz * np.exp(-t / 0.05) + 900.0 * np.exp(-t / 0.35)
    roar = lowpass(noise, cutoff, 2) * attack * (0.7 * np.exp(-t / roar_s) + 0.3 * np.exp(-t / (roar_s * 3.0)))
    sub = np.sin(phase(sub_hz * 0.55 + sub_hz * 0.45 * np.exp(-t / 0.12))) * attack * np.exp(-t / sub_s)
    turbulence = 1.0 + 0.6 * norm(lowpass(rng.standard_normal(t.size), 5.0, 2))
    rumble = lowpass(brown(rng, t.size), 140.0, 2) * (1.0 - np.exp(-t / 0.08)) * np.exp(-t / rumble_s) * turbulence
    debris = crackle(t, rng, 0.08, t[-1] * 0.8, crackle_count, 3500.0, t[-1] * 0.3)
    # The audible weight of a blast sits around 80-600 Hz (small speakers barely
    # reproduce the sub): a punchy broadband burst and a mid body carry it.
    punch = lowpass(noise, 3500.0, 2) * attack * np.exp(-t / 0.045)
    body = band(noise, 90.0, 650.0, 2) * attack * (np.exp(-t / (roar_s * 0.8)) + 0.25 * np.exp(-t / (roar_s * 3.0)))
    mix = (0.35 * crack + 0.9 * norm(punch) + 1.0 * norm(body) + 0.6 * norm(roar)
           + 0.3 * sub + 0.35 * norm(rumble) + 0.3 * norm(debris))
    mix -= lowpass(mix, 30.0, 1)
    tail = np.clip((t[-1] - t) / 0.25, 0.0, 1.0)
    return drive(0.45 * mix * tail, 1.4)


# --- Bomb ------------------------------------------------------------------------

def bomb_boom_a() -> np.ndarray:
    # A big, close explosion: bright crack, heavy roar, deep thump, rolling rumble.
    t = clock(2.4)
    return explosion(t, np.random.default_rng(4511), 7000.0, 0.32, 58.0, 0.5, 0.9, 40)


def bomb_boom_b() -> np.ndarray:
    # A deeper, longer blast that rolls away like thunder.
    t = clock(3.0)
    rng = np.random.default_rng(4512)
    body = explosion(t, rng, 4500.0, 0.45, 48.0, 0.7, 1.3, 55)
    roll = norm(lowpass(brown(rng, t.size), 90.0, 2)) * bump(t, 1.1, 0.5) * 0.6
    return body + roll


# --- Rocket (detonation) ----------------------------------------------------------

def rocket_boom_a() -> np.ndarray:
    # A rushing whoosh straight into a sharp, bright explosion with fiery crackle;
    # snappier and lighter than the Bomb.
    t = clock(2.0)
    rng = np.random.default_rng(4521)
    hit = 0.16
    pre, post = t[t < hit], t[t >= hit] - hit
    rise = np.clip(pre / hit, 0.0, 1.0)
    whoosh = band(rng.standard_normal(pre.size), 400.0 + 1500.0 * rise, 1500.0 + 5000.0 * rise, 1) * rise ** 2
    blast = explosion(post, rng, 9000.0, 0.22, 70.0, 0.35, 0.6, 70)
    fire = crackle(post, rng, 0.05, 1.2, 90, 6000.0, 0.4)
    return np.concatenate([0.45 * norm(whoosh), blast + 0.25 * norm(fire)])


def rocket_boom_b() -> np.ndarray:
    # A dry, cracking BANG with a short roar and a spray of sparks (no lead-in).
    t = clock(1.7)
    rng = np.random.default_rng(4522)
    blast = explosion(t, rng, 11000.0, 0.16, 80.0, 0.25, 0.45, 50)
    sparks = crackle(t, rng, 0.03, 1.0, 120, 8000.0, 0.3)
    return blast + 0.3 * norm(sparks)


# --- Paintball --------------------------------------------------------------------

def splat(t: np.ndarray, rng: np.random.Generator, body_hz: float, body_s: float,
          spray_count: int, spray_s: float) -> np.ndarray:
    noise = rng.standard_normal(t.size)
    attack = 1.0 - np.exp(-t / 0.0008)
    slap = lowpass(noise, 900.0 + 5000.0 * np.exp(-t / 0.015), 2) * attack * np.exp(-t / 0.03)
    thwack = band(noise, body_hz * 0.5, body_hz * 1.6, 2) * attack * np.exp(-t / body_s)
    spray = np.zeros_like(t)
    grain = round(0.004 * RATE)
    times = spray_s * rng.random(spray_count) ** 1.6
    for at in times:
        i = round((0.004 + at) * RATE)
        if i + grain >= t.size:
            continue
        g = band(rng.standard_normal(grain), rng.uniform(1200.0, 2500.0), rng.uniform(3500.0, 7000.0), 1)
        spray[i:i + grain] += g * np.hanning(grain) * np.exp(-at / (spray_s * 0.6)) * rng.uniform(0.3, 1.0)
    return 0.9 * norm(slap) + 1.0 * norm(thwack) + 0.55 * norm(spray)


def paintball_splat_a() -> np.ndarray:
    # A wet SPLAT: a broadband slap, a low-mid thwack and a spray of droplets.
    t = clock(0.6)
    out = splat(t, np.random.default_rng(4531), 520.0, 0.06, 140, 0.22)
    return out * np.clip((0.6 - t) / 0.1, 0.0, 1.0)


def paintball_splat_b() -> np.ndarray:
    # A thicker, juicier SPLORCH with more body and a longer drippy spray.
    t = clock(0.8)
    rng = np.random.default_rng(4532)
    out = splat(t, rng, 380.0, 0.09, 220, 0.35)
    drips = sum(0.12 * chirp(t, at, 1300.0, 2600.0, 0.008, 90.0) for at in np.sort(rng.uniform(0.3, 0.7, 5)))
    return (out + drips) * np.clip((0.8 - t) / 0.12, 0.0, 1.0)


# --- Glue, Jumping Bean --------------------------------------------------------------

def glue_squelch() -> np.ndarray:
    # Sticky "shlup": a thick resonant squish with a low blob and a little
    # suction pop as it settles. Short, because it can repeat in a pile.
    t = clock(0.38)
    rng = np.random.default_rng(4441)
    noise = rng.standard_normal(t.size)
    squish = resonate(smooth(noise, 7), 300.0 + 700.0 * np.exp(-t * 14.0), 4.5) * np.exp(-t * 11.0) * (1.0 - np.exp(-t * 500.0))
    blob = np.sin(phase(120.0 + 160.0 * np.exp(-t * 30.0))) * np.exp(-t * 16.0)
    suction = chirp(t, 0.21, 240.0, 620.0, 0.04, 40.0)
    return 2.4 * squish + 0.7 * blob + 0.45 * suction


def bean_hop_a() -> np.ndarray:
    # Cartoon "boing": a wobbling spring that bends up in pitch, plus a wooden tok.
    t = clock(0.42)
    rng = np.random.default_rng(4451)
    noise = rng.standard_normal(t.size)
    spring_hz = 210.0 * (1.0 + 0.9 * (1.0 - np.exp(-t * 11.0))) * (1.0 + 0.09 * np.sin(2.0 * np.pi * 17.0 * t))
    spring = np.sin(phase(spring_hz)) * np.exp(-t * 7.5) * (1.0 - np.exp(-t * 400.0))
    tok = resonate(noise * np.exp(-t * 160.0), 1500.0, 8.0)
    return spring + 0.5 * tok


def bean_hop_b() -> np.ndarray:
    # Slide-whistle "bwoop": a quick upward glide, round and short.
    t = clock(0.26)
    glide = 300.0 + 450.0 * np.clip(t / 0.18, 0.0, 1.0) ** 0.7
    voice = np.sin(phase(glide)) + 0.25 * np.sin(2.0 * phase(glide))
    return voice * (1.0 - np.exp(-t * 60.0)) * np.clip((0.26 - t) / 0.08, 0.0, 1.0)


# --- Loops (Earthquake, Magnet) ------------------------------------------------------

def quake_rumble_loop() -> np.ndarray:
    # A deep ground rumble with slow surges and gritty grinding, 3 s, seamless.
    seconds = 3.0
    n = round(seconds * RATE)
    t = np.arange(n) / RATE
    rng = np.random.default_rng(4461)
    rumble = circular_noise(rng, n, 25.0, 180.0, 0.8)
    grit = circular_noise(rng, n, 300.0, 1800.0, 0.3)
    sub = np.sin(2.0 * np.pi * whole_hz(34.0, seconds) * t)
    surge = 0.65 + 0.35 * np.sin(2.0 * np.pi * (2.0 / seconds) * t) * np.sin(2.0 * np.pi * (3.0 / seconds) * t + 0.6)
    grind = 0.5 + 0.5 * np.sin(2.0 * np.pi * (7.0 / seconds) * t) ** 8
    return surge * (1.4 * rumble + 0.35 * sub) + 0.18 * grit * grind


def magnet_hum_loop() -> np.ndarray:
    # An electric magnet hum: a buzzy fundamental, a pulsing tremolo, a high
    # wavering whine and faint crackle, 2 s, seamless.
    seconds = 2.0
    n = round(seconds * RATE)
    t = np.arange(n) / RATE
    rng = np.random.default_rng(4471)
    base = whole_hz(98.0, seconds)
    hum = np.tanh(2.5 * np.sin(2.0 * np.pi * base * t)) + 0.3 * np.sin(2.0 * np.pi * 3.0 * base * t)
    pulse = 0.7 + 0.3 * np.sin(2.0 * np.pi * whole_hz(6.0, seconds) * t)
    whine_hz = whole_hz(1180.0, seconds)
    # Phase wobble with a whole number of cycles keeps the whine seamless.
    whine = np.sin(2.0 * np.pi * whine_hz * t + 1.5 * np.sin(2.0 * np.pi * whole_hz(3.0, seconds) * t))
    crackle = circular_noise(rng, n, 2500.0, 9000.0, 0.0)
    crackle *= (np.sin(2.0 * np.pi * whole_hz(5.0, seconds) * t) > 0.97)
    return 0.6 * hum * pulse + 0.12 * whine + 0.25 * crackle


def save_loop(filename: str, samples: np.ndarray, rms_dbfs: float) -> None:
    # Loops: no edge ramps (they would click at the wrap), level by overall RMS.
    samples = samples - samples.mean()
    gain = min(10 ** (rms_dbfs / 20) / np.sqrt(np.mean(samples ** 2)), 10 ** (-1 / 20) / np.max(np.abs(samples)))
    pcm = np.rint(np.clip(samples * gain, -1, 1) * 32767).astype("<i2")
    with wave.open(str(DEST / filename), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(pcm.tobytes())
    print(f"{filename}: {samples.size / RATE:.2f}s loop")


def main() -> None:
    DEST.mkdir(parents=True, exist_ok=True)
    for name, synth in (("block_drop_a.wav", block_drop_a), ("block_drop_b.wav", block_drop_b),
                        ("bomb_boom_a.wav", bomb_boom_a), ("bomb_boom_b.wav", bomb_boom_b),
                        ("rocket_boom_a.wav", rocket_boom_a), ("rocket_boom_b.wav", rocket_boom_b),
                        ("paintball_splat_a.wav", paintball_splat_a), ("paintball_splat_b.wav", paintball_splat_b),
                        ("glue_squelch.wav", glue_squelch),
                        ("bean_hop_a.wav", bean_hop_a), ("bean_hop_b.wav", bean_hop_b)):
        save(name, synth())
    save_loop("quake_rumble_loop.wav", quake_rumble_loop(), -18.0)
    save_loop("magnet_hum_loop.wav", magnet_hum_loop(), -19.0)


if __name__ == "__main__":
    main()
