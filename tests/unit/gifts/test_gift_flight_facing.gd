extends GutTest
## the Rocket and Magnet MODEL nose (the GiftVisual child, not just the carrier
## body) follows the velocity in flight, on the host and on a client reading the wire pose.

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

var _tuning: PhysicsTuning = preload("res://config/physics/physics_tuning.tres")
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
