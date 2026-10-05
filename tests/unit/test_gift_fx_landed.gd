extends GutTest
## LandedProbe (docs/GIFT_EFFECTS_PLAN.md section 5 A1): velocity/hold/timeout
## detection instead of Jolt sleeping. The disc keeps tilting so the island never sleeps.

const TICK: float = 1.0 / 60.0
const TILT_KICK_EVERY_FRAMES: int = 10
const TILT_KICK: float = 0.3
const EXTRA_SECONDS: float = 2.0

var _field: Field
var _root: Node3D


func before_each() -> void:
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_fx_landed"
	map_def.field_radius = 10.0
	map_def.cell_size = 1.0
	map_def.disk_height = 1.0
	map_def.territory_res = 32
	_field = Field.new()
	_field.map_def = map_def
	add_child_autofree(_field)
	_root = Node3D.new()
	add_child_autofree(_root)
	_field.set_tilt_enabled(true)


func _block(at: Vector3) -> Block:
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var tuning: PhysicsTuning = load("res://config/physics_tuning.tres")
	var block: Block = BlockFactory.build(shape, tuning, 0)
	_root.add_child(block)
	block.global_position = at
	return block


func _tune() -> LandedTuning:
	var t: LandedTuning = LandedTuning.new()
	t.landed_timeout_s = 1.5
	return t


func test_block_on_a_continuously_tilting_disc_lands_within_the_timeout() -> void:
	var gift: Block = _block(Vector3(0.0, _field.surface_y() + 0.8, 0.0))
	var neighbour: Block = _block(Vector3(3.0, _field.surface_y() + 0.8, 0.0))
	var t: LandedTuning = _tune()
	var probe: LandedProbe = LandedProbe.new(t)
	var max_frames: int = int((t.landed_timeout_s + EXTRA_SECONDS) / TICK)
	var landed_frame: int = -1
	for frame: int in max_frames:
		if frame % TILT_KICK_EVERY_FRAMES == 0:
			var kick_sign: float = 1.0 if (frame / TILT_KICK_EVERY_FRAMES) % 2 == 0 else -1.0
			_field.apply_tilt_impulse(Vector2(kick_sign, 0.0), TILT_KICK)
		await wait_physics_frames(1)
		probe.update(gift, TICK)
		if probe.has_landed():
			landed_frame = frame
			break
	assert_true(is_instance_valid(neighbour))
	assert_gt(landed_frame, -1, "reported landed despite the disc never settling")
	probe.update(gift, TICK)
	probe.update(gift, TICK)
	assert_gt(probe.landed_age(), 0.0, "landed_age advances after landing")


func test_block_in_free_fall_is_not_landed() -> void:
	var gift: Block = _block(Vector3(0.0, _field.surface_y() + 60.0, 0.0))
	var probe: LandedProbe = LandedProbe.new(_tune())
	for _i: int in 20:
		await wait_physics_frames(1)
		probe.update(gift, TICK)
	assert_false(probe.has_landed(), "falling block has not landed")
	assert_eq(probe.landed_age(), 0.0)


func test_block_resting_on_a_level_disc_lands_by_speed() -> void:
	_field.set_tilt_enabled(false)
	var gift: Block = _block(Vector3(0.0, _field.surface_y() + 0.6, 0.0))
	var t: LandedTuning = _tune()
	t.landed_timeout_s = 100.0
	var probe: LandedProbe = LandedProbe.new(t)
	for _i: int in int((t.landed_hold_s + 1.0) / TICK):
		await wait_physics_frames(1)
		probe.update(gift, TICK)
	assert_true(probe.has_landed(), "settled via the speed/hold rule, not the timeout")


func test_tumbling_block_is_not_landed() -> void:
	_field.set_tilt_enabled(false)
	var gift: Block = _block(Vector3(0.0, _field.surface_y() + 0.6, 0.0))
	var t: LandedTuning = _tune()
	var probe: LandedProbe = LandedProbe.new(t)
	# Keep the block moving faster than the speed threshold, well inside the timeout.
	for _i: int in int((t.landed_timeout_s * 0.6) / TICK):
		gift.linear_velocity = Vector3(t.landed_speed_mps * 6.0, 0.0, 0.0)
		await wait_physics_frames(1)
		probe.update(gift, TICK)
	assert_false(probe.has_landed(), "fast-moving block does not report landed before the timeout")
