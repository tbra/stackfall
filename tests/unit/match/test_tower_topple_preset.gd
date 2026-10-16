extends GutTest
## the Tower topple preset builds settled cube towers clear of the beacons, and they stand.

const MAIN_SCENE: PackedScene = preload("res://game/main/Main.tscn")
const TOPPLE_PRESET_PATH: String = "res://config/match/sandbox_tower_topple.tres"
const TEST_FIELD_RADIUS_M: float = 20.0
const SETTLE_TICKS: int = 120
## Pre-placed blocks start asleep and exactly touching: the first ticks are a solver
## transient (the stack compresses, overshoots and re-sleeps, ~30 ticks) whose size
## varies a little run to run and under CPU load. The "stands" window starts after it.
const WARMUP_TICKS: int = 60
## Once warmed up, a standing tower does not move at all beyond a hair.
const MAX_MOVE_M: float = 0.05
## The transient may compress a tall stack by a couple of centimetres but never by
## anything near a cube (edge ~1 m): that would be a collapse, not a settle.
const MAX_SAG_FROM_BUILT_M: float = 0.25
## Boxes closer than (edge - this) on every axis count as interpenetrating.
const OVERLAP_EPSILON_M: float = 0.02
## Clearance a block centre must keep from a beacon axis beyond the beacon's
## own radius.
const BEACON_CLEARANCE_M: float = 0.5

var _main: Node3D = null


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	DebugMode.set_override_for_test(true)
	_main = MAIN_SCENE.instantiate()
	var tiny_map: MapDef = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	tiny_map.field_radius = TEST_FIELD_RADIUS_M
	(_main.get_node("Field") as Field).map_def = tiny_map
	var tiny_match_config: MatchConfig = (load("res://config/match/match_defaults.tres") as MatchConfig).duplicate(true)
	tiny_match_config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(tiny_match_config as TinyMapMatchConfig).set_tiny_map(tiny_map)
	tiny_match_config.rng_seed = 4242
	_main.match_config = tiny_match_config
	add_child_autofree(_main)


func after_each() -> void:
	DebugMode.clear_override_for_test()
	Match.abort_match()
	Match.set_process(true)
	await get_tree().process_frame
	await get_tree().process_frame
	MatchTestReset.clear_world()


func _run_countdown() -> void:
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)


func _blocks() -> Array[RigidBody3D]:
	var out: Array[RigidBody3D] = []
	for child: Node in Match.blocks_parent().get_children():
		var body: RigidBody3D = child as RigidBody3D
		if body != null:
			out.append(body)
	return out


func _assert_clear_of_beacons_and_each_other(blocks: Array[RigidBody3D]) -> void:
	var tuning: PhysicsTuning = load("res://config/physics/physics_tuning.tres") as PhysicsTuning
	var edge: float = tuning.cube_size - tuning.cube_margin
	var beacon: BeaconVisualTuning = load("res://config/territory/beacon_visual_tuning.tres") as BeaconVisualTuning
	var beacon_radius: float = maxf(beacon.socket_radius, beacon.crystal_radius) + BEACON_CLEARANCE_M
	var field: Field = _main.get_node("Field") as Field
	for slot_id: int in range(Match.slot_count()):
		var home: Vector2 = Match.slot(slot_id).home_position
		for block: RigidBody3D in blocks:
			var local: Vector3 = field.to_local(block.global_position)
			assert_gt(Vector2(local.x, local.z).distance_to(home), beacon_radius, "block clear of slot %d's beacon" % slot_id)
	for i: int in range(blocks.size()):
		for j: int in range(i + 1, blocks.size()):
			var d: Vector3 = (blocks[i].global_position - blocks[j].global_position).abs()
			var overlap: bool = d.x < edge - OVERLAP_EPSILON_M and d.y < edge - OVERLAP_EPSILON_M and d.z < edge - OVERLAP_EPSILON_M
			assert_false(overlap, "blocks %d and %d do not interpenetrate" % [i, j])


func _assert_towers_stand(blocks: Array[RigidBody3D]) -> void:
	var built: Array[Vector3] = []
	for block: RigidBody3D in blocks:
		built.append(block.global_position)
	for _tick: int in range(WARMUP_TICKS):
		await get_tree().physics_frame
	var before: Array[Vector3] = []
	var worst_sag: float = 0.0
	for i: int in range(blocks.size()):
		assert_true(is_instance_valid(blocks[i]), "block %d survives the settle" % i)
		before.append(blocks[i].global_position)
		worst_sag = maxf(worst_sag, blocks[i].global_position.distance_to(built[i]))
	assert_lt(worst_sag, MAX_SAG_FROM_BUILT_M, "no block left its built spot by anything near a cube (no collapse)")
	for _tick: int in range(SETTLE_TICKS):
		await get_tree().physics_frame
	var worst: float = 0.0
	for i: int in range(blocks.size()):
		assert_true(is_instance_valid(blocks[i]), "block %d still exists" % i)
		worst = maxf(worst, blocks[i].global_position.distance_to(before[i]))
	assert_lt(worst, MAX_MOVE_M, "no block moved more than the tolerance (towers stand)")


func test_tower_topple_preset_builds_the_row_and_it_stands() -> void:
	var preset: SandboxConfig = load(TOPPLE_PRESET_PATH) as SandboxConfig
	assert_not_null(preset)
	assert_false(preset.row_tower_heights.is_empty())
	var expected: int = 0
	for height: int in preset.row_tower_heights:
		expected += height
	_main.start_tower_topple_from_menu()
	assert_eq(_main._sandbox_preset, preset)
	assert_true(Match.config.gifts_enabled)
	_run_countdown()
	await get_tree().process_frame
	var blocks: Array[RigidBody3D] = _blocks()
	assert_eq(blocks.size(), expected, "every tower is fully built")
	_assert_clear_of_beacons_and_each_other(blocks)
	await _assert_towers_stand(blocks)

