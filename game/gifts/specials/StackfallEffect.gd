class_name StackfallEffect
extends SpecialEffect
## A triggered gift starts a bounded host-owned rain of ordinary blocks.
## Runtime state lives on StackfallRain, never on this shared Resource.

@export_range(1, 64, 1) var block_count: int = 28
@export_range(0.1, 30.0, 0.1) var blocks_per_second: float = 9.5
@export_range(1.0, 100.0, 0.5) var area_radius_m: float = 12.0
@export_range(1.0, 100.0, 0.5) var spawn_height_m: float = 30.0
@export_range(0.0, 10.0, 0.1) var min_spacing_m: float = 1.5
@export_range(1, 128, 1) var position_attempts: int = 40
@export_range(1, 2000, 1) var max_active_blocks: int = 600
## Fallback single shape, used only when `shape_weights` is null.
@export var block_shape: BlockShape = preload("res://config/blocks/cube.tres")
## Per-block shape pick (GiftShapeWeights); null = every block is `block_shape`.
@export var shape_weights: GiftShapeWeights = preload("res://config/gifts/gift_shape_weights.tres")
@export var random_yaw: bool = true


## Seed mixing for an in-place activation (no net_id): slot and activation counter.
const SLOT_SEED_MIX: int = 2654435761
const SEQ_SEED_MIX: int = 40503


## An in-place activation (MatchGiftActivation anchor) has nothing to wait for: rain now.
func wants_early_trigger(block: Block, _behavior: SpecialBehavior) -> bool:
	return block != null and block.has_meta(SpecialIds.IN_PLACE_META)


func detonate(block: Block, _behavior: SpecialBehavior, _chain_depth: int) -> void:
	var ctx: MatchContext = MatchContext.current()
	if block == null or not ctx.has_authority() or ctx.state() != MatchPhase.State.PLAYING:
		return
	if block.owner_slot < 0 or block.owner_slot >= ctx.slot_count():
		return
	var field: FieldBody = ctx.field()
	if field == null or ctx.blocks_parent() == null or (block_shape == null and shape_weights == null):
		return
	var rain: StackfallRain = StackfallRain.new()
	var seed_value: int = int(ctx.config().rng_seed) ^ (block.net_id * SLOT_SEED_MIX)
	if block.net_id < 0:
		# In-place anchor: the id is -1 for every activation, so mix slot + counter instead.
		seed_value = int(ctx.config().rng_seed) ^ ((block.owner_slot + 1) * SLOT_SEED_MIX) 			^ (int(block.get_meta(SpecialIds.ACTIVATION_SEQ_META, 0)) * SEQ_SEED_MIX)
	rain.bind(
		block.owner_slot, field.disk_local_from_world(block.global_position), seed_value,
		block_shape, block_count, blocks_per_second, area_radius_m, spawn_height_m,
		min_spacing_m, position_attempts, max_active_blocks, shape_weights, random_yaw
	)
	ctx.add_match_child(rain)
