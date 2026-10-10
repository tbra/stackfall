extends GutTest
## Bontago-1t5.13 (BT5): `--bot-difficulty`, `--bot-weights[-slots]` and `--match-seed` on the headless
## bot flow, and BotController.tuning_with_weights().

const MAIN_SCENE: PackedScene = preload("res://game/Main.tscn")
const SHIPPED_PATH: String = "res://config/bot_tuning.tres"
const TEST_HEIGHT_WEIGHT: float = 3.25

var _main: Variant = null
var _files: Array[String] = []


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	SnapshotSync.end_match()
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
	for path: String in _files:
		DirAccess.remove_absolute(path)
	_files.clear()


func _flow() -> Variant:
	return _main._headless_bots_flow_port()


func _write_json(text: String) -> String:
	var path: String = ProjectSettings.globalize_path("user://bt5_weights_%d.json" % Time.get_ticks_usec())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	_files.append(path)
	return path


func _start(args: PackedStringArray) -> void:
	assert_eq(Net.host_game(AgentProbe.free_udp_port(), "Hostie"), OK)
	_main._start_headless_bot_match_with_args(args)
	await get_tree().process_frame
	await get_tree().process_frame


func _bot_for(slot_id: int) -> BotController:
	for node: Node in _main._bot_controllers:
		if (node as BotController).bound_slot() == slot_id:
			return node as BotController
	return null


func test_difficulty_flag_sets_every_bot_slot() -> void:
	for name_and_value: Array in [["easy", MatchConfig.AiDifficulty.EASY], ["hard", MatchConfig.AiDifficulty.HARD], ["2", MatchConfig.AiDifficulty.HARD]]:
		var config: MatchConfig = _flow()._build_headless_bot_config(4, PackedStringArray(["--bot-difficulty=%s" % name_and_value[0]]))
		for slot_id: int in range(4):
			assert_eq(config.ai_difficulty_for_slot(slot_id), name_and_value[1], "slot %d %s" % [slot_id, name_and_value[0]])
	var unset: MatchConfig = _flow()._build_headless_bot_config(4, PackedStringArray())
	assert_eq(unset.ai_difficulty, MatchConfig.AiDifficulty.NORMAL, "no flag keeps the configured difficulty")


func test_difficulty_flag_reaches_running_controllers_and_header() -> void:
	await _start(PackedStringArray(["--bots=3", "--bot-difficulty=hard"]))
	assert_eq(_main._bot_controllers.size(), 3)
	for node: Node in _main._bot_controllers:
		assert_eq((node as BotController)._difficulty, MatchConfig.AiDifficulty.HARD)


func test_weights_override_reaches_only_named_slots() -> void:
	var shipped: BotTuning = load(SHIPPED_PATH) as BotTuning
	var before: float = shipped.weight_height
	var path: String = _write_json(JSON.stringify({"weight_height": TEST_HEIGHT_WEIGHT}))
	await _start(PackedStringArray(["--bots=4", "--bot-weights=%s" % path, "--bot-weights-slots=1,3"]))
	for slot_id: int in range(4):
		var bot: BotController = _bot_for(slot_id)
		assert_not_null(bot)
		if slot_id == 1 or slot_id == 3:
			assert_almost_eq(bot.tuning.weight_height, TEST_HEIGHT_WEIGHT, 0.0001)
			assert_ne(bot.tuning, shipped)
		else:
			assert_eq(bot.tuning, shipped, "slot %d keeps the shared shipped resource" % slot_id)
	assert_eq(shipped.weight_height, before, "shipped BotTuning untouched")


func test_slot_map_shape_and_flat_default_all_slots() -> void:
	var path: String = _write_json(JSON.stringify({"2": {"weight_risk": 0.5}}))
	_flow()._load_bot_weight_overrides(PackedStringArray(["--bot-weights=%s" % path]), 4)
	assert_eq(_flow()._bot_weight_overrides.keys(), [2])
	var flat: String = _write_json(JSON.stringify({"weight_risk": 0.5}))
	_flow()._load_bot_weight_overrides(PackedStringArray(["--bot-weights=%s" % flat]), 4)
	assert_eq(_flow()._bot_weight_overrides.size(), 4)


func test_bad_json_and_unknown_keys_keep_shipped_weights() -> void:
	var shipped: BotTuning = load(SHIPPED_PATH) as BotTuning
	var bad: String = _write_json("{not json")
	_flow()._load_bot_weight_overrides(PackedStringArray(["--bot-weights=%s" % bad]), 2)
	assert_true(_flow()._bot_weight_tunings.is_empty())
	_flow()._load_bot_weight_overrides(PackedStringArray(["--bot-weights=user://missing_bt5.json"]), 2)
	assert_true(_flow()._bot_weight_tunings.is_empty())
	var copy: BotTuning = BotController.tuning_with_weights(shipped, {"nonsense": 1.0, "weight_height": "x", "weight_risk": INF})
	assert_eq(copy.weight_height, shipped.weight_height)
	assert_eq(copy.weight_risk, shipped.weight_risk)
	var clamped: BotTuning = BotController.tuning_with_weights(shipped, {"weight_height": 1.0e9})
	assert_eq(clamped.weight_height, BotController.WEIGHT_OVERRIDE_LIMIT)
	# A bad file never stops the match.
	await _start(PackedStringArray(["--bots=2", "--bot-weights=%s" % bad]))
	assert_eq(_main._bot_controllers.size(), 2)
	assert_eq((_main._bot_controllers[0] as BotController).tuning, shipped)


func test_match_seed_is_deterministic() -> void:
	var args: PackedStringArray = PackedStringArray(["--match-seed=4242"])
	assert_eq(_flow()._build_headless_bot_config(2, args).rng_seed, 4242)
	assert_eq(_flow()._build_headless_bot_config(2, args).rng_seed, 4242)
	assert_eq(_flow()._derived_loop_seed(4242, 1), 4242)
	assert_eq(_flow()._derived_loop_seed(4242, 2), _flow()._derived_loop_seed(4242, 2))
	assert_ne(_flow()._derived_loop_seed(4242, 2), _flow()._derived_loop_seed(4242, 3))
	assert_eq(_flow()._build_headless_bot_config(2, PackedStringArray()).rng_seed, 90210, "no flag keeps the configured seed")


func test_seed_and_overrides_reach_the_header() -> void:
	var dir: String = ProjectSettings.globalize_path("user://bt5_rec_%d" % Time.get_ticks_usec())
	var path: String = _write_json(JSON.stringify({"weight_height": TEST_HEIGHT_WEIGHT}))
	await _start(PackedStringArray(["--bots=2", "--match-seed=777", "--bot-difficulty=hard", "--bot-record=%s" % dir, "--bot-weights=%s" % path, "--bot-weights-slots=0"]))
	_flow()._finish_bot_record(-1)
	var files: PackedStringArray = DirAccess.get_files_at(dir)
	assert_gt(files.size(), 0)
	var header: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(files[0])).split("\n")[0]) as Dictionary
	var text: String = JSON.stringify(header)
	assert_true(text.contains("\"seed\":777"), text)
	assert_true(text.contains("weight_overrides"), text)
	assert_almost_eq(float((header["weights"] as Dictionary)["height"]), TEST_HEIGHT_WEIGHT, 0.0001, "slot 0 header carries the overridden weight")
	Match.abort_match()
	for file: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)
