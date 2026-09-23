class_name BotPlacementScorer
extends RefCounted
## Pure (CLAUDE.md "core/ ... no dependence on the scene tree"): every
## argument is a value type or an already-built core/ object.
##
## docs/M5_PLAN.md P2 (Bontago-d5c.3): real scoring for the four spec 2.9
## factors -- height gained, goal progress, stability, risk -- combined with
## BotTuning's four weights, plus flattest_orientations()'s pure geometry and
## pick_best()'s highest-scorer selection. P1's trivial default bodies (always
## candidates[0], flattest_orientations() == [0], score() == 0.0) are gone;
## every signature below is exactly what P1 committed.
##
## DECISION (Bontago-d5c.3): "goal progress" and "stability" are the two
## factors spec 2.9 does not give an exact formula for, so both are estimates,
## not a recompute of the real territory/physics state:
## - Goal progress: distance(candidate.origin, nearest goal) minus the
##   candidate's own estimated future influence-circle radius
##   (InfluenceCircle.radius_for_height(candidate.support_height, ...)) -- a
##   smaller (even negative) number is better. A full TerritorySolver.solve()
##   per candidate (up to 120 per bot per think-cycle, docs/M5_PLAN.md's own
##   "Known risks: Perf") is the actual thing this estimate avoids doing.
## - Stability: BotCandidate carries `footprint_cells` (the geometric
##   footprint PlacementRules.footprint_cells() already computed) but not what
##   game/BotController.gd's own `_fire_stability_raycasts()` corner samples
##   found -- that file's class doc names this ("P2 is the package that stores
##   and scores what each one finds (BotCandidate may gain a field for that
##   then)"), but this package's own brief is explicit: "Must NOT touch
##   game/BotController.gd" (owned by another package's window right now). So
##   `corner_support_hits` is appended to BotCandidate as the real signal
##   *once something populates it*, defaulting to -1 ("not measured"); today,
##   with no producer wired in, every real candidate reports -1 and
##   `_stability_term()` falls back to treating the whole geometric footprint
##   as in contact. Flagged as a known limitation/follow-up: whichever package
##   next owns game/BotController.gd should have `_fire_stability_raycasts()`
##   tally hits near `support_height` into this field instead of discarding
##   them, at which point this scorer already knows what to do with it.

## Distance-decayed penalty for a candidate close to an enemy circle center or
## an active special -- 0 at or past `radius`, growing linearly to `radius` at
## `distance == 0`. Both risk terms below use the same shape, just different
## radii (BotTuning.risk_enemy_territory_radius_m /
## risk_active_special_radius_m), so one helper serves both lists.
static func _proximity_penalty(origin: Vector2, centers: PackedVector2Array, radius: float) -> float:
	if radius <= 0.0:
		return 0.0
	var penalty: float = 0.0
	for center: Vector2 in centers:
		var distance: float = origin.distance_to(center)
		if distance < radius:
			penalty += radius - distance
	return penalty


static func _risk_term(
	candidate: BotCandidate,
	enemy_circle_centers: PackedVector2Array,
	active_special_positions: PackedVector2Array,
	tuning: BotTuning
) -> float:
	return (
		_proximity_penalty(candidate.origin, enemy_circle_centers, tuning.risk_enemy_territory_radius_m)
		+ _proximity_penalty(candidate.origin, active_special_positions, tuning.risk_active_special_radius_m)
	)


## Estimated "how much closer the territory edge gets to the goal", spec 2.9's
## goal-progress factor: nearest-goal distance minus the candidate's own
## estimated future influence radius at its support height. Smaller (even
## negative, meaning the estimated circle already reaches the goal) is better;
## the caller negates this before adding it to the weighted sum. 0.0 (neutral)
## when there is no goal to measure against or no TerritoryTuning to compute a
## radius from (a raster built with a null tuning -- should not happen in real
## play, but score() must not crash a bot's think-cycle over it).
static func _goal_progress_metric(
	candidate: BotCandidate,
	goal_positions: PackedVector2Array,
	territory_tuning: TerritoryTuning,
	field_radius: float
) -> float:
	if goal_positions.is_empty() or territory_tuning == null:
		return 0.0
	var nearest: float = INF
	for goal: Vector2 in goal_positions:
		nearest = minf(nearest, candidate.origin.distance_to(goal))
	var radius: float = InfluenceCircle.radius_for_height(candidate.support_height, territory_tuning, field_radius)
	return nearest - radius


## True when `candidate.origin` -- the stand-in for the shape's own centre of
## mass (docs/M5_PLAN.md P2: "approximated as candidate.origin for a
## single-cube-pivot shape") -- falls inside the axis-aligned bounding box of
## `footprint_cells`' own cell centres, expanded by half a cell so a centre
## sitting exactly on a footprint cell still counts. That bounding box is a
## cheap, always-convex stand-in for "the convex hull of supported cells" --
## exact for the common rectangular footprints every shipped BlockShape
## produces, a safe over-approximation otherwise (errs towards calling a
## placement balanced, the same direction PlacementRules.footprint_cells()'s
## own square-per-cube approximation already leans).
static func _origin_within_footprint_bounds(candidate: BotCandidate, grid: CellGrid) -> bool:
	if grid == null or candidate.footprint_cells.is_empty():
		return true
	var half_cell: float = grid.cell_size * 0.5
	var min_x: float = INF
	var max_x: float = -INF
	var min_z: float = INF
	var max_z: float = -INF
	for index: int in candidate.footprint_cells:
		var center: Vector2 = grid.index_center(index)
		min_x = minf(min_x, center.x)
		max_x = maxf(max_x, center.x)
		min_z = minf(min_z, center.y)
		max_z = maxf(max_z, center.y)
	return (
		candidate.origin.x >= min_x - half_cell and candidate.origin.x <= max_x + half_cell
		and candidate.origin.y >= min_z - half_cell and candidate.origin.y <= max_z + half_cell
	)


## Spec 2.9's stability factor: how much of the footprint is actually in
## contact (see this file's own class doc on `corner_support_hits`'s
## not-yet-wired producer), whether the origin/centre-of-mass stand-in falls
## inside the supported area, and a flat bonus for resting on the bot's own
## already-placed stack -- "on_top_of_own_stack == true with full contact
## scores higher than one balanced on a corner" (docs/M5_PLAN.md P2).
static func _stability_term(candidate: BotCandidate, grid: CellGrid) -> float:
	var cell_count: int = candidate.footprint_cells.size()
	if cell_count == 0:
		return 0.0
	var contact_cells: float
	if candidate.corner_support_hits >= 0:
		contact_cells = float(mini(candidate.corner_support_hits, cell_count))
	else:
		# Not yet measured (see class doc): the whole geometric footprint is
		# assumed in contact, which is exactly what every real candidate
		# reports today.
		contact_cells = float(cell_count)
	var balance_factor: float = 1.0 if _origin_within_footprint_bounds(candidate, grid) else 0.5
	var stack_bonus: float = 1.0 if candidate.on_top_of_own_stack else 0.0
	return contact_cells * balance_factor + stack_bonus


## Weighted sum of the four spec 2.9 factors. `team_id` names whose territory
## `candidate` was sampled inside (BotController already only ever samples a
## point inside its own team's area -- see _sample_territory_point()), kept in
## the signature because P1 committed it and a future factor may want it; this
## package's own scoring math does not need it, since goal_positions/
## enemy_circle_centers/active_special_positions are already resolved relative
## to the calling bot before this is ever invoked.
static func score(
	candidate: BotCandidate,
	raster: TerritoryRaster,
	grid: CellGrid,
	team_id: int,
	goal_positions: PackedVector2Array,
	enemy_circle_centers: PackedVector2Array,
	active_special_positions: PackedVector2Array,
	tuning: BotTuning,
	field_radius: float
) -> float:
	var territory_tuning: TerritoryTuning = raster.tuning() if raster != null else null
	var goal_metric: float = _goal_progress_metric(candidate, goal_positions, territory_tuning, field_radius)
	var stability_term: float = _stability_term(candidate, grid)
	var risk_term: float = _risk_term(candidate, enemy_circle_centers, active_special_positions, tuning)
	return (
		tuning.weight_height * candidate.support_height
		- tuning.weight_goal_progress * goal_metric
		+ tuning.weight_stability * stability_term
		- tuning.weight_risk * risk_term
	)


## How many of `cells` (rotated by `basis`) sit at the lowest transformed
## height -- the flat-footprint coverage of resting this shape down on that
## face. Pure geometry: `basis` is always one of BlockOrientations' 24
## axis-aligned rotations, so every transformed offset lands on (or within
## float rounding of) an integer grid coordinate.
static func _flat_footprint_coverage(cells: Array[Vector3i], basis: Basis) -> int:
	if cells.is_empty():
		return 0
	var heights: PackedInt32Array = PackedInt32Array()
	heights.resize(cells.size())
	var min_height: int = 2147483647
	for i: int in range(cells.size()):
		var transformed: Vector3 = basis * Vector3(cells[i])
		var height: int = int(round(transformed.y))
		heights[i] = height
		min_height = mini(min_height, height)
	var coverage: int = 0
	for height: int in heights:
		if height == min_height:
			coverage += 1
	return coverage


## Spec 2.9 "the orientation (out of the 24) that gives the flattest base" --
## purely from `shape.cells` geometry, independent of terrain. Ranks every one
## of BlockOrientations' 24 entries by `_flat_footprint_coverage()` (highest
## first; ties broken by ascending index, so a shape with no single flattest
## face -- a cube, any face is equally flat -- still deterministically returns
## the identity orientation first) and returns up to `max_count` distinct
## indices. The caller still scores each returned index against the real site
## (terrain is not consulted here at all).
static func flattest_orientations(shape: BlockShape, max_count: int) -> Array[int]:
	var result: Array[int] = []
	if shape == null or shape.cells.is_empty() or max_count <= 0:
		return result
	var orientation_count: int = BlockOrientations.count()
	var coverage: PackedInt32Array = PackedInt32Array()
	coverage.resize(orientation_count)
	for i: int in range(orientation_count):
		coverage[i] = _flat_footprint_coverage(shape.cells, BlockOrientations.get_basis(i))
	var indices: Array[int] = []
	for i: int in range(orientation_count):
		indices.append(i)
	indices.sort_custom(func(a: int, b: int) -> bool:
		if coverage[a] != coverage[b]:
			return coverage[a] > coverage[b]
		return a < b
	)
	var limit: int = mini(max_count, indices.size())
	for i: int in range(limit):
		result.append(indices[i])
	return result


## The one entry point BotController calls once a think-tick's candidate list
## is complete. Null only when `candidates` is empty.
static func pick_best(
	candidates: Array[BotCandidate],
	raster: TerritoryRaster,
	grid: CellGrid,
	team_id: int,
	goal_positions: PackedVector2Array,
	enemy_circle_centers: PackedVector2Array,
	active_special_positions: PackedVector2Array,
	tuning: BotTuning,
	field_radius: float
) -> BotCandidate:
	if candidates.is_empty():
		return null
	var best: BotCandidate = null
	var best_score: float = -INF
	for candidate: BotCandidate in candidates:
		var candidate_score: float = score(
			candidate, raster, grid, team_id, goal_positions, enemy_circle_centers,
			active_special_positions, tuning, field_radius
		)
		if best == null or candidate_score > best_score:
			best = candidate
			best_score = candidate_score
	return best
