class_name EliminationObjective
extends ModeObjective
## Elimination (Bontago-22y.8, owner decision Bontago-fim). The existing home
## triggers (MatchTerritory._check_home_flags / _check_home_flags_v2) are reused
## unchanged: a slot is out when its home flag is lost. This objective only
## decides what that means for the match:
##  - classic all-goal victory is not used (update() never declares a winner);
##  - the last team with a living player wins;
##  - when the eliminations of ONE batch (one territory step) leave nobody
##    alive, the teams that just went out are compared by territory share: the
##    larger share wins and equal shares are a shared win (winners);
##  - the round timer is optional (round_timer_minutes 0 = off); when it expires
##    the surviving teams are ranked by territory share, highest wins, equal
##    shares share the win.
## _scores holds each team's living player count (0 = out).
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


func _init(slot_teams: PackedInt32Array = PackedInt32Array()) -> void:
	_slot_teams = slot_teams


func mode_id() -> int:
	return MatchConfig.GameMode.ELIMINATION


## Timed through round_timer_minutes; 0 minutes arms nothing, so the match runs
## until one team is left.
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
## decided (winners() lists all of them), else NO_TEAM.
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


## Slot ids in elimination order (first out first).
func elimination_order() -> PackedInt32Array:
	return _order.duplicate()


func winners() -> PackedInt32Array:
	return _winners.duplicate()


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
