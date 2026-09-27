# Original Bontago versus Stackfall: drop and stack comparison

This contains a measured standalone Tokamak reference and an original-game observation protocol, not evidence that Bontago used Tokamak's defaults. The engine release in `feedback/tokamak_release/` does not contain Bontago's game settings. Keep the original installed-game recording and measured values separate from the Godot run. Do not copy original assets into this repository.

## Measured Tokamak reference (2026-09-27)

The locally supplied Tokamak source now builds as a standalone headless Windows executable. Engine source is unmodified. See `tools/tokamak_compare/README.md` for compiler/version/checksum, source-default provenance and measurement definitions.

Both fixtures use a 0.98 m collision cube, 1 kg mass, gravity 9.8 m/s², 60 Hz and ten simulation seconds. Drop height is two cube edges; the three-cube stack starts with a resting bottom cube and releases the other two at two-second intervals with a 0.3-edge gap. Tokamak uses a fixed box floor; Stackfall uses its real Field. This compares configured behavior, not intrinsic engine quality or original-game fidelity.

Three repeats per engine and mode produced identical reported measurements within each configuration. Values below are medians; observed repeat ranges are zero. These deterministic repeats verify reproducibility of identical initial conditions, not statistical confidence across real-game placements.

| Measurement | Stackfall shipped tuning | Tokamak source defaults |
| --- | ---: | ---: |
| Drop first contact (simulation s) | 0.667 | 0.650 |
| Drop rebound (cube edges) | 0.000 | 0.345 |
| Rebound / drop-height ratio | 0.000 | 0.172 |
| Drop first engine sleep/idle (s after release) | 1.150 | 4.000 |
| Drop maximum sideways drift (cube edges) | approximately 0 | 0.678 |
| Stack first engine sleep/idle (s after final release) | 0.733 | 1.983 |
| Stack maximum top-cube sideways drift (cube edges) | 0.000089 | 0.042490 |

All bodies were asleep/idle at the end of both tests. Tokamak's lateral motion occurs in the controlled centred drop; it is a measured result of this fixture, not a confirmed property of Bontago. Sleep/idle thresholds and collision-event sampling differ between engines and must not be treated as equivalent visual settling measurements.

Tokamak's queried material defaults are friction 0.5 and restitution 0.4, with body linear/angular damping zero. Stackfall uses block friction 0.8, disc friction 0.9, restitution 0.05 and linear/angular damping 0.1. Tokamak has no comparable project-specific vertical rebound-damping feature. Matching material/damping settings would be a separate experiment before attributing any difference to the solvers.

Native raw records and per-tick traces are in `feedback/tokamak-comparison/results.json` and `drop-1.csv` through `stack-3.csv`. Stackfall raw records are in `feedback/stackfall-reference-{drop,stack}-{1,2,3}.log`. These evidence files are local and ignored by Git.

Rerun the native baseline (already built locally):

```powershell
pwsh -NoProfile -File tools/tokamak_compare/run.ps1
```

To compare manually in Sandbox, use F2 with height **2.0**, interval **2.0**, gap **0.3**, and compare your result with the table. The runner also accepts `-Height`, `-Interval`, `-Gap` and `-Repeats` when testing other conditions; regenerate the native baseline for the same conditions.

For a material/damping comparison on Jolt, select **F4 → Physics → Tokamak defaults (Jolt)** before the trial. It sets block and disc friction to 0.5, restitution to 0.4, linear/angular damping to zero and disables the custom vertical rebound reduction (multiplier 1). Cube mass 1 kg and gravity multiplier 1 are reference-fixture choices, not inferred Bontago values. Jolt's solver, contact mixing and sleep behavior remain unchanged; Tokamak's native sleep parameter is not mapped onto territory-settling thresholds. Select **Current** to restore shipped physics values.

Original-game measurements remain pending: no controlled original-game recording was available, and native app control/recording was unavailable in this session. Follow the protocol below; Beads `Bontago-2z7` tracks this remaining evidence step. No physics tuning was changed as a result of this comparison.

## Capture in the installed original

1. Use a quiet single-player/sandbox field with no specials, no board tilt and as few existing blocks as possible. Record screen at a fixed frame rate; keep the cube edge visible as the scale reference. Note game version, map, video frame rate, and any physics/settings changes.
2. Drop an ordinary single cube near the disk centre. Record the release, first disk contact, highest point after first impact, and first time it stays still for at least one second. Estimate release height and rebound height in **cube-edge lengths**, measured from the cube's bottom to its resting bottom position. Repeat three times; report median and range. If the cube never visibly leaves the disk, record rebound as below video resolution rather than exactly zero.
3. On a cleared field, place three single cubes in a vertical stack at the same spot, letting each land before releasing the next. Record the time from the third release until all three remain still for one second; measure the top cube's greatest sideways offset from the stack centre in cube-edge lengths. Repeat three times. Mark any attempt with a sloping/tilted disk or interference as invalid, rather than silently discarding it.

The original's placement cadence, hover height and exact release height are not yet known. Report them from the recording; do not assume the controlled Godot drop starts at the same height. A screenshot can show heights but not settle time—use video or frame-by-frame capture for timing.

## Run the remake fixture

### Interactive sandbox

Enter Sandbox from the main menu, then press **F2** (gamepad **Back + X**) to open the physics comparison controls. Run a single-cube drop or a sequential three-cube stack; adjust the release height, stack release interval and gap to match your original-game observations. Trials use the current physics tuning, so use **F4 → Physics** to select a preset or change its values before starting the next trial.

Read the measurements as simulated seconds and cube-edge lengths. Engine sleep is not the same measurement as the original recording's “visually still for one second.” These trials measure Stackfall; they do not supply missing Bontago measurements or run Tokamak inside Godot. Use a clear, level field and keep other blocks and specials away from the trial area.

From the repository root, after a normal Godot project import:

```powershell
godot --headless --path . res://tests/bench/compare_original_physics.tscn -- --mode=drop --drop-height-cubes=2.0
godot --headless --path . res://tests/bench/compare_original_physics.tscn -- --mode=stack
```

Set `--drop-height-cubes` to the median measured original release height; run at least the original minimum and maximum heights as a sensitivity check. The fixture uses the shipped `PhysicsTuning` and `BlockFactory`, a real `Field`, one cube dropped at the centre, or three cubes released sequentially over one another. It runs ten simulated seconds per invocation and prints a single `PHYSICS_COMPARE result=` JSON record. It does not change any tuning or assert a pass/fail verdict.

For the stack run, `--stack-interval-s=2.0` and `--stack-gap-cubes=0.3` are adjustable. Set these to the observed time between releases and release gap (bottom of cube above the previous cube's top), if measurable. The interval must be positive and under five seconds so the final release occurs within the ten-second fixture.

Compare `rebound_to_drop_ratio`, `first_asleep_s`, and `max_lateral_drift_cubes` with the original measurements. Godot's `first_asleep_s` is an engine sleep event, while the original observation is visually still for one second; those are related but not identical. The stack fixture places the bottom cube initially and releases the next two at the configured interval and gap; its settling timer starts at the third release. Original placement conditions may still differ, so its drift is a *diagnostic baseline*, not a direct acceptance test. If the numbers diverge, vary one physics setting at a time and rerun; do not relabel tuned values as original facts without matching observation.
