class_name TerritoryTuning
extends Resource
## Every tunable number the territory rules need (spec 2.2, 2.3, 3.3).
##
## DECISION (config/TerritoryTuning.gd): spec 3.6 sketches these as extra
## fields on PhysicsTuning. They live in their own resource instead, for the
## same reason GhostTuning already split off: PhysicsTuning holds rigid-body
## numbers that the physics benchmarks tune, while these are rule numbers that
## the pure core/ solver tunes, and the two are edited by different people at
## different times. PhysicsTuning keeps the settled-block thresholds
## (sleep_linear_threshold / sleep_angular_threshold / sleep_settle_time),
## which are read from here's consumers, not duplicated.
##
## Loaded once as config/territory_tuning.tres.

## -- Influence circles (spec 2.2) -------------------------------------------
## r = influence_base + influence_k * h, where h is the height of the block's
## highest point above the disk surface along the disk normal.
@export var influence_base: float = 1.5
@export var influence_k: float = 0.9
## r is capped at influence_max_fraction * field_radius (spec 2.2: 0.6).
@export var influence_max_fraction: float = 0.6
## The home flag's own circle, which exists while the flag is on the disk.
@export var home_radius: float = 6.0
## Safety valve for the raster fill cost: when more circles than this are
## live, keep the largest-radius ones per team and drop the rest. A dropped
## circle is always fully inside a kept one of the same team in practice,
## because the big ones are the tall towers.
@export var max_circles: int = 400

## -- Rates (spec 3.3 "Recompute territory at 10 Hz", 3.4 "diffs at 5 Hz") ---
@export var solve_hz: float = 10.0
@export var raster_upload_hz: float = 5.0

## -- Solver spatial hash (spec 3.3) -----------------------------------------
## DECISION: spec 3.3 says "cell size = influence_max". influence_max is
## 0.6 * 45 = 27 m at map size M, so the whole disk is about 3x3 hash cells
## and the hash degenerates into brute force. Each circle is instead inserted
## into every hash cell its bounding box covers, at this smaller fixed size;
## the few genuinely huge circles occupy many cells, which is correct and
## still far cheaper than all-pairs.
##
## Raised from the plan's starting 4.0 to 12.0 after measuring, which
## docs/M2_PLAN.md's P1 acceptance note explicitly allows ("raise
## hash_cell_size ... in the resource, never in code, and report the
## numbers"). Solve time on map M, 20 runs averaged, debug interpreter:
##
##   cell size |  4.0 |  6.0 |  8.0 | 10.0 | 12.0
##   200 circles | 5.75 | 3.98 | 3.69 | 3.30 | 3.20 ms
##   600 circles | 27.7 | 23.3 | 19.8 | 20.3 | 17.4 ms
##
## Cost tracks how many buckets each circle is inserted into, not how many
## overlapping pairs come back: small cells shred every circle across dozens
## of buckets, and each bucket then re-examines the same neighbours. A cell of
## roughly twice the typical influence diameter is the sweet spot.
@export var hash_cell_size: float = 12.0

## -- Contested zones and holes (spec 2.2) -----------------------------------
## A contested cell becomes a hole after this long.
@export var hole_delay: float = 0.75
## hole_mode = TEMPORARY: a hole closes this long after the overlap ends.
## Ignored when hole_mode = PERMANENT.
@export var hole_close_delay: float = 2.0
## Spec 3.3: "Batch the toggles so there are at most 64 per frame."
@export var max_cell_toggles_per_frame: int = 64

## -- Win check (spec 2.3) ---------------------------------------------------
## One connected territory must contain every goal flag for this long.
@export var capture_hold: float = 3.0

## -- Auto-drop (spec 2.5: "If that spot isn't valid, it drops at the closest
## valid point") -------------------------------------------------------------
## Spiral search step and how far out it is allowed to look, in meters.
@export var auto_drop_search_step: float = 1.0
@export var auto_drop_search_max_radius: float = 12.0

## -- Reject (spec 2.2: a block released in a contested area "is thrown off
## the map with a visible reject animation") ---------------------------------
@export var reject_impulse: float = 30.0
## Fraction of the reject impulse aimed straight up; the rest points radially
## outward from the disk center.
@export var reject_upward_fraction: float = 0.35
