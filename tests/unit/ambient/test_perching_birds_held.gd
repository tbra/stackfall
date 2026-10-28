extends GutTest
## PerchingBirds and the local held block: a perched bird flees a held block that is close
## (the view published through MatchContext.local_held()), but only while the view is
## visible and holds a shape. A hidden or cleared view is no threat.

const STEP_S: float = 0.1
const MAX_STEPS: int = 600
const POLL_STEPS: int = 5
const FAR_CAMERA: Vector3 = Vector3(0.0, 60.0, 400.0)
const NEAR_OFFSET: Vector3 = Vector3(0.0, 1.0, 1.0)

var _saved_context: MatchContext = null
var _fake_context: FakeMatchContext = null
var _shape: BlockShape = load("res://config/blocks/cube.tres") as BlockShape


func before_each() -> void:
	_saved_context = MatchContext.installed()
	_fake_context = FakeMatchContext.new()
	MatchContext.install(_fake_context)


func after_each() -> void:
	MatchContext.install(_saved_context)


func _life() -> AmbientLifeConfig:
	var life: AmbientLifeConfig = AmbientLifeConfig.new()
	life.perch_bird_count = 1
	life.spawn_delay_min_s = 0.0
	life.spawn_delay_max_s = 0.0
	life.approach_circle_time_min_s = 0.0
	life.approach_circle_time_max_s = 0.0
	life.approach_circle_radius_min_m = 50.0
	life.approach_circle_radius_max_m = 50.0
	life.perch_stay_min_s = 500.0
	life.perch_stay_max_s = 600.0
	life.perch_tower_fraction = 0.0
	life.perch_tower_min_settle_s = 0.0
	life.idle_hop_chance = 0.0
	return life


func _perched_bird() -> PerchingBird:
	var manager: PerchingBirds = PerchingBirds.new()
	manager.disc_radius = 30.0
	manager.camera_override = FAR_CAMERA
	add_child_autofree(manager)
	manager.configure(_life(), true)
	for _i: int in range(MAX_STEPS):
		manager._process(STEP_S)
		for child: Node in manager.get_children():
			if child is PerchingBird and (child as PerchingBird).state == PerchingBird.State.PERCHED:
				return child as PerchingBird
	return null


func _poll(bird: PerchingBird) -> void:
	var manager: PerchingBirds = bird.get_parent() as PerchingBirds
	for _i: int in range(POLL_STEPS):
		manager._process(STEP_S)


func _hold_beside(bird: PerchingBird, shape: BlockShape, is_visible: bool) -> void:
	_fake_context.local_held().publish(0, shape, bird.global_position + NEAR_OFFSET, 0,
			Quaternion.IDENTITY, is_visible, 0.0)


func test_bird_flees_a_visible_held_block_nearby() -> void:
	var bird: PerchingBird = _perched_bird()
	assert_not_null(bird)
	if bird == null:
		return
	_hold_beside(bird, _shape, true)
	_poll(bird)
	assert_eq(bird.state, PerchingBird.State.FLEE)


func test_bird_ignores_a_held_block_that_is_far_away() -> void:
	var bird: PerchingBird = _perched_bird()
	assert_not_null(bird)
	if bird == null:
		return
	_hold_beside(bird, _shape, true)
	_fake_context.local_held().origin = bird.global_position + Vector3(200.0, 0.0, 0.0)
	_poll(bird)
	assert_eq(bird.state, PerchingBird.State.PERCHED)


func test_bird_ignores_a_hidden_held_block() -> void:
	var bird: PerchingBird = _perched_bird()
	assert_not_null(bird)
	if bird == null:
		return
	_hold_beside(bird, _shape, false)
	_poll(bird)
	assert_eq(bird.state, PerchingBird.State.PERCHED)


func test_bird_ignores_a_view_with_no_shape() -> void:
	var bird: PerchingBird = _perched_bird()
	assert_not_null(bird)
	if bird == null:
		return
	_hold_beside(bird, null, true)
	_poll(bird)
	assert_eq(bird.state, PerchingBird.State.PERCHED)


func test_bird_ignores_a_cleared_view() -> void:
	var bird: PerchingBird = _perched_bird()
	assert_not_null(bird)
	if bird == null:
		return
	_hold_beside(bird, _shape, true)
	_fake_context.local_held().clear()
	_poll(bird)
	assert_eq(bird.state, PerchingBird.State.PERCHED)
