class_name PlacementRules
extends RefCounted
## Whether a block may be dropped where the player wants it, and where it goes
## instead when it may not (spec 2.2, 2.5, 3.3).
##
## **Two checks; only one runs in live play** (docs/TERRITORY_V2_PLAN.md;
## reconciled with the 2026-09-20 evidence audit by Bontago-cmc.7).
## validate_point()/closest_valid_point() are the placement contract for
## **every** MatchConfig.HoleMode -- owner clarifications 2026-09-20, "one
## raycast from the middle of the ghost block straight down; the hit point
## must be inside your own area and outside every goal flag's area. No cell
## footprint tests", which the audit's SPEC.md 2.5 "Placement legality" keeps
## verbatim and extends to reject a contested/holed point too (see
## validate_point()'s own comment). Package B does the raycast in
## autoload/Match.gd; everything from the hit point on is here.
## footprint_cells()/validate()/closest_valid_origin() are spec 3.3's original
## multi-cell check. autoload/Match.gd no longer calls them under any
## hole_mode; they stay compiled only for tests/bench/bench_territory.gd's
## legacy regression row and this file's own direct unit tests
## (tests/unit/test_placement_rules.gd), per the audit's instruction not to
## reintroduce a footprint test in normal play.
##
## Spec 3.3: "On the host, the cell under the ghost's footprint must be owned
## by the placing player's team and not contested or a hole." Every cell of
## the footprint has to pass, not just the center one.
##
## Spec 2.5: "When the timer runs out, the held block drops from its current
## ghost position. If that spot isn't valid, it drops at the closest valid
## point." closest_valid_origin() is that search: a widening ring scan in
## auto_drop_search_step increments out to auto_drop_search_max_radius,
## re-testing the whole rotated footprint at each candidate.
##
## Spec 2.2: "Players can't place blocks in contested areas. If a block is
## released there anyway, it is thrown off the map with a visible reject
## animation." This class decides *that* it is a reject and why; Match throws
## the block, because throwing it needs a body.
##
## Pure logic: no scene tree (CLAUDE.md). All static, so the host calls it
## without keeping an instance around.

enum Result {
	VALID,
	## The footprint covers a cell no group of the placing team owns.
	OUTSIDE_TERRITORY,
	## The footprint covers a contested cell.
	CONTESTED,
	## The footprint covers a cell that has already become a hole.
	HOLE,
	## The footprint reaches past the rim of the disk.
	OFF_DISK,
	## The footprint has no cells at all, which means a malformed intent.
	EMPTY,
	## The point falls inside a goal flag's no-build zone. Produced only by
	## validate_point(); appended rather than inserted so the ordinals the
	## legacy cases already have do not move, and deliberately outside
	## validate()'s "worst finding wins" severity order, which never sees it.
	GOAL_ZONE,
}

## Machine-readable reasons, carried by Events.placement_rejected and returned
## by Match.request_place. Kept here rather than on the Events autoload so
## core/ stays free of any scene-tree dependency.
const REASON_OK: StringName = &""
const REASON_OUTSIDE_TERRITORY: StringName = &"outside_territory"
const REASON_CONTESTED: StringName = &"contested"
const REASON_HOLE: StringName = &"hole"
const REASON_OFF_DISK: StringName = &"off_disk"
const REASON_EMPTY: StringName = &"empty_footprint"
const REASON_GOAL_ZONE: StringName = &"goal_zone"
## Raised by Match, not by validate(): the slot is not the hot-seat player
## whose turn it is, or it is holding nothing.
const REASON_NOT_YOUR_TURN: StringName = &"not_your_turn"
const REASON_NO_BLOCK: StringName = &"no_block"

## closest_valid_origin() returns this when nothing within the search radius
## works, which means the block must be rejected instead of relocated.
const NO_ORIGIN: Vector2 = Vector2(INF, INF)

## Insets each cube's footprint square before it is turned into cell indices.
## The 24 axis-aligned orientations come out of BlockOrientations as products
## of rotations, so a cube that should sit exactly on a cell boundary can miss
## it by ~1e-7 m; without this, a yawed domino claims three cells instead of
## two and demands territory it does not cover. A hundredth of a millimetre
## absorbs that and cannot hide a real overlap. Not a tunable, a numerical
## tolerance, so it stays in code rather than in TerritoryTuning.
const _BOUNDARY_EPSILON: float = 1e-5


## The grid cells a block's cubes cover once rotated, as row-major indices,
## deduplicated and ascending. `cells` is BlockShape.cells, `basis` the
## orientation (the 24-index basis times any free rotation), `origin` the
## disk-local (x, z) the block's local origin sits over, and `cube_size`
## PhysicsTuning.cube_size.
##
## A rotated cube covers up to four cells, so every cube contributes the cells
## its footprint square overlaps, not just the one under its center.
##
## Cells beyond the grid's bounding square cannot be named as row-major indices
## and are dropped, so a block held far off the map yields an empty footprint,
## which validate() reports as EMPTY. The square circumscribes the disk and
## touches it only at the four cardinal extremes, so everywhere else an
## overhanging block is caught by OFF_DISK as intended; only in a sliver right
## at those four points can up to half a cube hang over the rim unnoticed,
## where it simply topples off.
static func footprint_cells(
	cells: Array[Vector3i],
	basis: Basis,
	origin: Vector2,
	cube_size: float,
	grid: CellGrid
) -> PackedInt32Array:
	var found: PackedInt32Array = PackedInt32Array()
	if cells.is_empty():
		return found

	# DECISION (core/rules/PlacementRules.gd): each cube's footprint is taken as
	# the axis-aligned square of side cube_size centred on its projected centre.
	# For the 24 axis-aligned orientations that is exact. Under a free rotation
	# the true projection is a hexagon, and this square is a close
	# over-approximation of it, which errs towards refusing a placement rather
	# than allowing one over a hole -- the safe direction, and the reason the
	# stub's own note says a rotated cube covers "up to four cells".
	var half: float = maxf(cube_size * 0.5 - _BOUNDARY_EPSILON, 0.0)
	var cell_size: float = grid.cell_size
	var half_extent: float = grid.half_extent
	var res: int = grid.res

	for offset: Vector3i in cells:
		var local: Vector3 = basis * (Vector3(offset) * cube_size)
		var centre_x: float = origin.x + local.x
		var centre_z: float = origin.y + local.z

		# A cell spans [c * size - radius, (c + 1) * size - radius). It overlaps
		# [lo, hi] when c * size - radius < hi and (c + 1) * size - radius > lo,
		# which is exactly floor for the low end and ceil - 1 for the high end.
		# Doing it this way keeps a cube that lines up perfectly with the grid
		# on one cell instead of bleeding into its neighbour.
		var x0: int = maxi(0, floori((centre_x - half + half_extent) / cell_size))
		var x1: int = mini(res - 1, ceili((centre_x + half + half_extent) / cell_size) - 1)
		var y0: int = maxi(0, floori((centre_z - half + half_extent) / cell_size))
		var y1: int = mini(res - 1, ceili((centre_z + half + half_extent) / cell_size) - 1)

		for cy: int in range(y0, y1 + 1):
			var row: int = cy * res
			for cx: int in range(x0, x1 + 1):
				found.append(row + cx)

	# Footprints run to a handful of cells, so sorting and then skipping
	# repeats is cheaper than carrying a set around.
	found.sort()
	var unique: PackedInt32Array = PackedInt32Array()
	var previous: int = -1
	for index: int in found:
		if index != previous:
			unique.append(index)
			previous = index
	return unique


## Spec 3.3's check, over every cell of the footprint.
static func validate(
	footprint: PackedInt32Array, raster: TerritoryRaster, team_id: int
) -> Result:
	if footprint.is_empty():
		return Result.EMPTY

	var grid: CellGrid = raster.grid()
	# Result is declared in order of increasing severity, so the worst finding
	# across the footprint is simply the largest. Keep that ordering if the enum
	# ever gains a case.
	var worst: int = Result.VALID
	for index: int in footprint:
		var coords: Vector2i = grid.cell_coords(index)
		var cell: int = Result.VALID
		if not grid.is_in_disk(coords.x, coords.y):
			cell = Result.OFF_DISK
		elif raster.is_hole_index(index):
			cell = Result.HOLE
		elif raster.is_contested(coords.x, coords.y):
			cell = Result.CONTESTED
		elif raster.team_at(coords.x, coords.y) != team_id:
			cell = Result.OUTSIDE_TERRITORY
		worst = maxi(worst, cell)
	return worst as Result


## The reason StringName for a Result, for Events.placement_rejected.
static func reason_for(result: Result) -> StringName:
	match result:
		Result.OUTSIDE_TERRITORY:
			return REASON_OUTSIDE_TERRITORY
		Result.CONTESTED:
			return REASON_CONTESTED
		Result.HOLE:
			return REASON_HOLE
		Result.OFF_DISK:
			return REASON_OFF_DISK
		Result.EMPTY:
			return REASON_EMPTY
		Result.GOAL_ZONE:
			return REASON_GOAL_ZONE
		_:
			return REASON_OK


## The nearest disk-local origin at or around `desired` whose footprint
## validates, or NO_ORIGIN. Returns `desired` unchanged when it is already
## valid, so the common case costs one validate().
static func closest_valid_origin(
	desired: Vector2,
	cells: Array[Vector3i],
	basis: Basis,
	cube_size: float,
	grid: CellGrid,
	raster: TerritoryRaster,
	team_id: int,
	tuning: TerritoryTuning
) -> Vector2:
	if validate(
		footprint_cells(cells, basis, desired, cube_size, grid), raster, team_id
	) == Result.VALID:
		return desired

	var step: float = maxf(tuning.auto_drop_search_step, 0.001)
	var limit: float = tuning.auto_drop_search_max_radius
	var radius: float = step
	while radius <= limit:
		# Enough samples that neighbouring candidates on the ring sit about one
		# step apart, so the scan cannot thread past a valid pocket of cells.
		var samples: int = maxi(1, ceili(TAU * radius / step))
		for i: int in range(samples):
			var angle: float = TAU * float(i) / float(samples)
			var candidate: Vector2 = desired + Vector2(cos(angle), sin(angle)) * radius
			if validate(
				footprint_cells(cells, basis, candidate, cube_size, grid), raster, team_id
			) == Result.VALID:
				return candidate
		radius += step
	return NO_ORIGIN


static func is_no_origin(origin: Vector2) -> bool:
	return is_inf(origin.x) or is_inf(origin.y)


## -- The v2 point check ------------------------------------------------------

## Spec 3.3's check reduced to the single point the owner's raycast hit
## (owner clarifications 2026-09-20; reaffirmed as the placement contract for
## every hole_mode by the 2026-09-20 evidence audit, SPEC.md 2.5 "Placement
## legality" and Bontago-cmc.7). `point` is disk-local (x, z), already
## converted by the caller; this never touches physics.
##
## Order matters: off the disk first, because a point past the rim has no cell
## to ask anything about; then the goal flags' no-build zones, so a player
## standing in their own territory around a flag is told the real reason they
## cannot build there; then the legacy hole/contested state (SPEC.md 2.2
## "Overlap holes": "Opposing candidate influence creates a contested region
## that neither player may use for placement"), so a specific reason beats the
## generic OUTSIDE_TERRITORY a contested/holed cell's unowned (-1) team would
## otherwise report; then ownership.
##
## is_hole()/is_contested() only ever answer true under the legacy stamp fill
## (MatchConfig.HoleMode.TEMPORARY/PERMANENT, TerritoryRaster._fill_legacy());
## the v2 argmax fill (HoleMode.OFF) never sets either, so this same check is
## exactly the old OFF-only behaviour there -- one function now serves every
## mode without branching on which fill produced the raster.
static func validate_point(
	point: Vector2, raster: TerritoryRaster, team_id: int
) -> Result:
	var grid: CellGrid = raster.grid()
	var coords: Vector2i = grid.world_to_cell(point)
	if not grid.in_bounds(coords.x, coords.y) or not grid.is_in_disk(coords.x, coords.y):
		return Result.OFF_DISK
	if raster.is_goal_zone(coords.x, coords.y):
		return Result.GOAL_ZONE
	if raster.is_hole(coords.x, coords.y):
		return Result.HOLE
	if raster.is_contested(coords.x, coords.y):
		return Result.CONTESTED
	if raster.team_at(coords.x, coords.y) != team_id:
		return Result.OUTSIDE_TERRITORY
	return Result.VALID


## Spec 2.5's auto-drop relocation, now shared by every hole_mode
## (Bontago-cmc.7): the nearest disk-local point at or around `desired` that
## validate_point() accepts, or NO_ORIGIN when the placing team owns no valid
## point anywhere on the disk. SPEC.md's 2026-09-20 audit, 2.5 "Expiry and
## invalid actions", flags relocate-vs-lose-vs-retain as [OPEN] for the
## original and calls the closest-valid-point search only the remake's own
## [NEW] fallback -- kept unchanged here because nothing in the audit
## contradicts it, only notes that it is not evidenced.
##
## Bontago-xtq.23 (owner playtest 2026-09-24, "if I'm close to my area it
## relocates, otherwise it just yeets the block in a direction"): the ring
## search below only ever looked out to auto_drop_search_max_radius (12 m by
## default) and returned NO_ORIGIN past it, which sent request_place() down
## the burn/throw path even though the player's own territory was sitting
## right there on the disk, just further than 12 m from the expired ghost.
## `_scan_disk_for_closest_valid_point()` is the fix: whenever the ring search
## comes up empty, it falls back to a scan of every in-disk cell and returns
## the nearest one that validates, so NO_ORIGIN now means what request_place()
## has always assumed it means -- the team truly owns no valid point on the
## whole disk (home flag down and every stack lost) -- and the throw-off-the-
## map fallback is reachable only in that genuine case.
##
## DECISION (core/rules/PlacementRules.gd, Bontago-xtq.23): rather than raise
## or repurpose auto_drop_search_max_radius, it keeps its old meaning -- the
## radius of the cheap, sub-cell-accurate ring search below -- and the disk
## scan is a second, unconditional fallback with no tunable of its own. A
## bigger max_radius only makes the common near-miss case (a few metres off)
## keep costing a ring walk instead of a full scan; it does not change what
## the search can ultimately reach, since the scan below already covers the
## whole disk. tuning_panel_hints.tres's entry for this field is reworded to
## match (it no longer means "or the block is thrown").
##
## Same widening-ring geometry as closest_valid_origin(), and the same two
## tunables, but one point per candidate instead of a rotated footprint --
## ownership at a candidate is pure math once the raster is filled, so no
## second raycast is needed either. Returns `desired` untouched when it is
## already valid, so the common case costs one cell lookup.
static func closest_valid_point(
	desired: Vector2, raster: TerritoryRaster, team_id: int, tuning: TerritoryTuning
) -> Vector2:
	if validate_point(desired, raster, team_id) == Result.VALID:
		return desired

	var step: float = maxf(tuning.auto_drop_search_step, 0.001)
	var limit: float = tuning.auto_drop_search_max_radius
	var radius: float = step
	while radius <= limit:
		# Enough samples that neighbouring candidates on the ring sit about one
		# step apart, so the scan cannot thread past a valid pocket of cells.
		var samples: int = maxi(1, ceili(TAU * radius / step))
		for i: int in range(samples):
			var angle: float = TAU * float(i) / float(samples)
			var candidate: Vector2 = desired + Vector2(cos(angle), sin(angle)) * radius
			if validate_point(candidate, raster, team_id) == Result.VALID:
				return candidate
		radius += step
	return _scan_disk_for_closest_valid_point(desired, raster, team_id)


## The ring search's fallback: every in-disk cell, at most once, so a team
## whose only territory sits farther than auto_drop_search_max_radius from the
## expired ghost still gets relocated instead of burned (Bontago-xtq.23).
##
## Cost: one validate_point() per in-disk cell (CellGrid.in_disk_cells(),
## cached after the first call). At MapDef's default cell_size = 1 m this is
## a few hundred to a few thousand cells even on the largest shipped map (a
## square of side 2 * field_radius, res^2 cells, times roughly pi/4 in disk) --
## a single scan on an expiry auto-drop, not a per-frame cost, so brute force
## here is cheap enough not to need CellGrid's spatial hash.
static func _scan_disk_for_closest_valid_point(
	desired: Vector2, raster: TerritoryRaster, team_id: int
) -> Vector2:
	var grid: CellGrid = raster.grid()
	var best_point: Vector2 = NO_ORIGIN
	var best_distance_squared: float = INF
	for index: int in grid.in_disk_cells():
		var candidate: Vector2 = grid.index_center(index)
		if validate_point(candidate, raster, team_id) != Result.VALID:
			continue
		var distance_squared: float = candidate.distance_squared_to(desired)
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			best_point = candidate
	return best_point
