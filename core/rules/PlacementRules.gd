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


@warning_ignore_start("unused_parameter")
## The grid cells a block's cubes cover once rotated, as row-major indices,
## deduplicated and ascending. `cells` is BlockShape.cells, `basis` the
## orientation (the 24-index basis times any free rotation), `origin` the
## disk-local (x, z) the block's local origin sits over, and `cube_size`
## PhysicsTuning.cube_size.
##
## A rotated cube covers up to four cells, so every cube contributes the cells
## its footprint square overlaps, not just the one under its center.
static func footprint_cells(
	cells: Array[Vector3i],
	basis: Basis,
	origin: Vector2,
	cube_size: float,
	grid: CellGrid
) -> PackedInt32Array:
	return PackedInt32Array()


## Spec 3.3's check, over every cell of the footprint.
static func validate(
	footprint: PackedInt32Array, raster: TerritoryRaster, team_id: int
) -> Result:
	return Result.EMPTY


## The reason StringName for a Result, for Events.placement_rejected.
static func reason_for(result: Result) -> StringName:
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
	return NO_ORIGIN


static func is_no_origin(origin: Vector2) -> bool:
	return is_inf(origin.x) or is_inf(origin.y)
@warning_ignore_restore("unused_parameter")
