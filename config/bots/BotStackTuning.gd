class_name BotStackTuning
extends Resource
## Tower-statics tunables for core/ai/BotStack.gd (Distances are metres).
## C "1t5.53a"). Shipped values live in config/bots/bot_stack_tuning.tres. Distances are metres.

## A cube is above another when its centre is higher by 0 < dy <= cube size + this.
@export var rest_tolerance_m: float = 0.08
## Two cube squares touch only when their overlap is at least this wide on both axes.
@export var min_contact_overlap_m: float = 0.1
## A body tilted more than this from upright is unsound (so is everything resting on it).
@export var max_tilt_deg: float = 8.0
## a piece may rest on a block face (fallen debris included) only when the face lies within this
## angle of the disc plane. Measured against the disc normal (the snapshot's local y), so it holds while the
## field tilts. Starts at max_tilt_deg.
@export var support_face_tolerance_deg: float = 8.0
## Blocks whose centre of mass lies within this distance of a tower source are snapshotted (53b).
@export var snapshot_radius_m: float = 4.0
## Cap on snapshotted bodies, nearest first (53b).
@export var snapshot_max_bodies: int = 96
## Bodies contact-analysed per BotStack.analyse_step call.
@export var analyse_bodies_per_step: int = 8
## A block at or below this speed counts as settled (read by the 53b snapshot; spec 1.5 filter).
@export var settled_speed_mps: float = 0.15
## A projected cube square smaller than this (m^2) is degenerate and has no contact outline.
@export var degenerate_area_m2: float = 0.0001
## Cells of the column hash searched around a cube (1 = the 3x3 neighbourhood).
@export var hash_reach_cells: int = 1
## Cube lists kept between thinks by game/BotStackProbe (sleeping blocks cost one comparison); the
## cache is cleared when it grows past this (.53b).
@export var probe_cache_limit: int = 512
## A tower-top circle finds its body among the snapshot's bodies whose centre of mass
## lies within this distance of the circle centre (the circle is built on the same centre of mass).
@export var circle_match_radius_m: float = 1.0
## STATICS_DESIGN 3: the stability model's allowance for snapshot float noise and Jolt contact slop,
## about one cube_margin. A placement is stable only while its centre-of-mass margin exceeds the requirement.
@export var numeric_tolerance_m: float = 0.02
## Share of the tier's worst-case aim error (BotDifficultyProfile.aim_noise_m) the model requires as margin:
## 1.0 = the whole error (the), 0 = ignore aim.
@export var aim_margin_share: float = 1.0
## Extra margin required of a placement when gifts are on (read by the disturbance package).
@export var gift_disturbance_m: float = 0.1
