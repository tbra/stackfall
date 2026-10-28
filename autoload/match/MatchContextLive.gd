class_name MatchContextLive
extends MatchContext
## The live MatchContext: forwards every port method 1:1 to the Match / Net / SnapshotSync
## autoloads (the decoupling step S1b).
##
## DECISION (D5): values pass straight through (implicit, runtime-checked conversions) so this file
## names no game/ class outside game/world/. DECISION (D9): this and autoload/Match.gd are a
## deliberate 2-file adapter cycle.

var _match: MatchAutoload = null


func _init(match_node: MatchAutoload) -> void:
	_match = match_node


## DECISION (S2c): before Match.late_activate() the controllers do not exist, so every forward that
## reaches one answers the MatchContext null-object value instead (windowed boot only).
func _active() -> bool:
	return _match != null and _match.is_late_active()


func has_authority() -> bool:
	# DECISION: private read kept on purpose (the D9 two-file cycle); a public accessor would have one caller.
	return _match._is_host()


func net_is_client() -> bool:
	return Net.is_client()


func net_is_local_slot(slot_id: int) -> bool:
	return Net.is_local_slot(slot_id)


func config() -> MatchConfig:
	return _match.config


func physics_tuning() -> PhysicsTuning:
	# DECISION: private read kept on purpose (the D9 two-file cycle); a public accessor would have one caller.
	return _match._physics_tuning


func state() -> int:
	if not _active():
		return MatchPhase.State.LOBBY
	return _match.state()


func slot_count() -> int:
	if not _active():
		return 0
	return _match.slot_count()


func slot(slot_id: int) -> PlayerSlot:
	if not _active():
		return null
	return _match.slot(slot_id)


func slot_color(slot_id: int, fallback: Color = Color.WHITE) -> Color:
	if not _active():
		return fallback
	return _match.slot_color(slot_id, fallback)


func field() -> FieldBody:
	return _match.field()


func registry() -> Node:
	return _match.registry()


func blocks_parent() -> Node3D:
	return _match.blocks_parent()


func raster() -> TerritoryRaster:
	if not _active():
		return null
	return _match.raster()


func cell_grid() -> CellGrid:
	if not _active():
		return null
	return _match.cell_grid()


func qol_claim_radius() -> float:
	if not _active():
		return 0.0
	return _match.qol_claim_radius()


## not gated on _active(): the zone radius is static tuning, so a flag placed
## before late activation still draws its beacon zone.
func goal_zone_visual_radius() -> float:
	return _match.goal_zone_visual_radius()


func capture_hold_seconds() -> float:
	# DECISION: private read kept on purpose (the D9 two-file cycle); a public accessor would have one caller.
	return _match._territory_tuning.capture_hold


func glue_drops_left(slot_id: int) -> int:
	if not _active():
		return 0
	return _match.glue_drops_left(slot_id)


func feed_timer_enabled() -> bool:
	if not _active():
		return false
	return _match.feed_timer_enabled()


func feed_time_left(slot_id: int) -> float:
	if not _active():
		return 0.0
	return _match.feed_time_left(slot_id)


func has_weather() -> bool:
	if not _active():
		return false
	return _match.weather() != null


func weather_seed() -> int:
	if not _active():
		return 0
	return _match.weather().seed_value()


func weather_event_index() -> int:
	if not _active():
		return 0
	return _match.weather().event_index()


func shared_clock_seconds() -> float:
	return SnapshotSync.sky_cycle_seconds()


func start_cat(owner_slot: int, position: Vector3, effect: Resource) -> bool:
	if not _active():
		return false
	return _match.start_cat(owner_slot, position, effect)


func end_cat(activation_id: int) -> void:
	if not _active():
		return
	_match.end_cat(activation_id)


func grant_glue_drops(slot_id: int, count: int) -> bool:
	if not _active():
		return false
	return _match.grant_glue_drops(slot_id, count)


func convert_block_owner(block: RigidBody3D, new_slot: int) -> bool:
	if not _active():
		return false
	return _match.convert_block_owner(block, new_slot)


func spawn_special_projectile(shape: BlockShape, world_origin: Vector3, basis: Basis,
		owner_slot: int, initial_velocity: Vector3, orb_def: SpecialDef,
		orb_tuning: SpecialTuning) -> RigidBody3D:
	if not _active():
		return null
	return _match.spawn_special_projectile(shape, world_origin, basis, owner_slot,
			initial_velocity, orb_def, orb_tuning)


func punch_special_hole(disk_pos: Vector2, radius_m: float, hole_open_s: float) -> void:
	if not _active():
		return
	_match.punch_special_hole(disk_pos, radius_m, hole_open_s)


func add_match_child(node: Node) -> void:
	_match.add_child(node)


func held_shape(slot_id: int) -> BlockShape:
	if not _active():
		return null
	return _match.held_shape(slot_id)


func held_special(slot_id: int) -> StringName:
	if not _active():
		return &""
	return _match.held_special(slot_id)


func is_release_locked(slot_id: int) -> bool:
	return _match.is_release_locked(slot_id)


func gift_slot_head(slot_id: int) -> StringName:
	if not _active():
		return &""
	return _match.gift_slot_head(slot_id)


func default_ghost_origin(slot_id: int) -> Vector3:
	return _match.default_ghost_origin(slot_id)


func preview_placement(slot_id: int, origin: Vector3, orientation_index: int,
		free_quat: Quaternion) -> PlacementRules.Result:
	return _match.preview_placement(slot_id, origin, orientation_index, free_quat)


func active_cat() -> RigidBody3D:
	return _match.active_cat()


## The membrane (MatchNet) when installed: it acts inline on the host and sends the intent RPC on a
## client, quoting Match.feed_seq exactly as the controller did. Otherwise Match directly.
func submit_place(slot_id: int, origin: Vector3, orientation_index: int,
		free_quat: Quaternion, auto_drop: bool) -> StringName:
	var membrane: Variant = _match.replicator()
	if membrane == null:
		return _match.request_place(slot_id, origin, orientation_index, free_quat, auto_drop)
	return membrane.submit_place(slot_id, origin, orientation_index, free_quat, auto_drop,
			int(_match.feed_seq(slot_id)))


func submit_throw(slot_id: int, origin: Vector3, orientation_index: int,
		free_quat: Quaternion, velocity: Vector3) -> StringName:
	var membrane: Variant = _match.replicator()
	if membrane == null:
		return _match.request_throw(slot_id, origin, orientation_index, free_quat, velocity)
	return membrane.submit_throw(slot_id, origin, orientation_index, free_quat, velocity,
			int(_match.feed_seq(slot_id)))


func submit_use_gift_slot(slot_id: int) -> bool:
	var membrane: Variant = _match.replicator()
	if membrane == null:
		return _match.request_use_gift_slot(slot_id)
	return membrane.submit_use_gift_slot(slot_id)


func submit_cursor(slot_id: int, origin: Vector3, orientation_index: int,
		free_quat: Quaternion, aim: Vector3) -> void:
	var membrane: Variant = _match.replicator()
	if membrane != null:
		membrane.submit_cursor(slot_id, origin, orientation_index, free_quat, aim)


func submit_cat_target(slot_id: int, point: Vector3) -> void:
	var membrane: Variant = _match.replicator()
	if membrane != null:
		membrane.submit_cat_target(slot_id, point)


func note_aim(slot_id: int, forward: Vector3) -> void:
	_match.note_aim(slot_id, forward)
