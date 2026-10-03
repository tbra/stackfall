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

## Code-point ranges removed from a name, as (first, last) inclusive pairs:
## C0 controls (tab, newline, escape ...), DEL and the C1 controls, then the
## zero-width and bidirectional formatting characters that make a name look
## empty or flip surrounding text, and the Unicode line/paragraph separators.
const _STRIPPED_RANGES: Array[Vector2i] = [
	Vector2i(0x0000, 0x001F),
	Vector2i(0x007F, 0x009F),
	Vector2i(0x200B, 0x200F),
	Vector2i(0x2028, 0x202E),
	Vector2i(0x2060, 0x2064),
	Vector2i(0x2066, 0x2069),
	Vector2i(0xFEFF, 0xFEFF),
]


## The label for an unnamed seat: "Player 1" for slot 0, "Spectator" below it.
static func fallback_for_slot(slot_id: int) -> String:
	if slot_id < 0:
		return SPECTATOR_FALLBACK
	return FALLBACK_FORMAT % (slot_id + 1)


## `raw` with control/format characters removed, trimmed, and cut to
## `max_length` characters (a non-positive limit means "one character", never
## "unlimited": the limit is a wire guard). "" when nothing printable remains.
static func clean(raw: String, max_length: int) -> String:
	var kept: String = ""
	for index: int in range(raw.length()):
		if not _is_stripped(raw.unicode_at(index)):
			kept += raw[index]
	var trimmed: String = kept.strip_edges()
	if trimmed.length() > maxi(max_length, 1):
		trimmed = trimmed.substr(0, maxi(max_length, 1)).strip_edges()
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
