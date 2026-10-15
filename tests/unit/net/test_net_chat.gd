extends GutTest
## autoload/Net.gd chat relay (Bontago-1pi.192.3, docs/CHAT_PLAN.md sections 2 and 6):
## a real ENet host plus two clients (test_net_session.gd pattern), wall-clock
## deadlines. Each side is its own Net instance; they share the global Events bus,
## so lines are captured through the per-instance chat_line_accepted /
## chat_history_accepted signals.

const _NET_SCRIPT: GDScript = preload("res://autoload/Net.gd")
const _WAIT_MSEC: int = 8000
const _SETTLE_MSEC: int = 400
## Test clock steps (seconds) that clear the duplicate window and refill the bucket.
const _FAR_STEP_S: float = 100.0
const _FLOOD_COUNT: int = 50
const _OVERSIZE_FACTOR: int = 100
const _FAKE_PEER_ID: int = 4242
const _BIDI_OVERRIDE: int = 0x202E
const _ZERO_WIDTH_SPACE: int = 0x200B

var _host: Variant
var _c1: Variant
var _c2: Variant
var _host_lines: Array[Dictionary] = []
var _c1_lines: Array[Dictionary] = []
var _c2_lines: Array[Dictionary] = []
var _c1_history: Array = []
var _c2_history: Array = []
var _notices: Array[int] = []
var _last_port: int = 0


func _make_side(node_name: String) -> Variant:
	var node: Node = _NET_SCRIPT.new()
	node.name = node_name
	var path: NodePath = NodePath(String(get_path()) + "/" + node_name)
	get_tree().set_multiplayer(MultiplayerAPI.create_default_interface(), path)
	add_child_autofree(node)
	return node


func before_each() -> void:
	_host_lines.clear()
	_c1_lines.clear()
	_c2_lines.clear()
	_c1_history.clear()
	_c2_history.clear()
	_notices.clear()
	_host = _make_side("HostNet")
	_c1 = _make_side("Client1Net")
	_c2 = _make_side("Client2Net")
	_host.chat_line_accepted.connect(func(line: Dictionary) -> void: _host_lines.append(line))
	_c1.chat_line_accepted.connect(func(line: Dictionary) -> void: _c1_lines.append(line))
	_c2.chat_line_accepted.connect(func(line: Dictionary) -> void: _c2_lines.append(line))
	_c1.chat_history_accepted.connect(func(lines: Array) -> void: _c1_history.append_array(lines))
	_c2.chat_history_accepted.connect(func(lines: Array) -> void: _c2_history.append_array(lines))
	Events.chat_notice.connect(_on_notice)


func after_each() -> void:
	if Events.chat_notice.is_connected(_on_notice):
		Events.chat_notice.disconnect(_on_notice)
	_c2.leave()
	_c1.leave()
	_host.leave()
	await get_tree().process_frame
	await get_tree().process_frame


func _on_notice(code: int) -> void:
	_notices.append(code)


func _wait_msec(condition: Callable, msec: int = _WAIT_MSEC) -> bool:
	var deadline_msec: int = Time.get_ticks_msec() + msec
	while Time.get_ticks_msec() < deadline_msec:
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()


func _settle() -> void:
	var deadline_msec: int = Time.get_ticks_msec() + _SETTLE_MSEC
	while Time.get_ticks_msec() < deadline_msec:
		await get_tree().process_frame


## Hosts and seats `_c1` (and `_c2` when asked). Returns the port.
func _connect(with_second: bool) -> int:
	var port: int = AgentProbe.free_udp_port()
	_last_port = port
	assert_eq(_host.host_game(port, "Hostie"), OK)
	assert_eq(_c1.join_game("127.0.0.1", port, "Alice"), OK)
	var seated: bool = await _wait_msec(func() -> bool: return _host.peer_ids().size() == 2 and _c1.local_slot() == 1)
	assert_true(seated, "client 1 seated")
	if with_second:
		assert_eq(_c2.join_game("127.0.0.1", port, "Bob"), OK)
		seated = await _wait_msec(func() -> bool: return _host.peer_ids().size() == 3 and _c2.local_slot() == 2)
		assert_true(seated, "client 2 seated")
	return port


static func _text_lines(lines: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for line: Dictionary in lines:
		if int(line[ChatRules.KEY_KIND]) == ChatRules.KIND_TEXT:
			out.append(line)
	return out


func test_client_line_reaches_host_and_other_client_with_roster_identity() -> void:
	await _connect(true)
	_c1.send_chat("  hello   there ")
	var arrived: bool = await _wait_msec(func() -> bool:
		return _text_lines(_host_lines).size() == 1 and _text_lines(_c1_lines).size() == 1 and _text_lines(_c2_lines).size() == 1)
	assert_true(arrived, "host, sender and the other client all got the line")
	if not arrived:
		return
	for lines: Array[Dictionary] in [_host_lines, _c1_lines, _c2_lines]:
		var line: Dictionary = _text_lines(lines)[0]
		assert_eq(line[ChatRules.KEY_TEXT], "hello there")
		assert_eq(line[ChatRules.KEY_NAME], "Alice")
		assert_eq(line[ChatRules.KEY_SLOT], 1)
		assert_eq(line[ChatRules.KEY_PEER], _c1.local_peer_id())
		assert_eq(line[ChatRules.KEY_COLOR], 1, "slot is the colour fallback")
	_c2.send_chat("second")
	await _wait_msec(func() -> bool: return _text_lines(_c1_lines).size() == 2)
	var seqs: Array[int] = []
	for line: Dictionary in _c1_lines:
		seqs.append(int(line[ChatRules.KEY_SEQ]))
	for i: int in range(1, seqs.size()):
		assert_gt(seqs[i], seqs[i - 1], "seq is monotonic")


func test_spoofing_payloads_over_the_wire_are_ignored() -> void:
	await _connect(true)
	var spoof: Dictionary = {"peer": _c2.local_peer_id(), "name": "Bob", "text": "I am Bob"}
	_c1._rpc_chat_submit.rpc_id(1, spoof)
	_c1._rpc_chat_submit.rpc_id(1, 7)
	_c1._rpc_chat_submit.rpc_id(1, 1.5)
	await _settle()
	assert_eq(_text_lines(_host_lines).size(), 0, "non-string payloads relay nothing")
	assert_eq(_text_lines(_c2_lines).size(), 0)


func test_wrong_types_are_dropped_and_huge_string_is_bounded() -> void:
	await _connect(false)
	var sender: int = _c1.local_peer_id()
	var clock: float = 0.0
	for bad: Variant in [7, 1.5, [1, 2], {"text": "x"}, null, true, &"sn", Vector2.ONE]:
		clock += _FAR_STEP_S
		assert_false(_host._handle_chat(sender, bad, true, clock), "type %d refused" % typeof(bad))
	clock += _FAR_STEP_S
	var huge: String = "a".repeat(_host.chat_config.max_chars * _OVERSIZE_FACTOR)
	assert_true(_host._handle_chat(sender, huge, true, clock))
	var text: String = _text_lines(_host_lines)[0][ChatRules.KEY_TEXT]
	assert_eq(text.length(), _host.chat_config.max_chars, "cut to max_chars")
	clock += _FAR_STEP_S
	assert_false(_host._handle_chat(sender, "" + String.chr(_BIDI_OVERRIDE) + " " + String.chr(_ZERO_WIDTH_SPACE), true, clock), "nothing printable left")


func test_unknown_and_disconnecting_peers_cannot_chat() -> void:
	await _connect(false)
	assert_false(_host._handle_chat(_FAKE_PEER_ID, "hi", true, _FAR_STEP_S), "unknown id")
	_host._disconnecting_peers[_c1.local_peer_id()] = true
	assert_false(_host._handle_chat(_c1.local_peer_id(), "hi", true, _FAR_STEP_S), "disconnecting peer")
	assert_eq(_text_lines(_host_lines).size(), 0)


func test_flood_relays_burst_and_notifies_sender_only_throttled() -> void:
	await _connect(true)
	var sender: int = _c1.local_peer_id()
	var relayed: int = 0
	for i: int in _FLOOD_COUNT:
		if _host._handle_chat(sender, "line %d" % i, true, _FAR_STEP_S):
			relayed += 1
	assert_eq(relayed, _host.chat_config.burst)
	var got: bool = await _wait_msec(func() -> bool: return _notices.size() >= 1)
	assert_true(got, "sender got a rate notice")
	await _settle()
	assert_eq(_notices.size(), 1, "throttled to one notice inside the interval, sender only")
	assert_eq(_notices[0], ChatRules.NOTICE_RATE)
	assert_eq(_text_lines(_c2_lines).size(), _host.chat_config.burst, "other client only sees the relayed lines")


func test_duplicate_guard_notifies_and_expires() -> void:
	await _connect(false)
	var sender: int = _c1.local_peer_id()
	assert_true(_host._handle_chat(sender, "same", true, _FAR_STEP_S))
	assert_false(_host._handle_chat(sender, "same", true, _FAR_STEP_S + 1.0), "inside the window")
	var got: bool = await _wait_msec(func() -> bool: return _notices.has(ChatRules.NOTICE_DUPLICATE))
	assert_true(got, "duplicate notice reached the sender")
	assert_true(_host._handle_chat(sender, "same", true, _FAR_STEP_S * 2.0), "after the window")


func test_late_joiner_gets_bounded_history_once() -> void:
	await _connect(false)
	var total: int = _host.chat_config.history_lines + 10
	for i: int in total:
		_host._handle_chat(1, "msg %d" % i, false, float(i + 1) * _FAR_STEP_S)
	assert_eq(_c1_history.size(), 0, "an earlier joiner is not re-sent history")
	var before: int = _c1_lines.size()
	assert_eq(_c2.join_game("127.0.0.1", _last_port, "Bob"), OK)
	var got: bool = await _wait_msec(func() -> bool: return _c2_history.size() > 0)
	assert_true(got, "history arrived")
	assert_lte(_c2_history.size(), _host.chat_config.history_lines)
	var last_seq: int = -1
	for line: Dictionary in _c2_history:
		assert_gt(int(line[ChatRules.KEY_SEQ]), last_seq, "order kept")
		last_seq = int(line[ChatRules.KEY_SEQ])
	assert_eq(_c2_history.back()[ChatRules.KEY_TEXT], "msg %d" % (total - 1))
	assert_eq(_c1_history.size(), 0, "history is not re-broadcast")
	assert_gte(_c1_lines.size(), before, "client 1 only sees the join line")


func test_client_accepts_chat_only_from_the_host_and_revalidates() -> void:
	await _connect(false)
	var cfg: ChatConfig = _c1.chat_config
	var good: Dictionary = ChatRules.make_line(50, 1, 0, "Hostie", 0, "ok")
	assert_false(_c1._accept_chat_line(_FAKE_PEER_ID, good), "non-host sender")
	assert_true(_c1._accept_chat_line(1, good))
	assert_false(_c1._accept_chat_line(1, good), "replayed seq")
	assert_false(_c1._accept_chat_line(1, ChatRules.make_line(49, 1, 0, "H", 0, "old")), "older seq")
	assert_false(_c1._accept_chat_line(1, ChatRules.make_line(51, 1, 0, "H", 0, "x".repeat(cfg.max_chars + 1))), "too long")
	assert_false(_c1._accept_chat_line(1, {"seq": 52, "text": "short"}), "bad shape")
	assert_false(_c1._accept_chat_line(1, 5), "not a dictionary")
	assert_false(_c1._accept_chat_history(_FAKE_PEER_ID, [good]), "history from non-host")
	var too_many: Array = []
	for i: int in cfg.history_lines + 1:
		too_many.append(ChatRules.make_line(100 + i, 1, 0, "H", 0, "t"))
	assert_false(_c1._accept_chat_history(1, too_many), "over history_lines")
	assert_false(_c1._accept_chat_notice(_FAKE_PEER_ID, ChatRules.NOTICE_RATE), "notice from non-host")
	assert_false(_c1._accept_chat_notice(1, 99), "unknown notice code")
	assert_true(_c1._accept_chat_notice(1, ChatRules.NOTICE_RATE))

