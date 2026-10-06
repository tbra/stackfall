class_name GiftShapeWeights
extends Resource
## Bontago-1pi.85.31: pick weights for the blocks Stackfall and Volcano spawn. The shape set is the
## block set itself (BlockShape.load_all_shapes()); this resource only OVERRIDES the weight of the
## ids it lists (parallel arrays, same index). Unlisted shapes keep their own BlockShape.weight, so
## a new shape joins the rain without editing this file. A weight of 0 excludes a shape.

@export var shape_ids: PackedStringArray = PackedStringArray()
@export var weights: PackedFloat32Array = PackedFloat32Array()

## Resolves the override for `id`; returns -1.0 when the id is not listed (use the shape's weight).
func override_for(id: StringName) -> float:
	var count: int = mini(shape_ids.size(), weights.size())
	for i: int in range(count):
		if StringName(shape_ids[i]) == id:
			return weights[i]
	return -1.0


## True when sizes match and every weight is finite and non-negative.
func is_valid() -> bool:
	if shape_ids.size() != weights.size():
		return false
	for w: float in weights:
		if not is_finite(w) or w < 0.0:
			return false
	return true
