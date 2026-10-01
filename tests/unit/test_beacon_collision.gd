extends GutTest
## Home beacon collision (Bontago-6fc.4): static compound on the Field body.

var _tiny_map: MapDef


func before_each() -> void:
	_tiny_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 6.0


func _field() -> Field:
	var field: Field = Field.new()
	field.map_def = _tiny_map
	add_child_autofree(field)
	field.place_flags(2, PackedColorArray([Color.RED, Color.BLUE]), 0)
	return field


func test_home_flag_has_collider_matching_model() -> void:
	var field: Field = _field()
	var flag: HomeFlag = field.home_flags()[0]
	var tuning: BeaconVisualTuning = flag.beacon_visuals
	var owners: PackedInt32Array = field.flag_collision_owners(0)
	var body: AnimatableBody3D = field.beacon_body()
	assert_eq(owners.size(), 2, "socket plus crystal")
	var top: float = -INF
	var max_radius: float = 0.0
	for i: int in range(2):
		var shape: Shape3D = body.shape_owner_get_shape(owners[i], 0)
		var xform: Transform3D = body.shape_owner_get_transform(owners[i])
		var aabb: AABB = shape.get_debug_mesh().get_aabb()
		top = maxf(top, xform.origin.y + aabb.end.y)
		max_radius = maxf(max_radius, aabb.size.x * 0.5)
	var expected_top: float = tuning.socket_height + tuning.crystal_height
	assert_almost_eq(top, expected_top, 0.01, "collider top is the crystal tip")
	assert_almost_eq(max_radius, tuning.socket_radius, 0.01, "widest part is the socket")
	var offset: Vector3 = body.shape_owner_get_transform(owners[0]).origin
	assert_almost_eq(offset.x, flag.position.x, 0.001)
	assert_almost_eq(offset.z, flag.position.z, 0.001)


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


func test_collider_follows_tilted_field() -> void:
	var field: Field = _field()
	var body: AnimatableBody3D = field.beacon_body()
	var owner_id: int = field.flag_collision_owners(0)[0]
	var local_before: Transform3D = body.shape_owner_get_transform(owner_id)
	var tilt: Quaternion = Quaternion(Vector3(1.0, 0.0, 1.0).normalized(), deg_to_rad(15.0))
	field.apply_replicated_pose(Vector3.ZERO, tilt)
	var local_after: Transform3D = body.shape_owner_get_transform(owner_id)
	assert_true(local_before.is_equal_approx(local_after), "shape stays fixed in the body's frame")
	var world: Transform3D = body.global_transform * local_after
	var flat_world: Vector3 = local_before.origin
	assert_gt(world.origin.distance_to(flat_world), 0.1, "world pose moved with the tilt")
	assert_almost_eq(world.basis.get_rotation_quaternion().angle_to(tilt), 0.0, 0.01)


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
