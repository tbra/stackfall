# Original special activation cue pack

These four WAVs fill names already configured in `AudioConfig`: `bomb.wav`, `volcano.wav`, `quake2.wav`, and `propeller.wav`. The files were synthesized specifically for Stackfall using deterministic noise and oscillators; no recordings, samples, downloads, or original Bontago audio are used. The script at a script removed in Bontago-dbn.1 (see git history) is the reproducible source.

| Cue | Duration | Intended character |
| --- | ---: | --- |
| Bomb | 1.05 s | Hard transient, descending impact body, faint debris ticks under the blast |
| Volcano | 1.62 s | Two lava swells, low bubbling and sparse crackle |
| Quake | 1.88 s | Three uneven ground waves with a low sub tone |
| Propeller | 1.37 s | Accelerating blade chop and airy motor tone |

Format: 44.1 kHz, mono, 16-bit PCM. Levels target roughly -16 dBFS in the loudest 300 ms, with a peak cap of -1 dBFS. These are dry one-shots. Game event wiring and mix settings are unchanged. Listen beside gameplay music and existing placement sounds before integration.

Every cue gets a 1 ms fade-in and 8 ms fade-out so no file starts or stops on a non-zero sample.

Review (Claude, 2026-10-02, Bontago-mp0.42): judged from waveform/spectrogram renders, not by ear. Bomb debris ticks were lowered (0.35 -> 0.16) so the blast reads as one hit rather than a three-pop stutter. None of these four events has a caller yet.

## Activation cue per special (Bontago-eq0, 2026-10-12)

a script removed in Bontago-dbn.1 (see git history) now also renders one cue for each special that had none. Sfx plays them on `Events.special_triggered` (host and clients, silent during a late joiner's world replay, one cue per special per 0.3 s). The mapping is `AudioConfig.special_cue_files`; the four cues above are reused for Bomb, Volcano, Earthquake and Propeller and render byte-identically.

| Cue | Duration | Intended character |
| --- | ---: | --- |
| Anvil | 1.40 s | Struck steel bar partials, one beating pair, heavy thump |
| Black hole | 1.70 s | Swirling pitch dive collapsing into a sub implosion |
| Cat | 0.85 s | Synthetic formant "mi-a-ow" |
| Freeze | 1.30 s | Glassy tink, frost hiss, thinning ice crackle, high shimmer |
| Glue | 0.95 s | Two resonant squelches and three rising bubble pops |
| Jumping Bean | 1.15 s | Four springy boings rising in pitch, wooden ticks, seed rattle |
| Magnet | 1.35 s | Electric hum winding up an octave, rising sweep, sparks |
| Paintball | 0.80 s | Wet splat with a falling smear and droplets |
| Stackfall | 1.70 s | Falling whistle, then a cascade of wooden block clacks |
| Rocket (blast) | 1.10 s | Ignition whoosh into a bright crack, boom and sparks |

The Rocket's trigger is its detonation, so it uses `rocket_blast.wav`; `rocket.wav` (launch whistle) keeps no caller. Review (Claude, 2026-10-12): levels checked with a script removed in Bontago-dbn.1 (see git history), not judged by ear; the owner should listen in a match.
