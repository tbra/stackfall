extends GutTest
## Home beacon collision: static compound on the Field body.

var _tiny_map: MapDef


func before_each() -> void:
	_tiny_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 6.0
	_tiny_map.home_flag_edge_inset = 0.9  # keeps the old 0.85 * 6 m ring (5.1 m) so the tilt test moves the flag


func _field() -> Field:
	var field: Field = Field.new()
	field.map_def = _tiny_map
	add_child_autofree(field)
	field.place_flags(2, PackedColorArray([Color.RED, Color.BLUE]), 0)
	return field


func test_block_dropped_on_beacon_rests_above_it() -> void:
	var field: Field = _field()
	var flag: HomeFlag = field.home_flags()[0]
	var body: RigidBody3D = RigidBody3D.new()
	body.collision_mask |= Field.BEACON_COLLISION_LAYER
	var box: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3.ONE * 0.5
	box.shape = shape
	body.add_child(box)
	add_child_autofree(body)
	var rest_y: float = flag.beacon_visuals.socket_height
	body.global_position = Vector3(
		flag.position.x + flag.beacon_visuals.socket_radius * 0.8, rest_y + 3.0, flag.position.z
	)
	await wait_physics_frames(150)
	var floor_y: float = _tiny_map.disk_height * 0.5
	assert_gt(body.global_position.y - 0.25, floor_y + rest_y - 0.1, "rests on the socket, not the disc")


func test_elimination_removes_collider() -> void:
	var field: Field = _field()
	assert_eq(field.flag_collision_owners(1).size(), 2)
	Events.player_eliminated.emit(1, 1)
	assert_true(field.flag_collision_owners(1).is_empty())
	assert_eq(field.flag_collision_owners(0).size(), 2, "other beacons keep theirs")
	field.clear_match_state()
	assert_true(field.flag_collision_owners(0).is_empty(), "clearing frees every collider")
	assert_eq(field.get_shape_owners().size(), 1, "disc owner untouched")
	assert_eq(field.beacon_body().get_shape_owners().size(), 0, "no beacon shapes remain")


func test_placement_ray_ignores_beacon() -> void:
	var field: Field = _field()
	await wait_physics_frames(2)
	var flag: HomeFlag = field.home_flags()[0]
	var hit: Variant = field.raycast_down_disk_local(field.to_global(flag.position))
	assert_not_null(hit, "ray over a beacon hits the disc")
	var world_hit: Vector3 = field.world_from_disk_local(hit as Vector2, 0.0)
	assert_almost_eq(field.to_local(world_hit).y, 0.0, 0.01, "placement ray ignores the beacon")
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		field.to_global(flag.position + Vector3.UP * 5.0), field.to_global(flag.position + Vector3.DOWN)
	)
	assert_false(field.get_world_3d().direct_space_state.intersect_ray(query).is_empty(), "beacon exists for unmasked rays")
	query.collision_mask = Field.PLACEMENT_QUERY_MASK
	var masked: Dictionary = field.get_world_3d().direct_space_state.intersect_ray(query)
	assert_true(masked.is_empty() or masked["collider"] == field, "masked ray never hits the beacon body")
