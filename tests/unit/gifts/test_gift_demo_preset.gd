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
## Physics ticks to keep watching after the rebuild, so a late second build would show.
const HOLD_PAST_BUILD_TICKS: int = 60

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
	assert_not_null(MainNodes.sandbox(_main), "the gift demo opens the sandbox")
	assert_true(Match.config.sandbox)
	assert_true(Match.config.gifts_enabled)
	assert_eq(Match.config.special_frequency, MatchConfig.SPECIAL_FREQUENCY_MAX)
	_run_countdown()
	await get_tree().process_frame
	var preset: SandboxConfig = load("res://config/match/sandbox_gift_demo.tres") as SandboxConfig
	var expected: int = (Match.slot_count() - 1) * preset.preplaced_tower_blocks
	await PresetBuildWait.wait_for_blocks(get_tree(), expected)
	assert_eq(Match.blocks_parent().get_child_count(), expected, "opponent towers are pre-placed")
	var home: Vector2 = Match.slot(0).home_position
	for i: int in PLACE_ATTEMPTS:
		if not Match.gift_states().is_empty():
			break
		var origin: Vector3 = (_main.get_node("Field") as Field).to_global(Vector3(home.x, 4.0 + PLACE_STEP_HEIGHT_M * float(i % 4), home.y))
		Match.request_place(0, origin, 0, Quaternion.IDENTITY, false)
	assert_false(Match.gift_states().is_empty(), "at least one gift crate spawned")


## F5 rebuilds the world; the preset's opponent towers are placed again, once.
func test_f5_re_places_the_preset_towers() -> void:
	_main.start_gift_demo_from_menu()
	_run_countdown()
	await get_tree().process_frame
	var preset: SandboxConfig = load("res://config/match/sandbox_gift_demo.tres") as SandboxConfig
	var expected: int = (Match.slot_count() - 1) * preset.preplaced_tower_blocks
	await PresetBuildWait.wait_for_blocks(get_tree(), expected)
	assert_eq(Match.blocks_parent().get_child_count(), expected, "fixture: towers are up before the reset")

	var old_towers: Array[Node] = Match.blocks_parent().get_children()
	var key: InputEventKey = InputEventKey.new()
	key.device = -1
	key.physical_keycode = KEY_F5
	key.pressed = true
	assert_true(key.is_action_pressed(&"sandbox_reset_field"))
	MainNodes.sandbox(_main)._unhandled_input(key)
	_run_countdown()
	await get_tree().process_frame
	await get_tree().process_frame
	# only blocks that are not the old towers count, so a rebuild must really happen
	await PresetBuildWait.wait_for_blocks(get_tree(), expected, old_towers)
	for _tick: int in range(HOLD_PAST_BUILD_TICKS):
		await get_tree().physics_frame

	assert_true(Match.config.sandbox)
	assert_eq(PresetBuildWait.live_blocks(old_towers).size(), expected, "the towers are re-placed, not doubled or missing")
	assert_eq(PresetBuildWait.live_blocks().size(), expected, "the old towers are gone")


var _silent_at_placement: Array[bool] = []


## Cues that started before the build (match start, an impact on the settling field) are still
## playing when it begins, and how long they last depends on wall-clock load. Clearing the pool as
## the silence opens leaves only sounds the pre-placement itself made.
func _clear_cues_when_silence_opens(active: bool) -> void:
	if active:
		SfxChildren.stop_all()


## Connected after Sfx's own handler, so Sfx has already decided whether this placement sounds.
func _record_silence(_block: RigidBody3D, _shape_id: StringName) -> void:
	_silent_at_placement.append(not SfxChildren.any_playing())
	SfxChildren.stop_all()


## pre-placed scene blocks go through the ordinary placement path (their
## block_placed would sound the local drop cue for every block at once); Sfx must be silenced
## for exactly that build, and a real drop afterwards must not be.
func test_preplaced_blocks_are_silent_but_later_drops_are_not() -> void:
	SfxChildren.stop_all()
	Events.world_replay_changed.connect(_clear_cues_when_silence_opens)
	Events.block_placed.connect(_record_silence)
	_main.start_gift_demo_from_menu()
	_run_countdown()
	await get_tree().process_frame
	await PresetBuildWait.wait_for_blocks(get_tree(), 1)
	Events.block_placed.disconnect(_record_silence)
	Events.world_replay_changed.disconnect(_clear_cues_when_silence_opens)
	assert_gt(_silent_at_placement.size(), 0, "towers were pre-placed")
	assert_false(_silent_at_placement.has(false), "every pre-placed block was placed under Sfx silence")
	var own_block: BlockBody = BlockBody.new()
	own_block.owner_slot = Net.local_slot()
	add_child_autofree(own_block)
	SfxChildren.stop_all()
	Events.block_placed.emit(own_block, &"shape")
	assert_true(SfxChildren.any_playing(), "silence is released once the scene is built: a later own drop sounds")
	SfxChildren.stop_all()
