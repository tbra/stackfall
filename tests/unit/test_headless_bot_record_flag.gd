extends GutTest
## Bontago-1t5.11 (BT3): `--bot-record=<dir>` on the headless bot flow -- flag parsing, OFF by
## default, a header per bot file, per-match rotation under --loop-matches and the footer on END.

const MAIN_SCENE: PackedScene = preload("res://game/Main.tscn")

var _main: Variant = null
var _dir: String = ""


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	SnapshotSync.end_match()
	_dir = ProjectSettings.globalize_path("user://bot_record_flag_%d" % Time.get_ticks_usec())
	_main = MAIN_SCENE.instantiate()
	var tiny_map: MapDef = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	tiny_map.field_radius = 20.0
	(_main.get_node("Field") as Field).map_def = tiny_map
	var cfg: MatchConfig = (load("res://config/match_defaults.tres") as MatchConfig).duplicate(true)
	cfg.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(cfg as TinyMapMatchConfig).set_tiny_map(tiny_map)
	cfg.rng_seed = 90210
	_main.match_config = cfg
	add_child_autofree(_main)


func after_each() -> void:
	Net.leave()
	Match.abort_match()
	SnapshotSync.end_match()
	Match.set_process(true)
	await get_tree().process_frame
	await get_tree().process_frame
	if DirAccess.dir_exists_absolute(_dir):
		for file: String in DirAccess.get_files_at(_dir):
			DirAccess.remove_absolute(_dir.path_join(file))
		DirAccess.remove_absolute(_dir)


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _read_kinds(file_name: String) -> Array[String]:
	var kinds: Array[String] = []
	var file: FileAccess = FileAccess.open(_dir.path_join(file_name), FileAccess.READ)
	if file == null:
		return kinds
	while not file.eof_reached():
		var line: String = file.get_line()
		if not line.is_empty():
			kinds.append(String((JSON.parse_string(line) as Dictionary)["kind"]))
	return kinds


func test_flag_parses_and_defaults_off() -> void:
	var flow: Variant = _main._headless_bots_flow_port()
	assert_eq(flow._bot_record_arg(PackedStringArray(["--bots=8", "--bot-record=C:/x/y"])), "C:/x/y")
	assert_eq(flow._bot_record_arg(PackedStringArray(["--bots=8"])), "")


func test_without_flag_nothing_is_recorded() -> void:
	assert_eq(Net.host_game(AgentProbe.free_udp_port(), "Hostie"), OK)
	_main._start_headless_bot_match_with_args(PackedStringArray(["--bots=2"]))
	await _settle()
	assert_null(_main._headless_bots_flow_port()._bot_recorder)
	assert_false(DirAccess.dir_exists_absolute(_dir))
	for node: Node in _main._bot_controllers:
		assert_null((node as BotController)._recorder)


func test_flag_writes_headers_attaches_recorders_and_closes_on_end() -> void:
	assert_eq(Net.host_game(AgentProbe.free_udp_port(), "Hostie"), OK)
	_main._start_headless_bot_match_with_args(PackedStringArray(["--bots=2", "--bot-record=" + _dir]))
	await _settle()
	var flow: Variant = _main._headless_bots_flow_port()
	assert_true((flow._bot_recorder as BotDecisionRecorder).is_enabled())
	assert_eq(_main._bot_controllers.size(), 2)
	for node: Node in _main._bot_controllers:
		assert_not_null((node as BotController)._recorder, "every bot carries the recorder")
	Match._finish_match(0)
	await _settle()
	for slot_id: int in range(2):
		var kinds: Array[String] = _read_kinds("match001_slot%d.jsonl" % slot_id)
		assert_eq(kinds[0], "header")
		assert_eq(kinds[kinds.size() - 1], "footer")
		assert_has(kinds, "match_end")


func test_loop_matches_rotate_files_per_match() -> void:
	assert_eq(Net.host_game(AgentProbe.free_udp_port(), "Hostie"), OK)
	_main._start_headless_bot_match_with_args(PackedStringArray(["--bots=2", "--loop-matches", "--bot-record=" + _dir]))
	await _settle()
	Match._finish_match(0)
	await _settle()
	await _settle()
	assert_eq(_main._headless_loop_index, 2)
	assert_true(FileAccess.file_exists(_dir.path_join("match001_slot0.jsonl")))
	assert_true(FileAccess.file_exists(_dir.path_join("match002_slot0.jsonl")))
	assert_eq(_read_kinds("match001_slot0.jsonl").back(), "footer")


func test_unwritable_sink_does_not_stop_the_match() -> void:
	assert_eq(Net.host_game(AgentProbe.free_udp_port(), "Hostie"), OK)
	_main._start_headless_bot_match_with_args(PackedStringArray(["--bots=2", "--bot-record=res://nope"]))
	await _settle()
	assert_ne(Match.state(), Match.State.LOBBY, "the match still started")
	assert_false((_main._headless_bots_flow_port()._bot_recorder as BotDecisionRecorder).is_enabled())
