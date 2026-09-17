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
## 45-degree wedge instead of a full cube. Spec 2.4: "the wedge needs a sloped
## collision shape". Empty for every shape except the wedge.
@export var sloped_cells: Array[Vector3i] = []

## Optional custom mesh; when null the factory generates one from `cells` and
## `sloped_cells`.
@export var mesh: Mesh = null

## Directory scanned by load_all_shapes() for every BlockShape .tres resource.
const SHAPES_DIR: String = "res://config/blocks/"


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
