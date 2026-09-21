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
##
## DECISION (config/TerritoryTuning.gd, Bontago-cmc.5): the same capped list
## TerritorySolver keeps is what autoload/Match.gd now hands to
## game/TerritoryOverlay.gd's analytic circle shader and to
## net/MatchNet.gd's replicated circle list (core/net/CircleWire.gd), so this
## number is also the wire's hard cap (≤400 * 7 bytes ≈ 2.8 KB). A second,
## GPU-side budget, TerritoryVisuals.max_shader_circles, defaults to this
## value and can be lowered independently for a weaker GPU without touching
## the rules; it never raises the solver's own cap.
@export var max_circles: int = 400

## -- Rates (spec 3.3 "Recompute territory at 10 Hz", 3.4 "diffs at 5 Hz") ---
## DECISION (config/TerritoryTuning.gd): raised from spec 3.3's 10.0 to 20.0
## for the v2 rules. Owner clarifications 2026-09-20: "The area must update
## continuously -- if a stack falls the circles shrink/vanish immediately, not
## only when a new block is placed." BlockRegistry's settled flag already
## flips every physics frame, so the only lag left is how often the field is
## re-solved, and 50 ms is short enough that a toppling tower reads as
## instant. A full physics-tick rate would roughly triple the cost for a
## difference no player can see. Re-measured on tests/bench/bench_territory.tscn
## at this rate; see hash_cell_size below for the standing protocol when the
## budget is missed.
## DECISION (config/TerritoryTuning.gd, Bontago-cmc.7): this rate drives
## autoload/Match.gd's _tick_territory()/_run_territory_step() the same way
## under every MatchConfig.HoleMode -- TerritoryRaster._fill_legacy() (the
## default TEMPORARY/PERMANENT modes since the 2026-09-20 evidence audit) runs
## on the identical solve_accum loop as _fill_v2(), so a moving/collapsing
## tower's contest and hole state update at this rate too, not just its
## ownership.
@export var solve_hz: float = 20.0
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
## numbers").
##
## Re-measured for the M2 code review (2026-09-18: a single run had reported
## solve_ms≈8.95 / total_ms≈11.2, FAIL, against an earlier table's ~3.2 ms
## that didn't say where it came from). ~15 repeats here — idle, and under
## deliberate 6-way concurrent CPU contention — never reproduced anything
## close to that; worst observed total_ms at the graded 200-circle size was
## 6.44 ms even under contention, still inside the 8.0 ms budget. The
## TerritoryRaster/CellGrid change in the same milestone (odd-rounded `res`,
## `half_extent`) only renames a variable and grows the grid by at most one
## cell, and doesn't touch TerritorySolver at all — no regression found. The
## single bad reading is most likely a one-off scheduling/contention spike on
## whatever else was running on the reviewer's machine at the time, not a
## reproducible cost. hash_cell_size is unchanged; this is a documentation
## fix, not a tuning one.
##
## Total ms (solve + raster + win check) on map M, one run = 20 internal
## averages, 5 runs repeated, idle machine, Windows 10, Godot 4.7.2.stable,
## debug interpreter, M2 code-review fix pass:
##
##   cell size   |  4.0 |  6.0 |  8.0 | 10.0 | 12.0
##   200 circles | 5.96 | 4.13 | 3.51 | 3.54 | 3.59 ms
##   600 circles | 35.5 | 30.4 | 28.5 | 27.9 | 27.9 ms
##
## These run higher than the table they replace, most visibly at 600 circles
## (non-graded) — most likely a slower or busier machine than whatever
## recorded the old numbers, since the *relative* shape (12.0 best or
## tied-best throughout) hasn't changed and the graded 200-circle row still
## clears budget with room to spare either way.
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

## -- Goal-flag no-build zones (owner clarifications 2026-09-20) -------------
## "Goal flags have their own area of influence in which no player may place a
## block." A static disc of this radius around every goal flag, in meters,
## inside which PlacementRules.validate_point() refuses every placement.
## Ownership is deliberately unaffected: a player's area has to be able to
## reach through the zone, because winning means holding the flag's base
## inside that area (docs/TERRITORY_V2_PLAN.md, "Owner questions").
##
## DECISION (config/TerritoryTuning.gd): 4.0 m to start with -- a couple of
## cube widths of clearance around the pole, big enough that a player cannot
## wall the flag in with one block and small enough to leave the flag
## reachable on a 45 m map. A flat rule number like home_radius, not a
## per-map fraction, so it lives here and not on MapDef. Tune freely by eye.
@export var goal_zone_radius: float = 4.0

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
