class_name CaptureFlagObjective
extends ModeObjective
## Capture the Flag (Bontago-22y.7, owner decision Bontago-pi8). The beacons are
## the goal flags. Each beacon held by a team adds score_rate points per second
## to that team, starting immediately; the highest score at the round timer wins
## and a tie is a shared win. Classic all-goal victory is not used here.
##
## A beacon is held when WinChecker.goal_holder() says so: its base is in a
## final controlled group with an unbroken path to a living allied home. A
## contested, overlapped, holed or unowned beacon scores for nobody.
##
## Scoring is linear in the elapsed time each solve covers, so the total does
## not depend on how coarsely the territory solve is stepped. Host-only: clients
## display the replicated scores (replicates_state()).

## Scores closer than this are a tie (float sums at different step sizes differ
## in the last bits). Not a gameplay tunable.
const TIE_EPSILON: float = 0.001

var _goal_positions: PackedVector2Array = PackedVector2Array()
var _score_rate: float = 1.0
var _claim_radius: float = 0.0
## Beacons held per team at the last update (also replicated, for the HUD).
var _held_counts: PackedInt32Array = PackedInt32Array()
## Float accumulators kept at full precision; _scores only mirrors them.
var _totals: PackedFloat64Array = PackedFloat64Array()
## Score progress is replicated at most this often (seconds); a change in the
## held-beacon set replicates at once.
var _replicate_interval: float = 1.0
var _since_replicate: float = 0.0
var _score_changed: bool = false


func _init(
	goal_positions: PackedVector2Array = PackedVector2Array(), score_rate: float = 1.0, replicate_interval: float = 1.0
) -> void:
	_goal_positions = goal_positions
	_replicate_interval = maxf(replicate_interval, 0.0)
	_score_rate = maxf(score_rate, 0.0)


func set_claim_radius(radius: float) -> void:
	_claim_radius = maxf(radius, 0.0)


func mode_id() -> int:
	return MatchConfig.GameMode.CAPTURE_THE_FLAG


func is_timed() -> bool:
	return true


func replicates_state() -> bool:
	return true


func reset(team_count: int) -> void:
	super.reset(team_count)
	_totals.resize(_scores.size())
	_held_counts.resize(_scores.size())
	for i: int in range(_totals.size()):
		_totals[i] = 0.0
		_held_counts[i] = 0
	_since_replicate = 0.0
	_score_changed = false


func update(raster: TerritoryRaster, delta: float) -> void:
	var counts: PackedInt32Array = PackedInt32Array()
	counts.resize(_scores.size())
	for point: Vector2 in _goal_positions:
		var team: int = WinChecker.goal_holder(raster, point, _claim_radius)
		if team >= 0 and team < counts.size():
			counts[team] += 1
	for team: int in range(counts.size()):
		if counts[team] != _held_counts[team]:
			_held_counts[team] = counts[team]
			_state_dirty = true
		if counts[team] > 0 and delta > 0.0:
			_totals[team] += _score_rate * counts[team] * delta
			# Mirrored without _set_score(): that marks dirty on every solve.
			_scores[team] = _totals[team]
			_score_changed = true
	_since_replicate += maxf(delta, 0.0)
	if _score_changed and _since_replicate >= _replicate_interval:
		_score_changed = false
		_since_replicate = 0.0
		_state_dirty = true


func beacons_held(team: int) -> int:
	return _held_counts[team] if team >= 0 and team < _held_counts.size() else 0


## Highest score wins; ties resolve to the lowest tied team id here, and
## results_fields() reports every tied team as a shared win.
func on_round_timer_end() -> int:
	_state_dirty = true  # the exact final state always goes out
	var winners: PackedInt32Array = _top_teams()
	return winners[0] if not winners.is_empty() else 0


func extra_state() -> Dictionary:
	var out: Dictionary = {"beacons": _goal_positions.size()}
	for team: int in range(_held_counts.size()):
		out["held_%d" % team] = _held_counts[team]
	return out


func apply_extra_state(data: Dictionary) -> void:
	for team: int in range(_held_counts.size()):
		_held_counts[team] = int(data.get("held_%d" % team, 0))


## "winners" lists every top team (comma-separated team ids, 0-based); more
## than one means a shared win.
func results_fields() -> Dictionary:
	var ids: PackedStringArray = PackedStringArray()
	for team: int in _top_teams():
		ids.append(str(team))
	return {"winners": ",".join(ids)}


func _top_teams() -> PackedInt32Array:
	var best: float = -INF
	for total: float in _totals:
		best = maxf(best, total)
	var out: PackedInt32Array = PackedInt32Array()
	for team: int in range(_totals.size()):
		if _totals[team] >= best - TIE_EPSILON:
			out.append(team)
	return out
