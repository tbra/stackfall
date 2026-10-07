class_name ResultsPayload
extends RefCounted
## The one owner of the match-results payload schema (Bontago-fca.36.8, audit
## fca.36 finding [13]; docs/SINGLE_SOURCE_PLAN.md section 2). The payload is
## built by MatchStats.build_results_payload()/build_live_payload(), shipped as
## EVENT_MATCH_RESULTS / the live snapshot (net/MatchNet.gd), re-typed here on
## receipt and read by ResultsScreen, ScoreTable and ScoreboardOverlay.
##
## DECISION (minor): a small core/ class rather than MatchStats, because the
## readers are pure UI/rule helpers that should not depend on an autoload-side
## script, and core/ has no scene-tree dependence (unit-testable). MatchStats
## stays the builder and keeps validate_results_payload() as a thin delegate.
## The wire format and every string value are unchanged.
##
## Shape: {winner_kind, winner_id, winner_name, match_duration, rows[, mode][, live]};
## each row {slot_id, name, team_id, is_bot, blocks_placed, blocks_lost,
## gifts_claimed, specials_used, territory_share, eliminated_at, height,
## peak_territory, wins}; the optional mode block {mode_id, scores[, winners, order, ...]}.

const KEY_WINNER_KIND: String = "winner_kind"
const KEY_WINNER_ID: String = "winner_id"
const KEY_WINNER_NAME: String = "winner_name"
const KEY_MATCH_DURATION: String = "match_duration"
const KEY_ROWS: String = "rows"
const KEY_MODE: String = "mode"
const KEY_LIVE: String = "live"

const KEY_SLOT_ID: String = "slot_id"
const KEY_NAME: String = "name"
const KEY_TEAM_ID: String = "team_id"
const KEY_IS_BOT: String = "is_bot"
const KEY_BLOCKS_PLACED: String = "blocks_placed"
const KEY_BLOCKS_LOST: String = "blocks_lost"
const KEY_GIFTS_CLAIMED: String = "gifts_claimed"
const KEY_SPECIALS_USED: String = "specials_used"
const KEY_TERRITORY_SHARE: String = "territory_share"
const KEY_ELIMINATED_AT: String = "eliminated_at"
const KEY_HEIGHT: String = "height"
const KEY_PEAK_TERRITORY: String = "peak_territory"
const KEY_WINS: String = "wins"
## Client-side only (ResultsScreen.sorted_rows() adds it to a row copy); never on the wire.
const KEY_IS_WINNER: String = "is_winner"

const KEY_MODE_ID: String = "mode_id"
const KEY_SCORES: String = "scores"
const KEY_WINNERS: String = "winners"
const KEY_ORDER: String = "order"

const WINNER_KIND_SLOT: String = "slot"
const WINNER_KIND_TEAM: String = "team"
const NOT_ELIMINATED: float = -1.0


# --- Typed accessors (defaults mirror what the readers always used) ----------

static func int_of(dict: Dictionary, key: String, default: int = 0) -> int:
	return int(dict.get(key, default))


static func float_of(dict: Dictionary, key: String, default: float = 0.0) -> float:
	return float(dict.get(key, default))


static func bool_of(dict: Dictionary, key: String, default: bool = false) -> bool:
	return bool(dict.get(key, default))


static func string_of(dict: Dictionary, key: String, default: String = "") -> String:
	return String(dict.get(key, default))


static func winner_id(results: Dictionary) -> int:
	return int_of(results, KEY_WINNER_ID, -1)


static func winner_name(results: Dictionary) -> String:
	return string_of(results, KEY_WINNER_NAME)


static func winner_kind(results: Dictionary) -> String:
	return string_of(results, KEY_WINNER_KIND, WINNER_KIND_SLOT)


static func is_live(results: Dictionary) -> bool:
	return bool_of(results, KEY_LIVE)


static func rows(results: Dictionary) -> Array:
	return results.get(KEY_ROWS, []) as Array


## The optional mode block, or {} when the payload has none (classic).
static func mode_block(results: Dictionary) -> Dictionary:
	var block: Variant = results.get(KEY_MODE)
	if block is Dictionary:
		return block
	return {}


static func has_mode_block(results: Dictionary) -> bool:
	return results.get(KEY_MODE) is Dictionary


static func mode_id(results: Dictionary) -> int:
	return int_of(mode_block(results), KEY_MODE_ID, MatchConfig.GameMode.CLASSIC)


static func mode_scores(results: Dictionary) -> Array:
	return mode_block(results).get(KEY_SCORES, []) as Array


## The mode block's comma-separated winners ("0,2") split into id texts; empty when absent.
static func mode_winner_texts(results: Dictionary) -> PackedStringArray:
	return string_of(mode_block(results), KEY_WINNERS).split(",", false)


# --- The single validator (host build and client receipt) --------------------

## Strictly re-types a wire payload into this schema, or returns an empty
## Dictionary for anything malformed -- a short/renamed key, a wrong-shaped
## row, a winner_kind outside the two known values, or a negative/non-finite
## duration. Follows net/MatchNet.gd's `_gift_wire_ok()`/`_pose_is_acceptable()`
## precedent: reject rather than default, because a client only shows this
## payload on a results screen (never feeds it back into a rule).
static func validate(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var data: Dictionary = raw
	var kind: Variant = data.get(KEY_WINNER_KIND)
	if not (kind is String) or (kind != WINNER_KIND_SLOT and kind != WINNER_KIND_TEAM):
		return {}
	var win_id: Variant = data.get(KEY_WINNER_ID)
	if not (win_id is int or win_id is float):
		return {}
	var win_name: Variant = data.get(KEY_WINNER_NAME)
	if not (win_name is String):
		return {}
	var duration: Variant = data.get(KEY_MATCH_DURATION)
	if not (duration is int or duration is float) or not is_finite(float(duration)) or float(duration) < 0.0:
		return {}
	var raw_rows: Variant = data.get(KEY_ROWS)
	if not (raw_rows is Array):
		return {}

	var clean_rows: Array[Dictionary] = []
	for raw_row: Variant in (raw_rows as Array):
		var row: Dictionary = _validate_row(raw_row)
		if row.is_empty():
			return {}
		clean_rows.append(row)

	var validated: Dictionary = {
		KEY_WINNER_KIND: String(kind),
		KEY_WINNER_ID: int(win_id),
		KEY_WINNER_NAME: String(win_name),
		KEY_MATCH_DURATION: float(duration),
		KEY_ROWS: clean_rows,
	}
	if data.has(KEY_MODE):
		var block: Dictionary = validate_mode_block(data[KEY_MODE])
		if block.is_empty():
			return {}
		validated[KEY_MODE] = block
	return validated


## The results "mode" block: mode_id a known GameMode, scores a bounded array of
## finite numbers, every other key a scalar (ModeObjective owns the shared
## scalar/score helpers, which the live mode state uses too).
static func validate_mode_block(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var data: Dictionary = raw
	var mode: Variant = data.get(KEY_MODE_ID)
	if not (mode is int or mode is float) or not ModeObjective.is_known_mode(int(mode)):
		return {}
	var scores: Array = ModeObjective.clean_scores(data.get(KEY_SCORES))
	if scores.size() == 1 and scores[0] == null:
		return {}
	var rest: Dictionary = data.duplicate()
	rest.erase(KEY_MODE_ID)
	rest.erase(KEY_SCORES)
	var cleaned: Variant = ModeObjective.clean_scalars(rest)
	if cleaned == null:
		return {}
	var out: Dictionary = cleaned
	out[KEY_MODE_ID] = int(mode)
	out[KEY_SCORES] = scores
	return out


static func _validate_row(raw_row: Variant) -> Dictionary:
	if not (raw_row is Dictionary):
		return {}
	var row: Dictionary = raw_row
	var slot_id: Variant = row.get(KEY_SLOT_ID)
	var team_id: Variant = row.get(KEY_TEAM_ID)
	var row_name: Variant = row.get(KEY_NAME)
	var is_bot: Variant = row.get(KEY_IS_BOT)
	var placed: Variant = row.get(KEY_BLOCKS_PLACED)
	var lost: Variant = row.get(KEY_BLOCKS_LOST)
	var gifts: Variant = row.get(KEY_GIFTS_CLAIMED)
	var specials: Variant = row.get(KEY_SPECIALS_USED)
	var share: Variant = row.get(KEY_TERRITORY_SHARE)
	var eliminated: Variant = row.get(KEY_ELIMINATED_AT)
	# Bontago-1pi.72.2: optional (an older payload lacks them) but typed when present.
	var height: Variant = row.get(KEY_HEIGHT, 0.0)
	var peak: Variant = row.get(KEY_PEAK_TERRITORY, 0.0)
	var wins: Variant = row.get(KEY_WINS, 0)

	if not (slot_id is int or slot_id is float) or int(slot_id) < 0:
		return {}
	if not (team_id is int or team_id is float):
		return {}
	if not (row_name is String):
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
	for amount: Variant in [height, peak]:
		if not (amount is int or amount is float) or not is_finite(float(amount)) or float(amount) < 0.0:
			return {}
	if not (wins is int or wins is float) or int(wins) < 0:
		return {}

	return {
		KEY_SLOT_ID: int(slot_id),
		KEY_NAME: String(row_name),
		KEY_TEAM_ID: int(team_id),
		KEY_IS_BOT: bool(is_bot),
		KEY_BLOCKS_PLACED: int(placed),
		KEY_BLOCKS_LOST: int(lost),
		KEY_GIFTS_CLAIMED: int(gifts),
		KEY_SPECIALS_USED: int(specials),
		KEY_TERRITORY_SHARE: float(share),
		KEY_ELIMINATED_AT: float(eliminated),
		KEY_HEIGHT: float(height),
		KEY_PEAK_TERRITORY: float(peak),
		KEY_WINS: int(wins),
	}
