class_name NetChatService
extends RefCounted
## Chat of the Net autoload. Host: the refusal chain, per-peer flood buckets,
## duplicate filter, history ring and fan-out. Client: accepts lines, history and
## notices only from the host, shape-checked with a rising seq. Every send goes
## through injected Callables, so tests build it directly; it holds no
## MultiplayerAPI and reads no Events. Net subscribes to the signals and re-emits
## them on the bus.

## A line published by the host or accepted from it (Net re-emits it on Events).
signal line_accepted(line: Dictionary)
## A history batch a client accepted (Net re-emits it on Events).
signal history_accepted(lines: Array)
## A refusal notice for the local player (ChatRules.NOTICE_*).
signal notice_accepted(code: int)

## The wire method names the sends address (Net maps each to its RPC).
const METHOD_LINE: StringName = &"chat_line"
const METHOD_HISTORY: StringName = &"chat_history"
const METHOD_NOTICE: StringName = &"chat_notice"
## Peer id of the listen-server host.
const HOST_PEER_ID: int = 1
## Sender id of a host-generated system line.
const SYSTEM_SENDER: int = 0
## Palette index of a system line.
const SYSTEM_COLOR: int = 0


class Seams extends RefCounted:
	## () -> bool : this instance is the host of a non-private session.
	var is_chat_host: Callable = Callable()
	## () -> bool : this instance is a joined client. Optional (false when unset).
	var is_chat_client: Callable = Callable()
	## () -> float : seconds, monotonic.
	var now_s: Callable = Callable()
	## (peer_id: int) -> Dictionary : the roster entry, empty when unknown.
	var peer_info: Callable = Callable()
	## (peer_id: int, method: StringName, args: Array) -> void : one addressed send.
	var send_to_peer: Callable = Callable()
	## () -> Array : the peer ids a send may address.
	var targets: Callable = Callable()
	## (peer_id: int) -> bool : the peer is being disconnected. Optional.
	var is_peer_disconnecting: Callable = Callable()
	## (peer_id: int, slot_id: int) -> int : palette index of the sender. Optional
	## (falls back to the slot).
	var color_of: Callable = Callable()
	## () -> int : the local peer id, whose notices go to notice_accepted. Optional.
	var local_peer_id: Callable = Callable()
	## () -> bool : a match is running (no system lines then). Optional.
	var in_match: Callable = Callable()
	## Longest player name a client accepts in a line.
	var max_name_length: int = PlayerNames.BOT_NAME_MAX_LENGTH


var _config: ChatConfig = null
var _seams: NetChatService.Seams = null
var _buckets: Dictionary = {}
var _last: Dictionary = {}
var _notice_at: Dictionary = {}
var _history: ChatRules.History = null
## Host: sequence number of the next line. Client: highest seq accepted.
var _next_seq: int = 0
var _seen_seq: int = -1


func _init(config: ChatConfig, seams: NetChatService.Seams) -> void:
	_config = config
	_seams = seams


## Host: a chat line from `sender`, refused in this order: not the host or chat
## disabled; a sender not in the roster or being disconnected (spectators may
## chat); the sender's bucket is empty (a throttled notice goes to the sender); a
## non-String payload; nothing printable left; the same text inside the duplicate
## window (notice). Else it is published.
func on_submit(sender: int, payload: Variant) -> void:
	if not _host() or not _config.enabled:
		return
	var entry: Dictionary = _call_dict(_seams.peer_info, sender)
	if entry.is_empty() or _disconnecting(sender):
		return
	var clock: float = _now()
	var bucket: TokenBucket = _buckets.get(sender) as TokenBucket
	if bucket == null:
		bucket = TokenBucket.new()
		_buckets[sender] = bucket
	if not bucket.take(clock, _config.burst, _config.refill_per_s):
		_notify(sender, ChatRules.NOTICE_RATE, clock)
		return
	if typeof(payload) != TYPE_STRING:
		return
	var text: String = ChatRules.clean(payload, _config.max_chars)
	if text == "":
		return
	var previous: Dictionary = _last.get(sender, {})
	if not previous.is_empty() and String(previous["text"]) == text \
			and clock - float(previous["at"]) < _config.duplicate_window_s:
		_notify(sender, ChatRules.NOTICE_DUPLICATE, clock)
		return
	_last[sender] = {"text": text, "at": clock}
	var slot_id: int = int(entry.get(LobbySeats.FIELD_SLOT_ID, -1))
	publish(ChatRules.make_line(
		_take_seq(), sender, slot_id, String(entry.get(LobbySeats.FIELD_NAME, "")),
		_color_of(sender, slot_id), text
	))


## Host: a host-generated system line, lobby only.
func system_line(text: String) -> void:
	if not _host() or not _config.enabled or _in_match():
		return
	var cleaned: String = ChatRules.clean(text, _config.max_chars)
	if cleaned == "":
		return
	publish(ChatRules.make_line(
		_take_seq(), SYSTEM_SENDER, LobbySeats.SPECTATOR_SLOT, "", SYSTEM_COLOR, cleaned,
		ChatRules.KIND_SYSTEM
	))


## Host: the last history_lines lines, to a peer that just joined (not re-broadcast).
func send_history(peer_id: int) -> void:
	if _history == null or not _host() or not _targets().has(peer_id):
		return
	var lines: Array = _history.lines()
	if lines.is_empty():
		return
	_send(peer_id, METHOD_HISTORY, [lines])


## Host: ring, local listeners, then every sendable remote peer.
func publish(line: Dictionary) -> void:
	if _history == null:
		_history = ChatRules.History.new(_config.history_lines)
	_history.push(line)
	line_accepted.emit(line)
	for peer_id: int in _targets():
		_send(peer_id, METHOD_LINE, [line])


## Client: a line from `sender`; only the host's, valid, with a seq above the last.
func accept_line(sender: int, line: Variant) -> bool:
	if not _client() or sender != HOST_PEER_ID:
		return false
	if not ChatRules.validate_line(line, _config, _seams.max_name_length):
		return false
	var dict: Dictionary = line
	var seq: int = dict[ChatRules.KEY_SEQ]
	if seq <= _seen_seq:
		return false
	_seen_seq = seq
	line_accepted.emit(dict)
	return true


## Client: replaces the local log. Host sender only; at most history_lines entries
## (more is refused whole), each valid with strictly rising seq.
func accept_history(sender: int, lines: Variant) -> bool:
	if not _client() or sender != HOST_PEER_ID or typeof(lines) != TYPE_ARRAY:
		return false
	var raw: Array = lines
	if raw.size() > _config.history_lines:
		return false
	var accepted: Array[Dictionary] = []
	var last: int = -1
	for item: Variant in raw:
		if not ChatRules.validate_line(item, _config, _seams.max_name_length):
			return false
		var dict: Dictionary = item
		var seq: int = dict[ChatRules.KEY_SEQ]
		if seq <= last:
			return false
		last = seq
		accepted.append(dict)
	if accepted.is_empty():
		return false
	_seen_seq = maxi(_seen_seq, last)
	history_accepted.emit(accepted)
	return true


## Client: a refusal notice from the host.
func accept_notice(sender: int, code: int) -> bool:
	if not _client() or sender != HOST_PEER_ID:
		return false
	if code != ChatRules.NOTICE_RATE and code != ChatRules.NOTICE_DUPLICATE:
		return false
	notice_accepted.emit(code)
	return true


## A peer left: its flood, duplicate and notice state goes with it.
func forget_peer(peer_id: int) -> void:
	_buckets.erase(peer_id)
	_last.erase(peer_id)
	_notice_at.erase(peer_id)


## Session start/end: everything chat holds.
func reset() -> void:
	_buckets.clear()
	_last.clear()
	_notice_at.clear()
	_history = null
	_next_seq = 0
	_seen_seq = -1


func _take_seq() -> int:
	var seq: int = _next_seq
	_next_seq += 1
	return seq


## Tells `peer_id` why its line was refused, at most once per notice_min_interval_s.
## The host's own refusal goes to notice_accepted.
func _notify(peer_id: int, code: int, clock: float) -> void:
	if _notice_at.has(peer_id) and clock - float(_notice_at[peer_id]) < _config.notice_min_interval_s:
		return
	_notice_at[peer_id] = clock
	if _seams.local_peer_id.is_valid() and peer_id == int(_seams.local_peer_id.call()):
		notice_accepted.emit(code)
	elif _targets().has(peer_id):
		_send(peer_id, METHOD_NOTICE, [code])


func _color_of(peer_id: int, slot_id: int) -> int:
	if _seams.color_of.is_valid():
		return int(_seams.color_of.call(peer_id, slot_id))
	return maxi(slot_id, 0)


func _send(peer_id: int, method: StringName, args: Array) -> void:
	if _seams.send_to_peer.is_valid():
		_seams.send_to_peer.call(peer_id, method, args)


func _targets() -> Array:
	if not _seams.targets.is_valid():
		return []
	return _seams.targets.call() as Array


func _now() -> float:
	return float(_seams.now_s.call()) if _seams.now_s.is_valid() else 0.0


func _host() -> bool:
	return _seams.is_chat_host.is_valid() and bool(_seams.is_chat_host.call())


func _client() -> bool:
	return _seams.is_chat_client.is_valid() and bool(_seams.is_chat_client.call())


func _in_match() -> bool:
	return _seams.in_match.is_valid() and bool(_seams.in_match.call())


func _disconnecting(peer_id: int) -> bool:
	return _seams.is_peer_disconnecting.is_valid() and bool(_seams.is_peer_disconnecting.call(peer_id))


func _call_dict(callable: Callable, peer_id: int) -> Dictionary:
	if not callable.is_valid():
		return {}
	return callable.call(peer_id) as Dictionary
