extends GutTest
## Bontago-1pi.85.66: persistent gift nodes (black hole field + visual, paintball splash,
## blast puff) hang under the Field, so they keep their disc-local transform when the
## disc tilts or shakes, like the volcano and propeller stand do.

const TICK_S: float = 1.0 / 60.0
const MOVE_TICKS: int = 5
const TILT_STEP_RAD: float = 0.02
const SHIFT_PER_TICK: Vector3 = Vector3(0.0, 0.05, 0.02)
const DROP_POINT: Vector3 = Vector3(2.5, 0.5, -1.0)
const LOCAL_EPS: float = 0.0005
const PULL_PROBE_M: float = 2.0
const MAP_RADIUS_M: float = 6.0
const BOMB_ID: StringName = &"bomb"
const BLACK_HOLE_ID: StringName = &"black_hole"

var _field: Field = null
var _blocks_root: Node3D = null
var _registry: BlockRegistry = null


func before_each() -> void:
	_field = autofree(Field.new())
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_ride_disc"
	map_def.field_radius = MAP_RADIUS_M
	map_def.cell_size = 1.0
	map_def.disk_height = 1.0
	map_def.territory_res = 32
	_field.map_def = map_def
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)


func after_each() -> void:
	Match.set_net_provider(null)
	Match.abort_match()
	MatchTestReset.clear_world()


## Tilts and shifts the disc over several ticks (the replicated-pose write every peer's
## Field accepts), standing in for an earthquake / heavy stack / anvil wobble.
func _move_disc() -> void:
	var pose: Transform3D = _field.global_transform
	for i: int in range(MOVE_TICKS):
		pose = Transform3D(
			pose.basis * Basis(Vector3.RIGHT, TILT_STEP_RAD) * Basis(Vector3.BACK, -TILT_STEP_RAD),
			pose.origin + SHIFT_PER_TICK)
		_field.apply_replicated_pose(pose.origin, pose.basis.get_rotation_quaternion())
		await wait_physics_frames(1)


func _assert_rides(node: Node3D, label: String) -> void:
	assert_eq(node.get_parent(), _field, "%s is a child of the Field" % label)
	var local: Transform3D = node.transform
	var world_before: Transform3D = node.global_transform
	await _move_disc()
	assert_true(node.transform.is_equal_approx(local), "%s keeps its disc-local transform" % label)
	assert_false(node.global_transform.is_equal_approx(world_before), "%s moved in world space with the disc" % label)
	assert_true(
		node.global_transform.is_equal_approx(_field.global_transform * local), "%s follows the Field frame" % label)


func test_black_hole_field_rides_the_disc_and_pulls_toward_its_moved_centre() -> void:
	var carrier: Block = autofree(Block.new())
	_blocks_root.add_child(carrier)
	carrier.global_position = DROP_POINT
	var effect: BlackHoleEffect = BlackHoleEffect.new()
	effect.lifetime_s = 8.0
	effect.detonate(carrier, null, 0)
	var hole: BlackHoleField = null
	for child: Node in _field.get_children():
		if child is BlackHoleField:
			hole = child as BlackHoleField
	assert_not_null(hole, "detonate parents the black hole under the Field")
	if hole == null:
		return
	hole.set_physics_process(false)
	hole.bind_to_match = false # no live match in this fixture
	await _assert_rides(hole, "black hole field")
	assert_almost_eq(hole.global_position, _field.to_global(_field.to_local(hole.global_position)), Vector3.ONE * LOCAL_EPS)
	# The pull acts around the moved centre: a free block beside it is drawn towards it.
	var probe: Block = autofree(Block.new())
	probe.gravity_scale = 0.0
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	probe.add_child(shape)
	_blocks_root.add_child(probe)
	var side: Vector3 = _field.global_transform.basis.x.normalized()
	probe.global_position = hole.global_position + side * PULL_PROBE_M
	hole._age = (load("res://config/black_hole_visual.tres") as BlackHoleVisualTuning).grow_in_s
	await wait_physics_frames(1)
	hole.tick(TICK_S)
	await wait_physics_frames(1)
	assert_lt(probe.linear_velocity.dot(side), 0.0, "pulled towards the moved centre")


func test_black_hole_visual_rides_the_disc_for_every_peer() -> void:
	var presenter: GiftFxPresenter = autofree(GiftFxPresenter.new())
	add_child_autofree(presenter)
	presenter.on_special_triggered(-1, BLACK_HOLE_ID, DROP_POINT, 0)
	var visual: BlackHoleVisual = null
	for child: Node in _field.get_children():
		if child is BlackHoleVisual:
			visual = child as BlackHoleVisual
	assert_not_null(visual, "the replicated trigger draws the visual under the Field")
	if visual == null:
		return
	assert_true(visual.bind_to_match, "freed when the match ends")
	visual.bind_to_match = false # no live match in this fixture
	assert_almost_eq(visual.global_position, DROP_POINT, Vector3.ONE * LOCAL_EPS)
	await _assert_rides(visual, "black hole visual")


func test_blast_puff_rides_the_disc() -> void:
	var presenter: GiftFxPresenter = autofree(GiftFxPresenter.new())
	add_child_autofree(presenter)
	presenter.on_special_triggered(-1, BOMB_ID, DROP_POINT, 0)
	var puff: ImpactPuff = null
	for child: Node in _field.get_children():
		if child is ImpactPuff:
			puff = child as ImpactPuff
	assert_not_null(puff, "the blast puff is a child of the Field")
	if puff != null:
		await _assert_rides(puff, "blast puff")


func test_paintball_splash_rides_the_disc() -> void:
	var splash: PaintballSplash = PaintballSplash.new()
	splash.setup(Color.RED)
	DiscAnchor.attach(splash, DROP_POINT, _blocks_root)
	splash.set_process(false)
	await _assert_rides(splash, "paintball splash")


func test_anchor_falls_back_to_the_world_parent_without_a_field() -> void:
	Match.register_world(null, _registry, _blocks_root)
	var node: Node3D = Node3D.new()
	assert_eq(DiscAnchor.attach(node, DROP_POINT, _blocks_root), _blocks_root)
	assert_eq(node.get_parent(), _blocks_root)
	assert_almost_eq(node.global_position, DROP_POINT, Vector3.ONE * LOCAL_EPS)
