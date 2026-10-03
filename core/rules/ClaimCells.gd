class_name ClaimCells
extends RefCounted
## Bontago-1pi.18.11: the cells a goal's claim radius covers, computed once.
##
## WinChecker.claim_at() decides a goal over every cell whose centre lies within
## the claim radius of the beacon (the QoL "bigger goal radius" toggle). Which
## cells those are depends only on the grid's geometry (cell size and edge
## length), the beacon position and the radius -- never on the raster's contents
## -- yet claim_at() runs once per goal on every territory solve (20 Hz), and
## re-deriving the in-bounds test, the cell centre and the distance for each of a
## (2 * reach + 1)^2 square of cells was most of its cost (19.8 ms per update for
## five goals at 4x). So the list is built on first use and every later solve only
## reads the raster over it.
##
## DECISION (core/rules/ClaimCells.gd): the cache is keyed by VALUE -- (grid.res,
## grid.cell_size, point, radius) is everything the list is a function of -- not
## by grid or checker identity. A new map (different res / cell size), a changed
## radius (the toggle or its multiplier) or a different goal layout therefore
## simply misses and builds its own list; a stale list can never be returned, so
## no caller has to remember to invalidate. clear() exists only to free the lists
## when a match is reset and for tests. The cache is bounded (MAX_CACHED_LISTS):
## a full cache is emptied before the next insert, which a real match (at most
## GOAL_FLAG_MAX goals at one radius on one map) never reaches.
##
## The list is a flat PackedInt32Array of row-major CELL INDICES (CellGrid.
## cell_index(), the index TerritoryRaster's per-cell arrays use), only cells
## inside the grid, exactly the cells the uncached loop visited. Indices rather than
## (cx, cy) pairs let claim_at() read the raster's arrays directly, with no
## per-cell coordinate math or bounds check (the residual cost after the first
## pass of this bead: ~1.9 us per cell through TerritoryRaster.group_at/team_at).
##
## Main-thread only (the win check and bot scoring run there; the solver's
## worker task never calls it). Pure logic: no scene tree (CLAUDE.md).

## Implementation limit, not a gameplay tunable: far above the goal layouts one
## match holds (a handful of goals x one radius), small enough that a pathological
## caller (a different point every frame) cannot grow the cache without bound.
const MAX_CACHED_LISTS: int = 64

static var _lists: Dictionary = {}
## How many lists have been built since the last clear(); lets tests prove a
## second query was served from the cache rather than recomputed.
static var _build_count: int = 0


## The in-radius, in-bounds cells around `point` as row-major cell indices.
## Returned by reference: callers must not modify it.
static func indices_for(grid: CellGrid, point: Vector2, claim_radius: float) -> PackedInt32Array:
	var key: Array = [grid.res, grid.cell_size, point, claim_radius]
	var cached: Variant = _lists.get(key)
	if cached != null:
		return cached as PackedInt32Array
	var cells: PackedInt32Array = _build(grid, point, claim_radius)
	if _lists.size() >= MAX_CACHED_LISTS:
		_lists.clear()
	_lists[key] = cells
	_build_count += 1
	return cells


## Drops every cached list (a match reset, or a test wanting a cold cache).
static func clear() -> void:
	_lists.clear()
	_build_count = 0


## Lists currently cached.
static func cached_count() -> int:
	return _lists.size()


## Lists built since the last clear().
static func build_count() -> int:
	return _build_count


## The same scan the uncached claim_at() ran every call: the (2 * reach + 1)^2
## square around the beacon's cell, keeping the in-bounds cells whose centre is
## within the radius.
static func _build(grid: CellGrid, point: Vector2, claim_radius: float) -> PackedInt32Array:
	var cells: PackedInt32Array = PackedInt32Array()
	if claim_radius <= 0.0:
		return cells
	var center: Vector2i = grid.world_to_cell(point)
	var reach: int = ceili(claim_radius / grid.cell_size) + 1
	var radius_sq: float = claim_radius * claim_radius
	for cy: int in range(center.y - reach, center.y + reach + 1):
		for cx: int in range(center.x - reach, center.x + reach + 1):
			if not grid.in_bounds(cx, cy):
				continue
			if grid.cell_center(cx, cy).distance_squared_to(point) > radius_sq:
				continue
			cells.append(grid.cell_index(cx, cy))
	return cells
