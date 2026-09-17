class_name CellGrid
extends RefCounted
## The one disk-local coordinate convention shared by the solver, the raster,
## the field's collision cells and placement validation (spec 3.3).
##
## **Convention.** Disk-local space is plain Cartesian (x, z) in meters with
## the origin at the disk center; the y axis (height along the disk normal) is
## never part of it. A square grid of `res` x `res` cells of `cell_size`
## meters covers the bounding square of the disk, so cell (0, 0) is the
## -x/-z corner and the disk's center falls at cell coordinate res/2.
##
## DECISION (core/territory/CellGrid.gd): `res` is rounded **up to an odd
## number** and the square is centred on the disk centre, so one cell is
## centred exactly on the origin and every cell centre lands on a multiple of
## cell_size. That is a physics requirement, not a tidiness one. Field turns
## each cell into its own BoxShape3D; Jolt rounds every convex shape's edges
## by collision_margin_fraction of its extent, so a block that straddles the
## seam between cells rests on rounded, overlapping rims and creeps. Aligned,
## a block placed where blocks naturally sit — on a cell centre, since blocks
## and cells are both cube_size across — rests on one box's flat middle.
## Measured on tests/bench/bench_tower.tscn (40 cubes, 60 s): unaligned gives
## 0.78-0.83 m of lean and never sleeps whatever the overlap, aligned with
## MapDef.cell_overlap at 0.2 gives 0.02 m and sleeps in half a second, which
## is what the M1 single-cylinder disk did. The half cell this adds to each
## side of the square carries no collision, since is_in_disk() still measures
## against field_radius.
##
## Cell index is row-major, `cy * res + cx`, which is also the pixel index of
## the authoritative territory raster and the shape-owner order Field uses for
## its BoxShape3D cells. One cell is one raster pixel is one collision box.
## See docs/M2_PLAN.md, "Raster resolution", for why the rules run at cell
## resolution and MapDef.territory_res is the upload size instead.
##
## Pure logic: no scene tree, no nodes (CLAUDE.md).

var field_radius: float = 1.0
var cell_size: float = 1.0
## Cells along one edge of the square that covers the disk. Always odd, so
## there is a middle cell and it is centred on the disk centre.
var res: int = 1
## Half the width of that square, in meters: res * cell_size * 0.5. This, not
## field_radius, is the grid's origin offset — every conversion between
## disk-local meters and cell coordinates goes through it.
var half_extent: float = 0.5

## Lazily built by in_disk_cells(); every consumer of the disk membership list
## shares this one copy, because it is the denominator of every territory
## percentage and the iteration order of the raster's timer pass.
var _in_disk_cells: PackedInt32Array = PackedInt32Array()
var _in_disk_built: bool = false


func _init(p_field_radius: float = 1.0, p_cell_size: float = 1.0) -> void:
	field_radius = maxf(p_field_radius, 0.001)
	cell_size = maxf(p_cell_size, 0.001)
	res = int(ceil(2.0 * field_radius / cell_size))
	if res % 2 == 0:
		res += 1
	half_extent = float(res) * cell_size * 0.5


## Total cells in the square grid, including the corner cells outside the disk.
func cell_count() -> int:
	return res * res


## Row-major index of a cell. Callers that might be out of bounds check
## in_bounds() first; this does no clamping, because it sits in the raster's
## innermost loop.
func cell_index(cx: int, cy: int) -> int:
	return cy * res + cx


func cell_coords(index: int) -> Vector2i:
	return Vector2i(index % res, index / res)


func in_bounds(cx: int, cy: int) -> bool:
	return cx >= 0 and cy >= 0 and cx < res and cy < res


## The cell containing a disk-local point. May be out of bounds for a point
## beyond the bounding square.
func world_to_cell(point: Vector2) -> Vector2i:
	return Vector2i(
		floori((point.x + half_extent) / cell_size),
		floori((point.y + half_extent) / cell_size)
	)


## Disk-local center of a cell.
func cell_center(cx: int, cy: int) -> Vector2:
	return Vector2(
		(float(cx) + 0.5) * cell_size - half_extent,
		(float(cy) + 0.5) * cell_size - half_extent
	)


func index_center(index: int) -> Vector2:
	var coords: Vector2i = cell_coords(index)
	return cell_center(coords.x, coords.y)


## True when the cell's center lies inside the disk. Cells straddling the rim
## are in or out by their center, which keeps the collision grid and the
## raster agreeing on the same rim.
func is_in_disk(cx: int, cy: int) -> bool:
	return cell_center(cx, cy).length_squared() <= field_radius * field_radius


## How many cells of the grid are inside the disk. Used as the denominator of
## territory percentages, so it is computed once and cached by the
## implementation.
func in_disk_cell_count() -> int:
	return in_disk_cells().size()


## Every in-disk cell index, in row-major order. Built once.
func in_disk_cells() -> PackedInt32Array:
	if _in_disk_built:
		return _in_disk_cells
	_in_disk_built = true
	_in_disk_cells = PackedInt32Array()
	# DECISION (core/territory/CellGrid.gd): built by asking is_in_disk() about
	# every cell rather than by solving |x| <= sqrt(r^2 - z^2) per row. The
	# analytic form is O(res) instead of O(res^2), but it would evaluate the
	# rim in double precision while is_in_disk() evaluates it through Vector2,
	# whose components are 32-bit. The two can then disagree on a cell whose
	# center sits exactly on the rim, and this list and is_in_disk() are
	# precisely what Field, the raster and placement validation use to agree on
	# where the disk ends. This runs once per match over at most 120x120 cells,
	# so the shared definition is worth far more than the saved microseconds.
	for cy: int in range(res):
		var row_base: int = cy * res
		for cx: int in range(res):
			if is_in_disk(cx, cy):
				_in_disk_cells.append(row_base + cx)
	return _in_disk_cells
