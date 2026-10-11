class_name BotGenTuning
extends Resource
## Bot V2 site generation and analytic statics tunables (docs/BOT_AI_REDESIGN.md 2.3
## steps 4-5). Read by core/ai/BotCandidateGen.gd and core/ai/BotStatics.gd; the
## shipped values live in config/bot_gen_tuning.tres. Distances are metres unless a
## name says "cubes" (one cube is PhysicsTuning.cube_size).

@export_group("Tip sites")
## How far inside an own circle's edge a tip site sits (the circle's reach is only
## useful while the origin is still inside own territory).
@export var tip_inset_m: float = 0.3
## Best frontier circles kept as tip anchors ("best 12").
@export var tip_anchor_count: int = 12
## Anchors closer than this to an already kept anchor are dropped.
@export var tip_min_spacing_m: float = 0.75
## A circle's edge point inside another own circle by more than this is not frontier.
@export var tip_frontier_margin_m: float = 0.25
## Step and count when an edge point is not placeable (contested, hole, goal zone):
## walk back towards the circle centre.
@export var tip_backoff_step_m: float = 0.25
@export var tip_backoff_max_steps: int = 8
## Lateral offsets (each side) and depth rows (towards the circle centre) around an anchor.
@export var tip_lateral_steps: int = 2
@export var tip_lateral_step_m: float = 0.8
@export var tip_depth_rows: int = 2
@export var tip_depth_step_m: float = 0.8
## Orientations offered per tip anchor (best reach first).
@export var tip_orientation_variants: int = 2

@export_group("Stack sites")
## Own circles at least this tall count as a stack top.
@export var stack_min_height_m: float = 1.0
## Stack tops considered (tallest first), each with jittered neighbours.
@export var stack_site_count: int = 8
@export var stack_jitter_m: float = 0.5
## Flattest orientations offered per stack top.
@export var stack_orientation_variants: int = 2

@export_group("Mix")
## Share of the candidate budget per source; the remainder is uniform FILL.
## Default intents (RACE, DEFEND, STRIKE, SIEGE).
@export var tip_share: float = 0.55
@export var stack_share: float = 0.2
## Tower intents (ANCHOR, FINISH, HOLD).
@export var tower_tip_share: float = 0.35
@export var tower_stack_share: float = 0.4
## AREA intent.
@export var area_tip_share: float = 0.3
@export var area_stack_share: float = 0.1
## Uniform-fill attempts allowed per missing site before giving up.
@export var fill_attempts_per_site: int = 12
## Uniform-fill draws per think step (the fill is sliced so a step stays inside the budget).
@export var fill_chunk_attempts: int = 24
## Sites proxy-scored per think step.
@export var rank_chunk_sites: int = 8
## Fill sites prefer orientations at or below this tip risk.
@export var fill_risk_max: float = 0.5

@export_group("Orientations")
## Distinct (footprint, height) orientations kept per shape.
@export var max_orientations_per_shape: int = 6
## Sites closer than this with the same orientation count as duplicates.
@export var distinct_quantum_m: float = 0.25

@export_group("Statics")
## Highest tip risk at which an orientation is still offered at a tip.
@export var tip_risk_max: float = 0.4
## Height over the smaller support side (slenderness) at which risk starts / hits 1.
@export var slender_safe: float = 2.0
@export var slender_max: float = 5.0
## Centre of mass this many cubes outside the supported rectangle = risk 1.
@export var overhang_full_cubes: float = 0.5
## A bottom cube counts as supported when this share of the probed cells under it are.
@export var supported_cell_fraction: float = 0.5
## Probed support within this of the pivot support height counts as contact.
@export var contact_tolerance_m: float = 0.15
## Without a grid: unsupported share of probed cells tolerated before overhang risk grows.
@export var unsupported_safe_fraction: float = 0.25
