class_name ChatMute
extends RefCounted
## Per-session, client-side chat mute list (docs/CHAT_PLAN.md C5). Pure: no scene
## tree. Muting only hides a player's lines on this machine (the host still relays them); system
## lines are never muted. Keyed by peer id.
## DECISION: peer id, not slot or roster id. A line carries the sender's peer id, and a peer keeps
## its id from the lobby through the match and back, whereas a slot can be re-dealt between rounds.
## The set lives in a static so every chat view (lobby log, HUD log, seat rows, scoreboard) shares
## it; Net._reset_rejoin_state clears it whenever a session starts or ends.

static var _muted: Dictionary = {}


static func is_muted(peer_id: int) -> bool:
	return _muted.has(peer_id)


## Mutes or unmutes `peer_id`. Invalid ids (<= 0, the "no sender" id) are ignored.
static func set_muted(peer_id: int, muted: bool) -> void:
	if peer_id <= 0:
		return
	if muted:
		_muted[peer_id] = true
	else:
		_muted.erase(peer_id)


## Flips the mute of `peer_id`; returns the new state.
static func toggle(peer_id: int) -> bool:
	var now_muted: bool = not is_muted(peer_id)
	set_muted(peer_id, now_muted)
	return is_muted(peer_id)


static func clear() -> void:
	_muted.clear()


## True when `line` (a ChatRules wire dictionary) must be hidden: a TEXT line from a muted peer.
static func hides(line: Dictionary) -> bool:
	if int(line.get(ChatRules.KEY_KIND, ChatRules.KIND_TEXT)) == ChatRules.KIND_SYSTEM:
		return false
	return is_muted(int(line.get(ChatRules.KEY_PEER, -1)))


## `lines` without the muted ones (order kept).
static func filter_lines(lines: Array) -> Array:
	var out: Array = []
	for entry: Variant in lines:
		if entry is Dictionary and hides(entry as Dictionary):
			continue
		out.append(entry)
	return out

