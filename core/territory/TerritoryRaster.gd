class_name TerritoryRaster
extends RefCounted
## The authoritative grid: who owns each cell of the disk, which cells are
## contested, and which have become holes (spec 2.2, 3.3).
##
## One cell of CellGrid is one pixel here and one BoxShape3D in the field's
## collision, so the three never disagree about where a hole is. See
## docs/M2_PLAN.md, "Raster resolution", for why the rules run at cell
## resolution while MapDef.territory_res is the size the overlay uploads.
##
## **Fill.** Each solve, `group_ids` is cleared to NO_GROUP and every circle
## of every home-anchored group is stamped over its bounding box. A cell hit
## by a second group of the same team keeps its group id; a cell hit by a
## group of a *different* team becomes CONTESTED. Teammates therefore never
## contest each other, which is spec 2.2's "territories of teammates never
## create holes between them".
##
## **Contested time.** `contested_time[i]` accumulates delta while cell i is
## contested and drains while it is not. At hole_delay the cell becomes a
## hole. Under HoleMode.TEMPORARY a hole closes once it has been uncontested
## for hole_close_delay; under PERMANENT it never closes.
##
## Pure logic: no scene tree (CLAUDE.md). The image bytes go out as
## PackedByteArrays so that building the ImageTexture, which is presentation,
## stays in game/TerritoryOverlay.gd.

## Per-cell state bits, packed into state_bytes() for the shader.
const STATE_CONTESTED: int = 1
const STATE_HOLE: int = 2

var _grid: CellGrid = null
var _tuning: TerritoryTuning = null


func _init(grid: CellGrid, tuning: TerritoryTuning) -> void:
	_grid = grid
	_tuning = tuning


func grid() -> CellGrid:
	return _grid


func tuning() -> TerritoryTuning:
	return _tuning


@warning_ignore_start("unused_parameter")
## Rasterizes one solver result and advances the contested and hole timers by
## `delta` seconds. `permanent_holes` comes from MatchConfig.hole_mode.
## Called at TerritoryTuning.solve_hz with delta = 1 / solve_hz.
func update(
	circles: Array[InfluenceCircle],
	groups: TerritoryGroups,
	delta: float,
	permanent_holes: bool
) -> void:
	pass


## Group index at a cell, or TerritoryGroups.NO_GROUP / CONTESTED.
func group_at(cx: int, cy: int) -> int:
	return TerritoryGroups.NO_GROUP


## Group index at a disk-local point, or NO_GROUP when it is off the disk.
## This is what WinChecker uses on each goal flag position.
func group_at_point(point: Vector2) -> int:
	return TerritoryGroups.NO_GROUP


## Team owning a cell, or -1 when unowned or contested.
func team_at(cx: int, cy: int) -> int:
	return -1


func is_contested(cx: int, cy: int) -> bool:
	return false


func is_hole(cx: int, cy: int) -> bool:
	return false


func is_hole_index(index: int) -> bool:
	return false


## Seconds this cell has been contested, clamped to hole_delay.
func contested_time(cx: int, cy: int) -> float:
	return 0.0


## Cells that became holes during the last update(), row-major indices.
## Field consumes these and re-arms its batched shape toggles.
func holes_opened() -> PackedInt32Array:
	return PackedInt32Array()


## Cells that stopped being holes during the last update(). Always empty
## under HoleMode.PERMANENT.
func holes_closed() -> PackedInt32Array:
	return PackedInt32Array()


## Fraction of the disk's in-disk cells a team owns, 0..1. Feeds the HUD's
## "territory percentage per player" (spec 2.10).
func team_share(team_id: int) -> float:
	return 0.0


## One byte per cell for the shader's R channel: 0 = unowned, otherwise
## team_id + 1. Row-major, cell_count() long.
func owner_bytes() -> PackedByteArray:
	return PackedByteArray()


## One byte per cell for the shader's G channel: STATE_CONTESTED | STATE_HOLE.
func state_bytes() -> PackedByteArray:
	return PackedByteArray()


## Drops every circle, hole and timer. Called when a match starts.
func reset() -> void:
	pass
@warning_ignore_restore("unused_parameter")
