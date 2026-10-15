class_name ChatRules
extends RefCounted
## Pure rules for player chat (docs/CHAT_PLAN.md): cleaning a
## typed line, the wire line shape and its client-side check, the host's
## per-peer flood bucket and the history ring. No scene tree, no transport; the
## numbers come from ChatConfig (config/net/chat_config.tres).

const KIND_TEXT: int = 0
const KIND_SYSTEM: int = 1
const NOTICE_RATE: int = 0
const NOTICE_DUPLICATE: int = 1

## Wire keys of a line dictionary.
const KEY_SEQ: String = "seq"
const KEY_PEER: String = "peer"
const KEY_SLOT: String = "slot"
const KEY_NAME: String = "name"
const KEY_COLOR: String = "color"
const KEY_TEXT: String = "text"
const KEY_KIND: String = "kind"
const LINE_KEYS: PackedStringArray = [KEY_SEQ, KEY_PEER, KEY_SLOT, KEY_NAME, KEY_COLOR, KEY_TEXT, KEY_KIND]
const _INT_KEYS: PackedStringArray = [KEY_SEQ, KEY_PEER, KEY_SLOT, KEY_COLOR, KEY_KIND]
const _STRING_KEYS: PackedStringArray = [KEY_NAME, KEY_TEXT]

## Raw characters scanned per allowed character (bounds the cost of a huge
## any_peer string; same idea as PlayerNames.SCAN_FACTOR).
const SCAN_FACTOR: int = 4
const _SPACE: String = " "
const _DOUBLE_SPACE: String = "  "
## Whitespace controls that become one space instead of vanishing.
const _SPACE_LIKE: PackedStringArray = ["\t", "\n", "\r"]
## The lowest slot id a line may carry (-1 is a spectator).
const _MIN_SLOT: int = -1


## `text` cleaned for chat: "" when it is not a String or nothing printable is
## left. Control, bidi and zero-width characters are removed (PlayerNames list),
## tab/newline become a space, runs of spaces collapse, the ends are trimmed and
## the result is cut to `max_chars` code points. Square brackets are kept (the
## log renders plain text, never BBCode).
static func clean(text: Variant, max_chars: int) -> String:
	if typeof(text) != TYPE_STRING:
		return ""
	var limit: int = maxi(max_chars, 1)
	var scan: int = limit * SCAN_FACTOR
	var window: String = (text as String).substr(0, scan)
	for blank: String in _SPACE_LIKE:
		window = window.replace(blank, _SPACE)
	var kept: String = PlayerNames.strip_invisible(window, scan)
	while kept.contains(_DOUBLE_SPACE):
		kept = kept.replace(_DOUBLE_SPACE, _SPACE)
	kept = kept.strip_edges()
	if kept.length() > limit:
		# The cut can leave a ZWJ/ZWNJ hanging off the end: strip_invisible drops a joiner that no
		# longer joins two visible characters.
		kept = PlayerNames.strip_invisible(kept.substr(0, limit), limit).strip_edges()
	return kept


## The wire dictionary for one line (all keys always present).
static func make_line(
	seq: int,
	peer: int,
	slot: int,
	player_name: String,
	color_index: int,
	text: String,
	kind: int = KIND_TEXT
) -> Dictionary:
	return {
		KEY_SEQ: seq,
		KEY_PEER: peer,
		KEY_SLOT: slot,
		KEY_NAME: player_name,
		KEY_COLOR: color_index,
		KEY_TEXT: text,
		KEY_KIND: kind,
	}


## Client-side shape and cap check of a line received from the host: exactly the
## LINE_KEYS, int/String types, text within cfg.max_chars, name within
## `max_name_len`, a known kind. Never trusts the sender.
static func validate_line(line: Variant, cfg: ChatConfig, max_name_len: int) -> bool:
	if typeof(line) != TYPE_DICTIONARY or cfg == null:
		return false
	var dict: Dictionary = line
	if dict.size() != LINE_KEYS.size():
		return false
	for key: String in LINE_KEYS:
		if not dict.has(key):
			return false
	for key: String in _INT_KEYS:
		if typeof(dict[key]) != TYPE_INT:
			return false
	for key: String in _STRING_KEYS:
		if typeof(dict[key]) != TYPE_STRING:
			return false
	# A clean line never holds a control/bidi/zero-width character (the host strips them).
	for key: String in _STRING_KEYS:
		var value: String = dict[key]
		if PlayerNames.strip_invisible(value, value.length()) != value:
			return false
	var kind: int = dict[KEY_KIND]
	if kind != KIND_TEXT and kind != KIND_SYSTEM:
		return false
	if (dict[KEY_TEXT] as String).length() > cfg.max_chars:
		return false
	if (dict[KEY_NAME] as String).length() > maxi(max_name_len, 0):
		return false
	if int(dict[KEY_SEQ]) < 0 or int(dict[KEY_COLOR]) < 0 or int(dict[KEY_SLOT]) < _MIN_SLOT:
		return false
	return true


## Token bucket: starts full at `burst`, refills `refill_per_s` per second.
class Bucket extends RefCounted:
	var _tokens: float = -1.0
	var _last: float = 0.0

	## True (and one token spent) when a line may pass at time `now` seconds.
	func take(now: float, burst: int, refill_per_s: float) -> bool:
		var cap: float = float(maxi(burst, 1))
		if _tokens < 0.0:
			_tokens = cap
		else:
			_tokens = minf(cap, _tokens + maxf(now - _last, 0.0) * maxf(refill_per_s, 0.0))
		_last = now
		if _tokens >= 1.0:
			_tokens -= 1.0
			return true
		return false


## Ring of the most recent lines (oldest dropped first).
class History extends RefCounted:
	var _capacity: int
	var _items: Array[Dictionary] = []

	func _init(capacity: int = 1) -> void:
		_capacity = maxi(capacity, 1)

	func push(line: Dictionary) -> void:
		_items.append(line)
		while _items.size() > _capacity:
			_items.pop_front()

	## Oldest first; a copy.
	func lines() -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		out.append_array(_items)
		return out

	func clear() -> void:
		_items.clear()
