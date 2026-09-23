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
## **Two fills.** `update()`'s `holes_enabled` selects which ruleset decides a
## cell's owner (docs/TERRITORY_V2_PLAN.md). Two bools rather than a mode enum
## keeps core/ free of any MatchConfig reference (CLAUDE.md): nothing here
## needs to know the lobby setting's name, only whether holes are on and
## whether they are permanent.
##
## **v2 fill (`holes_enabled = false`, the default ruleset).** Owner
## clarifications 2026-09-20: "Areas of different players never overlap. Where
## they meet, the border is pushed by the heights of the stacks producing the
## contested area: the taller local stack gets more of the shared region, but
## not all of it, and it is the individual contesting stacks that count, never
## a global per-player value." Each cell goes to the single home-anchored
## circle with the largest kernel value, radius - distance, so ownership is a
## function of the point rather than a set: nothing is ever CONTESTED, no
## timer runs and no hole opens. A circle the solver dropped from every group
## (cut off from its home) is never evaluated, so it loses its *area* the same
## tick it loses the win check.
##
## **Legacy fill (`holes_enabled = true`).** Spec 2.2's original rule, kept
## whole behind MatchConfig.hole_mode for the lobby's holes mode: every circle
## of every home-anchored group is stamped over its bounding box. A cell hit
## by a second group of the same team keeps its group id; a cell hit by a
## group of a *different* team becomes CONTESTED. Teammates therefore never
## contest each other, which is spec 2.2's "territories of teammates never
## create holes between them".
##
## **Contested time** (legacy only). `contested_time[i]` accumulates delta
## while cell i is contested and drains while it is not. At hole_delay the
## cell becomes a hole. Under HoleMode.TEMPORARY a hole closes once it has
## been uncontested for hole_close_delay; under PERMANENT it never closes.
##
## **Goal zones.** A static no-build disc around each goal flag, stamped once
## per match by set_goal_zones(). It blocks placement only (PlacementRules.
## validate_point) and never ownership: a player's area has to be able to
## reach through it, because winning means holding the flag base inside that
## area.
##
## Pure logic: no scene tree (CLAUDE.md). The image bytes go out as
## PackedByteArrays so that building the ImageTexture, which is presentation,
## stays in game/TerritoryOverlay.gd.

## Per-cell state bits, packed into state_bytes() for the shader. Both
## rulesets' bits fit in the one byte without colliding, so switching mode
## needs no wire change (docs/TERRITORY_V2_PLAN.md, "Rendering").
const STATE_CONTESTED: int = 1
const STATE_HOLE: int = 2
const STATE_GOAL_ZONE: int = 4

## Group id written into every owned cell of a *replicated* raster (M3a).
##
## A client's raster is a mirror, not a solve (docs/M3a_PLAN.md, "The client's
## raster is a mirror"): the host ships one owner byte and one state byte per
## cell, which is exactly the set PlacementRules.validate() reads, but real
## group indices cannot be reconstructed from them and are not needed — the
## win check is host-only. So on a mirror only three group values ever occur:
## NO_GROUP (unowned), CONTESTED, and this placeholder for "owned by
## team_at(), group unknown". Never compare a mirror's group_at() to a host's.
const REPLICATED_GROUP: int = 0

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
## The v2 fill's scratch: the best kernel value any circle has scored on this
## cell so far this frame. Reset to -INF at the top of every _fill_v2().
##
## DECISION (core/territory/TerritoryRaster.gd): 64-bit, unlike every other
## per-cell array here, because this one is compared against a freshly
## computed value rather than only read back. Rounding the stored score to 32
## bits makes an exact tie compare as a win for whichever circle came second
## about half the time, which speckles the seam of a symmetric layout -- two
## equal home circles facing each other -- with alternating single cells
## instead of handing the whole seam to the lower team id. 8 bytes per cell
## over a few thousand cells is nothing; see the tie-break DECISION in
## _argmax().
var _best_value: PackedFloat64Array = PackedFloat64Array()
## 1 where a goal flag's no-build zone covers the cell. Static for a match.
var _goal_zone: PackedByteArray = PackedByteArray()

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
	_best_value.resize(count)
	_goal_zone.resize(count)

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


## Rasterizes one solver result. Called at TerritoryTuning.solve_hz with
## delta = 1 / solve_hz.
##
## `holes_enabled` picks the ruleset: false (the default game, MatchConfig.
## HoleMode.OFF) runs the v2 argmax fill and leaves the whole contested/hole
## state machine untouched, so holes_opened()/holes_closed() stay empty,
## is_contested()/is_hole_index() stay false and `delta` is unused. True runs
## spec 2.2's original stamp-and-contest fill and advances the timers by
## `delta` seconds, with `permanent_holes` from MatchConfig.hole_mode.
##
## Both bools default to the legacy behaviour, so a caller written before v2
## keeps exactly the fill and the timers it had.
func update(
	circles: Array[InfluenceCircle],
	groups: TerritoryGroups,
	delta: float,
	holes_enabled: bool = true,
	permanent_holes: bool = false
) -> void:
	_opened.resize(0)
	_closed.resize(0)
	_group_ids.fill(TerritoryGroups.NO_GROUP)
	_team_ids.fill(-1)
	_team_counts.clear()

	if holes_enabled:
		_fill_legacy(circles, groups)
		_advance_timers(delta, permanent_holes)
	else:
		_fill_v2(circles, groups)


## Stamps the goal flags' no-build zones, replacing any previous layout. Goal
## flags never move, so this is called once per match rather than per solve.
## The zones are placement-only: they never touch ownership or influence
## (docs/TERRITORY_V2_PLAN.md, "Owner questions").
func set_goal_zones(positions: PackedVector2Array, radius: float) -> void:
	_goal_zone.fill(0)
	if radius <= 0.0:
		return
	for position: Vector2 in positions:
		_stamp_goal_zone(position, radius)


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


## Team owning a cell, or -1 when unowned, contested, or a hole.
##
## DECISION (core/territory/TerritoryRaster.gd, Bontago-1en.20 review): a
## natural hole only ever opens on a CONTESTED cell (_team_ids == -1
## already), but force_hole_cell() can open a cell a single team's own
## circle still covers -- punch_special_hole()'s whole point (spec 2.6). Its
## own class doc says "do not touch update()/_fill_legacy()/_argmax()", so
## _stamp()/_argmax() keep re-stamping that cell to the team every solve
## exactly as before (that write-side bookkeeping is what lets
## _advance_timers() keep telling a still-contested cell apart from an idle
## one -- see its own class doc). Reading it back through this bit instead
## keeps a hole cell reading as unowned everywhere a caller asks -- here,
## owner_bytes() and team_share() below -- without disturbing that timer.
func team_at(cx: int, cy: int) -> int:
	if not _grid.in_bounds(cx, cy):
		return -1
	var index: int = _grid.cell_index(cx, cy)
	if _hole[index] == 1:
		return -1
	return _team_ids[index]


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


## True where a goal flag's no-build zone covers the cell. Ownership is not
## affected: team_at() still answers whoever's area reaches in there.
func is_goal_zone(cx: int, cy: int) -> bool:
	if not _grid.in_bounds(cx, cy):
		return false
	return _goal_zone[_grid.cell_index(cx, cy)] == 1


func is_goal_zone_index(index: int) -> bool:
	if index < 0 or index >= _goal_zone.size():
		return false
	return _goal_zone[index] == 1


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
##
## DECISION (core/territory/TerritoryRaster.gd, Bontago-1en.20 review): see
## team_at()'s own DECISION -- force_hole_cell() can leave a cell inside a
## single team's own uncontested circle, which _stamp()/_argmax() (unmodified)
## keep counting into _team_counts every solve. `_active` already lists every
## cell with a currently-open hole (force_hole_cell() and a naturally-opened
## hole both append to it, and _advance_timers() only ever drops a cell from
## it once neither contested nor a hole nor draining -- see that function's
## own class doc), so it is the cheap, already-existing place to find and
## subtract them without a second full-disk scan every call.
func team_share(team_id: int) -> float:
	var total: int = _grid.in_disk_cell_count()
	if total <= 0 or not _team_counts.has(team_id):
		return 0.0
	var owned: int = _team_counts[team_id]
	for index: int in _active:
		if _hole[index] == 1 and _team_ids[index] == team_id:
			owned -= 1
	return float(owned) / float(total)


## One byte per cell for the shader's R channel: 0 = unowned, otherwise
## team_id + 1. Row-major, cell_count() long.
##
## DECISION (core/territory/TerritoryRaster.gd, Bontago-1en.20 review): reads
## `_hole` the same way team_at() now does, so a punched cell inside a single
## team's own circle draws unowned (no floor) instead of that team's tint --
## see team_at()'s own DECISION for why the write side is left alone.
func owner_bytes() -> PackedByteArray:
	var count: int = _team_ids.size()
	_owner_bytes.resize(count)
	for index: int in range(count):
		var team: int = _team_ids[index]
		_owner_bytes[index] = 0 if (team < 0 or _hole[index] == 1) else team + 1
	return _owner_bytes


## One byte per cell for the shader's G channel:
## STATE_CONTESTED | STATE_HOLE | STATE_GOAL_ZONE. Under the v2 ruleset the
## first two are always 0 and only the goal-zone bit is ever set.
func state_bytes() -> PackedByteArray:
	var count: int = _group_ids.size()
	_state_bytes.resize(count)
	for index: int in range(count):
		var state: int = 0
		if _group_ids[index] == TerritoryGroups.CONTESTED:
			state |= STATE_CONTESTED
		if _hole[index] == 1:
			state |= STATE_HOLE
		if _goal_zone[index] == 1:
			state |= STATE_GOAL_ZONE
		_state_bytes[index] = state
	return _state_bytes


## Drops every circle, hole, timer and goal zone. Called when a match starts,
## so the caller re-stamps its own goal layout with set_goal_zones() after it.
func reset() -> void:
	_group_ids.fill(TerritoryGroups.NO_GROUP)
	_team_ids.fill(-1)
	_contested_time.fill(0.0)
	_idle_time.fill(0.0)
	_hole.fill(0)
	_is_active.fill(0)
	_best_value.fill(-INF)
	_goal_zone.fill(0)
	_active.resize(0)
	_opened.resize(0)
	_closed.resize(0)
	_team_counts.clear()


## -- Replication (M3a, clients only) -----------------------------------------

## Overwrites the whole raster from a host keyframe: `owners` is owner_bytes()
## (0 = unowned, otherwise team_id + 1) and `states` is state_bytes()
## (STATE_CONTESTED | STATE_HOLE), both cell_count() long and row-major.
##
## After this call team_at(), is_contested(), is_hole_index() and therefore
## PlacementRules.validate() answer exactly what the host's raster answered
## when the keyframe was built, and team_share() is rebuilt from the same
## bytes. holes_opened() / holes_closed() report the cells whose hole bit
## flipped, so the caller can re-emit Events.hole_cells_changed and Field
## opens the same holes without a second RPC. Nothing else here touches the
## Events bus: this stays pure logic (CLAUDE.md).
##
## A payload of the wrong length is ignored rather than half-applied — an
## inconsistent mirror would let a client's ghost tint disagree with the host
## about a hole, which is the one thing the mirror exists to prevent.
func apply_replicated_state(owners: PackedByteArray, states: PackedByteArray) -> void:
	var count: int = _team_ids.size()
	if owners.size() != count or states.size() != count:
		return
	_opened.resize(0)
	_closed.resize(0)
	_team_counts.clear()
	for index: int in range(count):
		_write_replicated_cell(index, owners[index], states[index])
	_rebuild_team_counts()


## Applies a host diff: `cells` are row-major indices and `owners` / `states`
## are the new bytes for each, all three the same length. Cells the diff does
## not name keep what they had, so a mirror that has drifted converges again
## on the next keyframe (which is why the host sends one when too much
## changed). holes_opened() / holes_closed() cover only the named cells.
func apply_replicated_diff(
	cells: PackedInt32Array, owners: PackedByteArray, states: PackedByteArray
) -> void:
	var count: int = cells.size()
	if owners.size() != count or states.size() != count:
		return
	_opened.resize(0)
	_closed.resize(0)
	for i: int in range(count):
		var index: int = cells[i]
		if index < 0 or index >= _team_ids.size():
			continue
		_write_replicated_cell(index, owners[i], states[i])
	_rebuild_team_counts()


## One cell of a keyframe or a diff; both take the same path, so a keyframe
## and the diff stream that follows it can never disagree about a cell.
func _write_replicated_cell(index: int, owner_byte: int, state_byte: int) -> void:
	var was_hole: bool = _hole[index] == 1
	var contested: bool = (state_byte & STATE_CONTESTED) != 0
	var is_hole_now: bool = (state_byte & STATE_HOLE) != 0

	if contested:
		_group_ids[index] = TerritoryGroups.CONTESTED
		_team_ids[index] = -1
	elif owner_byte > 0:
		_group_ids[index] = REPLICATED_GROUP
		_team_ids[index] = owner_byte - 1
	else:
		_group_ids[index] = TerritoryGroups.NO_GROUP
		_team_ids[index] = -1

	# The goal-zone bit rides along in the same byte, so a mirror answers
	# is_goal_zone() — and therefore PlacementRules.validate_point() — exactly
	# as the host does, with no extra RPC (docs/TERRITORY_V2_PLAN.md).
	_goal_zone[index] = 1 if (state_byte & STATE_GOAL_ZONE) != 0 else 0

	_hole[index] = 1 if is_hole_now else 0
	if is_hole_now and not was_hole:
		_opened.append(index)
	elif was_hole and not is_hole_now:
		_closed.append(index)


## team_share() reads _team_counts, which the solve maintains incrementally
## while it stamps. A mirror has no stamps, so the counts are recounted from
## the owner bytes after each keyframe or diff. The disk is a few thousand
## cells and this runs at NetConfig.raster_diff_hz (5 Hz), so a full recount
## is cheaper than the bookkeeping needed to keep it incremental — and it
## cannot drift, which a diff-maintained counter eventually would.
func _rebuild_team_counts() -> void:
	_team_counts.clear()
	for index: int in range(_team_ids.size()):
		if _in_disk[index] == 0:
			continue
		var team: int = _team_ids[index]
		if team < 0:
			continue
		_team_counts[team] = _team_counts.get(team, 0) + 1


## -- Fill: v2, the argmax field ----------------------------------------------

## The default ruleset. Ownership at a point is the team of the home-anchored
## circle with the largest kernel value, radius - distance, there; a point
## outside every anchored circle stays unowned. See the class comment and
## docs/TERRITORY_V2_PLAN.md, "The formula", for why that one expression
## satisfies every owner bullet at once.
func _fill_v2(circles: Array[InfluenceCircle], groups: TerritoryGroups) -> void:
	_best_value.fill(-INF)
	for group: int in range(groups.group_count()):
		var team: int = groups.team_of(group)
		for circle_index: int in groups.circles_of(group):
			_argmax(circles[circle_index], group, team)


## Scores one circle over its own bounding box, keeping it only where it beats
## whatever scored best on that cell so far this frame.
##
## The row scan is _stamp()'s, so a circle still only ever visits cells inside
## its own radius; only the per-cell decision differs. That bounds the kernel
## at 0 on the rim, which is exactly where "outside every circle" starts, so
## no separate `value > 0` test is needed.
##
## _team_counts is maintained in step, the way _stamp() does: taking a cell
## off a team decrements it, giving it to one increments it, so team_share()
## never has to rescan the disk.
func _argmax(circle: InfluenceCircle, group: int, team: int) -> void:
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
		var dz_squared: float = dz * dz
		var remaining: float = radius_squared - dz_squared
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
			var dx: float = _axis[cx] - circle.center.x
			var value: float = radius - sqrt(dx * dx + dz_squared)
			var best: float = _best_value[index]
			if value < best:
				continue
			# DECISION (core/territory/TerritoryRaster.gd): two circles that
			# score *exactly* equal on a cell -- a symmetric layout, or two
			# equal towers the same distance away -- go to the lower team id.
			# Implementation detail with no gameplay impact (an exact tie is a
			# single cell wide), but it has to be decided somewhere, and a
			# deterministic rule keeps the host and a replayed solve agreeing.
			if value == best and team >= _team_ids[index]:
				continue
			var previous_team: int = _team_ids[index]
			if previous_team >= 0:
				_team_counts[previous_team] = _team_counts[previous_team] - 1
			_best_value[index] = value
			_group_ids[index] = group
			_team_ids[index] = team
			_team_counts[team] = _team_counts.get(team, 0) + 1


## Marks every in-disk cell within `radius` of a goal flag as a no-build zone.
##
## DECISION (core/territory/TerritoryRaster.gd): only in-disk cells are
## marked, so an off-disk cell keeps carrying no state bits at all and the
## overlay's corners stay blank. Nothing is lost: PlacementRules.validate_point
## rejects an off-disk point before it ever asks about a zone.
func _stamp_goal_zone(center: Vector2, radius: float) -> void:
	var res: int = _grid.res
	var cell_size: float = _grid.cell_size
	var half_extent: float = _grid.half_extent
	var radius_squared: float = radius * radius

	var cy_min: int = maxi(0, ceili((center.y - radius + half_extent) / cell_size - 0.5))
	var cy_max: int = mini(res - 1, floori((center.y + radius + half_extent) / cell_size - 0.5))

	for cy: int in range(cy_min, cy_max + 1):
		var dz: float = _axis[cy] - center.y
		var remaining: float = radius_squared - dz * dz
		if remaining < 0.0:
			continue
		var half_span: float = sqrt(remaining)
		var cx_min: int = maxi(0, ceili((center.x - half_span + half_extent) / cell_size - 0.5))
		var cx_max: int = mini(
			res - 1, floori((center.x + half_span + half_extent) / cell_size - 0.5)
		)
		var row: int = cy * res
		for cx: int in range(cx_min, cx_max + 1):
			var index: int = row + cx
			if _in_disk[index] == 0:
				continue
			_goal_zone[index] = 1


## -- Fill: the legacy stamp (spec 2.2, hole modes) ---------------------------

## Every circle of every home-anchored group, stamped in group order. Exactly
## what update() did before v2, so the hole ruleset is unchanged.
func _fill_legacy(circles: Array[InfluenceCircle], groups: TerritoryGroups) -> void:
	for group: int in range(groups.group_count()):
		var team: int = groups.team_of(group)
		for circle_index: int in groups.circles_of(group):
			_stamp(circles[circle_index], group, team)


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


## -- Forced holes (M4 P5-HOLE) ------------------------------------------------

## Forces (cx, cy) into a hole right now, independent of any contest overlap
## (spec 2.6: a special effect's own hole, not spec 2.2's two-territories
## rule). MatchTerritory.punch_special_hole() is the one caller; it has
## already resolved the disk-local point to cell coordinates and the lobby's
## hole_mode to `permanent_holes` before calling in, so this never touches
## MatchConfig (core/ stays free of it, per the class comment).
##
## Reuses exactly the bookkeeping a natural hole already has -- `_hole`,
## `_contested_time`, `_idle_time`, `_active`/`_is_active`, `_opened` -- so the
## unmodified `_advance_timers()` (called from the next `update()`, same as
## always) is what actually closes this hole later; nothing here starts a
## second timer mechanism.
##
## DECISION (core/territory/TerritoryRaster.gd, Bontago-1en.20): once a cell is
## not CONTESTED, `_advance_timers()`'s `else` branch is the one that ever
## closes a hole -- it grows `_idle_time` by `delta` each call and closes once
## `_idle_time` reaches `hole_close_delay` (unless `permanent_holes`). A
## punched cell was never stamped CONTESTED by `_fill_legacy()`, so it always
## takes that branch on every future `_advance_timers()` pass (unless a real
## overlap happens to land on it later, in which case it behaves exactly like
## any other contested cell from then on -- also correct). To make that
## existing countdown land on `hole_open_s` instead of `hole_close_delay`, seed
## `_idle_time` at `hole_close_delay - hole_open_s`: the next `_advance_timers()`
## call adds `delta` on top exactly as it would for a naturally-idle hole, so
## it still needs precisely `hole_open_s` more seconds of `delta` to reach
## `hole_close_delay` and close -- to within one solve tick, the same tolerance
## every other timer in this file accepts (`_reached()`). No clamping: a
## `hole_open_s` longer than `hole_close_delay` seeds a negative `_idle_time`,
## which is a perfectly ordinary float for that accumulator (nothing else here
## requires it to be >= 0) and still reaches the threshold after exactly
## `hole_open_s` more seconds. `permanent_holes = true` skips the seeding
## question entirely: `_advance_timers()`'s own `not permanent_holes` guard
## already refuses to close such a hole no matter what `_idle_time` reaches, so
## `_idle_time` is simply zeroed, same as a hole that just opened.
##
## `_contested_time` is reset to 0.0: the punch is a fresh "hole opens now"
## event, not the tail end of some accumulated overlap, so a real contest that
## starts on this cell afterwards begins accumulating from zero, exactly as it
## would on any other previously-unheld cell.
##
## Out-of-bounds and off-disk cells are silently ignored, the same guard
## is_hole()/team_at() already use, so a caller need not re-check bounds
## itself (punch_special_hole() already filters to in-disk cells, but
## force_hole_cell() does not trust that alone).
func force_hole_cell(cx: int, cy: int, hole_open_s: float, permanent_holes: bool) -> void:
	if not _grid.in_bounds(cx, cy):
		return
	var index: int = _grid.cell_index(cx, cy)
	if _in_disk[index] == 0:
		return

	var was_hole: bool = _hole[index] == 1
	_contested_time[index] = 0.0
	if permanent_holes:
		_idle_time[index] = 0.0
	else:
		_idle_time[index] = _tuning.hole_close_delay - hole_open_s
	_hole[index] = 1

	if _is_active[index] == 0:
		_is_active[index] = 1
		_active.append(index)

	if not was_hole:
		_opened.append(index)
