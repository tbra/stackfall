# Original cue pack

`boing.wav`, `creak.wav`, and `rocket.wav` are original procedural sound assets for the existing `AudioConfig` filenames. They replace three files that were otherwise available only through the optional original Bontago asset install. No third-party recordings or samples were used.

| File | Duration | Intended use | Character |
| --- | ---: | --- | --- |
| `boing.wav` | 0.72 s | Gift claim / bounce | Spring bend with a small ceramic click |
| `creak.wav` | 1.15 s | Structural strain | Stick-slip pulse train (two rubs, slow-fast-slow) ringing damped wood resonances |
| `rocket.wav` | 1.28 s | Rocket activation | Rising motor whistle with soft air rush |

Render with `python tools/generate_sfx_cues.py`. Outputs are deterministic 44.1 kHz mono 16-bit PCM WAVs. The generator targets roughly -16 dBFS over the loudest 300 ms while capping the peak at -1 dBFS, in line with bundled effect guidance in `config/AudioConfig.gd`. Runtime wiring is unchanged; any use of `creak` or `rocket` depends on existing event hooks.

Every cue gets a 1 ms fade-in and 8 ms fade-out so no file starts or stops on a non-zero sample.

Review (Claude, 2026-10-02, Bontago-mp0.39): judged from waveform/spectrogram renders against the optional originals, not by ear. `creak` was re-synthesized as discrete stick-slip slips (the first version was a wobbling tone under noise). Only `boing.wav` is wired live (gift claim); owner should listen to it in a match.
