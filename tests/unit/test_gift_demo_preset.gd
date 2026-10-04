extends GutTest
## Bontago-1pi.70: the Debug page's Gift demo is the ordinary sandbox started
## with config/sandbox_gift_demo.tres. The old tools/gift_demo.tscn nested a
## second Main under the demo; windowed (non-headless) that Main still ran its
## splash, whose finish handler then replaced the sandbox with the main menu,
## so the demo opened onto a menu. The preset path starts the sandbox from
## Main itself, so it is covered here headlessly.

const MAIN_SCENE: PackedScene = preload("res://game/Main.tscn")
const PLACE_ATTEMPTS: int = 80
const PLACE_STEP_HEIGHT_M: float = 1.2

var _main: Node3D = null


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	DebugMode.set_override_for_test(true)
	_main = MAIN_SCENE.instantiate()
	var tiny_map: MapDef = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	tiny_map.field_radius = 20.0
	(_main.get_node("Field") as Field).map_def = tiny_map
	var tiny_match_config: MatchConfig = (load("res://config/match_defaults.tres") as MatchConfig).duplicate(true)
	tiny_match_config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
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


func test_preset_resource_is_a_gift_testing_sandbox() -> void:
	var preset: SandboxConfig = load("res://config/sandbox_gift_demo.tres") as SandboxConfig
	assert_not_null(preset)
	assert_gt(preset.preplaced_tower_blocks, 0)
	assert_eq(preset.special_frequency_override, MatchConfig.SPECIAL_FREQUENCY_MAX)


func test_gift_demo_preplaces_blocks_and_gifts_spawn() -> void:
	_main.start_gift_demo_from_menu()
	assert_not_null(_main._sandbox, "the gift demo opens the sandbox")
	assert_true(Match.config.sandbox)
	assert_true(Match.config.gifts_enabled)
	assert_eq(Match.config.special_frequency, MatchConfig.SPECIAL_FREQUENCY_MAX)
	_run_countdown()
	await get_tree().process_frame
	var preset: SandboxConfig = load("res://config/sandbox_gift_demo.tres") as SandboxConfig
	var expected: int = (Match.slot_count() - 1) * preset.preplaced_tower_blocks
	assert_eq(Match.blocks_parent().get_child_count(), expected, "opponent towers are pre-placed")
	var home: Vector2 = Match.slot(0).home_position
	for i: int in PLACE_ATTEMPTS:
		if not (Match._gifts._crates as Dictionary).is_empty():
			break
		var origin: Vector3 = (_main.get_node("Field") as Field).to_global(Vector3(home.x, 4.0 + PLACE_STEP_HEIGHT_M * float(i % 4), home.y))
		Match.request_place(0, origin, 0, Quaternion.IDENTITY, false)
	assert_false((Match._gifts._crates as Dictionary).is_empty(), "at least one gift crate spawned")


func test_plain_sandbox_from_menu_ignores_the_preset() -> void:
	_main.start_gift_demo_from_menu()
	Match.abort_match()
	_main.start_sandbox_from_menu()
	assert_null(_main._sandbox_preset)


func test_prev_next_cycle_the_forced_gift_only_in_the_preset() -> void:
	_main.start_gift_demo_from_menu()
	_run_countdown()
	var sandbox: Sandbox = _main._sandbox
	var next: InputEventAction = InputEventAction.new()
	next.action = "gift_demo_cycle_next"
	next.pressed = true
	var prev: InputEventAction = InputEventAction.new()
	prev.action = "gift_demo_cycle_prev"
	prev.pressed = true
	assert_eq(sandbox.forced_special(), &"")
	sandbox._unhandled_input(next)
	var first: StringName = sandbox.forced_special()
	assert_ne(first, &"", "next picks the first gift")
	sandbox._unhandled_input(next)
	assert_ne(sandbox.forced_special(), first)
	sandbox._unhandled_input(prev)
	assert_eq(sandbox.forced_special(), first)
	sandbox._unhandled_input(prev)
	sandbox._unhandled_input(prev)
	assert_ne(sandbox.forced_special(), &"", "prev wraps from off to the last gift")
	assert_eq(sandbox._gift_strip.glyph_texts().size(), 2, "bound prev/next glyphs are shown")


func test_plain_sandbox_ignores_the_gift_cycle_actions() -> void:
	_main.start_sandbox_from_menu()
	_run_countdown()
	var next: InputEventAction = InputEventAction.new()
	next.action = "gift_demo_cycle_next"
	next.pressed = true
	_main._sandbox._unhandled_input(next)
	assert_eq(_main._sandbox.forced_special(), &"")
