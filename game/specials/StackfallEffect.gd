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
@export var block_shape: BlockShape = preload("res://config/blocks/cube.tres")


func detonate(block: Block, _behavior: SpecialBehavior, _chain_depth: int) -> void:
	if block == null or not Match._is_host() or Match.state() != Match.State.PLAYING:
		return
	if block.owner_slot < 0 or block.owner_slot >= Match.slot_count():
		return
	var field: Field = Match.field()
	if field == null or Match.blocks_parent() == null or block_shape == null:
		return
	var rain: StackfallRain = StackfallRain.new()
	var seed_value: int = int(Match.config.rng_seed) ^ (block.net_id * 2654435761)
	rain.bind(
		block.owner_slot, field.disk_local_from_world(block.global_position), seed_value,
		block_shape, block_count, blocks_per_second, area_radius_m, spawn_height_m,
		min_spacing_m, position_attempts, max_active_blocks
	)
	Match.add_child(rain)
