class_name PlacementRules
extends RefCounted
## Whether a block may be dropped where the player wants it, and where it goes
## instead when it may not (spec 2.2, 2.5, 3.3).
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
