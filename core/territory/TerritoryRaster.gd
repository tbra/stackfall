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

## Per-cell state, all cell_count() long and all with a single owner, so the
## element writes in the fill loop happen in place rather than copy-on-write.
var _group_ids: PackedInt32Array = PackedInt32Array()
var _team_ids: PackedInt32Array = PackedInt32Array()
var _contested_time: PackedFloat32Array = PackedFloat32Array()
## Seconds since a cell stopped being contested; drives hole_close_delay.
var _idle_time: PackedFloat32Array = PackedFloat32Array()
var _hole: PackedByteArray = PackedByteArray()

## Cached from CellGrid so the fill loop never calls back into it.
var _in_disk: PackedByteArray = PackedByteArray()
## Disk-local centre coordinate of column cx / row cy; the grid is square, so
## one axis serves both.
var _axis: PackedFloat32Array = PackedFloat32Array()

## Only cells with a running timer or an open hole are worth advancing each
## tick. Keeping them in a compacted list makes the timer pass cost what the
## contest costs, not what the whole disk costs.
var _active: PackedInt32Array = PackedInt32Array()
var _is_active: PackedByteArray = PackedByteArray()

var _opened: PackedInt32Array = PackedInt32Array()
var _closed: PackedInt32Array = PackedInt32Array()
## team_id -> owned cell count, rebuilt during each fill so team_share() never
## has to rescan the disk.
var _team_counts: Dictionary[int, int] = {}

var _owner_bytes: PackedByteArray = PackedByteArray()
var _state_bytes: PackedByteArray = PackedByteArray()


func _init(grid: CellGrid, tuning: TerritoryTuning) -> void:
	_grid = grid
	_tuning = tuning

	var count: int = _grid.cell_count()
	_group_ids.resize(count)
	_team_ids.resize(count)
	_contested_time.resize(count)
	_idle_time.resize(count)
	_hole.resize(count)
	_is_active.resize(count)

	_in_disk.resize(count)
	for index: int in _grid.in_disk_cells():
		_in_disk[index] = 1

	_axis.resize(_grid.res)
	for i: int in range(_grid.res):
		_axis[i] = (float(i) + 0.5) * _grid.cell_size - _grid.half_extent

	reset()


func grid() -> CellGrid:
	return _grid


func tuning() -> TerritoryTuning:
	return _tuning


## Rasterizes one solver result and advances the contested and hole timers by
## `delta` seconds. `permanent_holes` comes from MatchConfig.hole_mode.
## Called at TerritoryTuning.solve_hz with delta = 1 / solve_hz.
func update(
	circles: Array[InfluenceCircle],
	groups: TerritoryGroups,
	delta: float,
	permanent_holes: bool
) -> void:
	_opened.resize(0)
	_closed.resize(0)
	_group_ids.fill(TerritoryGroups.NO_GROUP)
	_team_ids.fill(-1)
	_team_counts.clear()

	for group: int in range(groups.group_count()):
		var team: int = groups.team_of(group)
		for circle_index: int in groups.circles_of(group):
			_stamp(circles[circle_index], group, team)

	_advance_timers(delta, permanent_holes)


## Group index at a cell, or TerritoryGroups.NO_GROUP / CONTESTED.
func group_at(cx: int, cy: int) -> int:
	if not _grid.in_bounds(cx, cy):
		return TerritoryGroups.NO_GROUP
	return _group_ids[_grid.cell_index(cx, cy)]


## Group index at a disk-local point, or NO_GROUP when it is off the disk.
## This is what WinChecker uses on each goal flag position.
func group_at_point(point: Vector2) -> int:
	var cell: Vector2i = _grid.world_to_cell(point)
	return group_at(cell.x, cell.y)


## Team owning a cell, or -1 when unowned or contested.
func team_at(cx: int, cy: int) -> int:
	if not _grid.in_bounds(cx, cy):
		return -1
	return _team_ids[_grid.cell_index(cx, cy)]


func is_contested(cx: int, cy: int) -> bool:
	return group_at(cx, cy) == TerritoryGroups.CONTESTED


func is_hole(cx: int, cy: int) -> bool:
	if not _grid.in_bounds(cx, cy):
		return false
	return _hole[_grid.cell_index(cx, cy)] == 1


func is_hole_index(index: int) -> bool:
	if index < 0 or index >= _hole.size():
		return false
	return _hole[index] == 1


## Seconds this cell has been contested, clamped to hole_delay.
func contested_time(cx: int, cy: int) -> float:
	if not _grid.in_bounds(cx, cy):
		return 0.0
	return _contested_time[_grid.cell_index(cx, cy)]


## Cells that became holes during the last update(), row-major indices.
## Field consumes these and re-arms its batched shape toggles.
func holes_opened() -> PackedInt32Array:
	return _opened


## Cells that stopped being holes during the last update(). Always empty
## under HoleMode.PERMANENT.
func holes_closed() -> PackedInt32Array:
	return _closed


## Fraction of the disk's in-disk cells a team owns, 0..1. Feeds the HUD's
## "territory percentage per player" (spec 2.10).
func team_share(team_id: int) -> float:
	var total: int = _grid.in_disk_cell_count()
	if total <= 0 or not _team_counts.has(team_id):
		return 0.0
	return float(_team_counts[team_id]) / float(total)


## One byte per cell for the shader's R channel: 0 = unowned, otherwise
## team_id + 1. Row-major, cell_count() long.
func owner_bytes() -> PackedByteArray:
	var count: int = _team_ids.size()
	_owner_bytes.resize(count)
	for index: int in range(count):
		var team: int = _team_ids[index]
		_owner_bytes[index] = 0 if team < 0 else team + 1
	return _owner_bytes


## One byte per cell for the shader's G channel: STATE_CONTESTED | STATE_HOLE.
func state_bytes() -> PackedByteArray:
	var count: int = _group_ids.size()
	_state_bytes.resize(count)
	for index: int in range(count):
		var state: int = 0
		if _group_ids[index] == TerritoryGroups.CONTESTED:
			state |= STATE_CONTESTED
		if _hole[index] == 1:
			state |= STATE_HOLE
		_state_bytes[index] = state
	return _state_bytes


## Drops every circle, hole and timer. Called when a match starts.
func reset() -> void:
	_group_ids.fill(TerritoryGroups.NO_GROUP)
	_team_ids.fill(-1)
	_contested_time.fill(0.0)
	_idle_time.fill(0.0)
	_hole.fill(0)
	_is_active.fill(0)
	_active.resize(0)
	_opened.resize(0)
	_closed.resize(0)
	_team_counts.clear()


## -- Fill --------------------------------------------------------------------

## Stamps one circle's cells. A cell already held by another team becomes
## CONTESTED (spec 2.2); a cell held by the same team keeps the group it
## already has, which is why teammates never contest each other.
##
## The row scan solves dx^2 <= r^2 - dz^2 for the span instead of testing every
## cell of the bounding box, so the inner loop is integer work plus one lookup.
## Rounding at a circle's rim may differ from InfluenceCircle.contains_point()
## by well under a millimetre; unlike the disk rim in CellGrid, this edge is not
## a boundary three systems have to agree on.
func _stamp(circle: InfluenceCircle, group: int, team: int) -> void:
	var radius: float = circle.radius
	if radius <= 0.0:
		return

	var res: int = _grid.res
	var cell_size: float = _grid.cell_size
	var half_extent: float = _grid.half_extent
	var radius_squared: float = radius * radius

	var cy_min: int = maxi(0, ceili((circle.center.y - radius + half_extent) / cell_size - 0.5))
	var cy_max: int = mini(
		res - 1, floori((circle.center.y + radius + half_extent) / cell_size - 0.5)
	)

	for cy: int in range(cy_min, cy_max + 1):
		var dz: float = _axis[cy] - circle.center.y
		var remaining: float = radius_squared - dz * dz
		if remaining < 0.0:
			continue
		var half_span: float = sqrt(remaining)
		var cx_min: int = maxi(
			0, ceili((circle.center.x - half_span + half_extent) / cell_size - 0.5)
		)
		var cx_max: int = mini(
			res - 1, floori((circle.center.x + half_span + half_extent) / cell_size - 0.5)
		)
		var row: int = cy * res
		for cx: int in range(cx_min, cx_max + 1):
			var index: int = row + cx
			if _in_disk[index] == 0:
				continue
			var current: int = _group_ids[index]
			if current == TerritoryGroups.CONTESTED:
				continue
			if current == TerritoryGroups.NO_GROUP:
				_group_ids[index] = group
				_team_ids[index] = team
				_team_counts[team] = _team_counts.get(team, 0) + 1
			elif _team_ids[index] != team:
				_team_counts[_team_ids[index]] = _team_counts[_team_ids[index]] - 1
				_group_ids[index] = TerritoryGroups.CONTESTED
				_team_ids[index] = -1
				if _is_active[index] == 0:
					_is_active[index] = 1
					_active.append(index)


## -- Contested time and the hole state machine -------------------------------

## Advances only the cells that have something to advance, compacting the
## active list in place as cells go quiet.
func _advance_timers(delta: float, permanent_holes: bool) -> void:
	var hole_delay: float = _tuning.hole_delay
	var close_delay: float = _tuning.hole_close_delay
	var write: int = 0

	for read: int in range(_active.size()):
		var index: int = _active[read]
		var contested: bool = _group_ids[index] == TerritoryGroups.CONTESTED
		var elapsed: float = _contested_time[index]

		if contested:
			elapsed = minf(elapsed + delta, hole_delay)
			_contested_time[index] = elapsed
			_idle_time[index] = 0.0
			if _hole[index] == 0 and _reached(elapsed, hole_delay):
				_hole[index] = 1
				_opened.append(index)
		else:
			# Spec 2.2 is a drain, not a reset: brief flickers of contest still
			# add up towards a hole.
			elapsed = maxf(elapsed - delta, 0.0)
			_contested_time[index] = elapsed
			var idle: float = _idle_time[index] + delta
			_idle_time[index] = idle
			if _hole[index] == 1 and not permanent_holes and _reached(idle, close_delay):
				_hole[index] = 0
				_closed.append(index)

		if contested or _hole[index] == 1 or _contested_time[index] > 0.0:
			_active[write] = index
			write += 1
		else:
			_is_active[index] = 0

	_active.resize(write)


## Threshold test that tolerates the drift of summing `delta` many times: 30
## additions of 0.1 land on 2.9999999999999996, and a hole that refused to open
## on the tick it was due would be a real bug.
static func _reached(value: float, threshold: float) -> bool:
	return value >= threshold or is_equal_approx(value, threshold)
