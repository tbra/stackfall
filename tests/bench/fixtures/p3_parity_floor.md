# P3 parity floor

Fixture: `p3_parity_reference.json` (sha256 prefix c90b0080fa13), from `tests/bench/bench_p3_parity.tscn`, seed 20261025, 1420 ticks, 70940 keys.

Floor (largest pairwise diff of three separate-process reference runs, two on an idle machine, one while a GUT script ran in a second headless Godot): **0** on every key, bit-identical files. Every later gate says `differing=0`, no tolerance table.

Gate command (the first path must be the `res://` fixture; recordings are absolute paths):

    godot --headless --fixed-fps 60 --path <checkout> res://tests/bench/bench_p3_parity.tscn -- --out=<abs>/run.json
    godot --headless --path <checkout> res://tests/bench/bench_p3_parity.tscn -- --compare=res://tests/bench/fixtures/p3_parity_reference.json,<abs>/run.json

Pass is the `BENCH_P3_PARITY compare keys=70940 differing=0` line. No extra flag is needed for settings isolation: a scene under `res://tests/` makes `AgentProbe.is_active()` true, so `Settings` reads a per-process file (defaults) and never the user's `settings.cfg`; the run refuses to start otherwise, and the pinned `header.mouse_move_speed_scale` is part of the recording.
