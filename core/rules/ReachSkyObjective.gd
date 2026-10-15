class_name ReachSkyObjective
extends ModeObjective
## Reach the Sky (Bontago-22y.9, owner decision Bontago-0tn). Each player's
## record is the highest top of one of their own blocks, measured along the
## disk normal and sampled when that block SETTLES after placement (the
## BlockRegistry sleep rule), so a block balanced for an instant and then
## falling never counts. A record only ever rises: a later collapse cannot
## lower it. The highest team record at the round timer wins; a team's value is
## its best member's or the sum of its members' (sum_members). Ties go to the
## team that reached its final value first. Classic all-goal victory is not
## used. Bontago-1pi.166: the first team whose settled block reaches
## `target_height` wins at once (record_height() latches the winner, which the
## existing mode-objective winner path in MatchTerritory turns into the match
## end); if the timer ends first the highest record wins as above.
##
## DECISION (Bontago-1pi.166, single source of truth): the target is owned by
## NetConfig.build_height_target_m (the same number the network position band is
## derived from, so the band top is always >= target + margin). This pure class
## takes it as a constructor argument; MatchTerritory passes the NetConfig value,
## and the HUD reads the same resource, so host and clients agree. A member's
## own record (not the summed team value) is what must reach the target.
##
## Host-only logic; clients mirror the replicated scores and records
## (replicates_state()). Pure: the registry feeds record_height().

## Heights closer than this are the same height (float noise), so the earlier
## record wins. Not a gameplay tunable.
const TIE_EPSILON: float = 0.001

var _sum_members: bool = false
## Settled height (m) that wins at once; <= 0 disables the early win.
var _target_height: float = 0.0
## Team of each slot (index = slot id); slots past the end belong to nobody.
var _slot_teams: PackedInt32Array = PackedInt32Array()
## Best settled height per slot.
var _records: PackedFloat32Array = PackedFloat32Array()
## Order in which each team reached its current value (smaller = earlier); 0
## while a team has never scored, so untouched teams tie.
var _reached: PackedInt32Array = PackedInt32Array()
var _sequence: int = 0
## State changes replicate at once when the last publication is older than this
## many seconds, else at most once per interval (the final state always goes out
## from on_round_timer_end()).
var _replicate_interval: float = 0.5
var _since_publish: float = 0.0
var _publish_pending: bool = false


func _init(slot_teams: PackedInt32Array = PackedInt32Array(), sum_members: bool = false, replicate_interval: float = 0.5, target_height: float = 0.0) -> void:
	_target_height = target_height
	_slot_teams = slot_teams
	_sum_members = sum_members
	_replicate_interval = maxf(replicate_interval, 0.0)


func mode_id() -> int:
	return MatchConfig.GameMode.REACH_THE_SKY


func is_timed() -> bool:
	return true


func replicates_state() -> bool:
	return true


func reset(team_count: int) -> void:
	super.reset(team_count)
	_records.resize(_slot_teams.size())
	_records.fill(0.0)
	_reached.resize(_scores.size())
	_reached.fill(0)
	_sequence = 0
	_since_publish = _replicate_interval
	_publish_pending = false


func update(_raster: TerritoryRaster, delta: float) -> void:
	_since_publish += maxf(delta, 0.0)
	if _publish_pending and _since_publish >= _replicate_interval:
		_publish_pending = false
		_since_publish = 0.0
		_state_dirty = true


## Host: `slot`'s block just settled with its top `height` meters above the
## disk. Raises that slot's record (never lowers it) and the team value.
func record_height(slot: int, height: float) -> void:
	if slot < 0 or slot >= _slot_teams.size() or not is_finite(height):
		return
	if height <= _records[slot]:
		return
	_records[slot] = height
	var team: int = _slot_teams[slot]
	if team < 0 or team >= _scores.size():
		return
	if _target_height > 0.0 and height >= _target_height:
		_declare_winner(team)
	var value: float = _team_value(team)
	if value > _scores[team]:
		_scores[team] = value
		_sequence += 1
		_reached[team] = _sequence
	if _since_publish >= _replicate_interval:
		_since_publish = 0.0
		_state_dirty = true
	else:
		_publish_pending = true


func target_height() -> float:
	return _target_height


## Highest record wins; the earlier to reach it breaks a tie. A tie that
## remains (nobody built anything) is shared by results_fields().
func on_round_timer_end() -> int:
	_state_dirty = true  # the exact final state always goes out
	var winners: PackedInt32Array = _top_teams()
	return winners[0] if not winners.is_empty() else 0


func extra_state() -> Dictionary:
	var out: Dictionary = {"sum": _sum_members}
	for slot: int in range(_records.size()):
		out["rec_%d" % slot] = _records[slot]
	return out


func apply_extra_state(data: Dictionary) -> void:
	_sum_members = bool(data.get("sum", _sum_members))
	for slot: int in range(_records.size()):
		_records[slot] = float(data.get("rec_%d" % slot, 0.0))


## "winners" lists the winning team id(s) (0-based, comma-separated).
func results_fields() -> Dictionary:
	var ids: PackedStringArray = PackedStringArray()
	if _winner != NO_TEAM:
		return {"winners": str(_winner)}
	for team: int in _top_teams():
		ids.append(str(team))
	return {"winners": ",".join(ids)}


func _team_value(team: int) -> float:
	var best: float = 0.0
	var total: float = 0.0
	for slot: int in range(_slot_teams.size()):
		if _slot_teams[slot] == team:
			best = maxf(best, _records[slot])
			total += _records[slot]
	return total if _sum_members else best


func _top_teams() -> PackedInt32Array:
	var best: float = -INF
	for score: float in _scores:
		best = maxf(best, score)
	var first: int = 0x7fffffff
	for team: int in range(_scores.size()):
		if _scores[team] >= best - TIE_EPSILON:
			first = mini(first, _reached[team])
	var out: PackedInt32Array = PackedInt32Array()
	for team: int in range(_scores.size()):
		if _scores[team] >= best - TIE_EPSILON and _reached[team] == first:
			out.append(team)
	return out
