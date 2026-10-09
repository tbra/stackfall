class_name MatchContextLive
extends MatchContext
## The live MatchContext: forwards every port method 1:1 to the Match / Net / SnapshotSync
## autoloads (docs/AUTOLOAD_DECOUPLING_PLAN.md, S1b). Installed by Match._ready().
##
## DECISION (D5): values pass straight through (implicit, runtime-checked conversions) so this file
## names no game/ class outside game/world/. DECISION (D9): this and autoload/Match.gd are a
## deliberate 2-file adapter cycle.

var _match: MatchAutoload = null


func _init(match_node: MatchAutoload) -> void:
	_match = match_node


func has_authority() -> bool:
	return _match._is_host()


func net_is_host() -> bool:
	return Net.is_host()


func net_is_client() -> bool:
	return Net.is_client()


func net_is_offline() -> bool:
	return Net.is_offline()


func net_local_slot() -> int:
	return Net.local_slot()


func net_is_local_slot(slot_id: int) -> bool:
	return Net.is_local_slot(slot_id)


func config() -> MatchConfig:
	return _match.config


func physics_tuning() -> PhysicsTuning:
	return _match._physics_tuning


func state() -> int:
	return _match.state()


func slot_count() -> int:
	return _match.slot_count()


func slot(slot_id: int) -> PlayerSlot:
	return _match.slot(slot_id)


func slot_color(slot_id: int, fallback: Color = Color.WHITE) -> Color:
	return _match.slot_color(slot_id, fallback)


func active_slot() -> int:
	return _match.active_slot()


func field() -> FieldBody:
	return _match.field()


func registry() -> Node:
	return _match.registry()


func blocks_parent() -> Node3D:
	return _match.blocks_parent()


func raster() -> TerritoryRaster:
	return _match.raster()


func cell_grid() -> CellGrid:
	return _match.cell_grid()


func qol_claim_radius() -> float:
	return _match.qol_claim_radius()


func glue_drops_left(slot_id: int) -> int:
	return _match.glue_drops_left(slot_id)


func feed_timer_enabled() -> bool:
	return _match.feed_timer_enabled()


func feed_time_left(slot_id: int) -> float:
	return _match.feed_time_left(slot_id)


func has_weather() -> bool:
	return _match.weather() != null


func weather_seed() -> int:
	return _match.weather().seed_value()


func weather_event_index() -> int:
	return _match.weather().event_index()


func shared_clock_seconds() -> float:
	return SnapshotSync.sky_cycle_seconds()


func start_cat(owner_slot: int, position: Vector3, effect: Resource) -> bool:
	return _match.start_cat(owner_slot, position, effect)


func end_cat(activation_id: int) -> void:
	_match.end_cat(activation_id)


func grant_glue_drops(slot_id: int, count: int) -> bool:
	return _match.grant_glue_drops(slot_id, count)


func convert_block_owner(block: RigidBody3D, new_slot: int) -> bool:
	return _match.convert_block_owner(block, new_slot)


func spawn_special_projectile(shape: BlockShape, world_origin: Vector3, basis: Basis,
		owner_slot: int, initial_velocity: Vector3, orb_def: SpecialDef,
		orb_tuning: SpecialTuning) -> RigidBody3D:
	return _match.spawn_special_projectile(shape, world_origin, basis, owner_slot,
			initial_velocity, orb_def, orb_tuning)


func punch_special_hole(disk_pos: Vector2, radius_m: float, hole_open_s: float) -> void:
	_match.punch_special_hole(disk_pos, radius_m, hole_open_s)


func add_match_child(node: Node) -> void:
	_match.add_child(node)
