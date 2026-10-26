class_name GiftCrateTouch
extends RefCounted
## Pure overlap tests between a block's cells and a gift crate's box, no scene tree.

## Cross products shorter than this are parallel axes and add no separation test.
const MIN_CROSS_LENGTH_SQUARED: float = 0.00000001


## Whether the cube at `cell_center` (rotated by `basis`, half extent `cell_half`) overlaps the
## axis-aligned crate box at `crate_center` with half extents `crate_half`. Separating-axis test:
## the three face axes of each box plus nine edge cross-products cover every possible separation.
static func cell_overlaps_crate(
	cell_center: Vector3, basis: Basis, cell_half: float, crate_center: Vector3, crate_half: Vector3
) -> bool:
	var displacement: Vector3 = crate_center - cell_center
	var cell_x: Vector3 = basis.x
	var cell_y: Vector3 = basis.y
	var cell_z: Vector3 = basis.z
	if _separated(Vector3.RIGHT, displacement, cell_x, cell_y, cell_z, cell_half, crate_half):
		return false
	if _separated(Vector3.UP, displacement, cell_x, cell_y, cell_z, cell_half, crate_half):
		return false
	if _separated(Vector3.BACK, displacement, cell_x, cell_y, cell_z, cell_half, crate_half):
		return false
	if _separated(cell_x, displacement, cell_x, cell_y, cell_z, cell_half, crate_half):
		return false
	if _separated(cell_y, displacement, cell_x, cell_y, cell_z, cell_half, crate_half):
		return false
	if _separated(cell_z, displacement, cell_x, cell_y, cell_z, cell_half, crate_half):
		return false
	if _cross_separated(Vector3.RIGHT, displacement, cell_x, cell_y, cell_z, cell_half, crate_half):
		return false
	if _cross_separated(Vector3.UP, displacement, cell_x, cell_y, cell_z, cell_half, crate_half):
		return false
	if _cross_separated(Vector3.BACK, displacement, cell_x, cell_y, cell_z, cell_half, crate_half):
		return false
	return true


## Whether any of `cells` (grid cells about `pivot`, placed at `origin` with `basis`) overlaps the crate box.
static func shape_overlaps_crate(
	cells: Array[Vector3i], pivot: Vector3, origin: Vector3, basis: Basis, cube_size: float,
	cell_half: float, crate_center: Vector3, crate_half: Vector3
) -> bool:
	for cell: Vector3i in cells:
		var center: Vector3 = origin + basis * ((Vector3(cell) - pivot) * cube_size)
		if cell_overlaps_crate(center, basis, cell_half, crate_center, crate_half):
			return true
	return false


static func _separated(
	axis: Vector3, displacement: Vector3, cell_x: Vector3, cell_y: Vector3, cell_z: Vector3,
	cell_half: float, crate_half: Vector3
) -> bool:
	var crate_radius: float = crate_half.x * absf(axis.x) + crate_half.y * absf(axis.y) + crate_half.z * absf(axis.z)
	var cell_radius: float = cell_half * (absf(axis.dot(cell_x)) + absf(axis.dot(cell_y)) + absf(axis.dot(cell_z)))
	return absf(displacement.dot(axis)) > crate_radius + cell_radius


## The three edge cross-products of `world_axis` with the cell axes; true when any separates.
static func _cross_separated(
	world_axis: Vector3, displacement: Vector3, cell_x: Vector3, cell_y: Vector3, cell_z: Vector3,
	cell_half: float, crate_half: Vector3
) -> bool:
	var cross_x: Vector3 = world_axis.cross(cell_x)
	if cross_x.length_squared() > MIN_CROSS_LENGTH_SQUARED 			and _separated(cross_x, displacement, cell_x, cell_y, cell_z, cell_half, crate_half):
		return true
	var cross_y: Vector3 = world_axis.cross(cell_y)
	if cross_y.length_squared() > MIN_CROSS_LENGTH_SQUARED 			and _separated(cross_y, displacement, cell_x, cell_y, cell_z, cell_half, crate_half):
		return true
	var cross_z: Vector3 = world_axis.cross(cell_z)
	return cross_z.length_squared() > MIN_CROSS_LENGTH_SQUARED 		and _separated(cross_z, displacement, cell_x, cell_y, cell_z, cell_half, crate_half)
