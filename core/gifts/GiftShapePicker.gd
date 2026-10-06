class_name GiftShapePicker
extends RefCounted
## Bontago-1pi.85.35 (docs/GIFT_PLAYTEST2_PLAN.md, P0 contract): picks the BlockShape of a block
## an effect spawns (Stackfall rain, Volcano eruption). Pure, deterministic for a given RNG state.
## SIGNATURE IS THE CONTRACT; package PG replaces the stub with a weighted pick over
## BlockShape.load_all_shapes() using a GiftShapeWeights resource.

const CUBE_SHAPE_PATH: String = "res://config/blocks/cube.tres"


## Weighted random shape. `weights` is a GiftShapeWeights resource (null = unweighted).
## Stub: always the cube, without advancing `rng`.
static func pick(_rng: RandomNumberGenerator, _weights: Resource) -> BlockShape:
	return load(CUBE_SHAPE_PATH) as BlockShape
