class_name BlockShape
extends Resource
## One placeable block shape: a set of unit-cube offsets plus feed weight
## (spec 2.8, 1.4). The block factory (game/blocks/BlockFactory.gd) turns this data
## into a RigidBody3D with one BoxShape3D per cell.

## Unique identifier, e.g. &"cube", &"bar3".
@export var id: StringName = &""

## Player-facing name, e.g. "Long bar". Read it through DisplayNames.shape().
@export var display_name: String = ""

## Integer cube offsets from the shape's local origin. No two cells may repeat.
@export var cells: Array[Vector3i] = []

## Feed weight for the weighted bag. Must stay positive: it is a relative
## likelihood.
@export var weight: float = 1.0

## Whether this shape is dealt in matches (bag, gifts, Sandbox picker). Off keeps the
## resource on disk and resolvable by id but never fed to anyone.
## [OWNER decision]: bar4 and bar5 are off.
@export var in_match_bag: bool = true

## Cells (must also appear in `cells`) whose collision and mesh should be a
## 45-degree wedge instead of a full cube (spec 1.4's now-removed wedge shape
## used this; game/blocks/BlockFactory.gd's DECISION comment on the sloped branch
## explains why the machinery stays). Empty for every shipped shape today.
@export var sloped_cells: Array[Vector3i] = []

## Optional custom mesh; when null the factory generates one from `cells` and
## `sloped_cells`.
@export var mesh: Mesh = null

## The name shown to players: `display_name`, else the id with spaces and capitals.
func get_display_name() -> String:
	if display_name != "":
		return display_name
	return String(id).capitalize()


## Directory scanned by load_all_shapes() for every BlockShape .tres resource.
const SHAPES_DIR: String = "res://config/blocks/"

## Pivot of every body and ghost, in cell units, computed once and cached: the x/z
## centre of `cells`' bounds, with y at the bottom face of the lowest cell
## (min_y - 0.5). game/blocks/BlockFactory.gd builds every cell offset relative to
## this point, so a body's/ghost's local origin sits at the bottom of the unrotated
## shape instead of mid-height (which sank half the block into the disk).
##
## DECISION: bottom_center() is the only pivot convention, so BlockFactory,
## GhostPreview and Match cannot disagree about which one to use. See
## game/player/GhostPreview.gd's own DECISION for how rotation about this origin is
## compensated so the rotated shape's lowest point lands at the cursor height.
##
## DECISION: cached on the instance. load_all_shapes() hands back the same loaded
## Resource per id and `cells` never changes after load, so nothing invalidates it.
var _cached_bottom_center: Vector3 = Vector3.ZERO
var _bottom_center_computed: bool = false


func bottom_center() -> Vector3:
	if not _bottom_center_computed:
		_cached_bottom_center = _compute_bottom_center()
		_bottom_center_computed = true
	return _cached_bottom_center


## Signs of the eight corners of a cube.
const CORNER_SIGNS: Array[Vector3] = [
	Vector3(-1.0, -1.0, -1.0), Vector3(1.0, -1.0, -1.0), Vector3(-1.0, 1.0, -1.0), Vector3(1.0, 1.0, -1.0),
	Vector3(-1.0, -1.0, 1.0), Vector3(1.0, -1.0, 1.0), Vector3(-1.0, 1.0, 1.0), Vector3(1.0, 1.0, 1.0),
]


## Height (<= 0 for a tilted shape) of this shape's lowest collision corner relative to its
## bottom_center() pivot once rotated by `basis`. The pivot must be raised by -this value for the
## rotated shape to rest ON a surface instead of sinking into it. Shared by GhostPreview (human
## placement) and BotController (bot placement) so both send the same pose.
func rotated_bottom_offset(basis: Basis, cube_size: float, cube_margin: float) -> float:
	if cells.is_empty():
		return 0.0
	var half_size: float = (cube_size - cube_margin) * 0.5
	var pivot: Vector3 = bottom_center()
	var min_y: float = INF
	for cell: Vector3i in cells:
		var local: Vector3 = (Vector3(cell) - pivot) * cube_size
		for corner_sign: Vector3 in CORNER_SIGNS:
			min_y = minf(min_y, (basis * (local + corner_sign * half_size)).y)
	return 0.0 if min_y == INF else min_y


## the rotated bounding-box centre of the cube centres, relative to the pivot
## (GhostPreview.rotated_center_offset parity; xz is 0 for a yaw-only basis).
func rotated_center_offset(basis: Basis, cube_size: float) -> Vector3:
	if cells.is_empty():
		return Vector3.ZERO
	var pivot: Vector3 = bottom_center()
	var min_local: Vector3 = Vector3(INF, INF, INF)
	var max_local: Vector3 = Vector3(-INF, -INF, -INF)
	for cell: Vector3i in cells:
		var local: Vector3 = (Vector3(cell) - pivot) * cube_size
		min_local = min_local.min(local)
		max_local = max_local.max(local)
	return basis * ((min_local + max_local) * 0.5)


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


## load_all_shapes() minus the shapes switched off for matches (`in_match_bag` false).
## Use this wherever shapes are DEALT; use load_all_shapes() only for id lookups.
static func load_bag_shapes() -> Array[BlockShape]:
	var shapes: Array[BlockShape] = []
	for shape: BlockShape in load_all_shapes():
		if shape.in_match_bag:
			shapes.append(shape)
	return shapes


## Loads every BlockShape resource in SHAPES_DIR, sorted by id so the result is
## deterministic across platforms and directory-listing orders. The single
## source of truth for "what shapes exist". BlockFeedConfig falls back to this
## when its `shapes` list is empty, and core/blocks/BlockBag.gd needs the order to
## be stable so the same rng_seed always deals the same sequence (spec 1.4).
static func load_all_shapes() -> Array[BlockShape]:
	var shapes: Array[BlockShape] = []
	var dir: DirAccess = DirAccess.open(SHAPES_DIR)
	if dir == null:
		return shapes
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		# Exported PCKs list text resources as "<name>.tres.remap" (the editor's
		# convert-text-resources-to-binary step); load() resolves the original
		# path through that remap, so only the listing suffix needs stripping.
		# Without this no shape/special ever loads in an exported build.
		if file_name.ends_with(".remap"):
			file_name = file_name.trim_suffix(".remap")
		if file_name.ends_with(".tres"):
			var shape: BlockShape = load(SHAPES_DIR + file_name)
			if shape != null:
				shapes.append(shape)
		file_name = dir.get_next()
	dir.list_dir_end()
	shapes.sort_custom(func(a: BlockShape, b: BlockShape) -> bool: return String(a.id) < String(b.id))
	return shapes
