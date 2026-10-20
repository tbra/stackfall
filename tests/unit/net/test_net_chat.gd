extends GutTest
## Chat. The trust-boundary cases (spoofing, oversize, flood, duplicate, history) drive
## a directly built NetChatService with spy seams on a synthetic clock. The ENet cases
## run a real host plus two clients (test_net_session.gd pattern) and assert on Events:
## every Net instance re-emits what its own service accepted, so one line reaches the
## bus once per instance.

const _NET_SCRIPT: GDScript = preload("res://autoload/Net.gd")
const METHOD_LINE: StringName = NetChatService.METHOD_LINE
const METHOD_HISTORY: StringName = NetChatService.METHOD_HISTORY
const METHOD_NOTICE: StringName = NetChatService.METHOD_NOTICE
const HOST_ID: int = 1
const ALICE: int = 2
const BOB: int = 3
const SPECTATOR: int = 4
const STRANGER: int = 4242
const START_CLOCK_S: float = 100.0
## Clock step that clears the duplicate window and refills a bucket.
const FAR_STEP_S: float = 100.0
const FLOOD_COUNT: int = 50
const OVERSIZE_FACTOR: int = 100
const BIDI_OVERRIDE: int = 0x202E
const ZERO_WIDTH_SPACE: int = 0x200B
const WAIT_MSEC: int = 8000
const SETTLE_MSEC: int = 400
const INSTANCES: int = 3

var _cfg: ChatConfig
var _service: NetChatService
var _clock: float = START_CLOCK_S
var _chat_host: bool = true
var _roster: Dictionary = {}
var _targets: Array = []
var _sent: Array[Dictionary] = []
var _accepted: Array[Dictionary] = []

var _host: Variant
var _c1: Variant
var _c2: Variant
var _lines: Array[Dictionary] = []
var _histories: Array = []
var _notices: Array[int] = []
var _last_port: int = 0


func before_each() -> void:
	_cfg = (load("res://config/net/chat_config.tres") as ChatConfig).duplicate() as ChatConfig
	_clock = START_CLOCK_S
	_chat_host = true
	_roster = {
		HOST_ID: {LobbySeats.FIELD_SLOT_ID: 0, LobbySeats.FIELD_NAME: "Hostie"},
		ALICE: {LobbySeats.FIELD_SLOT_ID: 1, LobbySeats.FIELD_NAME: "Alice"},
		BOB: {LobbySeats.FIELD_SLOT_ID: 2, LobbySeats.FIELD_NAME: "Bob"},
		SPECTATOR: {LobbySeats.FIELD_SLOT_ID: -1, LobbySeats.FIELD_NAME: "Spec"},
	}
	_targets = [ALICE, BOB]
	_sent.clear()
	_accepted.clear()
	_service = _build_service()
	_lines.clear()
	_histories.clear()
	_notices.clear()
	Events.chat_line_received.connect(_on_line)
	Events.chat_history_received.connect(_on_history)
	Events.chat_notice.connect(_on_notice)


func after_each() -> void:
	for signal_cb: Array in [
		[Events.chat_line_received, _on_line],
		[Events.chat_history_received, _on_history],
		[Events.chat_notice, _on_notice],
	]:
		if (signal_cb[0] as Signal).is_connected(signal_cb[1]):
			(signal_cb[0] as Signal).disconnect(signal_cb[1])
	for side: Variant in [_c2, _c1, _host]:
		if side != null:
			side.leave()
	_host = null
	_c1 = null
	_c2 = null
	await get_tree().process_frame
	await get_tree().process_frame


func _on_line(line: Dictionary) -> void:
	_lines.append(line)


func _on_history(lines: Array) -> void:
	_histories.append(lines)


func _on_notice(code: int) -> void:
	_notices.append(code)


func _build_service() -> NetChatService:
	var seams: NetChatService.Seams = NetChatService.Seams.new()
	seams.is_chat_host = func() -> bool: return _chat_host
	seams.now_s = func() -> float: return _clock
	seams.peer_info = func(peer_id: int) -> Dictionary: return (_roster.get(peer_id, {}) as Dictionary).duplicate()
	seams.send_to_peer = func(peer_id: int, method: StringName, args: Array) -> void:
		_sent.append({"peer": peer_id, "method": method, "args": args})
	seams.targets = func() -> Array: return _targets.duplicate()
	var service: NetChatService = NetChatService.new(_cfg, seams)
	service.line_accepted.connect(func(line: Dictionary) -> void: _accepted.append(line))
	return service


func _sent_to(peer_id: int, method: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for call: Dictionary in _sent:
		if int(call["peer"]) == peer_id and call["method"] == method:
			out.append(call)
	return out


## Submits at a clock far enough from every earlier call to find a full bucket.
func _submit_fresh(sender: int, payload: Variant) -> void:
	_clock += FAR_STEP_S
	_service.on_submit(sender, payload)


# --- NetChatService on its own ------------------------------------------------------

func test_an_accepted_line_carries_roster_identity_and_goes_to_every_target() -> void:
	_service.on_submit(ALICE, "  hello   there ")
	assert_eq(_accepted.size(), 1)
	if _accepted.is_empty():
		return
	var line: Dictionary = _accepted[0]
	assert_eq(line[ChatRules.KEY_TEXT], "hello there")
	assert_eq(line[ChatRules.KEY_NAME], "Alice")
	assert_eq(line[ChatRules.KEY_SLOT], 1)
	assert_eq(line[ChatRules.KEY_PEER], ALICE, "the id is the transport's, never the payload's")
	assert_eq(line[ChatRules.KEY_COLOR], 1, "the slot is the colour fallback")
	assert_eq(line[ChatRules.KEY_KIND], ChatRules.KIND_TEXT)
	for peer_id: int in _targets:
		var calls: Array[Dictionary] = _sent_to(peer_id, METHOD_LINE)
		assert_eq(calls.size(), 1, "peer %d got the line once" % peer_id)
		if calls.is_empty():
			return
		assert_eq((calls[0]["args"] as Array)[0], line)
	assert_true(_sent_to(SPECTATOR, METHOD_LINE).is_empty(), "only the targets are addressed")


func test_the_line_is_validated_by_the_client_side_rules() -> void:
	_service.on_submit(ALICE, "ok")
	assert_eq(_accepted.size(), 1)
	if _accepted.is_empty():
		return
	assert_true(ChatRules.validate_line(_accepted[0], _cfg, LobbySeats.ROSTER_NAME_MAX))


func test_seq_rises_with_every_published_line() -> void:
	_submit_fresh(ALICE, "one")
	_submit_fresh(BOB, "two")
	_submit_fresh(ALICE, "three")
	assert_eq(_accepted.size(), 3)
	for i: int in range(1, _accepted.size()):
		assert_gt(int(_accepted[i][ChatRules.KEY_SEQ]), int(_accepted[i - 1][ChatRules.KEY_SEQ]), "seq is monotonic")


func test_a_spectator_may_chat_with_the_fallback_colour() -> void:
	_service.on_submit(SPECTATOR, "hi from the stands")
	assert_eq(_accepted.size(), 1)
	if _accepted.is_empty():
		return
	assert_eq(_accepted[0][ChatRules.KEY_SLOT], -1)
	assert_eq(_accepted[0][ChatRules.KEY_COLOR], 0)


func test_unknown_peers_and_a_non_host_instance_cannot_chat() -> void:
	_submit_fresh(STRANGER, "hi")
	assert_true(_accepted.is_empty(), "an id that is not in the roster")
	_chat_host = false
	_submit_fresh(ALICE, "hi")
	assert_true(_accepted.is_empty(), "only the host of a non-private session relays chat")
	assert_true(_sent.is_empty())


func test_a_peer_that_left_the_roster_is_refused() -> void:
	_submit_fresh(ALICE, "before")
	_roster.erase(ALICE)
	_submit_fresh(ALICE, "after")
	assert_eq(_accepted.size(), 1)


func test_disabled_chat_relays_nothing() -> void:
	_cfg.enabled = false
	_submit_fresh(ALICE, "hi")
	assert_true(_accepted.is_empty())
	assert_true(_sent.is_empty())


func test_wrong_payload_types_are_dropped() -> void:
	for bad: Variant in [7, 1.5, [1, 2], {"text": "x"}, null, true, &"sn", Vector2.ONE,
			{"peer": BOB, "name": "Bob", "text": "I am Bob"}]:
		_submit_fresh(ALICE, bad)
	assert_true(_accepted.is_empty(), "nothing relayed")
	assert_true(_sent_to(BOB, METHOD_LINE).is_empty(), "spoofed identity never reaches anyone")


func test_a_huge_string_is_cut_to_max_chars() -> void:
	_submit_fresh(ALICE, "a".repeat(_cfg.max_chars * OVERSIZE_FACTOR))
	assert_eq(_accepted.size(), 1)
	if _accepted.is_empty():
		return
	assert_eq((_accepted[0][ChatRules.KEY_TEXT] as String).length(), _cfg.max_chars)


func test_a_line_with_nothing_printable_is_refused() -> void:
	_submit_fresh(ALICE, String.chr(BIDI_OVERRIDE) + " " + String.chr(ZERO_WIDTH_SPACE))
	_submit_fresh(ALICE, "   \n\t ")
	assert_true(_accepted.is_empty())


func test_a_flood_relays_the_burst_and_notifies_the_sender_only_once() -> void:
	for i: int in FLOOD_COUNT:
		_service.on_submit(ALICE, "line %d" % i)
	assert_eq(_accepted.size(), _cfg.burst, "exactly the burst got through")
	var notices: Array[Dictionary] = _sent_to(ALICE, METHOD_NOTICE)
	assert_eq(notices.size(), 1, "throttled to one notice inside the interval")
	if notices.is_empty():
		return
	assert_eq((notices[0]["args"] as Array)[0], ChatRules.NOTICE_RATE)
	assert_true(_sent_to(BOB, METHOD_NOTICE).is_empty(), "the other client hears nothing of it")
	_clock += _cfg.notice_min_interval_s + 0.1
	_service.on_submit(ALICE, "still flooding")
	assert_eq(_sent_to(ALICE, METHOD_NOTICE).size(), 2, "another notice once the interval passed")


func test_honest_chat_at_the_refill_rate_is_never_clipped() -> void:
	var step: float = 1.0 / _cfg.refill_per_s
	for i: int in FLOOD_COUNT:
		_clock += step
		_service.on_submit(ALICE, "honest %d" % i)
	assert_eq(_accepted.size(), FLOOD_COUNT)
	assert_true(_sent_to(ALICE, METHOD_NOTICE).is_empty())


func test_one_peers_flood_does_not_spend_another_peers_bucket() -> void:
	for i: int in FLOOD_COUNT:
		_service.on_submit(ALICE, "line %d" % i)
	_accepted.clear()
	_service.on_submit(BOB, "my turn")
	assert_eq(_accepted.size(), 1)


func test_a_long_idle_refills_to_the_burst_and_no_further() -> void:
	for i: int in FLOOD_COUNT:
		_service.on_submit(ALICE, "first %d" % i)
	_accepted.clear()
	_clock += FAR_STEP_S
	for i: int in FLOOD_COUNT:
		_service.on_submit(ALICE, "second %d" % i)
	assert_eq(_accepted.size(), _cfg.burst)


func test_a_duplicate_inside_the_window_is_refused_with_a_notice_and_allowed_after_it() -> void:
	_clock = START_CLOCK_S
	_service.on_submit(ALICE, "same")
	_clock += _cfg.duplicate_window_s * 0.5
	_service.on_submit(ALICE, "same")
	assert_eq(_accepted.size(), 1, "inside the window")
	var notices: Array[Dictionary] = _sent_to(ALICE, METHOD_NOTICE)
	assert_eq(notices.size(), 1)
	if notices.is_empty():
		return
	assert_eq((notices[0]["args"] as Array)[0], ChatRules.NOTICE_DUPLICATE)
	_service.on_submit(ALICE, "different")
	assert_eq(_accepted.size(), 2, "other text is fine")
	_clock += _cfg.duplicate_window_s + FAR_STEP_S
	_service.on_submit(ALICE, "same")
	assert_eq(_accepted.size(), 3, "after the window")


func test_the_duplicate_filter_is_per_peer() -> void:
	_service.on_submit(ALICE, "same")
	_service.on_submit(BOB, "same")
	assert_eq(_accepted.size(), 2)


func test_history_is_empty_until_a_line_is_published() -> void:
	_service.send_history(ALICE)
	assert_true(_sent.is_empty())


func test_history_sends_the_bounded_ring_once_to_the_newcomer_only() -> void:
	var total: int = _cfg.history_lines + 10
	for i: int in total:
		_submit_fresh(ALICE if i % 2 == 0 else BOB, "msg %d" % i)
	_sent.clear()
	_service.send_history(ALICE)
	var calls: Array[Dictionary] = _sent_to(ALICE, METHOD_HISTORY)
	assert_eq(calls.size(), 1)
	assert_eq(_sent.size(), 1, "nobody else is sent anything")
	if calls.is_empty():
		return
	var lines: Array = (calls[0]["args"] as Array)[0]
	assert_lte(lines.size(), _cfg.history_lines)
	assert_eq(lines.size(), _cfg.history_lines, "a full ring")
	var last_seq: int = -1
	for line: Dictionary in lines:
		assert_gt(int(line[ChatRules.KEY_SEQ]), last_seq, "order kept")
		last_seq = int(line[ChatRules.KEY_SEQ])
	assert_eq((lines.back() as Dictionary)[ChatRules.KEY_TEXT], "msg %d" % (total - 1))


func test_history_is_not_sent_to_a_peer_the_session_cannot_address() -> void:
	_submit_fresh(ALICE, "hello")
	_sent.clear()
	_service.send_history(SPECTATOR)
	assert_true(_sent.is_empty(), "not a send target")
	_chat_host = false
	_service.send_history(ALICE)
	assert_true(_sent.is_empty(), "not the host")


func test_a_system_line_is_stamped_stored_emitted_and_fanned_out() -> void:
	_submit_fresh(ALICE, "first")
	_service.system_line("Bob joined")
	assert_eq(_accepted.size(), 2)
	if _accepted.size() < 2:
		return
	var published: Dictionary = _accepted[1]
	assert_eq(published[ChatRules.KEY_TEXT], "Bob joined")
	assert_eq(published[ChatRules.KEY_KIND], ChatRules.KIND_SYSTEM)
	assert_gt(int(published[ChatRules.KEY_SEQ]), int(_accepted[0][ChatRules.KEY_SEQ]), "stamped after the earlier line")
	for peer_id: int in _targets:
		assert_eq(_sent_to(peer_id, METHOD_LINE).size(), 2)
	_sent.clear()
	_service.send_history(BOB)
	var history_calls: Array[Dictionary] = _sent_to(BOB, METHOD_HISTORY)
	assert_eq(history_calls.size(), 1)
	if history_calls.is_empty():
		return
	var lines: Array = (history_calls[0]["args"] as Array)[0]
	assert_eq(lines.size(), 2, "the system line is in the ring")


# --- Real host and two clients: assertions on Events -------------------------------------

func _make_side(node_name: String) -> Variant:
	var node: Node = _NET_SCRIPT.new()
	node.name = node_name
	var path: NodePath = NodePath(String(get_path()) + "/" + node_name)
	get_tree().set_multiplayer(MultiplayerAPI.create_default_interface(), path)
	add_child_autofree(node)
	return node


func _wait_msec(condition: Callable, msec: int = WAIT_MSEC) -> bool:
	var deadline_msec: int = Time.get_ticks_msec() + msec
	while Time.get_ticks_msec() < deadline_msec:
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()


func _settle() -> void:
	var deadline_msec: int = Time.get_ticks_msec() + SETTLE_MSEC
	while Time.get_ticks_msec() < deadline_msec:
		await get_tree().process_frame


## Hosts and seats `_c1` (and `_c2` when asked). Returns whether everyone was seated.
func _connect(with_second: bool) -> bool:
	_host = _make_side("HostNet")
	_c1 = _make_side("Client1Net")
	_c2 = _make_side("Client2Net")
	var port: int = AgentProbe.free_udp_port()
	_last_port = port
	assert_eq(_host.host_game(port, "Hostie"), OK)
	assert_eq(_c1.join_game("127.0.0.1", port, "Alice"), OK)
	var seated: bool = await _wait_msec(func() -> bool: return _host.peer_ids().size() == 2 and _c1.local_slot() == 1)
	assert_true(seated, "client 1 seated")
	if with_second and seated:
		assert_eq(_c2.join_game("127.0.0.1", port, "Bob"), OK)
		seated = await _wait_msec(func() -> bool: return _host.peer_ids().size() == 3 and _c2.local_slot() == 2)
		assert_true(seated, "client 2 seated")
	await _settle()
	_lines.clear()
	_histories.clear()
	_notices.clear()
	return seated


func _text_lines() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for line: Dictionary in _lines:
		if int(line[ChatRules.KEY_KIND]) == ChatRules.KIND_TEXT:
			out.append(line)
	return out


func test_enet_a_client_line_reaches_every_instance_once_with_roster_identity() -> void:
	assert_true(await _connect(true))
	_c1.send_chat("  hello   there ")
	var arrived: bool = await _wait_msec(func() -> bool: return _text_lines().size() >= INSTANCES)
	assert_true(arrived, "host, sender and the other client all emitted")
	await _settle()
	var texts: Array[Dictionary] = _text_lines()
	assert_eq(texts.size(), INSTANCES, "one emit per Net instance")
	for line: Dictionary in texts:
		assert_eq(line[ChatRules.KEY_TEXT], "hello there")
		assert_eq(line[ChatRules.KEY_NAME], "Alice")
		assert_eq(line[ChatRules.KEY_SLOT], 1)
		assert_eq(line[ChatRules.KEY_PEER], _c1.local_peer_id())
	_c2.send_chat("second")
	await _wait_msec(func() -> bool: return _text_lines().size() >= 2 * INSTANCES)
	var seqs: Array[int] = []
	for line: Dictionary in _lines:
		if not seqs.has(int(line[ChatRules.KEY_SEQ])):
			seqs.append(int(line[ChatRules.KEY_SEQ]))
	for i: int in range(1, seqs.size()):
		assert_gt(seqs[i], seqs[i - 1], "seq is monotonic")


func test_enet_spoofing_payloads_over_the_wire_relay_nothing() -> void:
	assert_true(await _connect(true))
	var spoof: Dictionary = {"peer": _c2.local_peer_id(), "name": "Bob", "text": "I am Bob"}
	_c1._rpc_chat_submit.rpc_id(HOST_ID, spoof)
	_c1._rpc_chat_submit.rpc_id(HOST_ID, 7)
	_c1._rpc_chat_submit.rpc_id(HOST_ID, 1.5)
	await _settle()
	assert_eq(_text_lines().size(), 0)


func test_enet_a_flood_relays_about_a_burst_and_the_sender_gets_one_notice() -> void:
	assert_true(await _connect(true))
	var burst: int = _host.chat_config.burst
	for i: int in FLOOD_COUNT:
		_c1._rpc_chat_submit.rpc_id(HOST_ID, "line %d" % i)
	await _settle()
	var relayed: int = _text_lines().size()
	# The +1 line allows the token the wall clock refills while the test runs.
	assert_gte(relayed, burst * INSTANCES)
	assert_lte(relayed, (burst + 1) * INSTANCES)
	assert_eq(_notices, [ChatRules.NOTICE_RATE] as Array[int], "one throttled rate notice, at the sender only")


func test_enet_a_duplicate_is_relayed_once_and_the_sender_is_told() -> void:
	assert_true(await _connect(false))
	_c1._rpc_chat_submit.rpc_id(HOST_ID, "same")
	_c1._rpc_chat_submit.rpc_id(HOST_ID, "same")
	await _settle()
	assert_eq(_text_lines().size(), 2, "host and the sender, once each")
	assert_eq(_notices, [ChatRules.NOTICE_DUPLICATE] as Array[int])


func test_enet_a_kicked_peer_can_no_longer_chat() -> void:
	assert_true(await _connect(true))
	var kicked: int = _c1.local_peer_id()
	_c1._rpc_chat_submit.rpc_id(HOST_ID, "last words")
	_host.kick_peer(kicked)
	await _settle()
	assert_eq(_text_lines().size(), 0, "a line queued while the kick landed is refused")
	_c2.send_chat("still here")
	var arrived: bool = await _wait_msec(func() -> bool: return _text_lines().size() >= 2)
	assert_true(arrived, "chat keeps working for the others")
	await _settle()
	assert_eq(_text_lines().size(), 2, "host and the remaining client")


func test_enet_a_late_joiner_gets_the_history_once_and_nobody_else_does() -> void:
	assert_true(await _connect(false))
	var texts: Array[String] = ["one", "two", "three"]
	for text: String in texts:
		_c1._rpc_chat_submit.rpc_id(HOST_ID, text)
	await _settle()
	assert_eq(_histories.size(), 0, "an earlier joiner is not re-sent history")
	assert_eq(_c2.join_game("127.0.0.1", _last_port, "Bob"), OK)
	var got: bool = await _wait_msec(func() -> bool: return _histories.size() > 0)
	assert_true(got, "history arrived")
	await _settle()
	assert_eq(_histories.size(), 1, "one history batch, for the newcomer only")
	if _histories.is_empty():
		return
	var lines: Array = _histories[0]
	assert_lte(lines.size(), _host.chat_config.history_lines)
	var last_seq: int = -1
	var seen: Array[String] = []
	for line: Dictionary in lines:
		assert_gt(int(line[ChatRules.KEY_SEQ]), last_seq, "order kept")
		last_seq = int(line[ChatRules.KEY_SEQ])
		seen.append(line[ChatRules.KEY_TEXT])
	for text: String in texts:
		assert_true(seen.has(text), "%s is in the history" % text)


func test_enet_a_client_accepts_host_lines_only_when_they_validate_and_rise() -> void:
	assert_true(await _connect(false))
	var cfg: ChatConfig = _c1.chat_config
	var c1_id: int = _c1.local_peer_id()
	var good: Dictionary = ChatRules.make_line(50, 1, 0, "Hostie", 0, "ok")
	_host._rpc_chat_line.rpc_id(c1_id, good)
	await _wait_msec(func() -> bool: return _lines.size() >= 1)
	assert_eq(_lines.size(), 1, "a valid line from the host")
	_host._rpc_chat_line.rpc_id(c1_id, good)
	_host._rpc_chat_line.rpc_id(c1_id, ChatRules.make_line(49, 1, 0, "H", 0, "old"))
	_host._rpc_chat_line.rpc_id(c1_id, ChatRules.make_line(51, 1, 0, "H", 0, "x".repeat(cfg.max_chars + 1)))
	_host._rpc_chat_line.rpc_id(c1_id, {"seq": 52, "text": "short"})
	var tampered: Dictionary = ChatRules.make_line(53, 1, 0, "H", 0, "evil")
	tampered["extra"] = 1
	_host._rpc_chat_line.rpc_id(c1_id, tampered)
	await _settle()
	assert_eq(_lines.size(), 1, "replayed, older, too long, mis-shaped and padded lines are all dropped")
	_host._rpc_chat_line.rpc_id(c1_id, ChatRules.make_line(60, 1, 0, "H", 0, "next"))
	await _wait_msec(func() -> bool: return _lines.size() >= 2)
	assert_eq(_lines.size(), 2, "a later valid line still goes through")


func test_enet_a_client_refuses_oversize_history_and_unknown_notice_codes() -> void:
	assert_true(await _connect(false))
	var cfg: ChatConfig = _c1.chat_config
	var c1_id: int = _c1.local_peer_id()
	var too_many: Array = []
	for i: int in cfg.history_lines + 1:
		too_many.append(ChatRules.make_line(100 + i, 1, 0, "H", 0, "t"))
	_host._rpc_chat_history.rpc_id(c1_id, too_many)
	_host._rpc_chat_notice.rpc_id(c1_id, 99)
	await _settle()
	assert_eq(_histories.size(), 0, "over history_lines is refused whole")
	assert_eq(_notices.size(), 0, "an unknown notice code is ignored")
	_host._rpc_chat_history.rpc_id(c1_id, [ChatRules.make_line(200, 1, 0, "H", 0, "a"), ChatRules.make_line(201, 1, 0, "H", 0, "b")])
	_host._rpc_chat_notice.rpc_id(c1_id, ChatRules.NOTICE_RATE)
	await _wait_msec(func() -> bool: return _histories.size() >= 1 and _notices.size() >= 1)
	assert_eq(_histories.size(), 1)
	assert_eq(_notices, [ChatRules.NOTICE_RATE] as Array[int])
