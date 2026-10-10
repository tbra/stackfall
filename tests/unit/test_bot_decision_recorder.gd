extends GutTest
## Bontago-1t5.11 (BT2): game/BotDecisionRecorder.gd -- JSONL round trip, outcome join,
## sink validation and the error -> disabled (never crash) policy.

var _dir: String = ""
var _recorder: BotDecisionRecorder = null
var _fake: FakeRecMatch = null


class FakeRecMatch:
	var share: float = 0.2
	var alive: bool = true

	func slot(slot_id: int) -> PlayerSlot:
		var s: PlayerSlot = PlayerSlot.new(slot_id, slot_id, "Bot", Color.WHITE, Vector2.ZERO)
		s.home_flag_alive = alive
		return s

	func slot_count() -> int:
		return 2

	func team_of(slot_id: int) -> int:
		return slot_id

	func territory_share(_team_id: int) -> float:
		return share

	func max_height_for_slot(_slot_id: int) -> float:
		return 2.0


func before_each() -> void:
	_dir = ProjectSettings.globalize_path("user://bot_record_%d" % Time.get_ticks_usec())
	_fake = FakeRecMatch.new()
	_recorder = BotDecisionRecorder.new()
	add_child_autofree(_recorder)
	_recorder.set_match_provider(_fake)


func after_each() -> void:
	_recorder.end_match(-1)
	if DirAccess.dir_exists_absolute(_dir):
		for file: String in DirAccess.get_files_at(_dir):
			DirAccess.remove_absolute(_dir.path_join(file))
		DirAccess.remove_absolute(_dir)


func _context(slot_id: int = 0) -> Dictionary:
	var candidate: BotCandidate = BotCandidate.new()
	candidate.origin = Vector2(1.0, 2.0)
	candidate.support_height = 3.0
	var terms: BotScoreTerms = BotScoreTerms.new()
	terms.height = 3.0
	var cands: Array[BotCandidate] = [candidate]
	var term_list: Array[BotScoreTerms] = [terms]
	var state: Dictionary = BotDecisionRecorder.build_state(
		_fake, slot_id, slot_id, PackedVector2Array([Vector2(4.0, 0.0)]), 1, null,
		preload("res://config/bot_tuning.tres"), 0.001)
	return _recorder.capture(slot_id, slot_id, &"cube", cands, term_list, 0, false, state)


func _read_lines(slot_id: int = 0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var file: FileAccess = FileAccess.open(_dir.path_join("match001_slot%d.jsonl" % slot_id), FileAccess.READ)
	if file == null:
		return out
	while not file.eof_reached():
		var line: String = file.get_line()
		if not line.is_empty():
			out.append(JSON.parse_string(line) as Dictionary)
	return out


func test_disabled_by_default_writes_nothing() -> void:
	assert_false(_recorder.is_enabled())
	_recorder.begin_match({}, PackedInt32Array([0]), 1)
	assert_true(_context().is_empty())
	assert_false(DirAccess.dir_exists_absolute(_dir))


func test_rejects_res_and_relative_sinks() -> void:
	assert_false(_recorder.configure("res://nope"))
	assert_false(_recorder.configure("relative/dir"))
	assert_false(_recorder.configure(""))
	assert_false(_recorder.is_enabled())
	assert_false(_recorder.last_error().is_empty())


func test_round_trip_and_outcome_join() -> void:
	assert_true(_recorder.configure(_dir))
	_recorder.begin_match({"seed": 7, "mode": 0}, PackedInt32Array([0]), 1)
	_recorder.on_tick(5.0)
	_recorder.on_decision(_context(), 3, Vector2(1.0, 2.0), &"")
	_fake.share = 0.3
	_recorder.on_tick(15.0)
	_recorder.on_tick(36.0)
	_recorder.on_tick(66.0)
	_recorder.end_match(0)
	var lines: Array[Dictionary] = _read_lines()
	var kinds: Array[String] = []
	for record: Dictionary in lines:
		kinds.append(String(record["kind"]))
	assert_eq(kinds, ["header", "decision", "outcome", "match_end", "footer"] as Array[String])
	assert_eq(int(lines[0]["schema_version"]), 1)
	assert_eq(int(lines[0]["seed"]), 7)
	var decision: Dictionary = lines[1]
	var outcome: Dictionary = lines[2]
	assert_eq(int(outcome["id"]), int(decision["id"]), "outcome joins the decision by id")
	assert_almost_eq(float(decision["t"]), 5.0, 0.001)
	assert_almost_eq(float(outcome["d_share_10s"]), 0.1, 0.001)
	assert_almost_eq(float(outcome["d_share_60s"]), 0.1, 0.001)
	assert_true(bool(outcome["complete"]))
	assert_eq(int(decision["feed_seq"]), 3)
	assert_eq(int((decision["state"] as Dictionary)["active_specials"]), 1)
	assert_true(bool(lines[3]["won"]))
	assert_eq(int(lines[4]["policy_mismatch"]), 0)
	assert_eq(int(lines[4]["decisions"]), 1)


func test_unfinished_horizons_are_flushed_truncated_at_match_end() -> void:
	assert_true(_recorder.configure(_dir))
	_recorder.begin_match({}, PackedInt32Array([0]), 1)
	_recorder.on_decision(_context(), 1, Vector2.ZERO, &"")
	_recorder.on_tick(12.0)
	_recorder.end_match(-1)
	var outcome: Dictionary = _read_lines()[2]
	assert_false(bool(outcome["complete"]))
	assert_true(outcome.has("d_share_10s"))
	assert_false(outcome.has("d_share_30s"))


func test_elimination_time_is_recorded() -> void:
	assert_true(_recorder.configure(_dir))
	_recorder.begin_match({}, PackedInt32Array([0]), 1)
	_fake.alive = false
	_recorder.on_tick(9.0)
	_recorder.end_match(1)
	var lines: Array[Dictionary] = _read_lines()
	assert_almost_eq(float(lines[1]["eliminated_at"]), 9.0, 0.001)
	assert_false(bool(lines[1]["won"]))


func test_write_error_disables_instead_of_crashing() -> void:
	assert_true(_recorder.configure(_dir))
	_recorder.config = _recorder.config.duplicate() as BotRecordingConfig
	_recorder.config.max_bytes = 10
	_recorder.begin_match({"seed": 1}, PackedInt32Array([0]), 1)
	assert_false(_recorder.is_enabled(), "byte cap trips the disable path")
	assert_true(_recorder.last_error().contains("byte cap"))
	_recorder.on_decision(_context(), 0, Vector2.ZERO, &"")
	_recorder.on_tick(1.0)
	_recorder.end_match(-1)
	pass_test("no crash after disable")


func test_unopenable_file_disables() -> void:
	assert_true(_recorder.configure(_dir))
	# Occupy the target path with a directory so FileAccess.open fails.
	DirAccess.make_dir_recursive_absolute(_dir.path_join("match001_slot0.jsonl"))
	_recorder.begin_match({}, PackedInt32Array([0]), 1)
	assert_false(_recorder.is_enabled())
	DirAccess.remove_absolute(_dir.path_join("match001_slot0.jsonl"))


func test_checked_in_sample_fixture_is_valid_schema_v1() -> void:
	var path: String = "res://tests/fixtures/bot_record_sample.jsonl"
	assert_lt(FileAccess.get_file_as_bytes(path).size(), 100000)
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var kinds: Dictionary = {}
	var first: bool = true
	while not file.eof_reached():
		var line: String = file.get_line()
		if line.is_empty():
			continue
		var record: Dictionary = JSON.parse_string(line) as Dictionary
		if first:
			assert_eq(record["kind"], "header")
			assert_eq(int(record["schema_version"]), 1)
			first = false
		kinds[record["kind"]] = int(kinds.get(record["kind"], 0)) + 1
		if record["kind"] == "decision":
			var cand: Dictionary = (record["cands"] as Array)[0] as Dictionary
			assert_eq((cand["terms"] as Array).size(), 5)
	assert_eq(kinds["decision"], kinds["outcome"])
	assert_eq(kinds["footer"], 1)
