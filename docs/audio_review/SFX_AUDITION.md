# SFX audition reel

Listen to [sfx_audition_reel.wav](sfx_audition_reel.wav) in the order below. Each cue is copied byte for byte from its source WAV; only 0.75 seconds of digital silence is added between cues. No gain, compression, fades, or resampling are applied.

Format: 1 channel, 44100 Hz, 16 bit PCM. Total duration: 00:25.420.

| # | Source cue | Start | End | Source PCM SHA-256 |
| --- | --- | --- | --- | --- |
| 1 | `assets/effects/boing.wav` | 00:00.000 | 00:00.720 | `876371cc5d9b46685b7240a4020d2b65f799e26e7f6754b77b6cd7109cae6a02` |
| 2 | `assets/effects/creak.wav` | 00:01.470 | 00:02.620 | `bb70074d3330abeff0902656a1c26b715bbc662ce2e76a81060355014f7180fb` |
| 3 | `assets/effects/rocket.wav` | 00:03.370 | 00:04.650 | `22e7015fb4413c2a1210a83203b960aecc32bfaba25eaa7acea5cf60fcb0b55f` |
| 4 | `assets/effects/bomb.wav` | 00:05.400 | 00:06.450 | `a5b79ce146a4937e942ff7c315b32ac59d6e8c1cdb3f6644666d1b1f457a93f5` |
| 5 | `assets/effects/volcano.wav` | 00:07.200 | 00:08.820 | `967c7d92178fc2e795c3f1281559ec24284a5fbe85651006934a421fce795cfc` |
| 6 | `assets/effects/quake2.wav` | 00:09.570 | 00:11.450 | `c99718f7990992633ef4c90a65f8ecf21e58b7e6c15916922e4eb29dc3fae216` |
| 7 | `assets/effects/propeller.wav` | 00:12.200 | 00:13.570 | `a0031468029fbdd2202c573ffa9f29056cf11fb5fdf89f2d41ca408e92388adb` |
| 8 | `assets/effects/claim_tension_loop.wav` | 00:14.320 | 00:22.320 | `085045940f4db555364102a7a3a21bd06559385c610970e36f96c5070e52d779` |
| 9 | `assets/effects/claim_interrupt_sting.wav` | 00:23.070 | 00:24.070 | `812e8fafb69b76c9abad8e77bc02ab79dc33c2e5bf3c0db0584105c17d8c2ac6` |
| 10 | `assets/effects/claim_rival_broken.wav` | 00:24.820 | 00:25.420 | `ef631918845ad3a88c3c32d5a7e91cf8d0fa23abebce56abe4744023729a68be` |

## Listening notes

Check the attack, tail, loudness balance, and whether each cue reads as its intended event at normal gameplay volume. In particular, audition boing and creak with a gift claim; the special rocket, bomb, volcano, quake, and propeller cues are candidates awaiting live wiring; the three claim_* cues are procedural placeholders (see CLAIM_TENSION.md). Log any cue requiring revision in Beads before integration.

This sheet verifies digital integrity only. A person still needs to listen to the WAV and judge the sound.
