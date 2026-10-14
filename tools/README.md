# tools/

Only tools that something executes or loads live here (Bontago-dbn.1). Asset generators, one-off screenshot, capture and bench probes were removed; see git history. Each `test_*.py` belongs to the tool of the same name; run them with `python -m unittest discover -s tools -p "test_*.py"`.

## Game build
- `bootstrap_project.gd` - regenerates project settings and the Input Map (`godot --headless --path . -s tools/bootstrap_project.gd`).
- `export_windows.ps1` - Windows export.
- `stamp_build_info.gd` - stamps build info during export.

## Gates and tests
- `full_gate.py`, `full_gate_serial.txt` - sharded full GUT suite (one `FULL GATE GREEN|RED` line).
- `run_gut.ps1` - targeted GUT runner.
- `affected_tests.py` - lists the tests a change affects.
- `godot_slots.py`, `godot_exe.py` - Godot process slots and executable lookup.
- `check_scripts.gd` - script parse check used by `integrate_batch.py`.
- `integrate_batch.py` - merge, gate, push and close a reviewed batch.
- `probe_lint.py`, `probe_allowlist.txt` - blocks stray probe/screenshot files and missing `.uid`s.
- `lint_all.py` - runs the four lints below.
- `lint_magic_numbers.py`, `lint_single_source.py`, `lint_layers.py`, `lint_ui_components.py` with `magic_number_baseline.json`, `single_source_baseline.json`, `layer_baseline.json`, `ui_components_baseline.json`.
- `dep_graph.py`, `dep_graph_viewer.html` - dependency graph used by `lint_layers.py`.
- `normalize_eol.py` - LF normalisation before staging.
- `triage_log.py` - ranked summary of a long headless log.

## Multiplayer and bots
- `run_m3a_local.ps1` - one host plus N-1 ENet clients with simulated lag.
- `run_*_enet.ps1`, `enet_result.ps1` - two-to-four peer ENet acceptance drivers; each prints one `ENET RESULT` line.
- `bot_h2h.py` - bot head-to-head harness.
- `run_bot_think_cost.ps1` - bot decision cost measurement.
- `check_steam_setup.ps1`, `steam_probe.gd` - verify the per-developer GodotSteam install.

## Measurement and capture
- `measure_startup.py` - startup time.
- `measure_gpu_steady.py` - steady-state GPU cost via `tests/bench/bench_gpu_frame.tscn`.
- `perf_log_summary.py` - summarises PerfLogger logs (also run by `test_debug_mode`).
- `cpumon.ps1` - CPU monitor.
- `screenshot_main.gd/.tscn`, `sandbox_shot.gd/.tscn`, `menu_atlas.gd/.tscn` - off-screen capture tools named in `docs/AGENT_WORKFLOW.md`.
- `ContactSheet.gd`, `contact_sheet.py` - contact sheets for captures.

## Agent workflow
- `new_worktree.py`, `agent_worktree_setup.py`, `prune_worktrees.py`, `scratch.py` - worktrees and scratch space.
- `board_brief.py`, `session_brief.py`, `owner_replies.py` - session and Beads briefs (owner replies run as a hook).
- `skill_versions.py` - skill version check.
- `route_model.py`, `rank_context.py` - Jev routing and relevance hints.
- `validate_worker_handback.py`, `guard_reviewer_bash.py`, `guard_store_python.py` - hooks.
- `stage_codex_handoffs.py` - stage Codex handoff files.
