class_name CatEffect
extends SpecialEffect
## One cat per match. A newer activation replaces the previous chase.

@export_range(1.0, 60.0, 0.5) var duration_s: float = 15.0
@export_range(1.0, 30.0, 0.5) var speed_mps: float = 9.0
@export_range(1.0, 100.0, 0.5) var target_range_m: float = 25.0
@export_range(0.2, 5.0, 0.1) var body_radius_m: float = 0.8
@export_range(1.0, 100.0, 0.5) var push_impulse: float = 12.0
@export_range(1, 2000, 1) var max_active_blocks: int = 600


func detonate(block: Block, _behavior: SpecialBehavior, _chain_depth: int) -> void:
	if block == null or not Match._is_host() or Match.state() != Match.State.PLAYING:
		return
	if block.owner_slot < 0 or block.owner_slot >= Match.slot_count():
		return
	Match.start_cat(block.owner_slot, block.global_position, self)
