class_name BotStackTuning
extends Resource
## Tower-statics tunables for core/ai/BotStack.gd (Bontago-1t5.53a, docs/BOT_TOWER_PLAN.md
## C "1t5.53a"). Shipped values live in config/bot_stack_tuning.tres. Distances are metres.

## A cube is above another when its centre is higher by 0 < dy <= cube size + this.
@export var rest_tolerance_m: float = 0.08
## Two cube squares touch only when their overlap is at least this wide on both axes.
@export var min_contact_overlap_m: float = 0.1
## A body tilted more than this from upright is unsound (so is everything resting on it).
@export var max_tilt_deg: float = 8.0
## Centre-of-mass margin (metres inside the support hull) at which a site counts as fully safe.
## Read by the evaluator (53b); BotStack itself only reports the margin.
@export var safe_margin_m: float = 0.2
## Blocks whose centre of mass lies within this distance of a tower source are snapshotted (53b).
@export var snapshot_radius_m: float = 4.0
## Cap on snapshotted bodies, nearest first (53b).
@export var snapshot_max_bodies: int = 96
## Bodies contact-analysed per BotStack.analyse_step call.
@export var analyse_bodies_per_step: int = 8
## A block at or below this speed counts as settled (read by the 53b snapshot; spec 2.2 filter).
@export var settled_speed_mps: float = 0.15
## A projected cube square smaller than this (m^2) is degenerate and has no contact outline.
@export var degenerate_area_m2: float = 0.0001
## Cells of the column hash searched around a cube (1 = the 3x3 neighbourhood).
@export var hash_reach_cells: int = 1
## Cube lists kept between thinks by game/BotStackProbe (sleeping blocks cost one comparison); the
## cache is cleared when it grows past this (Bontago-1t5.53b).
@export var probe_cache_limit: int = 512
