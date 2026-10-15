---
name: stackfall-godot
description: How Stackfall workers run, test, lint, probe and measure the game in Godot safely (targeted tests, lints, off-screen captures, ENet harnesses, benchmarks, process limits). Preloaded into workers that launch Godot.
---

# Running Stackfall in Godot (workers)

## Checkout setup

- Agent worktrees come from `python tools/new_worktree.py <name>`, which adds the untracked off-screen `override.cfg`. If it is missing, run `python tools/agent_worktree_setup.py <worktree>` before any windowed launch (never in the main checkout).
- In a fresh worktree run `godot --headless --editor --path <wt> --quit` twice before anything else: the first run builds `.godot` (it is not shared between checkouts) and a run without it hangs on parse errors. Never delete another checkout's `.godot`.

## Tests

- Use the targeted runner only: `powershell -NoProfile -File tools/run_gut.ps1 <script>[,<script>] [-Unit <substr>] [-Path <checkout>]`. Read its `Totals` block; its exit code is not trustworthy. GUT "Unexpected Errors" (engine `ERROR:` lines) count as failures. Never run the full suite (`tools/guard_shell.py` refuses it for writer roles). `test_match_flow` and `test_match_lifecycle` take minutes; include them only when your files touch them.
- Before handback run `python tools/affected_tests.py --path <checkout>` and the tests it lists. Also grep `tests/` for assertions on every value, ordering, label, node name or fingerprint you changed, and for fixtures that use any gift, piece or rule id whose behaviour you changed (`&"rocket"`, `"bomb"`, `held_special_by_slot`, ...). Name them all in `checks`.
- Before calling a failure unrelated or pre-existing, rerun the same scripts on the base revision and report both results.
- Tests touching MultiplayerAPI/RPC set up their own peer state or use a send seam: an earlier suite test can leave `multiplayer.multiplayer_peer` cleared.
- Run an ENet harness (`tools/run_*_enet.ps1`, or `./tools/run_m3a_local.ps1 -Peers 4 -SimLag 100 -SimLoss 0.02`) only for `net/`, `autoload/`, rules or lobby changes. Report PASS only from its single `ENET RESULT PASS` / `ENET RESULT FAIL: <reason>` line, never from per-peer lines.

## Lints

- Before handback run `python tools/lint_all.py --path <checkout>` and name its `LINT ALL GREEN|RED` line in `checks`. Each lint's rules and options are in its docstring.
- Baselines only shrink: fix the code (tunables into `config/` Resources, the concept's single owner API, `ui/components`, delete dead code) instead of adding entries. A new file needs an explicit `--update --allow-new <path>` (for new `core/` or `config/` files reachable from autoloads: `python tools/lint_layers.py --update --allow-new <files>`); a true dead-weight false positive needs an `allow` entry with a reason; on a baseline merge conflict re-run the lint's update command.
- Every new numeric/bool/Color `@export` on an F4 tuning Resource (CameraTuning, GhostTuning, PhysicsTuning, TerritoryTuning, TerritoryVisuals, BlockFeedConfig) needs a one-sentence entry in `config/ui/tuning_panel_hints.tres` `descriptions` (and a slider range if the default is <= 0 or the useful range is not about [0, 4x default]); run `test_tuning_panel`.
- Any added or changed `tools/*.gd` gets `godot --headless --check-only -s <script>`: headless import does not compile unreferenced tool scripts.

## Godot runs, probes and screenshots

- Windowed launches follow the off-screen rule in CLAUDE.md §Environment. There is no probe-run cap: read code first, then probe as often as the problem needs and checkpoint progress on the Bead.
- Take screenshots with `tools/shot` (flags in the header of `tools/shot.gd`; extend it, with a test in `tests/unit/main/test_shot.gd`, when it cannot capture what you need) and judge its contact sheet, not single PNGs.
- `-s script.gd` runs a bare SceneTree without autoloads (Match, Net, Events). Throwaway probe scenes live under `res://tools/_scratch_<name>/` (deleted before handback) or your scratchpad and quit via `get_tree().quit()`. Never add `tools/screenshot_*`, `tools/capture_*` or `tools/*probe*` files: `tools/probe_lint.py` rejects them at integration.
- In probe mode `Net.host_game()` picks a random free port and skips LAN advertising, so benches do not block the ENet harness or appear in the user's LAN browser.
- Visual/UI acceptance: your contact sheet shows that each player's colour stays identifiable on the changed object, validity colours (valid/invalid placement, claim states) stay distinct, nothing clips, overflows or misaligns at 1280x720 and 1920x1080, and before/after shots use the same camera and layout. Say so in the handback if the sheet cannot show one of these.
- Synthetic OS keyboard injection does not reach the game window: drive `_unhandled_input` with `InputEventKey`/`InputEventJoypad*` in tests and leave real key presses to the user's manual steps. Real mouse input can leak into a windowed run.
- Never write `Steam` or `SteamMultiplayerPeer` as a bare identifier or static type: the GodotSteam addon is untracked and absent on most checkouts. Go through `Engine.has_singleton`/`ClassDB`.

## Processes and machine load

- Under Git Bash `tasklist | findstr /i godot` always fails; use `tasklist | grep -i godot` or `wmic process where "name like '%godot%'" get ProcessId,CommandLine`. Other agents run Godot in other worktrees: never kill Godot by image name (`tools/guard_shell.py` refuses it); kill only PIDs you started (`taskkill //F //PID <n>`), after reading their CommandLine.
- The launchers (`run_gut.ps1`, `full_gate.py`, `bot_h2h.py`, `measure_startup.py`, `new_worktree.py`) queue on `tools/godot_slots.py`; wrap any other launch in `python tools/godot_slots.py run -- godot ...`. `godot_slots.py status` shows holders and waiters.
- Never hand back while a Godot run you started is still alive: wait for its `Totals`/result line, then report.

## Measurements

- Benchmarks only for physics, territory or wire changes, and only alone: `python tools/godot_slots.py run --exclusive -- <cmd>` (Python launchers: `with godot_slots.godot_exclusive("label"):`). Label a contended run invalid. Headless physics timing is not a GPU frame rate or a two-machine Steam test; real hardware stays unverified until the user runs it.
- Startup timing: `python tools/measure_startup.py --path <checkout> [--runs 3]` (at least 3 off-screen real boots; AgentProbe `--quit-on-menu` quits when the main menu is ready), never `--quit-after` frames, which can exit mid-load.
- GPU cost: the only accepted measurement is `python tools/measure_gpu_steady.py run <preset>[:<feature>...] --repeat N --out <scratch>/runs.jsonl`, then `report`. Do not use `viewport_get_measured_render_time_gpu` alone (it excludes probe/sky passes), a harness that leaves the main menu rendering, or single uncapped samples (GPU clock states make them bimodal). Serialize GPU runs against every windowed Godot process.
