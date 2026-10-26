# P6 parity floor

`p6_parity_reference.json` is the recording of `tests/bench/bench_p6_parity.tscn` on the unmodified base.

Floor: three reference runs (separate processes, same seed; two with no other Godot running, one while a second
headless Godot ran the crate part) were byte-identical. The largest pairwise diff is 0 for every field of parts A
(effect state), R (Volcano and Jumping Bean) and B (crate lifecycle: air-touch claim, landed claim, expiry and
relocation, event order). Every later gate therefore compares at `--tol=0` (the default) with event order exact.

Record: `godot --headless --fixed-fps 60 --path . res://tests/bench/bench_p6_parity.tscn -- --out=run.json`
Compare: `godot --headless --path . res://tests/bench/bench_p6_parity.tscn -- --compare=a.json,b.json`

Settings isolation needs no flag: a scene under `res://tests/` makes `AgentProbe.is_active()` true, so `Settings` reads a per-process file with defaults and never the user's `settings.cfg` (the recipe reads no setting anyway). Part R draws from the game's own unseeded random
generators (Volcano bursts, Jumping Bean hops) and was reproducible in all three runs; if a later run differs
only in part R, re-measure it before treating it as a regression.
