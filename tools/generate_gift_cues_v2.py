#!/usr/bin/env python3
"""Second round of original gift / drop cues (Bontago-eq0 owner feedback 2026-10-12).

Run: python tools/generate_gift_cues_v2.py
Writes deterministic 44.1 kHz mono 16-bit PCM WAVs to assets/effects. No samples.

Owner feedback on round one: the new drop, Bomb, Rocket and Paintball cues were
disliked (two candidates each here, "_a" wired by default); Earthquake and Magnet
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


# --- Bomb ------------------------------------------------------------------------

def bomb_boom_a() -> np.ndarray:
    # Cartoon KA-BOOM: a bright crack, a fat saturated low drop, a rolling noise
    # body, then a short crumble of low pops.
    t = clock(1.45)
    rng = np.random.default_rng(4411)
    noise = rng.standard_normal(t.size)
    crack = (noise - smooth(noise, 3)) * np.exp(-t * 160.0)
    drop = np.sin(phase(38.0 + 110.0 * np.exp(-t * 7.0))) * np.exp(-t * 3.2)
    roar = smooth(noise, 45) * np.exp(-t * 4.2) * (1.0 - np.exp(-t * 120.0))
    crumble = ticks(t, np.sort(rng.uniform(0.35, 1.1, 9)), 0.012, smooth(noise, 20), np.linspace(0.5, 0.15, 9))
    return drive(0.9 * crack + 1.2 * drop + 1.5 * roar, 2.2) + 0.6 * crumble


def bomb_boom_b() -> np.ndarray:
    # Deep "BWOOM": a slower, heavier swell with a hollow low ring and debris
    # rattling down afterwards.
    t = clock(1.7)
    rng = np.random.default_rng(4412)
    noise = rng.standard_normal(t.size)
    swell = smooth(noise, 70) * (1.0 - np.exp(-t * 60.0)) * np.exp(-t * 2.6)
    ring = np.sin(phase(52.0 + 40.0 * np.exp(-t * 4.0))) * np.exp(-t * 2.2)
    snap = (noise - smooth(noise, 5)) * np.exp(-t * 90.0)
    debris = np.zeros_like(t)
    for at in np.sort(rng.uniform(0.45, 1.5, 12)):
        local, on = since(t, at)
        debris += 0.35 * on * resonate(noise * np.exp(-local * 90.0), rng.uniform(700.0, 1600.0), 8.0)
    return drive(1.6 * swell + 0.9 * ring + 0.5 * snap, 1.8) + debris


# --- Rocket (detonation) ----------------------------------------------------------

def rocket_boom_a() -> np.ndarray:
    # Firework-style "fwee-POP-boom": a short rising whistle, a sharp pop, a
    # mid-weight boom and a crackling sparkle tail. Lighter than the Bomb.
    t = clock(1.3)
    rng = np.random.default_rng(4421)
    noise = rng.standard_normal(t.size)
    hit = 0.17
    whistle = np.sin(phase(900.0 + 1700.0 * np.clip(t / hit, 0.0, 1.0) ** 2)) * np.clip(t / hit, 0.0, 1.0) * (t < hit)
    local, on = since(t, hit)
    pop = on * (noise - smooth(noise, 3)) * np.exp(-local * 120.0)
    boom = on * np.sin(phase(60.0 + 160.0 * np.exp(-local * 14.0))) * np.exp(-local * 5.5)
    body = on * smooth(noise, 35) * np.exp(-local * 6.5)
    sparkle = ticks(t, np.sort(rng.uniform(0.3, 1.15, 26)), 0.0015, noise - smooth(noise, 2),
                    np.linspace(0.55, 0.12, 26))
    return 0.22 * whistle + drive(0.9 * pop + 1.1 * boom + 1.3 * body, 2.0) + sparkle


def rocket_boom_b() -> np.ndarray:
    # "Fwoosh-BANG": a hissing thrust swell that cuts into a bright metallic bang.
    t = clock(1.2)
    rng = np.random.default_rng(4422)
    noise = rng.standard_normal(t.size)
    hit = 0.22
    rise = np.clip(t / hit, 0.0, 1.0)
    thrust = resonate(noise, 1200.0 + 2400.0 * rise, 1.2) * rise ** 1.5 * (t < hit)
    local, on = since(t, hit)
    bang = on * (noise - smooth(noise, 4)) * np.exp(-local * 45.0)
    clang = on * np.sin(phase(np.full_like(t, 410.0))) * np.sin(phase(np.full_like(t, 1130.0))) * np.exp(-local * 18.0)
    low = on * smooth(noise, 60) * np.exp(-local * 5.0)
    return 0.5 * thrust + drive(0.8 * bang + 0.4 * clang + 1.5 * low, 2.0)


# --- Paintball --------------------------------------------------------------------

def paintball_splat_a() -> np.ndarray:
    # Juicy SPLORCH: a wet resonant sweep down, a fat "blop", a squishy second
    # squelch and four drips.
    t = clock(0.95)
    rng = np.random.default_rng(4431)
    noise = rng.standard_normal(t.size)
    splat = resonate(noise, 260.0 + 1500.0 * np.exp(-t * 16.0), 3.0) * np.exp(-t * 9.0) * (1.0 - np.exp(-t * 800.0))
    blop = np.sin(phase(140.0 + 300.0 * np.exp(-t * 45.0))) * np.exp(-t * 18.0)
    squish = resonate(smooth(noise, 6), 500.0 + 300.0 * bump(t, 0.24, 0.05), 4.0) * bump(t, 0.24, 0.06)
    drips = sum(0.35 * (0.8 ** i) * chirp(t, at, 900.0, 1900.0, 0.03, 60.0)
                for i, at in enumerate((0.36, 0.5, 0.63, 0.8)))
    return 1.4 * splat + 0.9 * blop + 1.6 * squish + drips


def paintball_splat_b() -> np.ndarray:
    # Paint balloon: a rubbery pop, a spray of wet noise sliding down, and drips.
    t = clock(0.85)
    rng = np.random.default_rng(4432)
    noise = rng.standard_normal(t.size)
    pop = np.sin(phase(900.0 + 600.0 * np.exp(-t * 200.0))) * np.exp(-t * 90.0)
    spray = resonate(noise, 900.0 + 3200.0 * np.exp(-t * 7.0), 1.2) * np.exp(-t * 7.5) * (1.0 - np.exp(-t * 400.0))
    slap = smooth(noise, 30) * np.exp(-t * 30.0)
    drips = sum(0.3 * chirp(t, at, 1100.0, 2200.0, 0.025, 70.0) for at in (0.3, 0.45, 0.66))
    return 0.6 * pop + spray + 1.5 * slap + drips


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
