extends GutTest
## the Debug page's Gift demo is the ordinary sandbox started
## with config/match/sandbox_gift_demo.tres. The old tools/gift_demo.tscn nested a
## second Main under the demo; windowed (non-headless) that Main still ran its
## splash, whose finish handler then replaced the sandbox with the main menu,
## so the demo opened onto a menu. The preset path starts the sandbox from
## Main itself, so it is covered here headlessly.

const MAIN_SCENE: PackedScene = preload("res://game/main/Main.tscn")
const PLACE_ATTEMPTS: int = 80
const PLACE_STEP_HEIGHT_M: float = 1.2

var _main: Node3D = null


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	DebugMode.set_override_for_test(true)
	_main = MAIN_SCENE.instantiate()
	var tiny_map: MapDef = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	tiny_map.field_radius = 20.0
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


func test_gift_demo_preplaces_blocks_and_gifts_spawn() -> void:
	_main.start_gift_demo_from_menu()
	assert_not_null(_main._sandbox, "the gift demo opens the sandbox")
	assert_true(Match.config.sandbox)
	assert_true(Match.config.gifts_enabled)
	assert_eq(Match.config.special_frequency, MatchConfig.SPECIAL_FREQUENCY_MAX)
	_run_countdown()
	await get_tree().process_frame
	var preset: SandboxConfig = load("res://config/match/sandbox_gift_demo.tres") as SandboxConfig
	var expected: int = (Match.slot_count() - 1) * preset.preplaced_tower_blocks
	assert_eq(Match.blocks_parent().get_child_count(), expected, "opponent towers are pre-placed")
	var home: Vector2 = Match.slot(0).home_position
	for i: int in PLACE_ATTEMPTS:
		if not (Match._gifts._crates as Dictionary).is_empty():
			break
		var origin: Vector3 = (_main.get_node("Field") as Field).to_global(Vector3(home.x, 4.0 + PLACE_STEP_HEIGHT_M * float(i % 4), home.y))
		Match.request_place(0, origin, 0, Quaternion.IDENTITY, false)
	assert_false((Match._gifts._crates as Dictionary).is_empty(), "at least one gift crate spawned")


## F5 rebuilds the world; the preset's opponent towers are placed again, once.
func test_f5_re_places_the_preset_towers() -> void:
	_main.start_gift_demo_from_menu()
	_run_countdown()
	await get_tree().process_frame
	var preset: SandboxConfig = load("res://config/match/sandbox_gift_demo.tres") as SandboxConfig
	var expected: int = (Match.slot_count() - 1) * preset.preplaced_tower_blocks
	assert_eq(Match.blocks_parent().get_child_count(), expected, "fixture: towers are up before the reset")

	var key: InputEventKey = InputEventKey.new()
	key.device = -1
	key.physical_keycode = KEY_F5
	key.pressed = true
	assert_true(key.is_action_pressed(&"sandbox_reset_field"))
	_main._sandbox._unhandled_input(key)
	_run_countdown()
	await get_tree().process_frame
	await get_tree().process_frame

	assert_true(Match.config.sandbox)
	assert_eq(Match.blocks_parent().get_child_count(), expected, "the towers are re-placed, not doubled or missing")


var _silent_at_placement: Array[bool] = []


func _record_silence(_block: RigidBody3D, _shape_id: StringName) -> void:
	_silent_at_placement.append(Sfx._world_replay_silent)


## pre-placed scene blocks go through the ordinary placement path (their
## block_placed would sound the local drop cue for every block at once); Sfx must be silenced
## for exactly that build, and a real drop afterwards must not be.
func test_preplaced_blocks_are_silent_but_later_drops_are_not() -> void:
	Events.block_placed.connect(_record_silence)
	_main.start_gift_demo_from_menu()
	_run_countdown()
	await get_tree().process_frame
	Events.block_placed.disconnect(_record_silence)
	assert_gt(_silent_at_placement.size(), 0, "towers were pre-placed")
	assert_false(_silent_at_placement.has(false), "every pre-placed block was placed under Sfx silence")
	assert_false(Sfx._world_replay_silent, "silence is released once the scene is built")
