class_name ModeObjective
extends RefCounted
## What decides a match (Bontago-22y.11). One objective is active per match;
## MatchTerritory feeds it every territory solve and MatchLifecycle asks it
## about the round timer, so neither hard-codes the classic all-goal hold.
##
## Authority: only the HOST calls update()/on_round_timer_end() and reads
## winner(). Clients never decide an outcome: they receive mode_state() through
## net/MatchNet.gd and mirror it with apply_mode_state() for display only.
##
## Pure logic: no scene tree (CLAUDE.md). Subclasses override the hooks below;
## the base class is a no-score, never-ending objective, which is also what a
## test stub extends.

const NO_TEAM: int = -1

## Latched winner set by a subclass through _declare_winner(); NO_TEAM until
## the objective itself ends the round.
var _winner: int = NO_TEAM
## Per-team scores, indexed by team id. Subclasses write through _set_score().
var _scores: PackedFloat32Array = PackedFloat32Array()
## True when mode_state() changed since the last consume_state_dirty().
var _state_dirty: bool = false


## Factory: the objective for `mode` (a MatchConfig.GameMode). Reserved ids
## resolve to CLASSIC exactly as MatchConfig.resolve_game_mode() does, so a
## caller cannot get null.
static func create(
	mode: int,
	goal_positions: PackedVector2Array,
	capture_hold: float,
	team_count: int,
	beacon_score_rate: float = 1.0,
	beacon_replicate_interval: float = 1.0,
	slot_teams: PackedInt32Array = PackedInt32Array(),
	sky_sum_members: bool = false,
	sky_replicate_interval: float = 0.5
) -> ModeObjective:
	# DECISION: every id resolves to CLASSIC until a mode package (22y.7/.8/.9)
	# adds its `match` branch here and its id to SELECTABLE_GAME_MODES.
	var objective: ModeObjective = null
	match MatchConfig.resolve_game_mode(mode):
		MatchConfig.GameMode.CAPTURE_THE_FLAG:
			objective = CaptureFlagObjective.new(goal_positions, beacon_score_rate, beacon_replicate_interval)
		MatchConfig.GameMode.ELIMINATION:
			objective = EliminationObjective.new(slot_teams)
		MatchConfig.GameMode.REACH_THE_SKY:
			objective = ReachSkyObjective.new(slot_teams, sky_sum_members, sky_replicate_interval)
		_:
			objective = ClassicObjective.new(goal_positions, capture_hold)
	objective.reset(team_count)
	return objective


## The MatchConfig.GameMode this objective implements.
func mode_id() -> int:
	return MatchConfig.GameMode.CLASSIC


## Bontago-6fc.2: whether the match spawns goal flags (nodes, no-build zones,
## HUD/minimap markers, bot targets) for this mode. Classic (the goal hold) and
## CTF (beacons are the goal flags) say true; Reach the Sky and Elimination
## override to false. Mirrors MatchConfig.mode_uses_goal_flags().
func uses_goal_flags() -> bool:
	return MatchConfig.mode_uses_goal_flags(mode_id())


## True for a timed mode: MatchLifecycle then arms config.round_timer_minutes
## and finishes the match through on_round_timer_end() when it hits zero (no
## sudden death). False (classic) keeps match_timer_minutes + sudden_death.
func is_timed() -> bool:
	return false


## Default false (DECISION: opt-in, so a new objective never silently adds
## traffic). A mode that wants its scores/extras mirrored to clients overrides
## this to true. Classic stays false: its state is the capture ring
## (goal_capture_progress), already replicated.
func replicates_state() -> bool:
	return false


## Clears score and the latched winner for a new match of `team_count` teams.
func reset(team_count: int) -> void:
	_winner = NO_TEAM
	_scores.resize(maxi(team_count, 0))
	for i: int in range(_scores.size()):
		_scores[i] = 0.0
	_state_dirty = true


## Host, once per territory solve (`delta` = time that solve covers). Hook for
## scoring and for declaring a winner.
func update(_raster: TerritoryRaster, _delta: float) -> void:
	pass


## The winning team once the objective itself ended the round, else NO_TEAM.
func winner() -> int:
	return _winner


## Host, when the round timer of a timed mode reaches zero: the team that wins
## now. Default: highest score, ties to the lowest team id (DECISION: the same
## tie rule as the sudden-death territory tiebreak, MatchLifecycle).
func on_round_timer_end() -> int:
	var best_team: int = 0
	var best_score: float = -INF
	for team: int in range(_scores.size()):
		if _scores[team] > best_score:
			best_score = _scores[team]
			best_team = team
	return best_team


func team_score(team: int) -> float:
	return _scores[team] if team >= 0 and team < _scores.size() else 0.0


func scores() -> PackedFloat32Array:
	return _scores.duplicate()


## HUD feed for the goal-capture ring; objectives without one report none.
func capturing_team() -> int:
	return NO_TEAM


func capture_progress() -> float:
	return 0.0


## Mode-specific replicated values, small and wire-safe: String keys mapped to
## int, float or bool only (net/MatchNet.gd validates exactly that).
func extra_state() -> Dictionary:
	return {}


func apply_extra_state(_data: Dictionary) -> void:
	pass


## Extra results fields for the results payload ("mode" block); numbers and
## strings only. Classic returns {} so its payload is byte-identical.
func results_fields() -> Dictionary:
	return {}


## The replicated state: {"mode_id", "scores", "extra"}. The round time left
## is added by MatchLifecycle, which owns the timer.
func mode_state() -> Dictionary:
	return {"mode_id": mode_id(), "scores": Array(_scores), "extra": extra_state()}


## Client mirror of mode_state() (already validated by the caller). Display
## only: it never touches _winner.
func apply_mode_state(state: Dictionary) -> void:
	var raw_scores: Array = state.get("scores", [])
	_scores.resize(raw_scores.size())
	for i: int in range(raw_scores.size()):
		_scores[i] = float(raw_scores[i])
	apply_extra_state(state.get("extra", {}) as Dictionary)


## True once after mode_state() changed; the host publishes on it.
func consume_state_dirty() -> bool:
	var was_dirty: bool = _state_dirty
	_state_dirty = false
	return was_dirty


func _set_score(team: int, value: float) -> void:
	if team < 0 or team >= _scores.size():
		return
	if not is_equal_approx(_scores[team], value):
		_scores[team] = value
		_state_dirty = true


func _declare_winner(team: int) -> void:
	if _winner == NO_TEAM and team != NO_TEAM:
		_winner = team
		_state_dirty = true


# --- Wire validation (net/MatchNet.gd, autoload/match/MatchStats.gd) ---------

const MAX_WIRE_KEYS: int = 16
const MAX_WIRE_STRING: int = 64


## Strictly re-types a replicated mode state, or {} when malformed: mode_id
## must be a known GameMode, scores a bounded array of finite numbers,
## round_left a finite non-negative number, extra a scalar-only dictionary.
static func validate_state(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var data: Dictionary = raw
	var mode: Variant = data.get("mode_id")
	if not (mode is int or mode is float) or not _is_known_mode(int(mode)):
		return {}
	var scores: Array = _clean_scores(data.get("scores"))
	if scores.size() == 1 and scores[0] == null:
		return {}
	var round_left: Variant = data.get("round_left", 0.0)
	if not (round_left is int or round_left is float) or not is_finite(float(round_left)) or float(round_left) < 0.0:
		return {}
	var extra: Variant = _clean_scalars(data.get("extra", {}))
	if extra == null:
		return {}
	return {"mode_id": int(mode), "scores": scores, "extra": extra, "round_left": float(round_left)}


## Same checks for the results "mode" block (mode_id, scores and scalars).
static func validate_results_block(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var data: Dictionary = raw
	var mode: Variant = data.get("mode_id")
	if not (mode is int or mode is float) or not _is_known_mode(int(mode)):
		return {}
	var scores: Array = _clean_scores(data.get("scores"))
	if scores.size() == 1 and scores[0] == null:
		return {}
	var rest: Dictionary = data.duplicate()
	rest.erase("mode_id")
	rest.erase("scores")
	var cleaned: Variant = _clean_scalars(rest)
	if cleaned == null:
		return {}
	var out: Dictionary = cleaned
	out["mode_id"] = int(mode)
	out["scores"] = scores
	return out


static func _is_known_mode(mode: int) -> bool:
	return mode >= MatchConfig.GameMode.CLASSIC and mode <= MatchConfig.GameMode.REACH_THE_SKY


## Array of floats, or [null] as the malformed sentinel.
static func _clean_scores(raw: Variant) -> Array:
	if not (raw is Array) or (raw as Array).size() > MatchConfig.PLAYER_COUNT_MAX:
		return [null]
	var out: Array = []
	for value: Variant in (raw as Array):
		if not (value is int or value is float) or not is_finite(float(value)):
			return [null]
		out.append(float(value))
	return out


## A copy of `raw` when it is a small dictionary of String keys mapped to
## int/float(finite)/bool/short String; null otherwise.
static func _clean_scalars(raw: Variant) -> Variant:
	if not (raw is Dictionary) or (raw as Dictionary).size() > MAX_WIRE_KEYS:
		return null
	var out: Dictionary = {}
	for key: Variant in (raw as Dictionary):
		var value: Variant = (raw as Dictionary)[key]
		if not (key is String) or (key as String).length() > MAX_WIRE_STRING:
			return null
		if value is float:
			if not is_finite(value as float):
				return null
		elif value is String:
			if (value as String).length() > MAX_WIRE_STRING:
				return null
		elif not (value is int or value is bool):
			return null
		out[key] = value
	return out
