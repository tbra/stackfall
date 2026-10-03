class_name PlayerNames
extends RefCounted
## Pure rules for the name a human player goes by (Bontago-1pi.49): cleaning a
## typed or received name, the "Player N" fallback, and which label a slot shows.
## No scene tree and no transport (CLAUDE.md: rule logic lives in core/); the
## maximum length is NetConfig.max_player_name_length, passed in by the caller.
##
## The host runs sanitize() on every name it is handed (a joiner's handshake, its
## own typed name) before replicating it, so a client can never put control
## characters, an empty string or an oversized string into the roster. The
## menu and Settings run clean() on what the local player types so the host
## normally has nothing left to change.

## "Player %d" with the 1-based seat number: the label an unnamed human seat has
## always had (MatchLifecycle._build_slots), and the host's fallback for an
## empty name.
const FALLBACK_FORMAT: String = "Player %d"
## A joiner with no seat (slot -1, Bontago-8or.11) who sent no name.
const SPECTATOR_FALLBACK: String = "Spectator"

## How many raw characters clean() looks at per allowed name character. A name is
## cut to its maximum length anyway, so a longer string is padding or an attack:
## the host runs this on whatever a joiner's handshake carries (any_peer RPC, no
## size cap), and a multi-megabyte name must cost one cheap substr, not a
## per-character scan. The slack over the maximum lets a real name survive the
## invisible characters that get stripped out of it; anything beyond the window
## is ignored, never scanned.
const SCAN_FACTOR: int = 4

## Code-point ranges removed from a name, as (first, last) inclusive pairs:
## C0 controls (tab, newline, escape ...), DEL and the C1 controls, then the
## characters that print nothing or flip surrounding text and so make a name look
## empty or spoof another: soft hyphen, Arabic letter mark, zero-width space,
## the left/right marks, the line/paragraph separators and bidi embeddings, the
## word joiner / invisible operators / deprecated format controls, Hangul filler,
## braille blank and the byte-order mark. ZWNJ/ZWJ (U+200C/U+200D) are handled
## separately by clean(): scripts and emoji sequences need them between letters.
const _STRIPPED_RANGES: Array[Vector2i] = [
	Vector2i(0x0000, 0x001F),
	Vector2i(0x007F, 0x009F),
	Vector2i(0x00AD, 0x00AD),
	Vector2i(0x061C, 0x061C),
	Vector2i(0x200B, 0x200B),
	Vector2i(0x200E, 0x200F),
	Vector2i(0x2028, 0x202E),
	Vector2i(0x2060, 0x206F),
	Vector2i(0x2800, 0x2800),
	Vector2i(0x3164, 0x3164),
	Vector2i(0xFEFF, 0xFEFF),
]
## Zero-width non-joiner and joiner: kept only between two visible characters.
const _ZWNJ: int = 0x200C
const _ZWJ: int = 0x200D
## The highest code point strip_edges() treats as blank (the space); a joiner next
## to one of these, or at either end of the name, joins nothing.
const _LAST_BLANK: int = 0x20


## The label for an unnamed seat: "Player 1" for slot 0, "Spectator" below it.
static func fallback_for_slot(slot_id: int) -> String:
	if slot_id < 0:
		return SPECTATOR_FALLBACK
	return FALLBACK_FORMAT % (slot_id + 1)


## The number of leading characters of a raw name clean() will look at for a
## limit of `max_length` (see SCAN_FACTOR). Public so a test can prove the bound.
static func scan_limit(max_length: int) -> int:
	return maxi(max_length, 1) * SCAN_FACTOR


## `raw` with control/format characters removed, trimmed, and cut to
## `max_length` characters (a non-positive limit means "one character", never
## "unlimited": the limit is a wire guard). "" when nothing printable remains.
## Only the first scan_limit(max_length) characters of `raw` are examined, so the
## cost is bounded however long the string is. ZWNJ/ZWJ survive only between two
## visible characters.
static func clean(raw: String, max_length: int) -> String:
	var limit: int = maxi(max_length, 1)
	var window: String = raw.substr(0, scan_limit(max_length))
	var codes: PackedInt32Array = PackedInt32Array()
	for index: int in range(window.length()):
		var code: int = window.unicode_at(index)
		if not _is_stripped(code):
			codes.append(code)
	var kept: String = ""
	for index: int in range(codes.size()):
		var code: int = codes[index]
		if _is_joiner(code) and not _joins_visible_characters(codes, index):
			continue
		kept += String.chr(code)
	var trimmed: String = kept.strip_edges()
	if trimmed.length() > limit:
		# The cut can leave a joiner (or space) hanging off the end: drop it.
		trimmed = _trim_trailing_blank_or_joiner(trimmed.substr(0, limit))
	return trimmed


## clean() with the "Player N" (or spectator) fallback when nothing is left.
## This is what the host stores in its roster.
static func sanitize(raw: String, max_length: int, slot_id: int) -> String:
	var cleaned: String = clean(raw, max_length)
	return cleaned if cleaned != "" else fallback_for_slot(slot_id)


## The text a UI shows for `slot`. A bot keeps the slot's own label ("Player N"
## / the bot label the screen adds); a human seat shows the replicated roster
## name when there is one, else whatever the slot already carries, else
## "Player N". `peer_name` is "" when no peer holds the seat.
static func label_for_slot(slot_id: int, slot_display_name: String, is_bot: bool, peer_name: String) -> String:
	if not is_bot and peer_name != "":
		return peer_name
	if slot_display_name != "":
		return slot_display_name
	return fallback_for_slot(slot_id)


static func _is_stripped(code: int) -> bool:
	for span: Vector2i in _STRIPPED_RANGES:
		if code >= span.x and code <= span.y:
			return true
	return false


static func _is_joiner(code: int) -> bool:
	return code == _ZWNJ or code == _ZWJ


## True when the code point before and the one after `codes[index]` (the name with
## the always-stripped characters already removed) are both visible: neither
## missing, nor blank, nor another joiner.
static func _joins_visible_characters(codes: PackedInt32Array, index: int) -> bool:
	if index <= 0 or index >= codes.size() - 1:
		return false
	return _is_visible(codes[index - 1]) and _is_visible(codes[index + 1])


static func _is_visible(code: int) -> bool:
	return code > _LAST_BLANK and not _is_joiner(code)


static func _trim_trailing_blank_or_joiner(text: String) -> String:
	var end: int = text.length()
	while end > 0:
		var code: int = text.unicode_at(end - 1)
		if code > _LAST_BLANK and not _is_joiner(code):
			break
		end -= 1
	return text.substr(0, end)
