class_name BlockShape
extends Resource
## One placeable block shape: a set of unit-cube offsets plus feed weight
## (spec 3.6, 2.4). The block factory (game/BlockFactory.gd) turns this data
## into a RigidBody3D with one BoxShape3D per cell.

## Unique identifier, e.g. &"cube", &"bar3".
@export var id: StringName = &""

## Integer cube offsets from the shape's local origin. No two cells may repeat.
@export var cells: Array[Vector3i] = []

## Feed weight for the weighted bag (M2). Must stay positive so the M1 plain
## random pick can still use it as a relative likelihood.
@export var weight: float = 1.0

## Cells (must also appear in `cells`) whose collision and mesh should be a
## 45-degree wedge instead of a full cube (spec 2.4's now-removed wedge shape
## used this; game/BlockFactory.gd's DECISION comment on the sloped branch
## explains why the machinery stays). Empty for every shipped shape today.
@export var sloped_cells: Array[Vector3i] = []

## Optional custom mesh; when null the factory generates one from `cells` and
## `sloped_cells`.
@export var mesh: Mesh = null

## Directory scanned by load_all_shapes() for every BlockShape .tres resource.
const SHAPES_DIR: String = "res://config/blocks/"

## Bontago-mv0.12 (owner-reported playability): `cells`' bounding-box centre,
## in cell units, computed once and cached. Every shape whose cells don't
## straddle the origin symmetrically (bar3's cells run 0..2, so its centre is
## (1, 0, 0); domino's run 0..1, so its centre is (0.5, 0, 0)) used to hang off
## the cursor and rotate about the wrong point, because game/BlockFactory.gd
## and autoload/Match.gd both treated cell (0, 0, 0) as the pivot.
##
## Bontago-mv0.17 item 3 (owner feel report: "the ghost/body pivot is the
## block's middle, so half the block sinks below the cursor point and clips
## into the disk"): the geometric centre from mv0.12 fixed the *rotation*
## drift but was still a mid-height pivot for placement purposes. This is now
## `bottom_center()` instead of `center()` — the x/z centre of the cell
## bounds unchanged, but y is the bottom face of the lowest cell
## (min_y - 0.5 cell, i.e. half a cube below the lowest cell's own centre)
## rather than the vertical midpoint. game/BlockFactory.gd builds every cell
## offset relative to this point now, so a body's/ghost's own local origin
## (0, 0, 0) sits at the bottom of the *unrotated* shape.
##
## DECISION (config/blocks/BlockShape.gd): renamed rather than kept alongside
## the old geometric-centre method — nothing in the project still wants a
## mid-height pivot, so carrying two pivot conventions would just be a second
## place for BlockFactory/GhostPreview/Match to disagree about which one to
## use. See game/GhostPreview.gd's own DECISION for how rotation (which still
## happens about this same local origin) is compensated so the *rotated*
## shape's lowest point — not always this unrotated bottom-centre point after
## a 90-degree pitch/roll — is what actually lands at the cursor height.
##
## DECISION (config/blocks/BlockShape.gd): cached on the instance rather than
## recomputed every call. BlockShape.load_all_shapes() hands back the same
## loaded Resource to every caller for a given id (Godot's resource cache), so
## one shape's bottom_center() is computed once per process and reused by
## every block of that shape for the rest of the run; `cells` never changes
## after load, so there is nothing to invalidate the cache for.
var _cached_bottom_center: Vector3 = Vector3.ZERO
var _bottom_center_computed: bool = false


func bottom_center() -> Vector3:
	if not _bottom_center_computed:
		_cached_bottom_center = _compute_bottom_center()
		_bottom_center_computed = true
	return _cached_bottom_center


func _compute_bottom_center() -> Vector3:
	if cells.is_empty():
		return Vector3.ZERO
	var min_x: float = INF
	var max_x: float = -INF
	var min_y: float = INF
	var max_y: float = -INF
	var min_z: float = INF
	var max_z: float = -INF
	for cell: Vector3i in cells:
		min_x = minf(min_x, float(cell.x))
		max_x = maxf(max_x, float(cell.x))
		min_y = minf(min_y, float(cell.y))
		max_y = maxf(max_y, float(cell.y))
		min_z = minf(min_z, float(cell.z))
		max_z = maxf(max_z, float(cell.z))
	return Vector3((min_x + max_x) * 0.5, min_y - 0.5, (min_z + max_z) * 0.5)


## Loads every BlockShape resource in SHAPES_DIR, sorted by id so the result is
## deterministic across platforms and directory-listing orders. The single
## source of truth for "what shapes exist" — used by the M1 plain-random feed
## (game/PlayerController.gd), the rain benchmark (tests/bench/bench_rain.gd),
## and M2's weighted bag. BlockFeedConfig falls back to this when its `shapes`
## list is empty, and core/feed/BlockBag.gd needs the order to be stable so the
## same rng_seed always deals the same sequence (spec 2.4).
static func load_all_shapes() -> Array[BlockShape]:
	var shapes: Array[BlockShape] = []
	var dir: DirAccess = DirAccess.open(SHAPES_DIR)
	if dir == null:
		return shapes
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var shape: BlockShape = load(SHAPES_DIR + file_name)
			if shape != null:
				shapes.append(shape)
		file_name = dir.get_next()
	dir.list_dir_end()
	shapes.sort_custom(func(a: BlockShape, b: BlockShape) -> bool: return String(a.id) < String(b.id))
	return shapes
