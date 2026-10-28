extends GutTest
## F2 pose, F3 net and F9 bot-cost panels are round debugs: they exist only while the match world does,
## so their toggle does nothing in the menu and lobby, opens in a round and closes when the round is left.

const MAIN_SCENE: PackedScene = preload("res://game/main/Main.tscn")
const POSE: StringName = &"pose"
const NET: StringName = &"net"
const BOT_COST: StringName = &"bot_cost"
const KINDS: Array[StringName] = [POSE, NET, BOT_COST]
const KEY_FOR_KIND: Dictionary = {POSE: KEY_F2, NET: KEY_F3, BOT_COST: KEY_F9}
const BOT_COST_SCRIPT_FILE: String = "PerfBotCostOverlay.gd"

var _main: Variant = null
var _tiny_map: MapDef = null


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	SnapshotSync.end_match()
	DebugMode.set_override_for_test(true)
	_main = MAIN_SCENE.instantiate()
	_tiny_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	(_main.get_node("Field") as Field).map_def = _tiny_map
	add_child_autofree(_main)


func after_each() -> void:
	Net.leave()
	Match.abort_match()
	SnapshotSync.end_match()
	Match.set_process(true)
	DebugMode.clear_override_for_test()
	await _settle()


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _host() -> void:
	assert_eq(Net.host_game(AgentProbe.free_udp_port(), "Hostie"), OK)


func _start_round() -> void:
	_host()
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.rng_seed = 777
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)


## The panel of `kind` under Main, or null.
func _overlay(kind: StringName) -> CanvasLayer:
	for child: Node in _main.get_children():
		if kind == POSE and child is PoseOverlay:
			return child as CanvasLayer
		if kind == NET and child is NetDebugOverlay:
			return child as CanvasLayer
		var script: Script = child.get_script() as Script
		if kind == BOT_COST and script != null and script.resource_path.ends_with(BOT_COST_SCRIPT_FILE):
			return child as CanvasLayer
	return null


func _key(kind: StringName) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.device = -1
	event.physical_keycode = KEY_FOR_KIND[kind]
	event.pressed = true
	return event


## Through the game's own input path: the real event reaches whatever panels exist.
func _press(kind: StringName) -> void:
	Input.parse_input_event(_key(kind))
	await _settle()


func _toggle(kind: StringName) -> void:
	_overlay(kind)._unhandled_input(_key(kind))


func _shown(kind: StringName) -> bool:
	var overlay: CanvasLayer = _overlay(kind)
	return overlay.visible if kind == NET else bool(overlay.call(&"is_shown"))


func test_outside_a_round_no_round_debug_exists_and_the_toggles_do_nothing() -> void:
	for kind: StringName in KINDS:
		await _press(kind)
		assert_null(_overlay(kind), "%s: nothing to open in the main menu" % kind)
	_host()
	for kind: StringName in KINDS:
		await _press(kind)
		assert_null(_overlay(kind), "%s: nothing to open in the lobby" % kind)


func test_in_a_round_each_toggle_opens_its_panel() -> void:
	_start_round()
	for kind: StringName in KINDS:
		assert_not_null(_overlay(kind), "%s exists in a round" % kind)
		if _overlay(kind) == null:
			continue
		assert_false(_shown(kind), "%s starts closed" % kind)
		_toggle(kind)
		assert_true(_shown(kind), "%s opens" % kind)


func test_leaving_the_round_closes_each_panel() -> void:
	_start_round()
	var opened: Array[CanvasLayer] = []
	for kind: StringName in KINDS:
		assert_not_null(_overlay(kind), "%s exists in a round" % kind)
		_toggle(kind)
		opened.append(_overlay(kind))
	Net.leave()
	await _settle()
	for kind: StringName in KINDS:
		assert_null(_overlay(kind), "%s is gone with the round" % kind)
	for overlay: CanvasLayer in opened:
		assert_false(is_instance_valid(overlay), "the opened panel was freed")
