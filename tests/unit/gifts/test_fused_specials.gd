extends GutTest
## Glue fusion: weather, Paintball, Black hole and blast against a FusedBody
## built directly through GlueFusion.

const DELTA: float = 1.0 / 60.0
const HIGH_SURFACE_Y_M: float = -100.0
const WIND_TICKS: int = 30
const MEMBER_GAP_M: float = 4.0
const SPLASH_RADIUS_M: float = 2.0
const BLAST_RADIUS_M: float = 8.0
const BLAST_PEAK_MPS: float = 10.0
const BLAST_MAX_MPS: float = 20.0
const SPEED_EPSILON: float = 0.01
const SETTLE_FRAMES: int = 10

var _field: Field
var _blocks: Node3D
var _registry: BlockRegistry


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	var map: MapDef = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = map
	add_child_autofree(_field)
	_blocks = autofree(Node3D.new())
	add_child_autofree(_blocks)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks)
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true)
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(map)
	config.player_count = 2
	config.hot_seat = false
	config.gifts_enabled = false
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)


func after_each() -> void:
	Match._net_provider = null
	Match.abort_match()
	for child: Node in _blocks.get_children():
		child.free()
	Match.set_process(true)
	await get_tree().process_frame
	MatchTestReset.clear_world()


func _origin() -> Vector3:
	return _field.world_from_disk_local(Match.slot(0).home_position, 5.0)


func _block(slot_id: int, offset: Vector3) -> Block:
	var block: Block = Match.spawn_special_projectile(
		load("res://config/blocks/cube.tres"), _origin() + offset, Basis.IDENTITY,
		slot_id, Vector3.ZERO, null, null
	) as Block
	block.gravity_scale = 0.0
	block.linear_damp = 0.0
	return block


## Two members of different owners, MEMBER_GAP_M apart, in one FusedBody.
func _group() -> FusedBody:
	var a: Block = _block(0, Vector3.ZERO)
	var b: Block = _block(1, Vector3(MEMBER_GAP_M, 0.0, 0.0))
	var carrier: FusedBody = GlueFusion.fuse(a, b, null)
	assert_not_null(carrier, "fuse built a group")
	carrier.gravity_scale = 0.0
	carrier.linear_damp = 0.0
	return carrier


func test_storm_leaves_fused_body_and_members_untouched_but_pushes_a_loose_block() -> void:
	var carrier: FusedBody = _group()
	var loose: Block = _block(0, Vector3(0.0, 0.0, MEMBER_GAP_M * 2.0))
	var effect: StormEffect = StormEffect.new()
	effect.tuning = load("res://config/weather/storm.tres") as StormTuning
	effect.set_seed(1)
	var listed: Array[Block] = [carrier, loose]
	listed.append_array(carrier.members)
	effect.set_test_world(func() -> Array: return listed, func() -> float: return HIGH_SURFACE_Y_M)
	for _i: int in range(WIND_TICKS):
		effect.tick(DELTA, 1.0)
		await wait_physics_frames(1)
	assert_lt(carrier.linear_velocity.length(), SPEED_EPSILON, "carrier ignores wind")
	for member: Block in carrier.members:
		assert_lt(member.linear_velocity.length(), SPEED_EPSILON, "member ignores wind")
	assert_gt(loose.linear_velocity.length(), SPEED_EPSILON, "a loose block is still pushed")


func test_paintball_converts_only_members_inside_the_splash() -> void:
	var carrier: FusedBody = _group()
	var glob: Block = _block(0, Vector3(-1.0, 0.0, 0.0))
	await wait_physics_frames(1)
	var near: Block = carrier.members[0]
	var far: Block = carrier.members[1]
	var near_slot: int = near.owner_slot
	var far_slot: int = far.owner_slot
	var effect: PaintballEffect = PaintballEffect.new()
	effect.splash_radius_m = SPLASH_RADIUS_M
	var inside: Block = near if near.global_position.distance_to(glob.global_position) < far.global_position.distance_to(glob.global_position) else far
	var outside: Block = far if inside == near else near
	var outside_slot: int = far_slot if outside == far else near_slot
	effect.detonate(glob, null, 0)
	assert_eq(inside.owner_slot, glob.owner_slot, "member in the splash converts")
	assert_eq(outside.owner_slot, outside_slot, "member outside the splash keeps its owner")


func test_blast_pushes_the_group_as_one_body() -> void:
	var carrier: FusedBody = _group()
	var tuning: ExplosionTuning = ExplosionTuning.new()
	tuning.radius_m = BLAST_RADIUS_M
	tuning.peak_speed_mps = BLAST_PEAK_MPS
	tuning.max_delta_v_mps = BLAST_MAX_MPS
	await wait_physics_frames(1)
	var hit: Array[RigidBody3D] = ExplosionFx.blast(
		carrier.get_world_3d().direct_space_state, _origin() + Vector3(0.0, 0.0, -1.0), tuning, []
	)
	assert_true(hit.has(carrier), "the carrier is the pushed body")
	for member: Block in carrier.members:
		assert_false(hit.has(member), "no follower is pushed on its own")
	await wait_physics_frames(1)
	assert_gt(carrier.linear_velocity.length(), SPEED_EPSILON)
	assert_eq(carrier.members.size(), 2, "group not split")


func test_black_hole_capture_takes_the_whole_group() -> void:
	var carrier: FusedBody = _group()
	var members: Array[Block] = carrier.members.duplicate()
	var field: BlackHoleField = BlackHoleField.new()
	autofree(field)
	var before: int = _registry.hole_dissolver().dissolves_started
	assert_true(field._capture(carrier))
	assert_eq(_registry.hole_dissolver().dissolves_started - before, members.size(), "every member dissolves")
	# Let the dissolves finish so teardown does not free blocks with a pending dissolve.
	var wait_frames: int = int(ceil(_registry.hole_dissolver().tuning.dissolve_delay_s / DELTA)) + SETTLE_FRAMES
	await wait_physics_frames(wait_frames)
	for member: Block in members:
		assert_false(is_instance_valid(member) and not member.is_queued_for_deletion(), "member removed")
