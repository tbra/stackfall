class_name BenchBudgets
extends Resource
## Render-cost ceilings for the headless benchmark scripts under
## res://tests/bench/. These budgets are set from a real (windowed,
## GPU-backed) run of the matching bench scene -- a headless run always
## reports 0 from RenderingServer.get_rendering_info() (no rendering backend
## is active), so the bench that reads this resource skips the check
## entirely rather than failing on the missing data. CLAUDE.md: "No magic
## numbers... every tunable value belongs in a Resource under res://config/".
## Loaded once as config/bench_budgets.tres.

## -- tests/bench/bench_block_material_cost.gd (Bontago-xtq.38): 300 blocks,
## each built by BlockFactory with the M7 toon-shading + inverted-hull
## outline pass (two MeshInstance3D per block, see game/BlockFactory.gd's
## own DECISION comment). Intended to be set to 1.25x a real measured value
## -- see the bench's own printed render_result= line for the last measured
## numbers.
##
## DECISION (Bontago-xtq.38 round 3, orchestrator): the bench has no floor,
## so its 300 blocks free-fall out of the camera's frustum during the 5 s sim;
## the metric is therefore the PEAK per-frame count over the run, not the
## end-of-run sample (round 2 read 1/1 that way). Windowed run with the
## Camera3D + DirectionalLight3D from _ready() measured peak draw_calls=23,
## objects=425 (300 blocks x 2 MeshInstance3D each, partly frustum-culled).
## Budgets = 1.25x measured rounded up to a round number: 30 / 540. Measured
## 2026-09-26, Windows 10 Pro, Godot 4.7.2 Forward+, --windowed --position
## 10000,10000 (off-screen windows do render; earlier 0/0 was the missing camera).
@export var block_material_cost_draw_call_budget: int = 30
@export var block_material_cost_object_budget: int = 540

## Camera setup for windowed render sampling (bench_block_material_cost.tscn):
## horizontal distance from field center to camera position, in units.
@export var bench_camera_distance: float = 50.0
## vertical offset above field center for camera position, in units.
@export var bench_camera_height: float = 35.0
