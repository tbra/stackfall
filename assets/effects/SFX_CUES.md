# Original cue pack

`boing.wav`, `creak.wav`, and `rocket.wav` are original procedural sound assets for the existing `AudioConfig` filenames. They replace three files that were otherwise available only through the optional original Bontago asset install. No third-party recordings or samples were used.

| File | Duration | Intended use | Character |
| --- | ---: | --- | --- |
| `boing.wav` | 0.72 s | Gift claim / bounce | Spring bend with a small ceramic click |
| `creak.wav` | 1.15 s | Structural strain | Stick-slip pulse train (two rubs, slow-fast-slow) ringing damped wood resonances |
| `rocket.wav` | 1.28 s | Rocket activation | Rising motor whistle with soft air rush |

Render with a script removed in Bontago-dbn.1 (see git history). Outputs are deterministic 44.1 kHz mono 16-bit PCM WAVs. The generator targets roughly -16 dBFS over the loudest 300 ms while capping the peak at -1 dBFS, in line with bundled effect guidance in `config/AudioConfig.gd`. Runtime wiring is unchanged; any use of `creak` or `rocket` depends on existing event hooks.

Every cue gets a 1 ms fade-in and 8 ms fade-out so no file starts or stops on a non-zero sample.

Review (Claude, 2026-10-02, Bontago-mp0.39): judged from waveform/spectrogram renders against the optional originals, not by ear. `creak` was re-synthesized as discrete stick-slip slips (the first version was a wobbling tone under noise). Only `boing.wav` is wired live (gift claim); owner should listen to it in a match.

# Menu and drop cue replacements (Bontago-eq0, 2026-10-12)

a script removed in Bontago-dbn.1 (see git history) renders three original replacements, wired through `AudioConfig.click_file`, `hover_file` and `drop_file`. The old files remain in the folder for comparison.

| File | Replaces | Duration | Character |
| --- | --- | ---: | --- |
| `ui_hover.wav` | `button_hover_pcm.wav` | 0.04 s | Quiet D6 tick; the old file started on a non-zero sample (click) |
| `ui_select.wav` | `select.wav` | 0.16 s | Soft rising D5 -> A5 pluck, same family as the lobby cues |
| `block_release.wav` | `block_placed.wav` | 0.16 s | Woody tock from quickly damped body modes; the old cue's sustained ~1 kHz -> 516 Hz tone read as a sharp, off-key note over the music |

Not judged by ear; the owner should listen in the menu and in a match.
