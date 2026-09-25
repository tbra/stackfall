# Original Bontago versus Stackfall: drop and stack comparison

This is an observation protocol, not evidence that Bontago used Tokamak's defaults. The engine release in `feedback/tokamak_release/` does not contain Bontago's game settings. Keep the original installed-game recording and measured values separate from the Godot run. Do not copy original assets into this repository.

## Capture in the installed original

1. Use a quiet single-player/sandbox field with no specials, no board tilt and as few existing blocks as possible. Record screen at a fixed frame rate; keep the cube edge visible as the scale reference. Note game version, map, video frame rate, and any physics/settings changes.
2. Drop an ordinary single cube near the disk centre. Record the release, first disk contact, highest point after first impact, and first time it stays still for at least one second. Estimate release height and rebound height in **cube-edge lengths**, measured from the cube's bottom to its resting bottom position. Repeat three times; report median and range. If the cube never visibly leaves the disk, record rebound as below video resolution rather than exactly zero.
3. On a cleared field, place three single cubes in a vertical stack at the same spot, letting each land before releasing the next. Record the time from the third release until all three remain still for one second; measure the top cube's greatest sideways offset from the stack centre in cube-edge lengths. Repeat three times. Mark any attempt with a sloping/tilted disk or interference as invalid, rather than silently discarding it.

The original's placement cadence, hover height and exact release height are not yet known. Report them from the recording; do not assume the controlled Godot drop starts at the same height. A screenshot can show heights but not settle time—use video or frame-by-frame capture for timing.

## Run the remake fixture

From the repository root, after a normal Godot project import:

```powershell
godot --headless --path . res://tests/bench/compare_original_physics.tscn -- --mode=drop --drop-height-cubes=2.0
godot --headless --path . res://tests/bench/compare_original_physics.tscn -- --mode=stack
```

Set `--drop-height-cubes` to the median measured original release height; run at least the original minimum and maximum heights as a sensitivity check. The fixture uses the shipped `PhysicsTuning` and `BlockFactory`, a real `Field`, one cube dropped at the centre, or three cubes released sequentially over one another. It runs ten simulated seconds per invocation and prints a single `PHYSICS_COMPARE result=` JSON record. It does not change any tuning or assert a pass/fail verdict.

For the stack run, `--stack-interval-s=2.0` and `--stack-gap-cubes=0.3` are adjustable. Set these to the observed time between releases and release gap (bottom of cube above the previous cube's top), if measurable. The interval must be positive and under five seconds so the final release occurs within the ten-second fixture.

Compare `rebound_to_drop_ratio`, `first_asleep_s`, and `max_lateral_drift_cubes` with the original measurements. Godot's `first_asleep_s` is an engine sleep event, while the original observation is visually still for one second; those are related but not identical. The stack fixture places the bottom cube initially and releases the next two at the configured interval and gap; its settling timer starts at the third release. Original placement conditions may still differ, so its drift is a *diagnostic baseline*, not a direct acceptance test. If the numbers diverge, vary one physics setting at a time and rerun; do not relabel tuned values as original facts without matching observation.
