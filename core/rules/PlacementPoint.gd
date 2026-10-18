class_name PlacementPoint
extends RefCounted
## Where a pose is judged for placement legality (spec 2.5 "Placement legality"): the horizontal
## centre of the rotated shape's bounds, projected straight down. The spawned body still uses its
## bottom-centre pivot (BlockShape.bottom_center()) as origin; for an upright piece the two points
## coincide, for a tilted or rolled one the pivot can sit 1-2 m from the piece's middle.
##
## Pure math, no scene dependence. The centre is the same one GhostPreview parks under the cursor
## (BlockShape.rotated_center_offset()), so the point the player aims is the point the host judges.


## Vector from the pivot to the legality point, world axes (y is the centre's height over the pivot).
static func centre_offset(shape: BlockShape, basis: Basis, cube_size: float) -> Vector3:
	if shape == null:
		return Vector3.ZERO
	return shape.rotated_center_offset(basis, cube_size)


## The world point whose straight-down column is judged for a piece with `pivot` as its origin.
static func legality_point(pivot: Vector3, shape: BlockShape, basis: Basis, cube_size: float) -> Vector3:
	return pivot + centre_offset(shape, basis, cube_size)
