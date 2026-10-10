extends GutTest
## Bontago-1t5.11 (BT2): the recorder is a pure observer. The same seeded controller run
## with and without a recorder must send identical placement requests (same rng stream,
## same chosen candidates), and the recorded `chosen` must agree with the live policy.

const ControllerTests := preload("res://tests/unit/test_bot_controller.gd")
const CUBE_SHAPE: BlockShape = preload("res://config/blocks/cube.tres")
const FRAMES: int = 400

var _dir: String = ""


class RecFakeMatch:
	extends ControllerTests.BotControllerFakeMatch

	func territory_share(_team_id: int) -> float:
		return 0.25

	func max_height_for_slot(_slot_id: int) -> float:
		return 1.5


func before_each() -> void:
	_dir = ProjectSettings.globalize_path("user://bot_record_passive_%d" % Time.get_ticks_usec())


func after_each() -> void:
	if not DirAccess.dir_exists_absolute(_dir):
		return
	for file: String in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(file))
	DirAccess.remove_absolute(_dir)


func _run(record: bool) -> Dictionary:
	var small: MapDef = MapDef.new()
	small.id = &"test_bot_disk"
	small.field_radius = 10.0
	small.cell_size = 1.0
	small.disk_height = 1.0
	small.territory_res = 16
	var field: Field = Field.new()
	field.map_def = small
	add_child_autofree(field)
	var fake: RecFakeMatch = RecFakeMatch.new()
	fake.config = MatchConfig.new()
	fake.config.rng_seed = 4242
	fake.config.goal_flag_count = 1
	fake.config.map_size = MapDef.MapSize.SMALL
	fake.slot_count_value = 2
	for slot_id: int in range(2):
		var slot: PlayerSlot = PlayerSlot.new(slot_id, slot_id, "Bot %d" % slot_id, Color.WHITE, Vector2(1.0 if slot_id == 0 else -5.0, 0.0))
		fake.slots_by_id[slot_id] = slot
		fake.team_by_slot[slot_id] = slot_id
	fake.held_shapes[0] = CUBE_SHAPE
	fake.release_locked[0] = false
	var grid: CellGrid = CellGrid.new(small.field_radius, small.cell_size)
	var raster: TerritoryRaster = TerritoryRaster.new(grid, preload("res://config/territory_tuning.tres"))
	var circles: Array[InfluenceCircle] = [InfluenceCircle.new(Vector2.ZERO, 6.0, 0, 0, true, 0)]
	raster.update(circles, TerritorySolver.new(preload("res://config/territory_tuning.tres")).solve(circles), 0.1, false, false)
	fake.raster_value = raster
	fake.cell_grid_value = grid
	var net_ref: ControllerTests.BotControllerFakeNet = ControllerTests.BotControllerFakeNet.new()
	var controller: BotController = BotController.new()
	add_child_autofree(controller)
	controller.set_match_provider(fake)
	controller.set_net_provider(net_ref)
	var recorder: BotDecisionRecorder = null
	if record:
		recorder = BotDecisionRecorder.new()
		add_child_autofree(recorder)
		recorder.set_match_provider(fake)
		assert_true(recorder.configure(_dir))
		recorder.begin_match({"seed": 4242}, PackedInt32Array([0]), 1)
		controller.set_recorder(recorder)
	controller.setup(0, MatchConfig.AiDifficulty.HARD, field, null)
	Events.feed_block_issued.emit(0, &"cube", &"")
	var fed: int = 0
	for frame: int in range(FRAMES):
		controller._physics_process(1.0 / 60.0)
		if recorder != null:
			recorder.on_tick(float(frame) / 60.0)
		# A new piece is fed after every request, like the real feed loop.
		if fake.request_place_calls.size() > fed:
			fed = fake.request_place_calls.size()
			Events.feed_block_issued.emit(0, &"cube", &"")
	if recorder != null:
		recorder.end_match(-1)
	return {"calls": fake.request_place_calls, "recorder": recorder}


func test_recording_does_not_change_the_placements() -> void:
	var plain: Dictionary = _run(false)
	var recorded: Dictionary = _run(true)
	var a: Array = plain["calls"]
	var b: Array = recorded["calls"]
	assert_gt(a.size(), 1, "fixture: the bot placed more than once")
	assert_eq(b.size(), a.size())
	for i: int in range(mini(a.size(), b.size())):
		assert_eq((b[i] as Dictionary)["origin"], (a[i] as Dictionary)["origin"], "request %d origin" % i)
		assert_eq((b[i] as Dictionary)["orientation_index"], (a[i] as Dictionary)["orientation_index"])


func test_recorded_decisions_match_the_requests_and_score_policy() -> void:
	var recorded: Dictionary = _run(true)
	var calls: Array = recorded["calls"]
	var file: FileAccess = FileAccess.open(_dir.path_join("match001_slot0.jsonl"), FileAccess.READ)
	assert_not_null(file)
	var decisions: Array[Dictionary] = []
	while not file.eof_reached():
		var line: String = file.get_line()
		if line.is_empty():
			continue
		var record: Dictionary = JSON.parse_string(line) as Dictionary
		if record["kind"] == "decision":
			decisions.append(record)
	assert_eq(decisions.size(), calls.size(), "one decision line per request_place")
	for record: Dictionary in decisions:
		assert_eq(record["policy"], "score")
		assert_eq(int(record["chosen"]), int(record["scored_best"]), "recorder terms agree with the live policy")
	assert_eq(int((recorded["recorder"] as BotDecisionRecorder).stats()["mismatches"]), 0)
