class_name GhostSilhouette
extends RefCounted
## Pure footprint geometry of a held shape: outline loops, wall segments and heights, and the
## collision probes, built from meshes and their offsets. No scene tree. Stub: empty results
## until GhostPreview's geometry moves here.


## What build() returns.
class Result extends RefCounted:
	## Footprint outline loops in the ground plane (x, z).
	var loops: Array[PackedVector2Array] = []
	## Consecutive (a, b) ghost-local XZ pairs, one per wall piece.
	var wall_segments: PackedVector2Array = PackedVector2Array()
	## Per wall piece, the shape's underside Y at a (x) and at b (y), relative to the ghost origin.
	var wall_heights: PackedVector2Array = PackedVector2Array()
	## One ghost-local XZ probe point per wall piece, nudged just inside the silhouette.
	var probes: PackedVector2Array = PackedVector2Array()


static func build(_meshes: Array[Mesh], _offsets: PackedVector3Array, _basis: Basis) -> Result:
	return Result.new()


## Alpha mask of `loops` over `origin` .. `origin + extent`; width and height are each
## ceil(extent * pixels_per_meter) clamped to 2 .. max_pixels. Stub: null.
static func rasterize_mask(
	_loops: Array[PackedVector2Array], _origin: Vector2, _extent: Vector2,
	_pixels_per_meter: float, _max_pixels: int
) -> Image:
	return null
