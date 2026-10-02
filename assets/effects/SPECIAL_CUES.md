# Original special activation cue pack

These four WAVs fill names already configured in `AudioConfig`: `bomb.wav`, `volcano.wav`, `quake2.wav`, and `propeller.wav`. The files were synthesized specifically for Stackfall using deterministic noise and oscillators; no recordings, samples, downloads, or original Bontago audio are used. The script at `tools/generate_special_sfx.py` is the reproducible source.

| Cue | Duration | Intended character |
| --- | ---: | --- |
| Bomb | 1.05 s | Hard transient, descending impact body, faint debris ticks under the blast |
| Volcano | 1.62 s | Two lava swells, low bubbling and sparse crackle |
| Quake | 1.88 s | Three uneven ground waves with a low sub tone |
| Propeller | 1.37 s | Accelerating blade chop and airy motor tone |

Format: 44.1 kHz, mono, 16-bit PCM. Levels target roughly -16 dBFS in the loudest 300 ms, with a peak cap of -1 dBFS. These are dry one-shots. Game event wiring and mix settings are unchanged. Listen beside gameplay music and existing placement sounds before integration.

Every cue gets a 1 ms fade-in and 8 ms fade-out so no file starts or stops on a non-zero sample.

Review (Claude, 2026-10-02, Bontago-mp0.42): judged from waveform/spectrogram renders, not by ear. Bomb debris ticks were lowered (0.35 -> 0.16) so the blast reads as one hit rather than a three-pop stutter. None of these four events has a caller yet.
