class_name LobbySeats
extends RefCounted
## Pure lobby seat model for the lobby rework (Bontago-1pi.53, docs/LOBBY_REWORK_PLAN.md
## section 3). The lobby keeps ONE seat table, next to "roster" in the lobby data:
##
##   { "humans": [ {"peer_id": int, "color": int, "team": int} ],
##     "bots":   [ {"color": int, "team": int, "difficulty": int} ] }
##
## color = index into MatchConfig.default_player_colors() (0-7); team = 0 (Random,
## MatchConfig.TEAM_PICK_RANDOM) or a lobby team number 1..TEAM_PICK_MAX;
## difficulty = MatchConfig.AiDifficulty. Humans are keyed by peer id and bots by
## ordinal, so a join or leave never shifts anyone else's picks. Seat order is
## humans (in the order the caller lists their peers, i.e. slot order) then bots.
##
## No scene tree, no global RNG, no Net: the table is a plain Dictionary so it can
## ride in lobby data, and every rule is a static function over it. Operations that
## edit a table (set_*, cycle_*, add_bot, remove_bot, seed_team_picks,
## apply_human_pref) change it IN PLACE and return whether it changed (false = the
## request was invalid or a no-op, nothing was touched); reconcile() and
## normalize() return a fresh table and never touch their input.
##
## A seat is addressed by a KEY: human_key(peer_id) = the (positive) peer id,
## bot_key(ordinal) = -(ordinal + 1), KEY_NONE (0) = no seat. Bot keys are
## positional: remove_bot() compacts the list, so a later bot's key moves down by
## one and its picks move with it.
##
## DECISION (core/rules/LobbySeats.gd): the palette is MatchConfig.default_player_colors(),
## never config.player_colors, which flatten_to_config() permutes per match. Eight
## seats is the cap (MatchConfig.PLAYER_COUNT_MAX) and the palette has eight
## colours, so colours are unique across seats and a full lobby is always valid.

const KEY_HUMANS: String = "humans"
const KEY_BOTS: String = "bots"
const FIELD_PEER_ID: String = "peer_id"
const FIELD_COLOR: String = "color"
const FIELD_TEAM: String = "team"
const FIELD_DIFFICULTY: String = "difficulty"

## "No seat": never a valid human key (peer ids are positive) nor a bot key (negative).
const KEY_NONE: int = 0
## A table field that reconcile() has to fill in (colour/team/difficulty not chosen yet).
const UNSET: int = -1
## apply_human_pref(): leave this field as it is (the wire value Net.request_seat_pref uses).
const UNCHANGED: int = -1

## Added to the caller's seed before TeamAssigner.resolve(), so the team shuffle never
## repeats the block bag / gift / bot streams that share config.rng_seed
## (repo convention: MatchGifts +999983, BotController RNG_OFFSET).
const TEAM_RNG_OFFSET: int = 555557

## Start-gate reasons from this model (TeamAssigner.BLOCKER_ONE_TEAM is the third).
const BLOCKER_SLOT_CONFLICT: String = "A player's lobby seat clashes with the bot seats. Ask the player to rejoin."
const BLOCKER_TOO_MANY_SEATS: String = "There are more players and bots than seats."

## Largest integer a wire float may carry and still become a peer id / pick.
const _WIRE_INT_LIMIT: float = 2147483647.0


## Where every seat landed in the match slots (layout()). `slot_keys[slot]` is the
## key of the seat in that slot, KEY_NONE for a vacant slot. Humans keep their real
## Net slots, bots take the trailing `ai_count` slots (the formula
## MatchLifecycle._build_slots uses for PlayerSlot.is_bot). `error` is "" or a
## start-blocker reason, in which case the other fields are not meaningful.
class Layout:
	extends RefCounted
	var error: String = ""
	var player_count: int = 0
	var ai_count: int = 0
	var slot_keys: Array[int] = []

	func is_valid() -> bool:
		return error.is_empty()

	## Slot of seat `key`, or -1 (also for KEY_NONE: a vacant slot is not a seat).
	func slot_of(key: int) -> int:
		if key == LobbySeats.KEY_NONE:
			return -1
		return slot_keys.find(key)


# --- Keys, palette -------------------------------------------------------------

static func human_key(peer_id: int) -> int:
	return peer_id


static func bot_key(ordinal: int) -> int:
	return -(ordinal + 1)


static func is_bot_key(key: int) -> bool:
	return key < KEY_NONE


static func bot_ordinal(key: int) -> int:
	return -key - 1


static func palette_size() -> int:
	return MatchConfig.default_player_colors().size()


## The colour of palette index `index` (clamped into the palette).
static func palette_color(index: int) -> Color:
	var palette: PackedColorArray = MatchConfig.default_player_colors()
	return palette[clampi(index, 0, palette.size() - 1)]


# --- Building and reading the table --------------------------------------------

static func empty() -> Dictionary:
	var humans: Array[Dictionary] = []
	var bots: Array[Dictionary] = []
	return {KEY_HUMANS: humans, KEY_BOTS: bots}


## Parses a table that came off the wire (JSON floats, missing keys, junk entries)
## into a well-formed fresh one: typed arrays, ints, at most 8 entries each, peer
## ids positive and unique. A field that is missing or out of range becomes UNSET
## (colour, team, difficulty); it is NOT filled in here, reconcile() does that.
static func normalize(raw: Variant) -> Dictionary:
	var result: Dictionary = empty()
	if typeof(raw) != TYPE_DICTIONARY:
		return result
	var source: Dictionary = raw
	var humans: Array[Dictionary] = []
	var bots: Array[Dictionary] = []
	var seen_peers: Dictionary = {}
	for item: Variant in _array_of(source.get(KEY_HUMANS)):
		var fields: Dictionary = _dict_of(item)
		var peer_id: int = _int_value(fields.get(FIELD_PEER_ID), KEY_NONE)
		if peer_id <= 0 or seen_peers.has(peer_id):
			continue
		if humans.size() >= MatchConfig.PLAYER_COUNT_MAX:
			break
		seen_peers[peer_id] = true
		humans.append({
			FIELD_PEER_ID: peer_id,
			FIELD_COLOR: _color_value(fields),
			FIELD_TEAM: _team_value(fields),
		})
	for item: Variant in _array_of(source.get(KEY_BOTS)):
		if bots.size() >= MatchConfig.PLAYER_COUNT_MAX:
			break
		var fields: Dictionary = _dict_of(item)
		bots.append({
			FIELD_COLOR: _color_value(fields),
			FIELD_TEAM: _team_value(fields),
			FIELD_DIFFICULTY: _difficulty_value(fields),
		})
	result[KEY_HUMANS] = humans
	result[KEY_BOTS] = bots
	return result


## Brings `raw` (the previous table, possibly stale, empty or off the wire) in line
## with the live lobby and returns the result as a new table:
##   * humans = exactly `peer_ids`, in that order (pass the SEATED peers in slot
##     order; spectators have no seat). A peer that stays keeps its picks, a new
##     one gets the lowest free colour and the smaller of teams 1/2, a leaver's
##     entry (and colour) is dropped. At most 8 seats: later peers are not seated.
##   * bots = `ai_count` bots, trimmed to the room humans leave (8 - humans): extra
##     trailing bots are cut, missing ones are new bots at `default_difficulty`;
##     the bots that stay keep their picks.
##   * colours are repaired to be valid and unique (the first seat in table order
##     keeps a contested one), teams are 0..TEAM_PICK_MAX and, while teams are on
##     (`cap` = MatchConfig.team_pick_cap() > 0), clamped to `cap`; with cap 0
##     picks are kept untouched (hidden, "toggle off keeps picks").
## A stale or missing table degrades to the defaults, never an error.
static func reconcile(raw: Variant, peer_ids: PackedInt32Array, ai_count: int, default_difficulty: int, cap: int) -> Dictionary:
	var previous: Dictionary = normalize(raw)
	var humans_by_peer: Dictionary = {}
	for entry: Dictionary in _array_of(previous[KEY_HUMANS]):
		humans_by_peer[int(entry[FIELD_PEER_ID])] = entry

	var humans: Array[Dictionary] = []
	var listed: Dictionary = {}
	for peer_id: int in peer_ids:
		if peer_id <= 0 or listed.has(peer_id):
			continue
		if humans.size() >= MatchConfig.PLAYER_COUNT_MAX:
			break
		listed[peer_id] = true
		if humans_by_peer.has(peer_id):
			var kept: Dictionary = humans_by_peer[peer_id]
			humans.append(kept)
		else:
			humans.append(_new_human(peer_id))

	var difficulty: int = _clamp_difficulty(default_difficulty)
	var bot_total: int = clampi(ai_count, 0, MatchConfig.PLAYER_COUNT_MAX - humans.size())
	var old_bots: Array = _array_of(previous[KEY_BOTS])
	var bots: Array[Dictionary] = []
	for ordinal: int in range(bot_total):
		if ordinal < old_bots.size():
			var kept_bot: Dictionary = old_bots[ordinal]
			bots.append(kept_bot)
		else:
			bots.append(_new_bot(difficulty))

	var result: Dictionary = {KEY_HUMANS: humans, KEY_BOTS: bots}
	_complete(result, difficulty, cap)
	return result


## Seat keys in seat order: humans (table order), then bots by ordinal.
static func seat_keys(seats: Dictionary) -> Array[int]:
	var keys: Array[int] = []
	for entry: Dictionary in _array_of(seats.get(KEY_HUMANS)):
		keys.append(human_key(int(entry.get(FIELD_PEER_ID, KEY_NONE))))
	for ordinal: int in range(_array_of(seats.get(KEY_BOTS)).size()):
		keys.append(bot_key(ordinal))
	return keys


static func seat_count(seats: Dictionary) -> int:
	return human_count(seats) + bot_count(seats)


static func human_count(seats: Dictionary) -> int:
	return _array_of(seats.get(KEY_HUMANS)).size()


static func bot_count(seats: Dictionary) -> int:
	return _array_of(seats.get(KEY_BOTS)).size()


static func has_seat(seats: Dictionary, key: int) -> bool:
	return not _find(seats, key).is_empty()


## Palette index of the seat, UNSET for an unknown key.
static func color_of(seats: Dictionary, key: int) -> int:
	return int(_find(seats, key).get(FIELD_COLOR, UNSET))


## Team pick of the seat (0 = Random, 1..4), UNSET for an unknown key.
static func team_of(seats: Dictionary, key: int) -> int:
	return int(_find(seats, key).get(FIELD_TEAM, UNSET))


## Difficulty of a bot seat, UNSET for a human or an unknown key.
static func difficulty_of(seats: Dictionary, key: int) -> int:
	return int(_find(seats, key).get(FIELD_DIFFICULTY, UNSET))


# --- Edits (host side; each returns true when the table changed) ----------------

## Gives seat `key` palette colour `color_index`. If another seat holds that colour
## the two SWAP, so colours stay unique and a full lobby stays valid.
static func set_color(seats: Dictionary, key: int, color_index: int) -> bool:
	if color_index < 0 or color_index >= palette_size():
		return false
	var entry: Dictionary = _find(seats, key)
	if entry.is_empty():
		return false
	var current: int = entry[FIELD_COLOR]
	if current == color_index:
		return false
	for other: Dictionary in _entries(seats):
		if int(other[FIELD_COLOR]) != color_index:
			continue
		# `current` can only be invalid on a table nobody reconciled; hand the other
		# seat any free colour then.
		other[FIELD_COLOR] = current if current >= 0 else _lowest_free_color(seats)
		break
	entry[FIELD_COLOR] = color_index
	return true


## The next (or previous) palette colour, wrapping, with the same swap rule: what a
## click (right click) on the colour box does.
static func cycle_color(seats: Dictionary, key: int, backwards: bool = false) -> bool:
	var entry: Dictionary = _find(seats, key)
	if entry.is_empty():
		return false
	var step: int = -1 if backwards else 1
	return set_color(seats, key, posmod(int(entry[FIELD_COLOR]) + step, palette_size()))


## Sets the team pick: 0 (Random) or 1..cap. `cap` = MatchConfig.team_pick_cap();
## 0 (teams off) accepts nothing, the default accepts every number the model knows.
## No clamping: an out-of-range pick is refused.
static func set_team(seats: Dictionary, key: int, pick: int, cap: int = MatchConfig.TEAM_PICK_MAX) -> bool:
	if cap <= 0 or pick < MatchConfig.TEAM_PICK_RANDOM or pick > cap:
		return false
	var entry: Dictionary = _find(seats, key)
	if entry.is_empty() or int(entry[FIELD_TEAM]) == pick:
		return false
	entry[FIELD_TEAM] = pick
	return true


## What a click (right click) on the team button does: TeamAssigner.next_pick().
static func cycle_team(seats: Dictionary, key: int, cap: int, backwards: bool = false) -> bool:
	if cap <= 0:
		return false
	var entry: Dictionary = _find(seats, key)
	if entry.is_empty():
		return false
	return set_team(seats, key, TeamAssigner.next_pick(int(entry[FIELD_TEAM]), cap, backwards), cap)


## Bots only (a human has no difficulty); `difficulty` must be a real AiDifficulty.
static func set_difficulty(seats: Dictionary, key: int, difficulty: int) -> bool:
	if not is_bot_key(key):
		return false
	if difficulty < MatchConfig.AiDifficulty.EASY or difficulty > MatchConfig.AiDifficulty.HARD:
		return false
	var entry: Dictionary = _find(seats, key)
	if entry.is_empty() or int(entry[FIELD_DIFFICULTY]) == difficulty:
		return false
	entry[FIELD_DIFFICULTY] = difficulty
	return true


## Appends a bot (lowest free colour, the smaller of teams 1/2, `default_difficulty`)
## and returns its key, or KEY_NONE when all 8 seats are taken.
static func add_bot(seats: Dictionary, default_difficulty: int = MatchConfig.AiDifficulty.NORMAL) -> int:
	if seat_count(seats) >= MatchConfig.PLAYER_COUNT_MAX:
		return KEY_NONE
	_ensure_shape(seats)
	var difficulty: int = _clamp_difficulty(default_difficulty)
	var bots: Array = _array_of(seats[KEY_BOTS])
	bots.append(_new_bot(difficulty))
	_complete(seats, difficulty, 0)
	return bot_key(bots.size() - 1)


## Removes bot `key` and compacts the list: later bots move down one ordinal and keep
## their picks, and the freed colour is free again. Humans cannot be removed here
## (they leave by disconnecting; the next reconcile() drops them).
static func remove_bot(seats: Dictionary, key: int) -> bool:
	if not is_bot_key(key):
		return false
	var bots: Array = _array_of(seats.get(KEY_BOTS))
	var ordinal: int = bot_ordinal(key)
	if ordinal >= bots.size():
		return false
	bots.remove_at(ordinal)
	return true


## What switching Teams on does: every seat, in seat order, gets 1,2,1,2...
## (TeamAssigner.default_picks()). Returns whether any pick changed.
static func seed_team_picks(seats: Dictionary) -> bool:
	var entries: Array[Dictionary] = _entries(seats)
	var picks: PackedInt32Array = TeamAssigner.default_picks(entries.size())
	var changed: bool = false
	for index: int in range(entries.size()):
		if int(entries[index][FIELD_TEAM]) != picks[index]:
			entries[index][FIELD_TEAM] = picks[index]
			changed = true
	return changed


## The validated "a client edits its own seat" request (Net.request_seat_pref ->
## Events.net_seat_pref_requested): `peer_id` must hold a human seat; `color_index`
## and `team_pick` are UNCHANGED (-1) or in range (colour 0..7, team 0..cap with
## teams on). All or nothing: a bad value refuses the whole request, nothing is
## clamped. Returns whether the table changed.
static func apply_human_pref(seats: Dictionary, peer_id: int, color_index: int, team_pick: int, cap: int) -> bool:
	var key: int = human_key(peer_id)
	if peer_id <= 0 or not has_seat(seats, key):
		return false
	if color_index != UNCHANGED and (color_index < 0 or color_index >= palette_size()):
		return false
	if team_pick != UNCHANGED and (cap <= 0 or team_pick < MatchConfig.TEAM_PICK_RANDOM or team_pick > cap):
		return false
	var changed: bool = false
	if color_index != UNCHANGED:
		changed = set_color(seats, key, color_index) or changed
	if team_pick != UNCHANGED:
		changed = set_team(seats, key, team_pick, cap) or changed
	return changed


# --- Slots, start blocker, flatten ----------------------------------------------

## Maps the seats to match slots. `slot_of_peer` = {peer_id: slot_id} from Net (a
## peer missing from it, or with a negative slot, is a spectator and holds no seat);
## an EMPTY dictionary means "no Net": humans take slots 0.. in seat order (tests,
## offline). The slot count is the seated humans + bots, at least
## MatchConfig.PLAYER_COUNT_MIN (the spec 2.8 floor): a lobby with fewer seats keeps
## a vacant slot, exactly as the legacy lobby did. Reports an error instead of a
## layout when there are more than 8 seats or a human's real slot is not below the
## trailing bot slots (two seats in one slot; Net slots never compact, plan R4).
static func layout(seats: Dictionary, slot_of_peer: Dictionary = {}) -> Layout:
	var plan: Layout = Layout.new()
	var data: Dictionary = normalize(seats)
	var seated_keys: Array[int] = []
	var seated_slots: Array[int] = []
	for entry: Dictionary in _array_of(data[KEY_HUMANS]):
		var peer_id: int = entry[FIELD_PEER_ID]
		var slot: int = seated_keys.size()
		if not slot_of_peer.is_empty():
			slot = _int_value(slot_of_peer.get(peer_id), UNSET)
		if slot < 0:
			continue
		seated_keys.append(human_key(peer_id))
		seated_slots.append(slot)
	var bots_total: int = _array_of(data[KEY_BOTS]).size()
	if seated_keys.size() + bots_total > MatchConfig.PLAYER_COUNT_MAX:
		plan.error = BLOCKER_TOO_MANY_SEATS
		return plan
	plan.ai_count = bots_total
	plan.player_count = clampi(seated_keys.size() + bots_total, MatchConfig.PLAYER_COUNT_MIN, MatchConfig.PLAYER_COUNT_MAX)
	var bot_start: int = plan.player_count - bots_total
	plan.slot_keys.resize(plan.player_count)
	plan.slot_keys.fill(KEY_NONE)
	for index: int in range(seated_keys.size()):
		var human_slot: int = seated_slots[index]
		if human_slot >= bot_start or plan.slot_keys[human_slot] != KEY_NONE:
			plan.error = BLOCKER_SLOT_CONFLICT
			return plan
		plan.slot_keys[human_slot] = seated_keys[index]
	for ordinal: int in range(bots_total):
		plan.slot_keys[bot_start + ordinal] = bot_key(ordinal)
	return plan


## Team pick of every slot (size = layout().player_count): the seat's pick, Random
## for a vacant slot. Empty when layout() reports an error.
static func team_picks_by_slot(seats: Dictionary, slot_of_peer: Dictionary = {}) -> PackedInt32Array:
	var data: Dictionary = _prepared(seats, MatchConfig.AiDifficulty.NORMAL, 0)
	var plan: Layout = layout(data, slot_of_peer)
	if not plan.is_valid():
		return PackedInt32Array()
	return _slot_picks(data, plan)


## "" when the lobby may start, else the reason Start must be disabled with: a seat
## layout that cannot become match slots (BLOCKER_*), or teams on (`cap` =
## MatchConfig.team_pick_cap() > 0) with everyone explicitly on one team
## (TeamAssigner.BLOCKER_ONE_TEAM). Same checks flatten_to_config() makes, so a
## green blocker means flatten succeeds.
static func start_blocker(seats: Dictionary, slot_of_peer: Dictionary, cap: int) -> String:
	var data: Dictionary = _prepared(seats, MatchConfig.AiDifficulty.NORMAL, cap)
	var plan: Layout = layout(data, slot_of_peer)
	if not plan.is_valid():
		return plan.error
	if cap <= 0:
		return ""
	return TeamAssigner.blocker(_slot_picks(data, plan), cap)


## The base seed to hand flatten_to_config(): the match seed when one is set, else
## `fresh_seed` (the host's randi(); this file never touches the global RNG).
static func resolve_seed(config: MatchConfig, fresh_seed: int) -> int:
	return config.rng_seed if config.rng_seed >= 0 else fresh_seed


## Writes the seat table into `config` for the match about to start, consistently:
##   * player_count / ai_count from the seats (the same total
##     MatchConfig.clamp_to_connected_peers would reach for the seated humans, so
##     calling that afterwards with the seated-human count changes nothing);
##   * player_colors[slot] = the seat's colour (a permutation of the palette; vacant
##     and unused slots get the leftover colours);
##   * slot_ai_difficulties (size player_count) from the bots; cleared with no bots;
##   * slot_team_ids / team_numbers from TeamAssigner.resolve() when
##     config.team_mode is on (cap = config.team_pick_cap()), cleared when it is OFF.
##     Random resolves with seed `rng_seed + TEAM_RNG_OFFSET`; pass
##     resolve_seed(config, randi()). A vacant slot counts as a Random pick.
## All per-slot arrays have exactly player_count entries, so MatchConfig.sanitize()
## keeps them (it drops team arrays of any other size).
## Returns "" on success, else the start-blocker reason; on failure `config` is NOT
## touched. Call it LAST, after any clamp_to_connected_peers, and do not change
## player_count afterwards.
static func flatten_to_config(seats: Dictionary, slot_of_peer: Dictionary, config: MatchConfig, rng_seed: int) -> String:
	var cap: int = config.team_pick_cap()
	var data: Dictionary = _prepared(seats, config.ai_difficulty, cap)
	var plan: Layout = layout(data, slot_of_peer)
	if not plan.is_valid():
		return plan.error
	var slot_picks: PackedInt32Array = _slot_picks(data, plan)
	var teams: TeamAssigner.Result = null
	if cap > 0:
		var reason: String = TeamAssigner.blocker(slot_picks, cap)
		if not reason.is_empty():
			return reason
		teams = TeamAssigner.resolve(slot_picks, cap, rng_seed + TEAM_RNG_OFFSET)

	# Nothing below can fail: commit.
	config.player_count = plan.player_count
	config.ai_count = plan.ai_count
	config.player_colors = _colors_by_slot(data, plan)
	var difficulties: PackedInt32Array = PackedInt32Array()
	if plan.ai_count > 0:
		var fallback: int = _clamp_difficulty(config.ai_difficulty)
		for key: int in plan.slot_keys:
			difficulties.append(int(_find(data, key).get(FIELD_DIFFICULTY, fallback)) if is_bot_key(key) else fallback)
	config.slot_ai_difficulties = difficulties
	if teams != null:
		config.slot_team_ids = teams.team_ids
		config.team_numbers = teams.team_numbers
	else:
		config.slot_team_ids = PackedInt32Array()
		config.team_numbers = PackedInt32Array()
	return ""


# --- Internals -------------------------------------------------------------------

static func _new_human(peer_id: int) -> Dictionary:
	return {FIELD_PEER_ID: peer_id, FIELD_COLOR: UNSET, FIELD_TEAM: UNSET}


static func _new_bot(difficulty: int) -> Dictionary:
	return {FIELD_COLOR: UNSET, FIELD_TEAM: UNSET, FIELD_DIFFICULTY: difficulty}


static func _clamp_difficulty(difficulty: int) -> int:
	return clampi(difficulty, MatchConfig.AiDifficulty.EASY, MatchConfig.AiDifficulty.HARD)


## normalize + _complete: a copy of `seats` with every field valid.
static func _prepared(seats: Dictionary, default_difficulty: int, cap: int) -> Dictionary:
	var data: Dictionary = normalize(seats)
	_complete(data, _clamp_difficulty(default_difficulty), cap)
	return data


## Fills every UNSET or invalid field in place: colours (valid and unique, the first
## seat in table order keeps a contested one, the rest take the lowest free), team
## picks (clamped to `cap` when > 0; a new seat joins the smaller of teams 1/2, ties
## to team 1, counting picks in seat order) and bot difficulties.
static func _complete(data: Dictionary, default_difficulty: int, cap: int) -> void:
	var entries: Array[Dictionary] = _entries(data)
	var taken: Array[bool] = []
	taken.resize(palette_size())
	taken.fill(false)
	var colorless: Array[Dictionary] = []
	for entry: Dictionary in entries:
		var color: int = entry[FIELD_COLOR]
		if color < 0 or color >= taken.size() or taken[color]:
			colorless.append(entry)
		else:
			taken[color] = true
	for entry: Dictionary in colorless:
		# Never -1 in practice: at most 8 seats share 8 colours.
		var free_color: int = taken.find(false)
		entry[FIELD_COLOR] = free_color
		if free_color >= 0:
			taken[free_color] = true

	var populations: Array[int] = []
	populations.resize(TeamAssigner.DEFAULT_TEAM_COUNT)
	populations.fill(0)
	var unpicked: Array[Dictionary] = []
	for entry: Dictionary in entries:
		var pick: int = entry[FIELD_TEAM]
		if pick < MatchConfig.TEAM_PICK_RANDOM or pick > MatchConfig.TEAM_PICK_MAX:
			unpicked.append(entry)
			continue
		if cap > 0 and pick > cap:
			pick = cap
			entry[FIELD_TEAM] = pick
		if pick >= 1 and pick <= populations.size():
			populations[pick - 1] += 1
	for entry: Dictionary in unpicked:
		var smaller: int = 0
		for index: int in range(1, populations.size()):
			if populations[index] < populations[smaller]:
				smaller = index
		entry[FIELD_TEAM] = smaller + 1
		populations[smaller] += 1

	for entry: Dictionary in _array_of(data.get(KEY_BOTS)):
		var difficulty: int = entry.get(FIELD_DIFFICULTY, UNSET)
		if difficulty < MatchConfig.AiDifficulty.EASY or difficulty > MatchConfig.AiDifficulty.HARD:
			entry[FIELD_DIFFICULTY] = default_difficulty


## Team pick per slot of `plan` (a vacant slot is Random).
static func _slot_picks(data: Dictionary, plan: Layout) -> PackedInt32Array:
	var picks: PackedInt32Array = PackedInt32Array()
	for key: int in plan.slot_keys:
		var pick: int = int(_find(data, key).get(FIELD_TEAM, MatchConfig.TEAM_PICK_RANDOM))
		picks.append(maxi(pick, MatchConfig.TEAM_PICK_RANDOM))
	return picks


## player_colors for the match: the palette colour of the seat in each slot, the
## leftover colours (lowest index first) for vacant slots and slots past player_count.
static func _colors_by_slot(data: Dictionary, plan: Layout) -> PackedColorArray:
	var palette: PackedColorArray = MatchConfig.default_player_colors()
	var taken: Array[bool] = []
	taken.resize(palette.size())
	taken.fill(false)
	var indices: Array[int] = []
	for slot: int in range(MatchConfig.PLAYER_COUNT_MAX):
		var index: int = UNSET
		if slot < plan.slot_keys.size():
			index = int(_find(data, plan.slot_keys[slot]).get(FIELD_COLOR, UNSET))
		if index >= 0 and index < taken.size():
			taken[index] = true
		else:
			index = UNSET
		indices.append(index)
	var colors: PackedColorArray = PackedColorArray()
	for index: int in indices:
		var chosen: int = index
		if chosen == UNSET:
			chosen = maxi(taken.find(false), 0)
			taken[chosen] = true
		colors.append(palette[chosen])
	return colors


## Humans (table order) then bots, as the live entry dictionaries.
static func _entries(data: Dictionary) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for entry: Dictionary in _array_of(data.get(KEY_HUMANS)):
		entries.append(entry)
	for entry: Dictionary in _array_of(data.get(KEY_BOTS)):
		entries.append(entry)
	return entries


## The live entry dictionary of seat `key`, or {} for no such seat.
static func _find(data: Dictionary, key: int) -> Dictionary:
	if key == KEY_NONE:
		return {}
	if not is_bot_key(key):
		for entry: Dictionary in _array_of(data.get(KEY_HUMANS)):
			if int(entry.get(FIELD_PEER_ID, KEY_NONE)) == key:
				return entry
		return {}
	var bots: Array = _array_of(data.get(KEY_BOTS))
	var ordinal: int = bot_ordinal(key)
	if ordinal < bots.size():
		var bot: Dictionary = bots[ordinal]
		return bot
	return {}


static func _lowest_free_color(seats: Dictionary) -> int:
	var taken: Array[bool] = []
	taken.resize(palette_size())
	taken.fill(false)
	for entry: Dictionary in _entries(seats):
		var color: int = entry[FIELD_COLOR]
		if color >= 0 and color < taken.size():
			taken[color] = true
	return maxi(taken.find(false), 0)


## Makes sure both lists exist as arrays (a hand-built table may lack one).
static func _ensure_shape(seats: Dictionary) -> void:
	for list_key: String in [KEY_HUMANS, KEY_BOTS]:
		if typeof(seats.get(list_key)) != TYPE_ARRAY:
			var fresh: Array[Dictionary] = []
			seats[list_key] = fresh


static func _array_of(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		var array: Array = value
		return array
	return []


static func _dict_of(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		var dictionary: Dictionary = value
		return dictionary
	return {}


## An int from the wire: JSON delivers whole numbers as floats; anything else, NaN
## or out of int range gives `fallback`.
static func _int_value(value: Variant, fallback: int) -> int:
	match typeof(value):
		TYPE_INT:
			var whole: int = value
			return whole
		TYPE_FLOAT:
			var number: float = value
			if is_finite(number) and absf(number) <= _WIRE_INT_LIMIT:
				return int(number)
	return fallback


static func _color_value(fields: Dictionary) -> int:
	var color: int = _int_value(fields.get(FIELD_COLOR), UNSET)
	return color if color >= 0 and color < palette_size() else UNSET


static func _team_value(fields: Dictionary) -> int:
	var pick: int = _int_value(fields.get(FIELD_TEAM), UNSET)
	return pick if pick >= MatchConfig.TEAM_PICK_RANDOM and pick <= MatchConfig.TEAM_PICK_MAX else UNSET


static func _difficulty_value(fields: Dictionary) -> int:
	var difficulty: int = _int_value(fields.get(FIELD_DIFFICULTY), UNSET)
	if difficulty < MatchConfig.AiDifficulty.EASY or difficulty > MatchConfig.AiDifficulty.HARD:
		return UNSET
	return difficulty
