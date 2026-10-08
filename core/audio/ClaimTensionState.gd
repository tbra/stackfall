class_name ClaimTensionState
extends RefCounted
## Local-player-relative beacon-claim tension (Bontago-1pi.114). Pure rules, no
## scene tree: Sfx feeds it the already-replicated Events.goal_capture_progress
## (team, progress) plus "which team am I" and "is the match live"; it answers
## how tense the bed should be and whether a hold just broke. Nothing here is
## replicated and the host stays authoritative: every machine derives this from
## the same territory result it already solves.

const NO_TEAM: int = -1
const MIN_SPAN: float = 0.001
## local_team for a machine with no seat on the holding team (rival flavour).
const NO_LOCAL_TEAM: int = -2

var _config: AudioConfig
var _team: int = NO_TEAM
var _progress: float = 0.0
var _mine: bool = false
var _peak: float = 0.0
var _pending: Dictionary = {}
var _last_interrupt_s: float = -INF


func _init(config: AudioConfig) -> void:
	_config = config


## One capture-progress reading. `local_team` is the team this machine's human
## seat plays for (any value that never equals a real team = spectator/rival
## flavour). `now_s` is a monotonic clock for the interrupt rate limit.
func update(team_id: int, progress: float, local_team: int, match_live: bool, now_s: float = 0.0) -> void:
	var holding: bool = team_id != NO_TEAM and progress > 0.0
	if _progress > 0.0 and _team != NO_TEAM and (not holding or team_id != _team):
		_register_break(match_live, now_s)
	if holding:
		if team_id != _team or _progress <= 0.0:
			_peak = 0.0
		_peak = maxf(_peak, progress)
		_team = team_id
		_progress = progress
		_mine = team_id == local_team
	else:
		_team = NO_TEAM
		_progress = 0.0
		_peak = 0.0
		_mine = false


func _register_break(match_live: bool, now_s: float) -> void:
	if not match_live or _peak < _config.claim_interrupt_min_progress:
		return
	if now_s - _last_interrupt_s < _config.claim_interrupt_min_interval_s:
		return
	_last_interrupt_s = now_s
	_pending = {"was_mine": _mine, "peak": _peak}


## 0..1 tension: zero below claim_tension_start_progress, then the remaining
## range raised to claim_tension_curve_exp; a rival's hold is scaled down.
func level() -> float:
	if _progress <= _config.claim_tension_start_progress:
		return 0.0
	var span: float = maxf(1.0 - _config.claim_tension_start_progress, MIN_SPAN)
	var t: float = clampf((_progress - _config.claim_tension_start_progress) / span, 0.0, 1.0)
	var shaped: float = pow(t, _config.claim_tension_curve_exp)
	return shaped if _mine else shaped * _config.claim_rival_tension_scale


func is_mine() -> bool:
	return _mine


func progress() -> float:
	return _progress


## Like take_interrupt() but leaves it pending.
func peek_interrupt() -> Dictionary:
	return _pending


## The break recorded by the last update() as {"was_mine": bool, "peak": float},
## consumed on read; {} when there is none.
func take_interrupt() -> Dictionary:
	var out: Dictionary = _pending
	_pending = {}
	return out


## The match was won: a hold that completed is a win, never an interruption.
func mark_won() -> void:
	reset()


## New match scope / full reset.
func reset() -> void:
	_team = NO_TEAM
	_progress = 0.0
	_peak = 0.0
	_mine = false
	_pending = {}
	_last_interrupt_s = -INF
