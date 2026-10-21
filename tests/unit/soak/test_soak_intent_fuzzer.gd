extends GutTest
## game/debug/SoakIntentFuzzer.gd: the client-side authority probe (SOAK_PLAN sections 6.3, 7.1).
## The fuzzer's collaborators are set before add_child, through SoakIntentFuzzer.Seams, as Main does.

const _STEP_S: float = 0.01
const _OWN_SLOT: int = 1
const _DISC_RADIUS_M: float = 40.0
const _START_S: float = 0.2
const _INTERVAL_S: float = 0.1
const _ROLE_CLIENT: StringName = &"client"
const _KIND_NAMES: PackedStringArray = [
	"NEGATIVE_SEQ", "STALE_SEQ", "NON_FINITE_POSE", "FOREIGN_SLOT", "OUT_OF_DISC", "FLOOD",
]

var _net_config: NetConfig = preload("res://config/net/net_config.tres")
var _frame: int = 0
var _current_seq: int = 7
## One entry per submitted intent: slot, origin, seq, auto_drop, frame, current.
var _sent: Array[Dictionary] = []
var _lines: PackedStringArray = PackedStringArray()
var _playing: bool = true
var _slot: int = _OWN_SLOT


func before_each() -> void:
	_frame = 0
	_current_seq = 7
	_playing = true
	_sent.clear()
	_lines.clear()


func _config(rng_seed: int = 8331) -> SoakConfig:
	var config: SoakConfig = SoakConfig.new()
	config.fuzz_seed = rng_seed
	config.fuzz_start_after_s = _START_S
	config.fuzz_interval_s = _INTERVAL_S
	return config


func _make(config: SoakConfig, slot: int = _OWN_SLOT) -> SoakIntentFuzzer:
	_slot = slot
	var seams: SoakIntentFuzzer.Seams = SoakIntentFuzzer.Seams.new()
	seams.playing = func() -> bool: return _playing
	seams.local_slot = func() -> int: return _slot
	seams.feed_seq = func(_s: int) -> int: return _current_seq
	seams.field_radius = func() -> float: return _DISC_RADIUS_M
	seams.submit_place = _on_place
	seams.line = func(line: String) -> void: _lines.append(line)
	var fuzzer: SoakIntentFuzzer = SoakIntentFuzzer.new()
	fuzzer.config = config
	fuzzer.seams = seams
	add_child_autofree(fuzzer)
	return fuzzer


func _on_place(
	slot_id: int, origin: Vector3, _orientation: int, _quat: Quaternion, auto_drop: bool, feed_seq: int
) -> StringName:
	_sent.append({
		"slot": slot_id, "origin": origin, "seq": feed_seq, "auto_drop": auto_drop,
		"frame": _frame, "current": _current_seq,
	})
	return PlacementRules.REASON_OK


func _run(fuzzer: SoakIntentFuzzer, seconds: float) -> void:
	for _i: int in roundi(seconds / _STEP_S):
		_frame += 1
		simulate(fuzzer, 1, _STEP_S)


func _is_finite_vec(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


func _is_legitimate(sent: Dictionary) -> bool:
	var origin: Vector3 = sent["origin"]
	return (
		int(sent["slot"]) == _OWN_SLOT
		and int(sent["seq"]) == int(sent["current"])
		and _is_finite_vec(origin)
		and Vector2(origin.x, origin.z).length() <= _DISC_RADIUS_M
	)


func _is_refusable(sent: Dictionary) -> bool:
	var origin: Vector3 = sent["origin"]
	return (
		int(sent["seq"]) < 0
		or int(sent["seq"]) < int(sent["current"])
		or int(sent["slot"]) != _OWN_SLOT
		or not _is_finite_vec(origin)
		or Vector2(origin.x, origin.z).length() > _DISC_RADIUS_M
	)


func _signature() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for sent: Dictionary in _sent:
		out.append("%d|%s|%d" % [sent["slot"], str(sent["origin"]), sent["seq"]])
	return out


func _batch_sizes() -> Dictionary:
	var sizes: Dictionary = {}
	for sent: Dictionary in _sent:
		sizes[sent["frame"]] = int(sizes.get(sent["frame"], 0)) + 1
	return sizes


func test_nothing_is_sent_before_the_start_delay() -> void:
	var fuzzer: SoakIntentFuzzer = _make(_config())
	_run(fuzzer, _START_S - 0.05)
	assert_eq(_sent.size(), 0)
	assert_eq(_lines.size(), 0)


func test_sends_begin_once_the_start_delay_has_passed() -> void:
	var fuzzer: SoakIntentFuzzer = _make(_config())
	_run(fuzzer, _START_S + _INTERVAL_S + 0.05)
	assert_gt(_sent.size(), 0, "the fuzzer must send after fuzz_start_after_s")


func test_batches_arrive_once_per_interval() -> void:
	var fuzzer: SoakIntentFuzzer = _make(_config())
	_run(fuzzer, _START_S)
	_run(fuzzer, _INTERVAL_S * 10.0)
	assert_between(_batch_sizes().size(), 9, 11, "ten intervals give about ten batches")


func test_batches_are_at_least_one_interval_apart() -> void:
	var fuzzer: SoakIntentFuzzer = _make(_config())
	_run(fuzzer, _START_S + _INTERVAL_S * 3.0)
	var frames: Array = _batch_sizes().keys()
	frames.sort()
	assert_gt(frames.size(), 1, "fixture: more than one batch")
	for i: int in range(1, frames.size()):
		var gap_s: float = float(int(frames[i]) - int(frames[i - 1])) * _STEP_S
		assert_gte(gap_s, _INTERVAL_S - _STEP_S * 1.5, "batches are fuzz_interval_s apart")


func test_every_intent_is_one_the_host_must_refuse() -> void:
	var fuzzer: SoakIntentFuzzer = _make(_config())
	_run(fuzzer, _START_S + 6.0)
	assert_gt(_sent.size(), 20, "fixture: enough intents to mean something")
	for sent: Dictionary in _sent:
		assert_true(_is_refusable(sent), "refusable intent, got %s" % [sent])


func test_no_intent_is_a_legitimate_own_home_placement_at_the_current_seq() -> void:
	var fuzzer: SoakIntentFuzzer = _make(_config())
	_run(fuzzer, _START_S + 3.0)
	_current_seq = 12
	_run(fuzzer, 3.0)
	assert_gt(_sent.size(), 0)
	for sent: Dictionary in _sent:
		assert_false(_is_legitimate(sent), "legitimate intent leaked: %s" % [sent])


func test_no_intent_is_an_auto_drop() -> void:
	var fuzzer: SoakIntentFuzzer = _make(_config())
	_run(fuzzer, _START_S + 2.0)
	assert_gt(_sent.size(), 0)
	for sent: Dictionary in _sent:
		assert_false(bool(sent["auto_drop"]), "a client never auto-drops")


func test_a_flood_is_the_configured_multiple_of_the_burst_in_one_tick() -> void:
	var config: SoakConfig = _config()
	var fuzzer: SoakIntentFuzzer = _make(config)
	_run(fuzzer, _START_S + 10.0)
	var expected: int = ceili(config.fuzz_flood_factor * float(_net_config.flood_place_burst))
	var floods: int = 0
	for size: int in _batch_sizes().values():
		if size > 1:
			floods += 1
			assert_eq(size, expected, "a flood burst is factor x flood_place_burst intents")
	assert_gt(floods, 0, "a ten second run includes a flood")


func test_a_seatless_client_sends_nothing() -> void:
	var fuzzer: SoakIntentFuzzer = _make(_config(), -1)
	_run(fuzzer, _START_S + 2.0)
	assert_eq(_sent.size(), 0)
	assert_eq(_lines.size(), 0)


func test_the_same_seed_gives_the_same_sequence() -> void:
	var first: SoakIntentFuzzer = _make(_config(77))
	_run(first, _START_S + 3.0)
	var first_signature: PackedStringArray = _signature()
	first.queue_free()
	before_each()
	var second: SoakIntentFuzzer = _make(_config(77))
	_run(second, _START_S + 3.0)
	assert_gt(first_signature.size(), 0)
	assert_eq(_signature(), first_signature)


func test_a_different_seed_gives_a_different_sequence() -> void:
	var first: SoakIntentFuzzer = _make(_config(77))
	_run(first, _START_S + 3.0)
	var first_signature: PackedStringArray = _signature()
	first.queue_free()
	before_each()
	var second: SoakIntentFuzzer = _make(_config(78))
	_run(second, _START_S + 3.0)
	assert_gt(first_signature.size(), 0)
	assert_ne(_signature(), first_signature)


func test_one_fuzz_line_is_logged_for_each_intent_sent() -> void:
	var fuzzer: SoakIntentFuzzer = _make(_config())
	_run(fuzzer, _START_S + 3.0)
	assert_gt(_sent.size(), 0)
	assert_eq(_lines.size(), _sent.size(), "logged lines equal sent intents")
	for i: int in mini(_lines.size(), _sent.size()):
		var line: String = _lines[i]
		var tokens: PackedStringArray = line.split(" ")
		assert_eq(tokens[0], "SOAK_FUZZ")
		assert_true(tokens.has("role=%s" % _ROLE_CLIENT), line)
		assert_true(tokens.has("seq=%d" % (i + 1)), "line counter counts from 1: %s" % line)
		assert_true(tokens.has("slot=%d" % int(_sent[i]["slot"])), line)
		var kind_ok: bool = false
		for kind_name: String in _KIND_NAMES:
			kind_ok = kind_ok or tokens.has("kind=%s" % kind_name)
		assert_true(kind_ok, "kind is a SoakFuzzPlan.Kind name: %s" % line)


func test_nothing_is_sent_while_the_match_is_not_playing() -> void:
	_playing = false
	var fuzzer: SoakIntentFuzzer = _make(_config())
	_run(fuzzer, _START_S + 2.0)
	assert_eq(_sent.size(), 0)
	assert_eq(_lines.size(), 0)


func test_the_start_delay_counts_only_playing_time() -> void:
	_playing = false
	var fuzzer: SoakIntentFuzzer = _make(_config())
	_run(fuzzer, 5.0)
	_playing = true
	_run(fuzzer, _START_S - 0.05)
	assert_eq(_sent.size(), 0, "time spent not playing does not count toward the delay")
	_run(fuzzer, _INTERVAL_S + 0.1)
	assert_gt(_sent.size(), 0)
