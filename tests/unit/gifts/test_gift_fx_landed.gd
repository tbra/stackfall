extends GutTest
## LandedProbe: velocity/hold/timeout
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
	var tuning: PhysicsTuning = load("res://config/physics/physics_tuning.tres")
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


## speed is measured relative to the supporting disc. A carrier riding a
## disc that moves at a steady rate (faster than landed_speed_mps) lands by the speed/hold
## rule well before the timeout. The carrier is slaved to the disc each tick (the stand-in
## for friction carrying it).
const DISC_SPEED_MPS: float = 2.0
const LONG_TIMEOUT_S: float = 100.0


func _drive_on_moving_disc(carrier_follows: bool, probe: LandedProbe, seconds: float) -> void:
	_field.set_tilt_enabled(false)
	var gift: Block = _block(Vector3(0.0, _field.surface_y() + 0.6, 0.0))
	for _i: int in int(seconds / TICK):
		_field.global_position.x += DISC_SPEED_MPS * TICK
		PhysicsServer3D.body_set_state(_field.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, _field.global_transform)
		if carrier_follows:
			gift.global_position.x += DISC_SPEED_MPS * TICK
			gift.linear_velocity = Vector3(DISC_SPEED_MPS, 0.0, 0.0)
		else:
			gift.linear_velocity = Vector3.ZERO
		await wait_physics_frames(1)
		probe.update(gift, TICK)
		if probe.has_landed():
			break


func test_carrier_riding_a_moving_disc_lands_by_relative_speed() -> void:
	var t: LandedTuning = _tune()
	t.landed_timeout_s = LONG_TIMEOUT_S
	var probe: LandedProbe = LandedProbe.new(t)
	await _drive_on_moving_disc(true, probe, t.landed_hold_s + 1.0)
	assert_true(probe.has_landed(), "moves with the disc, so it is at rest relative to it")
