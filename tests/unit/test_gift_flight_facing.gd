extends GutTest
## Bontago-1pi.85.49: the Rocket and Magnet MODEL nose (the GiftVisual child, not just the carrier
## body) follows the velocity in flight, on the host and on a client reading the wire pose.

const TICK: float = 1.0 / 60.0
const START: Vector3 = Vector3(0.0, 40.0, 0.0)
const FLIGHT_FRAMES: int = 30
## Checked well inside the old 0.4 s arm delay (24 frames); gravity bends its line.
const MAGNET_FLIGHT_FRAMES: int = 20
const MAGNET_FIRST_CHECK_FRAME: int = 3
const MAGNET_NOSE_ERROR_DEG: float = 3.0
const MAX_NOSE_ERROR_DEG: float = 1.0
const WIRE_NOSE_ERROR_DEG: float = 2.0
const THROW_VELOCITY: Vector3 = Vector3(6.0, 3.0, -8.0)
const AIM: Vector3 = Vector3(0.6, -0.3, -0.8)

var _tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
var _blocks: Array[Block] = []


func after_each() -> void:
	for block: Block in _blocks:
		if is_instance_valid(block):
			block.free()
	_blocks.clear()


## A real factory-built gift carrier (visual child, 2x activation scale) with the shipped
## effect's SpecialBehavior bound, flying under real physics.
func _gift(id: StringName) -> Block:
	var shape: BlockShape = BlockShape.load_all_shapes()[0]
	var block: Block = BlockFactory.build(shape, _tuning, 0)
	BlockFactory.apply_gift_visual(block, shape, _tuning, id)
	add_child(block)
	_blocks.append(block)
	block.global_position = START
	block.continuous_cd = true
	var behavior: SpecialBehavior = SpecialBehavior.new()
	block.add_child(behavior)
	behavior.bind(block, SpecialDef.find_by_id(id), SpecialTuning.new())
	return block


func _visual(block: Block) -> Node3D:
	return block.get_node(NodePath(String(BlockFactory.GIFT_VISUAL_NODE))) as Node3D


func _nose_of(id: StringName) -> Vector3:
	var effect: SpecialEffect = SpecialDef.find_by_id(id).effect
	if effect is RocketEffect:
		return (effect as RocketEffect).model_nose_axis.normalized()
	return (effect as MagnetEffect).model_nose_axis.normalized()


func _wire_basis(block: Block) -> Basis:
	var packet: PackedByteArray = PackedByteArray()
	packet.resize(16)
	Quantize.pack_quat(packet, 0, block.global_basis.get_rotation_quaternion(), false)
	return Basis(Quantize.unpack_quat(packet, 0))


func _assert_model_faces_velocity(block: Block, id: StringName, check_wire: bool, tolerance_deg: float = MAX_NOSE_ERROR_DEG) -> void:
	var nose: Vector3 = _nose_of(id)
	var direction: Vector3 = block.linear_velocity.normalized()
	var host_nose: Vector3 = _visual(block).global_basis * nose
	assert_lt(rad_to_deg(host_nose.angle_to(direction)), tolerance_deg, "%s host model nose along velocity" % id)
	if check_wire:
		var client_nose: Vector3 = _wire_basis(block) * nose
		assert_lt(rad_to_deg(client_nose.angle_to(direction)), tolerance_deg + WIRE_NOSE_ERROR_DEG, "%s wire pose nose along velocity" % id)


func test_rocket_model_nose_follows_velocity_on_host_and_wire() -> void:
	var block: Block = _gift(&"rocket")
	RocketEffect.set_launch_direction(block, AIM)
	for i: int in range(FLIGHT_FRAMES):
		await wait_physics_frames(1)
		if i > 1:
			_assert_model_faces_velocity(block, &"rocket", true)


func test_thrown_magnet_model_nose_follows_velocity() -> void:
	var block: Block = _gift(&"magnet")
	block.linear_velocity = THROW_VELOCITY
	for i: int in range(MAGNET_FLIGHT_FRAMES):
		await wait_physics_frames(1)
		if i >= MAGNET_FIRST_CHECK_FRAME:
			_assert_model_faces_velocity(block, &"magnet", true, MAGNET_NOSE_ERROR_DEG)


func test_launch_direction_input_already_faces_the_carrier() -> void:
	var block: Block = _gift(&"rocket")
	RocketEffect.set_launch_direction(block, AIM)
	var nose: Vector3 = _visual(block).global_basis * _nose_of(&"rocket")
	assert_lt(rad_to_deg(nose.angle_to(AIM.normalized())), MAX_NOSE_ERROR_DEG, "faced before the first tick")


func test_magnet_arm_delay_does_not_gate_facing_but_the_pull_still_waits() -> void:
	var def: SpecialDef = SpecialDef.find_by_id(&"magnet")
	assert_eq(def.arm_delay, 0.0, "ticked from the first frame")
	assert_gt((def.effect as MagnetEffect).pull_start_delay_s, 0.0, "the pull keeps its start delay")


func test_shipped_magnet_numbers() -> void:
	var effect: MagnetEffect = SpecialDef.find_by_id(&"magnet").effect as MagnetEffect
	assert_eq(effect.pull_duration_s, 6.0)
	assert_eq(effect.model_nose_axis, Vector3.UP)
	assert_gt(effect.face_min_speed_mps, 0.0)
	assert_eq(effect.effect_lifetime_s(), effect.pull_start_delay_s + effect.pull_duration_s)


func test_nose_basis_maps_nose_onto_every_direction() -> void:
	for nose: Vector3 in [Vector3.UP, Vector3.RIGHT, Vector3(0.0, 0.0, 1.0)]:
		for direction: Vector3 in [Vector3.UP, Vector3.DOWN, Vector3.RIGHT, Vector3.LEFT, Vector3(0.3, -0.9, 0.1)]:
			var basis: Basis = FlightFacing.nose_basis(nose, direction)
			assert_lt((basis * nose).angle_to(direction.normalized()), 0.001, "nose %s onto %s" % [nose, direction])
			assert_almost_eq(basis.determinant(), 1.0, 0.001, "a proper rotation")


func test_face_velocity_ignores_a_slow_body() -> void:
	var block: Block = _gift(&"magnet")
	block.linear_velocity = Vector3(0.0, 0.0, 0.1)
	var before: Basis = block.global_basis
	FlightFacing.face_velocity(block, Vector3.UP, 1.0)
	assert_eq(block.global_basis, before, "below the minimum speed the pose is left alone")


func test_rocket_nose_delegates_to_flight_facing() -> void:
	assert_eq(RocketEffect.nose_basis(Vector3.UP, Vector3.RIGHT), FlightFacing.nose_basis(Vector3.UP, Vector3.RIGHT))
