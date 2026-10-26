class_name GiftCrateTouch
extends RefCounted
## Pure overlap tests between a block's cells and a gift crate's box, no scene tree.
## Stub revision: neutral (no overlap) until the core package fills the bodies.


## Whether the cube at `cell_center` (rotated by `basis`, half extent `cell_half`) overlaps the
## axis-aligned crate box at `crate_center` with half extents `crate_half`.
static func cell_overlaps_crate(
	_cell_center: Vector3, _basis: Basis, _cell_half: float, _crate_center: Vector3, _crate_half: Vector3
) -> bool:
	return false


## Whether any of `cells` (grid cells about `pivot`, placed at `origin` with `basis`) overlaps the crate box.
static func shape_overlaps_crate(
	_cells: Array[Vector3i], _pivot: Vector3, _origin: Vector3, _basis: Basis, _cube_size: float,
	_cell_half: float, _crate_center: Vector3, _crate_half: Vector3
) -> bool:
	return false
