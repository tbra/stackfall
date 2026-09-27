extends GutTest
var _field: Field
var _trial: PhysicsComparison

func before_each() -> void:
	_field = Field.new()
	var map: MapDef = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	map.field_radius = 8.0
	_field.map_def = map
	add_child_autofree(_field)
	_trial = PhysicsComparison.new()
	add_child_autofree(_trial)

func test_invalid_settings_do_not_start() -> void:
	assert_false(_trial.start(_field, "bad", 2.0, 2.0, 0.3))
	assert_false(_trial.start(_field, "drop", 0.0, 2.0, 0.3))
	assert_false(_trial.start(_field, "stack", 2.0, 5.0, 0.3))
	assert_false(_trial.running)
	assert_eq(_trial.blocks.size(), 0)

func test_original_feel_release_tilt_high_gap_only() -> void:
	_trial.tuning = load("res://config/physics_presets/original_feel.tres") as PhysicsTuning
	assert_true(_trial.start(_field, "impact", 2.0, 2.0, 0.3))
	await wait_physics_frames(3)
	assert_almost_eq(_trial.blocks[0].rotation.length(), 0.0, 0.001)
	assert_almost_eq(_trial.blocks[1].rotation.length(), 0.0, 0.001)
	assert_true(_trial.start(_field, "impact", 2.0, 2.0, 1.0))
	await wait_physics_frames(3)
	assert_almost_eq(_trial.blocks[0].rotation.length(), 0.0, 0.001)
	assert_gt(_trial.blocks[1].rotation.length(), 0.02)
	_trial.clear()

func test_original_feel_does_not_tilt_scripted_launch() -> void:
	_trial.tuning = load("res://config/physics_presets/original_feel.tres") as PhysicsTuning
	assert_true(_trial.start(_field, "impact", 2.0, 2.0, 2.0))
	(_trial.blocks[1] as Block).kick(Vector3.RIGHT)
	await wait_physics_frames(3)
	assert_almost_eq(_trial.blocks[1].rotation.length(), 0.0, 0.001)
	_trial.clear()

func test_drop_measures_actual_contact_and_owns_only_trial_bodies() -> void:
	assert_true(_trial.start(_field, "drop", 2.0, 2.0, 0.3))
	await wait_physics_frames(602)
	assert_false(_trial.running)
	assert_eq(_trial.result.get("mode"), "drop")
	assert_gt(float(_trial.result.get("first_contact_s", -1.0)), 0.0)
	assert_gte(float(_trial.result.get("rebound_height_cubes", -1.0)), 0.0)
	assert_lt(float(_trial.result.get("max_lateral_drift_cubes", 100.0)), 0.1)
	var body: RigidBody3D = _trial.blocks[0]
	_trial.clear()
	await wait_physics_frames(2)
	assert_false(is_instance_valid(body))
	assert_true(is_instance_valid(_field))
	assert_eq(_trial.blocks.size(), 0)

func test_stack_releases_sequentially_and_keeps_a_tuning_snapshot() -> void:
	_trial.tuning = _trial.tuning.duplicate() as PhysicsTuning
	var original_mass: float = _trial.tuning.cube_mass
	assert_true(_trial.start(_field, "stack", 2.0, 0.5, 0.3))
	assert_eq(_trial.blocks.size(), 1)
	_trial.tuning.cube_mass = original_mass * 2.0
	await wait_physics_frames(32)
	assert_eq(_trial.blocks.size(), 2)
	assert_eq(_trial.blocks[1].mass, original_mass)
	assert_false(_trial.blocks[1].is_in_group(Block.TUNING_GROUP))
	await wait_physics_frames(32)
	assert_eq(_trial.blocks.size(), 3)
	await wait_physics_frames(540)
	assert_false(_trial.running)
	assert_eq(_trial.result.get("stack_count"), 3)
	var snapshot: Dictionary = _trial.result.get("tuning", {})
	assert_eq(snapshot.get("cube_mass"), original_mass)

func test_repeat_clears_old_bodies_and_cancel_stops_measurement() -> void:
	assert_true(_trial.start(_field, "drop", 2.0, 2.0, 0.3))
	var old: RigidBody3D = _trial.blocks[0]
	assert_true(_trial.start(_field, "stack", 2.0, 2.0, 0.3))
	await wait_physics_frames(2)
	assert_false(is_instance_valid(old))
	assert_eq(_trial.blocks.size(), 1)
	_trial.clear()
	await wait_physics_frames(130)
	assert_false(_trial.running)
	assert_eq(_trial.blocks.size(), 0)
