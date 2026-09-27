class_name MatchStats
extends RefCounted
## Match's per-slot statistics + the results-screen data/flow interface
## (Bontago-1pi.13, split from Bontago-1pi.6: the results-screen UI worker
## consumes this file's payload and Events.match_results_ready; it does not
## own or edit this file).
##
## Split out the same way MatchFeed/MatchPlacement/MatchTerritory/
## MatchLifecycle/MatchGifts are (docs/AGENT_WORKFLOW.md "file ownership over
## function ownership"): a RefCounted wired to autoload/Match.gd via
## setup(self) in Match's own _ready().
##
## **Host-only collection.** Every counter here only accumulates while
## `_match._is_host()` is true, mirroring every other controller's tick/event
## gate (see MatchGifts.gd's own header: "Host-only logic is gated exactly
## like MatchTerritory's"). A client's own copy of this object exists (its
## local Match runs the same start_match()/_build_slots() calls the host's
## does) but never accumulates: it receives the host's authoritative numbers
## as one payload over Events.match_results_ready, replicated by
## net/MatchNet.gd's single EVENT_MATCH_RESULTS RPC and re-validated by
## validate_results_payload() below before that signal ever reaches a
## client's game code.
##
## **Counters are driven by the existing Events bus, not by new call sites in
## MatchPlacement/MatchGifts** — Events.block_placed/block_removed already
## carry the Block (whose owner_slot identifies the slot) and
## Events.gift_claimed/special_consumed already carry slot_id directly, so
## this file listens for those instead of adding hooks to files another
## package edits concurrently (docs/AGENT_WORKFLOW.md "disjoint file
## ownership"; this package's own brief flagged MatchGifts.gd's expiry logic
## as a concurrent edit to avoid colliding with).
##
## --- Results payload contract (for the results-screen UI worker) ----------
## Events.match_results_ready(results: Dictionary) fires once per match end,
## on the host directly from MatchLifecycle._finish_match() and on every
## client after net/MatchNet.gd's EVENT_MATCH_RESULTS dispatch has validated
## the wire payload with validate_results_payload() below. `results` is
## always shaped:
## ```
## {
##   "winner_kind": "team" | "slot",   # "slot" iff MatchConfig.team_mode ==
##       MatchConfig.TeamMode.OFF (free-for-all: every slot is its own team,
##       see MatchConfig.team_of_slot()) -- the results screen must not
##       always say "Team N wins!" (the reported defect) and should read this
##       field to choose between a player name and a team name.
##   "winner_id": int,                 # the winning team_id; in FFA this is
##       also the winning slot_id (MatchConfig.team_of_slot() is the
##       identity in FFA).
##   "winner_name": String,            # a slot's own display_name in FFA, or
##       "Team %d" % (winner_id + 1) in team mode -- 1-based, matching
##       ui/HUD.gd's existing "Team %d wins!" numbering.
##   "match_duration": float,          # seconds spent in State.PLAYING or
##       State.SUDDEN_DEATH (the two "live" states, MatchLifecycle.
##       is_live_state()) over the whole match, ticked by _tick() below.
##   "rows": Array[Dictionary],        # one entry per slot, in slot_id order:
##     {
##       "slot_id": int,
##       "name": String,               # PlayerSlot.display_name.
##       "team_id": int,               # MatchConfig.team_of_slot(slot_id).
##       "is_bot": bool,
##       "blocks_placed": int,         # Events.block_placed for this slot.
##       "blocks_lost": int,           # Events.block_removed, reason ==
##           Events.REASON_KILL_PLANE, for this slot (spec 3.5's kill plane:
##           "a block fell below tuning.kill_plane_y" -- "off the disc").
##       "gifts_claimed": int,         # Events.gift_claimed for this slot.
##       "specials_used": int,         # Events.special_consumed for this
##           slot (a special actually spent, not merely claimed/queued).
##       "territory_share": float,     # 0..1, this slot's TEAM's final
##           share (MatchTerritory.territory_share(team_id)) -- territory is
##           tracked per team, not per slot, so teammates share one number.
##       "eliminated_at": float,       # seconds into the match this slot's
##           home flag was lost (MatchLifecycle._eliminate_slot()), or
##           NOT_ELIMINATED (-1.0) if it survived to match end.
##     }
## }
## ```
## validate_results_payload(raw: Variant) -> Dictionary rebuilds and
## strictly re-types a wire Dictionary into exactly this shape, or returns an
## empty Dictionary for anything malformed (net/MatchNet.gd's dispatch treats
## an empty return as "drop the packet", the same convention
## _gift_wire_ok()/_pose_is_acceptable() already use there).

const NOT_ELIMINATED: float = -1.0
const WINNER_KIND_SLOT: String = "slot"
const WINNER_KIND_TEAM: String = "team"

var _match: MatchAutoload = null

var _blocks_placed: Array[int] = []
var _blocks_lost: Array[int] = []
var _gifts_claimed: Array[int] = []
var _specials_used: Array[int] = []
var _eliminated_at: Array[float] = []

## Seconds accumulated by _tick() while the match is live (State.PLAYING or
## State.SUDDEN_DEATH). Reset to 0.0 by reset(); read by match_duration() and
## snapshotted into build_results_payload()'s "match_duration" field.
var _elapsed: float = 0.0


func setup(match_ref: MatchAutoload) -> void:
	_match = match_ref
	Events.block_placed.connect(_on_block_placed)
	Events.block_removed.connect(_on_block_removed)
	Events.gift_claimed.connect(_on_gift_claimed)
	Events.special_consumed.connect(_on_special_consumed)
	Events.player_eliminated.connect(_on_player_eliminated)


## Called from MatchLifecycle._reset_match_state(), shared by abort_match()
## and start_match() exactly like MatchGifts.reset() (see that file's own
## call site) -- so a replay or a return-to-lobby can never leak one match's
## numbers into the next.
func reset() -> void:
	_blocks_placed.clear()
	_blocks_lost.clear()
	_gifts_claimed.clear()
	_specials_used.clear()
	_eliminated_at.clear()
	_elapsed = 0.0


## Called from MatchLifecycle._build_slots(), once the new match's slot count
## is known (reset() alone cannot size these: it runs before _build_slots()
## on start_match()'s own call order). Every counter starts at 0 (or
## NOT_ELIMINATED for elimination time), mirroring MatchLifecycle's own
## per-slot array resets in the same function.
func resize_for_slots(slot_count: int) -> void:
	_blocks_placed.resize(slot_count)
	_blocks_lost.resize(slot_count)
	_gifts_claimed.resize(slot_count)
	_specials_used.resize(slot_count)
	_eliminated_at.resize(slot_count)
	for i: int in range(slot_count):
		_blocks_placed[i] = 0
		_blocks_lost[i] = 0
		_gifts_claimed[i] = 0
		_specials_used[i] = 0
		_eliminated_at[i] = NOT_ELIMINATED


## Ticked from Match._process()'s State.PLAYING and State.SUDDEN_DEATH
## branches (mirroring MatchLifecycle._tick_match_timer/_tick_sudden_death's
## own call sites) -- both are "live" states a match can actually be played
## and won from (MatchLifecycle.is_live_state()). A no-op on a client: only
## the host's own _process() reaches either branch at all (Match._process()'s
## `if not _is_host(): return` at its top), so this guard is defense in depth
## rather than the only thing stopping client accumulation.
func _tick(delta: float) -> void:
	if not _match._is_host():
		return
	_elapsed += delta


func match_duration() -> float:
	return _elapsed


func blocks_placed(slot_id: int) -> int:
	return _count_for(_blocks_placed, slot_id)


func blocks_lost(slot_id: int) -> int:
	return _count_for(_blocks_lost, slot_id)


func gifts_claimed(slot_id: int) -> int:
	return _count_for(_gifts_claimed, slot_id)


func specials_used(slot_id: int) -> int:
	return _count_for(_specials_used, slot_id)


## Seconds into the match this slot was eliminated, or NOT_ELIMINATED (-1.0)
## if it never was (including if `slot_id` is out of range).
func eliminated_at(slot_id: int) -> float:
	if slot_id < 0 or slot_id >= _eliminated_at.size():
		return NOT_ELIMINATED
	return _eliminated_at[slot_id]


## Builds the typed results payload documented in this file's own header,
## for `winning_team` (a team_id; in FFA also the winning slot_id -- see
## MatchLifecycle._finish_match()'s own caller, which always passes a team_id
## either way). Called exactly once per match, from
## MatchLifecycle._finish_match(), after _elapsed has stopped advancing (the
## state has already left PLAYING/SUDDEN_DEATH by the time this runs).
func build_results_payload(winning_team: int) -> Dictionary:
	var config: MatchConfig = _match.config
	var ffa: bool = config == null or config.team_mode == MatchConfig.TeamMode.OFF

	var rows: Array[Dictionary] = []
	for slot_id: int in range(_match.slot_count()):
		var slot: PlayerSlot = _match.slot(slot_id)
		if slot == null:
			continue
		var team_id: int = _match.team_of(slot_id)
		rows.append({
			"slot_id": slot_id,
			"name": slot.display_name,
			"team_id": team_id,
			"is_bot": slot.is_bot,
			"blocks_placed": blocks_placed(slot_id),
			"blocks_lost": blocks_lost(slot_id),
			"gifts_claimed": gifts_claimed(slot_id),
			"specials_used": specials_used(slot_id),
			"territory_share": _match.territory_share(team_id),
			"eliminated_at": eliminated_at(slot_id),
		})

	return {
		"winner_kind": WINNER_KIND_SLOT if ffa else WINNER_KIND_TEAM,
		"winner_id": winning_team,
		"winner_name": _winner_name(winning_team, ffa),
		"match_duration": _elapsed,
		"rows": rows,
	}


func _winner_name(winning_team: int, ffa: bool) -> String:
	if ffa:
		var slot: PlayerSlot = _match.slot(winning_team)
		return slot.display_name if slot != null else "Player %d" % (winning_team + 1)
	return "Team %d" % (winning_team + 1)


# --- Wire validation (net/MatchNet.gd EVENT_MATCH_RESULTS dispatch) ---------

## Strictly re-types a wire payload into this file's own results shape, or
## returns an empty Dictionary for anything malformed -- a short/renamed key,
## a wrong-shaped row, a winner_kind outside the two known values, or a
## negative/non-finite duration. Follows net/MatchNet.gd's own
## `_gift_wire_ok()`/`_pose_is_acceptable()` precedent: reject rather than
## default, because a client only ever shows this payload on a results
## screen (never feeds it back into a rule), so there is no safe partial
## value to fall back to the way MatchConfig.from_dict() falls back to a
## field default.
static func validate_results_payload(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var data: Dictionary = raw
	var winner_kind: Variant = data.get("winner_kind")
	if not (winner_kind is String) or (winner_kind != WINNER_KIND_SLOT and winner_kind != WINNER_KIND_TEAM):
		return {}
	var winner_id: Variant = data.get("winner_id")
	if not (winner_id is int or winner_id is float):
		return {}
	var winner_name: Variant = data.get("winner_name")
	if not (winner_name is String):
		return {}
	var duration: Variant = data.get("match_duration")
	if not (duration is int or duration is float) or not is_finite(float(duration)) or float(duration) < 0.0:
		return {}
	var raw_rows: Variant = data.get("rows")
	if not (raw_rows is Array):
		return {}

	var rows: Array[Dictionary] = []
	for raw_row: Variant in (raw_rows as Array):
		var row: Dictionary = _validate_row(raw_row)
		if row.is_empty():
			return {}
		rows.append(row)

	return {
		"winner_kind": String(winner_kind),
		"winner_id": int(winner_id),
		"winner_name": String(winner_name),
		"match_duration": float(duration),
		"rows": rows,
	}


static func _validate_row(raw_row: Variant) -> Dictionary:
	if not (raw_row is Dictionary):
		return {}
	var row: Dictionary = raw_row
	var slot_id: Variant = row.get("slot_id")
	var team_id: Variant = row.get("team_id")
	var name: Variant = row.get("name")
	var is_bot: Variant = row.get("is_bot")
	var placed: Variant = row.get("blocks_placed")
	var lost: Variant = row.get("blocks_lost")
	var gifts: Variant = row.get("gifts_claimed")
	var specials: Variant = row.get("specials_used")
	var share: Variant = row.get("territory_share")
	var eliminated: Variant = row.get("eliminated_at")

	if not (slot_id is int or slot_id is float) or int(slot_id) < 0:
		return {}
	if not (team_id is int or team_id is float):
		return {}
	if not (name is String):
		return {}
	if not (is_bot is bool):
		return {}
	for count: Variant in [placed, lost, gifts, specials]:
		if not (count is int or count is float) or int(count) < 0:
			return {}
	if not (share is int or share is float) or not is_finite(float(share)):
		return {}
	if not (eliminated is int or eliminated is float) or not is_finite(float(eliminated)):
		return {}

	return {
		"slot_id": int(slot_id),
		"name": String(name),
		"team_id": int(team_id),
		"is_bot": bool(is_bot),
		"blocks_placed": int(placed),
		"blocks_lost": int(lost),
		"gifts_claimed": int(gifts),
		"specials_used": int(specials),
		"territory_share": float(share),
		"eliminated_at": float(eliminated),
	}


# --- Event listeners (host only) --------------------------------------------

func _on_block_placed(block: RigidBody3D, _shape_id: StringName) -> void:
	if not _match._is_host():
		return
	var typed: Block = block as Block
	if typed == null:
		return
	_bump(_blocks_placed, typed.owner_slot)


## Spec 3.5's kill plane is the only "off the disc" removal reason that
## exists today (Events.REASON_KILL_PLANE's own doc: "a block fell below
## tuning.kill_plane_y"); a future removal reason (the body-cap dissolve
## spec 3.5 also describes) is deliberately not counted as "lost" here unless
## a later package decides it should be.
func _on_block_removed(block: RigidBody3D, reason: String) -> void:
	if not _match._is_host():
		return
	if reason != String(Events.REASON_KILL_PLANE):
		return
	var typed: Block = block as Block
	if typed == null:
		return
	_bump(_blocks_lost, typed.owner_slot)


func _on_gift_claimed(_gift_id: int, slot_id: int, _special_id: StringName) -> void:
	if not _match._is_host():
		return
	_bump(_gifts_claimed, slot_id)


func _on_special_consumed(slot_id: int, _special_id: StringName) -> void:
	if not _match._is_host():
		return
	_bump(_specials_used, slot_id)


func _on_player_eliminated(slot_id: int, _team_id: int) -> void:
	if not _match._is_host():
		return
	if slot_id < 0 or slot_id >= _eliminated_at.size():
		return
	if _eliminated_at[slot_id] >= 0.0:
		# Already recorded -- MatchLifecycle._eliminate_slot() only fires this
		# once per slot (its own home_flag_alive guard), but a second listener
		# elsewhere re-emitting the same slot must not overwrite an earlier,
		# more accurate elapsed time with a later one.
		return
	_eliminated_at[slot_id] = _elapsed


func _bump(counter: Array[int], slot_id: int) -> void:
	if slot_id < 0 or slot_id >= counter.size():
		return
	counter[slot_id] += 1


func _count_for(counter: Array[int], slot_id: int) -> int:
	if slot_id < 0 or slot_id >= counter.size():
		return 0
	return counter[slot_id]
