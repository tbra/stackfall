class_name DominationObjective
extends ModeObjective
## Domination (Bontago-1pi.25, owner roadmap: "control the biggest territory
## when the round ends"). There is no early win: update() only tracks each
## team's territory share (TerritoryRaster.team_share, the figure the HUD
## percentages show, 0..1) and never declares a winner. The round timer
## (config.round_timer_minutes, never off for this mode) ends the match through
## on_round_timer_end(): the team with the largest share wins.
##
## DECISION (tie rule): equal shares (within TIE_EPSILON) at the timer are a
## SHARED WIN, the same rule as EliminationObjective. winners() / the results
## "winners" field list every tied team; the single id returned to MatchLifecycle
## is the lowest tied team id (the base-class tie convention). No sudden death:
## timed modes never run one.
##
## Home eliminations are untouched: a team that loses its home flag is out and
## the last team standing still wins early through MatchLifecycle, exactly as in
## CTF / Reach the Sky.
##
## _scores holds each team's share. Host-only logic; clients mirror the
## replicated scores (replicates_state()). Pure: no scene tree.

## Shares closer than this are equal (float noise). Not a gameplay tunable.
const TIE_EPSILON: float = 0.0001

var _replicate_interval: float = 1.0
var _since_publish: float = 0.0
var _publish_pending: bool = false
var _winners: PackedInt32Array = PackedInt32Array()


func _init(replicate_interval: float = 1.0) -> void:
	_replicate_interval = maxf(replicate_interval, 0.0)


func mode_id() -> int:
	return MatchConfig.GameMode.DOMINATION


func uses_goal_flags() -> bool:
	return false


func is_timed() -> bool:
	return true


func replicates_state() -> bool:
	return true


func reset(team_count: int) -> void:
	super.reset(team_count)
	_winners.clear()
	_since_publish = _replicate_interval
	_publish_pending = false


## Host, once per territory solve: refresh the shares. A change replicates at
## once after a quiet spell, else at most once per interval.
func update(raster: TerritoryRaster, delta: float) -> void:
	_since_publish += maxf(delta, 0.0)
	if raster != null:
		for team: int in range(_scores.size()):
			var share: float = raster.team_share(team)
			if not is_equal_approx(_scores[team], share):
				_scores[team] = share
				_publish_pending = true
	if _publish_pending and _since_publish >= _replicate_interval:
		_publish_pending = false
		_since_publish = 0.0
		_state_dirty = true


## Test / host hook: set the shares directly (same effect as update()).
func set_shares(shares: PackedFloat32Array) -> void:
	for team: int in range(mini(shares.size(), _scores.size())):
		_scores[team] = shares[team]
	_publish_pending = true


## Largest share wins; equal shares share the win (see the class DECISION).
func on_round_timer_end() -> int:
	_state_dirty = true  # the exact final state always goes out
	_winners = leading_teams()
	return _winners[0] if not _winners.is_empty() else 0


## Teams currently holding the largest share (more than one = a tie). Live
## during the round (HUD "leader"), final after on_round_timer_end().
func leading_teams() -> PackedInt32Array:
	var best: float = -INF
	for score: float in _scores:
		best = maxf(best, score)
	var out: PackedInt32Array = PackedInt32Array()
	for team: int in range(_scores.size()):
		if _scores[team] >= best - TIE_EPSILON:
			out.append(team)
	return out


## Winning team ids once the timer ended (empty before).
func winners() -> PackedInt32Array:
	return _winners.duplicate()


## "winners" lists the winning team id(s) (0-based, comma-separated); the
## per-team shares ride in the block's "scores" (0..1).
func results_fields() -> Dictionary:
	var ids: PackedStringArray = PackedStringArray()
	for team: int in _winners:
		ids.append(str(team))
	return {"winners": ",".join(ids)}
