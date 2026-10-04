# Lobby UI cue audition

`waveform_review.png` visualizes the delivered mono PCM. `audition.wav` plays
all eleven cues at stored levels with 700 ms gaps. No autoplay was used.

| Start seconds | Cue |
| --- | --- |
| 0.000 | player_joined.wav |
| 0.900 | player_left.wav |
| 1.780 | ready_on.wav |
| 2.660 | ready_off.wav |
| 3.520 | team_change.wav |
| 4.315 | colour_change.wav |
| 5.100 | bot_added.wav |
| 5.935 | bot_removed.wav |
| 6.770 | section_expanded.wav |
| 7.535 | section_collapsed.wav |
| 8.295 | all_players_ready.wav |

Technical checks and deterministic regeneration pass; waveforms were inspected.
Listening and live UI mixing remain review work. See the asset README, manifest
and Bontago-mp0.103 for intended triggers, source and handoff.
