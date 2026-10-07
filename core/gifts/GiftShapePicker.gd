class_name GiftShapePicker
extends RefCounted
## Bontago-1pi.85.31 (docs/GIFT_PLAYTEST2_PLAN.md, PG): picks the BlockShape of a block an effect
## spawns (Stackfall rain, Volcano eruption). Pure, deterministic for a given RNG state: exactly one
## rng.randf() is consumed per pick (none when no shape is available).

const CUBE_SHAPE_PATH: String = "res://config/blocks/cube.tres"

## Shape list cached once per process: BlockShape.load_all_shapes() scans a directory and effects
## pick per spawned block. Tests that add shapes call reset_cache_for_tests().
static var _cached_shapes: Array[BlockShape] = []
static var _cache_loaded: bool = false
## Number of directory scans this class triggered (test seam).
static var scan_count: int = 0


static func reset_cache_for_tests() -> void:
	_cached_shapes = []
	_cache_loaded = false
	scan_count = 0


static func _shapes() -> Array[BlockShape]:
	if not _cache_loaded:
		_cached_shapes = BlockShape.load_all_shapes()
		_cache_loaded = true
		scan_count += 1
	return _cached_shapes


## Weighted random shape over BlockShape.load_all_shapes(). `weights` is a GiftShapeWeights
## (null or invalid = every shape at its own BlockShape.weight). Zero-weight shapes are never picked.
static func pick(rng: RandomNumberGenerator, weights: Resource) -> BlockShape:
	var shapes: Array[BlockShape] = _shapes()
	var table: GiftShapeWeights = weights as GiftShapeWeights
	if table != null and not table.is_valid():
		table = null
	var effective: PackedFloat32Array = _effective_weights(shapes, table)
	var total: float = 0.0
	for w: float in effective:
		total += w
	if total <= 0.0 and table != null:
		effective = _effective_weights(shapes, null)
		total = 0.0
		for w: float in effective:
			total += w
	if total <= 0.0:
		return load(CUBE_SHAPE_PATH) as BlockShape
	var roll: float = (rng.randf() if rng != null else 0.5) * total
	var last_positive: int = -1
	for i: int in range(shapes.size()):
		if effective[i] <= 0.0:
			continue
		last_positive = i
		roll -= effective[i]
		if roll < 0.0:
			return shapes[i]
	return shapes[last_positive]


static func _effective_weights(shapes: Array[BlockShape], table: GiftShapeWeights) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	for shape: BlockShape in shapes:
		var w: float = shape.weight
		if table != null:
			var override: float = table.override_for(shape.id)
			if override >= 0.0:
				w = override
		out.append(w if is_finite(w) and w > 0.0 else 0.0)
	return out


## Largest horizontal distance from the shape's cell-bounds centre to a cell centre, in metres per
## cell unit (cube = 0). Rotation about the vertical axis does not change it.
static func footprint_radius(shape: BlockShape, cell_size: float) -> float:
	if shape == null or shape.cells.is_empty():
		return 0.0
	var centre: Vector3 = shape.bottom_center()
	var radius: float = 0.0
	for cell: Vector3i in shape.cells:
		radius = maxf(radius, Vector2(float(cell.x) - centre.x, float(cell.z) - centre.z).length())
	return radius * cell_size
