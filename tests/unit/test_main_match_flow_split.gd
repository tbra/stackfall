extends GutTest
## Bontago-1pi.11.84 (MF3): game/Main.gd no longer names the match-world classes; the match flow
## lives in game/MainMatchFlow.gd and is loaded before the first LOBBY -> LOADING reaction.

const MAIN_SCRIPT_PATH: String = "res://game/Main.gd"
const MAIN_SCENE: PackedScene = preload("res://game/Main.tscn")
const MATCH_FLOW_PATH: String = "res://game/MainMatchFlow.gd"
const FORBIDDEN_CLASSES: PackedStringArray = [
	"HotSeat", "Sandbox", "Tutorial", "Lobby", "BotController", "TuningPanel", "HUD",
	"RemoteCursors", "NetDebugOverlay", "StableBlockManager", "MainMatchFlow",
]
const MOVED_FUNCTIONS: PackedStringArray = [
	"_build_match_world", "_end_match_world", "_spawn_bot_controllers", "_reset_match_scope",
	"_on_match_state_changed", "_finish_loading_when_ready", "_release_countdown_hold",
]

var _main: Variant = null


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_main = MAIN_SCENE.instantiate()
	add_child_autofree(_main)


func after_each() -> void:
	Match.abort_match()
	Match.set_process(true)


func test_main_script_property_types_name_no_match_only_class() -> void:
	var script: Script = (_main as Node).get_script() as Script
	for prop: Dictionary in script.get_script_property_list():
		var type_name: String = str(prop.get("class_name", ""))
		assert_false(FORBIDDEN_CLASSES.has(type_name), "Main.%s is typed %s" % [prop.get("name", ""), type_name])
		var hint: String = str(prop.get("hint_string", ""))
		assert_false(FORBIDDEN_CLASSES.has(hint), "Main.%s hint_string names %s" % [prop.get("name", ""), hint])


func test_main_resource_dependencies_exclude_match_classes() -> void:
	var deps: PackedStringArray = ResourceLoader.get_dependencies(MAIN_SCRIPT_PATH)
	# Bontago-6cw: a script may list no dependencies (then the loop asserts nothing: GUT "Risky").
	if deps.is_empty():
		pass_test("Main.gd lists no resource dependencies, so none is a match class")
	for dep: String in deps:
		var base: String = dep.get_file().get_basename()
		assert_false(FORBIDDEN_CLASSES.has(base), "Main.gd depends on %s" % dep)



func test_main_source_does_not_declare_match_only_types() -> void:
	var source: String = FileAccess.get_file_as_string(MAIN_SCRIPT_PATH)
	for cls: String in FORBIDDEN_CLASSES:
		for pattern: String in [":\\s*%s\\b" % cls, "\\bas %s\\b" % cls, "Array\\[%s\\]" % cls, "\\b%s\\.new\\(" % cls]:
			var regex: RegEx = RegEx.create_from_string(pattern)
			for line: String in source.split("\n"):
				if line.strip_edges().begins_with("#"):
					continue
				assert_null(regex.search(line), "Main.gd names %s in: %s" % [cls, line])


func test_moved_bodies_live_in_the_flow_and_main_keeps_forwarders() -> void:
	var flow_source: String = FileAccess.get_file_as_string(MATCH_FLOW_PATH)
	for fn: String in MOVED_FUNCTIONS:
		assert_true((_main as Node).has_method(fn), "Main keeps forwarder %s" % fn)
	assert_true(flow_source.contains("func build_match_world("))
	assert_true(flow_source.contains("func end_match_world("))
	assert_true(flow_source.contains("func on_match_state_changed("))
	var main_source: String = FileAccess.get_file_as_string(MAIN_SCRIPT_PATH)
	assert_false(main_source.contains("_field.rebuild_for_map("), "world build body left Main")
	assert_false(main_source.contains("SnapshotSync.begin_match(Match"), "snapshot wiring left Main")


func test_state_change_forwarder_loads_the_flow_before_the_first_reaction() -> void:
	assert_null(_main._match_flow, "no flow before the first match state change")
	_main._on_match_state_changed(Match.State.LOBBY, Match.State.LOBBY)
	assert_not_null(_main._match_flow, "the forwarder ensured the flow")
	assert_true(_main._match_flow is MainMatchFlow)
	assert_eq(_main._match_flow.main, _main, "bound to this Main")


func test_end_match_world_without_a_world_is_idempotent_through_the_forwarder() -> void:
	_main._end_match_world()
	_main._end_match_world()
	assert_false(_main._world_built)
