class_name QolExperiments
extends Resource
## Opt-in quality-of-life experiments (Bontago-1pi.18.1, owner roadmap "Qol
## tests (friction)"). Every toggle defaults OFF, so the default rules are
## untouched.
##
## DECISION (config/QolExperiments.gd): the shared config/qol_experiments.tres
## is what the F4 panel edits. The host snapshots it into MatchConfig.qol at
## start_match() and MatchConfig.to_dict()/from_dict() carry it (appended last)
## in net_match_start, so clients see the values in effect at match start. Only
## the host's copy decides anything; a client reads backlog/paused state from
## the replicated QoL feed event.
##
## Loaded once as config/qol_experiments.tres.

## -- Toggle 1: pause the block timer during events / big topples ------------
## Master switch. While a slot's timer is paused it neither counts down nor
## force-drops.
@export var timer_pause_enabled: bool = false
## Pause every slot's timer for pause_event_s whenever a special triggers.
@export var timer_pause_on_special: bool = true
## Seconds every timer stays paused after a special triggers (refreshed by the next one).
@export var pause_event_s: float = 4.0
## A slot's timer pauses while at least this many of its own placed blocks move faster than the speed below.
@export var topple_moving_blocks_min: int = 4
## Linear speed in m/s above which a block counts as moving for the topple test.
@export var topple_speed_threshold_mps: float = 1.5
## Seconds a slot's timer stays paused after its topple condition last held.
@export var pause_tail_s: float = 1.5
## Seconds between host scans of block velocities for the topple test.
@export var topple_scan_interval_s: float = 0.25

## -- Toggle 2: backlog instead of forced drop --------------------------------
## When a timer expires the held block is queued in a backlog and the player is
## handed a fresh block; the forced drop only happens once the backlog is full.
@export var backlog_enabled: bool = false
## Most blocks the backlog may hold before the next expiry force-drops.
@export var backlog_max: int = 2

## -- Toggle 3: bigger goal beacon radius -------------------------------------
## Multiply TerritoryTuning.goal_zone_radius (the beacon's area, both the
## no-build disc and the circle drawn/replicated for it).
@export var goal_radius_enabled: bool = false
## Factor applied to the goal zone radius while the toggle is on.
@export var goal_radius_multiplier: float = 2.0

const BACKLOG_MAX_CEILING: int = 3
const GOAL_RADIUS_MULTIPLIER_MAX: float = 4.0


## Radius to use for goal beacons given the base TerritoryTuning radius.
func effective_goal_radius(base_radius: float) -> float:
	if not goal_radius_enabled:
		return base_radius
	return base_radius * clampf(goal_radius_multiplier, 1.0, GOAL_RADIUS_MULTIPLIER_MAX)


## Backlog capacity actually in force (0 when the toggle is off).
func effective_backlog_max() -> int:
	if not backlog_enabled:
		return 0
	return clampi(backlog_max, 1, BACKLOG_MAX_CEILING)


## Clamps every value into a sane range; the host calls it on a received dict.
func sanitize() -> void:
	pause_event_s = clampf(pause_event_s, 0.0, 30.0)
	topple_moving_blocks_min = clampi(topple_moving_blocks_min, 1, 64)
	topple_speed_threshold_mps = clampf(topple_speed_threshold_mps, 0.1, 50.0)
	pause_tail_s = clampf(pause_tail_s, 0.0, 30.0)
	topple_scan_interval_s = clampf(topple_scan_interval_s, 0.05, 2.0)
	backlog_max = clampi(backlog_max, 1, BACKLOG_MAX_CEILING)
	goal_radius_multiplier = clampf(goal_radius_multiplier, 1.0, GOAL_RADIUS_MULTIPLIER_MAX)


func to_dict() -> Dictionary:
	return {
		"timer_pause_enabled": timer_pause_enabled,
		"timer_pause_on_special": timer_pause_on_special,
		"pause_event_s": pause_event_s,
		"topple_moving_blocks_min": topple_moving_blocks_min,
		"topple_speed_threshold_mps": topple_speed_threshold_mps,
		"pause_tail_s": pause_tail_s,
		"topple_scan_interval_s": topple_scan_interval_s,
		"backlog_enabled": backlog_enabled,
		"backlog_max": backlog_max,
		"goal_radius_enabled": goal_radius_enabled,
		"goal_radius_multiplier": goal_radius_multiplier,
	}


## Rebuilds from to_dict(); wrong-typed or missing values keep the (OFF) defaults.
static func from_dict(data: Dictionary) -> QolExperiments:
	var qol: QolExperiments = QolExperiments.new()
	qol.timer_pause_enabled = _bool(data, "timer_pause_enabled", qol.timer_pause_enabled)
	qol.timer_pause_on_special = _bool(data, "timer_pause_on_special", qol.timer_pause_on_special)
	qol.pause_event_s = _num(data, "pause_event_s", qol.pause_event_s)
	qol.topple_moving_blocks_min = int(_num(data, "topple_moving_blocks_min", float(qol.topple_moving_blocks_min)))
	qol.topple_speed_threshold_mps = _num(data, "topple_speed_threshold_mps", qol.topple_speed_threshold_mps)
	qol.pause_tail_s = _num(data, "pause_tail_s", qol.pause_tail_s)
	qol.topple_scan_interval_s = _num(data, "topple_scan_interval_s", qol.topple_scan_interval_s)
	qol.backlog_enabled = _bool(data, "backlog_enabled", qol.backlog_enabled)
	qol.backlog_max = int(_num(data, "backlog_max", float(qol.backlog_max)))
	qol.goal_radius_enabled = _bool(data, "goal_radius_enabled", qol.goal_radius_enabled)
	qol.goal_radius_multiplier = _num(data, "goal_radius_multiplier", qol.goal_radius_multiplier)
	qol.sanitize()
	return qol


static func _bool(data: Dictionary, key: String, fallback: bool) -> bool:
	var value: Variant = data.get(key, fallback)
	return value if value is bool else fallback


static func _num(data: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = data.get(key, fallback)
	if (value is float or value is int) and is_finite(float(value)):
		return float(value)
	return fallback
