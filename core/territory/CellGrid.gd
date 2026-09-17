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
## Cell index is row-major, `cy * res + cx`, which is also the pixel index of
## the authoritative territory raster and the shape-owner order Field uses for
## its BoxShape3D cells. One cell is one raster pixel is one collision box.
## See docs/M2_PLAN.md, "Raster resolution", for why the rules run at cell
## resolution and MapDef.territory_res is the upload size instead.
##
## Pure logic: no scene tree, no nodes (CLAUDE.md).

var field_radius: float = 1.0
var cell_size: float = 1.0
## Cells along one edge of the square that covers the disk.
var res: int = 2


func _init(p_field_radius: float = 1.0, p_cell_size: float = 1.0) -> void:
	field_radius = maxf(p_field_radius, 0.001)
	cell_size = maxf(p_cell_size, 0.001)
	res = int(ceil(2.0 * field_radius / cell_size))


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
		floori((point.x + field_radius) / cell_size),
		floori((point.y + field_radius) / cell_size)
	)


## Disk-local center of a cell.
func cell_center(cx: int, cy: int) -> Vector2:
	return Vector2(
		(float(cx) + 0.5) * cell_size - field_radius,
		(float(cy) + 0.5) * cell_size - field_radius
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
	return 0


## Every in-disk cell index, in row-major order. Built once.
func in_disk_cells() -> PackedInt32Array:
	return PackedInt32Array()
