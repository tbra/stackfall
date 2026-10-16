class_name EliminationObjective
extends ModeObjective
## Elimination. The existing home
## triggers (MatchTerritory._check_home_flags / _check_home_flags_v2) are reused
## unchanged: a slot is out when its home flag is lost. This objective only
## decides what that means for the match:
##  - classic all-goal victory is not used (update() never declares a winner);
##  - the last team with a living player wins;
##  - when the eliminations of ONE batch (one territory step) leave nobody
##    alive, the teams that just went out are compared by territory share: the
##    larger share wins and equal shares are a shared win (results_fields "winners");
##  - the round timer is optional (round_timer_minutes 0 = off); when it expires
##    the surviving teams are ranked by territory share, highest wins, equal
##    shares share the win.
## _scores holds each team's living player count (0 = out).
## [OWNER decision] A home flag is only knocked out
## after the attacker has kept the pressure on it continuously for the claim
## time (TerritoryTuning.capture_hold, the goal-beacon claim duration). The
## per-slot claim timers live here (pure); MatchTerritory feeds the pressure.
##
## Host-only logic; clients mirror the replicated state (replicates_state()).
## Pure: MatchLifecycle feeds slot_eliminated() and resolve().

## Shares closer than this are equal (float noise). Not a gameplay tunable.
const TIE_EPSILON: float = 0.0001

var _slot_teams: PackedInt32Array = PackedInt32Array()
## Slot ids in the order they were eliminated.
var _order: PackedInt32Array = PackedInt32Array()
## Teams whose last living player went out since the last resolve().
var _pending_teams: PackedInt32Array = PackedInt32Array()
var _out: Dictionary = {}
## Latest territory shares per team (update(), resolve()).
var _shares: PackedFloat32Array = PackedFloat32Array()
## Every winning team once the round is decided (more than one = shared win).
var _winners: PackedInt32Array = PackedInt32Array()
## Claim time in seconds (<= 0 = instant knockout).
var _claim_hold: float = 0.0
## Seconds of claim progress lost per second while the pressure has lapsed
## (<= 0 = the old instant reset). [OWNER decision b]
var _claim_decay_rate: float = 0.0
## slot -> seconds the current attacker has held its home flag.
var _claim_held: Dictionary = {}
## slot -> attacker team id (NO_TEAM when the pressure has no single owner).
var _claim_team: Dictionary = {}
## slot -> team that completed the knockout (NO_TEAM = unknown).
var _eliminator_team: Dictionary = {}


func _init(slot_teams: PackedInt32Array = PackedInt32Array(), claim_hold: float = 0.0, claim_decay_rate: float = 0.0) -> void:
	_slot_teams = slot_teams
	_claim_hold = maxf(claim_hold, 0.0)
	_claim_decay_rate = maxf(claim_decay_rate, 0.0)


func mode_id() -> int:
	return MatchConfig.GameMode.ELIMINATION


func is_timed() -> bool:
	return true


func replicates_state() -> bool:
	return true


func reset(team_count: int) -> void:
	super.reset(team_count)
	_order.clear()
	_pending_teams.clear()
	_out.clear()
	_winners.clear()
	_claim_held.clear()
	_claim_team.clear()
	_eliminator_team.clear()
	_shares.resize(_scores.size())
	_shares.fill(0.0)
	for slot: int in range(_slot_teams.size()):
		var team: int = _slot_teams[slot]
		if team >= 0 and team < _scores.size():
			_scores[team] += 1.0


func update(raster: TerritoryRaster, _delta: float) -> void:
	if raster == null:
		return
	for team: int in range(_shares.size()):
		_shares[team] = raster.team_share(team)


## Host: advances every home-flag claim by `delta`. `pressure` maps each slot
## whose home flag is currently under attack to the attacking team id
## (NO_TEAM when unknown). [OWNER decision b] A slot
## missing from `pressure` keeps its claim and FADES by claim_decay_rate seconds
## per second (removed at 0) instead of resetting, so brief lapses (temporary
## holes) do not undo it; resumed pressure from the same attacker continues from
## the faded value. A different attacker restarts at 0. Returns the slots whose
## claim just completed; the caller eliminates them.
func step_claims(pressure: Dictionary, delta: float) -> PackedInt32Array:
	var done: PackedInt32Array = PackedInt32Array()
	for slot_key: Variant in _claim_held.keys():
		if pressure.has(slot_key):
			continue
		var faded: float = float(_claim_held[slot_key]) - _claim_decay_rate * maxf(delta, 0.0)
		if _claim_decay_rate > 0.0 and faded > 0.0 and not _out.has(int(slot_key)):
			_claim_held[slot_key] = faded
		else:
			_claim_held.erase(slot_key)
			_claim_team.erase(slot_key)
	var slots: Array = pressure.keys()
	slots.sort()
	for slot_key: Variant in slots:
		var slot: int = int(slot_key)
		if _out.has(slot):
			continue
		var attacker: int = int(pressure[slot_key])
		if not _claim_held.has(slot) or int(_claim_team.get(slot, NO_TEAM)) != attacker:
			_claim_held[slot] = 0.0
			_claim_team[slot] = attacker
		_claim_held[slot] = float(_claim_held[slot]) + delta
		if _claim_hold <= 0.0 or float(_claim_held[slot]) >= _claim_hold or is_equal_approx(float(_claim_held[slot]), _claim_hold):
			_eliminator_team[slot] = attacker
			_claim_held.erase(slot)
			_claim_team.erase(slot)
			done.append(slot)
	return done


## The team that knocked `slot` out, or NO_TEAM when unknown.
func eliminator_team(slot: int) -> int:
	return int(_eliminator_team.get(slot, NO_TEAM))


## The slot whose claim is furthest along (-1 when none).
func leading_claim_slot() -> int:
	var best: int = -1
	var best_held: float = 0.0
	for slot_key: Variant in _claim_held:
		var held: float = float(_claim_held[slot_key])
		if held > best_held or (held == best_held and best >= 0 and int(slot_key) < best):
			best = int(slot_key)
			best_held = held
	return best


## HUD ring feed: the attacking team and progress of the furthest claim.
## DECISION: a pressure with no owning team (a hole under the
## flag in the overlap modes) has no attacker colour, so the ring is drawn in the
## victim's team colour; the knockout is then attributed to nobody ("Eliminated").
func capturing_team() -> int:
	var slot: int = leading_claim_slot()
	if slot < 0:
		return NO_TEAM
	var attacker: int = int(_claim_team.get(slot, NO_TEAM))
	if attacker == NO_TEAM and slot < _slot_teams.size():
		return _slot_teams[slot]
	return attacker


func capture_progress() -> float:
	var slot: int = leading_claim_slot()
	if slot < 0 or _claim_hold <= 0.0:
		return 0.0
	return clampf(float(_claim_held[slot]) / _claim_hold, 0.0, 1.0)


## Host: `slot`'s home flag was lost. Idempotent. The match outcome is only
## evaluated by resolve(), so eliminations of one batch are judged together.
func slot_eliminated(slot: int) -> void:
	if slot < 0 or slot >= _slot_teams.size() or _out.has(slot):
		return
	_out[slot] = true
	_order.append(slot)
	var team: int = _slot_teams[slot]
	if team >= 0 and team < _scores.size():
		_set_score(team, _scores[team] - 1.0)
		if _scores[team] <= 0.0:
			_pending_teams.append(team)
	_state_dirty = true


## Host, after a batch of eliminations (a no-op without news). `shares` is the
## current territory share per team. Returns the winning team once the match is
## decided (results_fields "winners" lists all of them), else NO_TEAM.
func resolve(shares: PackedFloat32Array) -> int:
	if _pending_teams.is_empty() or _winner != NO_TEAM:
		return _winner
	for team: int in range(mini(shares.size(), _shares.size())):
		_shares[team] = shares[team]
	var alive: PackedInt32Array = surviving_teams()
	var pending: PackedInt32Array = _pending_teams
	_pending_teams = PackedInt32Array()
	if alive.size() == 1:
		_end_with(alive)
	elif alive.is_empty():
		_end_with(_top_by_share(pending))
	return _winner


## Teams that still have a living player.
func surviving_teams() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for team: int in range(_scores.size()):
		if _scores[team] > 0.0:
			out.append(team)
	return out


## Timer expiry: the surviving teams ranked by territory share; the highest
## wins and equal shares share the win.
func on_round_timer_end() -> int:
	_state_dirty = true
	var alive: PackedInt32Array = surviving_teams()
	if alive.is_empty():
		alive = _all_teams()
	_winners = _top_by_share(alive)
	return _winners[0] if not _winners.is_empty() else 0


func is_slot_out(slot: int) -> bool:
	return _out.has(slot)


## Out slots as a bitmask, so a reconnecting or late client can mirror who is
## out; the order itself reaches clients in the results payload.
func extra_state() -> Dictionary:
	var mask: int = 0
	for slot: Variant in _out:
		mask |= 1 << int(slot)
	return {"out_mask": mask}


func apply_extra_state(data: Dictionary) -> void:
	var mask: int = int(data.get("out_mask", 0))
	_out.clear()
	for slot: int in range(_slot_teams.size()):
		if mask & (1 << slot) != 0:
			_out[slot] = true


## "winners" lists the winning team id(s) (0-based, comma-separated); "order"
## the slot ids in elimination order.
func results_fields() -> Dictionary:
	var winner_ids: PackedStringArray = PackedStringArray()
	for team: int in _winners:
		winner_ids.append(str(team))
	var order_ids: PackedStringArray = PackedStringArray()
	for slot: int in _order:
		order_ids.append(str(slot))
	return {"winners": ",".join(winner_ids), "order": ",".join(order_ids)}


func _end_with(teams: PackedInt32Array) -> void:
	_winners = teams
	_state_dirty = true
	if not teams.is_empty():
		_declare_winner(teams[0])


func _all_teams() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for team: int in range(_scores.size()):
		out.append(team)
	return out


func _top_by_share(teams: PackedInt32Array) -> PackedInt32Array:
	var best: float = -INF
	for team: int in teams:
		best = maxf(best, _share_of(team))
	var out: PackedInt32Array = PackedInt32Array()
	for team: int in teams:
		if _share_of(team) >= best - TIE_EPSILON:
			out.append(team)
	return out


func _share_of(team: int) -> float:
	return _shares[team] if team >= 0 and team < _shares.size() else 0.0
