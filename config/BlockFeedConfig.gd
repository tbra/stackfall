class_name BlockFeedConfig
extends Resource
## Which shapes the feed hands out and how often (spec 2.4).
##
## Spec 2.4: "Weights are set per shape in BlockFeedConfig. Use a 'bag'
## randomizer so no player goes long without getting a stabilizing shape."
## BlockShape already carries a `weight`; this resource lets the lobby
## override it per match without editing the shape resources, and names the
## shapes that count as stabilizers.

## The shapes in the feed. Leave empty to use every BlockShape under
## res://config/blocks/ (BlockShape.load_all_shapes()).
@export var shapes: Array[BlockShape] = []

## Optional per-shape weight overrides, parallel to `shapes`. When this is
## shorter than `shapes`, the remaining shapes fall back to shape.weight.
@export var weight_overrides: PackedFloat32Array = PackedFloat32Array()

## Shapes that count as "stabilizing" (spec 2.4). Every bag is guaranteed to
## contain at least min_stabilizers_per_bag of them.
@export var stabilizer_ids: Array[StringName] = [&"square4", &"slab6", &"cube"]
@export var min_stabilizers_per_bag: int = 2

## A bag holds round(weight * bag_multiplier) copies of each shape, shuffled.
## Bigger means a longer bag and a looser guarantee; smaller means more
## predictable draws.
@export var bag_multiplier: float = 2.0

## Spec 2.4: the HUD shows the next block, optionally the next 3.
@export var preview_count: int = 1
