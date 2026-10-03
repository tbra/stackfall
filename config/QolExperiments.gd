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
## Stall guard (Bontago-1pi.18.4): longest continuous pause. After this many seconds paused, the slot's timer runs
## again until the pause cause fully clears, then the guard re-arms.
@export var pause_max_s: float = PAUSE_MAX_DEFAULT_S

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

## -- Toggle B: gift slot instead of the block queue (Bontago-1pi.18.2) ------
## A claimed gift waits in a per-player slot instead of replacing the next
## block; the player spends it with the use_gift_slot action. No timer runs on
## a slotted gift.
@export var gift_slot_enabled: bool = false
## Gifts a slot holds. DECISION: when full, a new claim drops the OLDEST slotted gift.
@export var gift_slot_capacity: int = 1
## Minimum seconds left on the block timer right after a slotted gift is
## activated, so it cannot be auto-dropped the instant it appears.
@export var gift_slot_min_window_s: float = 2.0

## Stable ids of the four opt-in toggles (HUD line, lobby chip, logs), reported by
## active_ids() in this declaration order.
const ID_TIMER_PAUSE: StringName = &"timer_pause"
const ID_BACKLOG: StringName = &"backlog"
const ID_GOAL_RADIUS: StringName = &"goal_radius"
const ID_GIFT_SLOT: StringName = &"gift_slot"

const PAUSE_MAX_DEFAULT_S: float = 10.0
const PAUSE_MAX_MIN_S: float = 1.0
const PAUSE_MAX_MAX_S: float = 60.0
const BACKLOG_MAX_CEILING: int = 3
const GIFT_SLOT_CAPACITY_CEILING: int = 3
const GIFT_MIN_WINDOW_MAX_S: float = 10.0
const GOAL_RADIUS_MULTIPLIER_MAX: float = 4.0


## True when at least one of the four opt-in toggles is on.
func any_enabled() -> bool:
	return timer_pause_enabled or backlog_enabled or goal_radius_enabled or gift_slot_enabled


## Ids (ID_* constants) of the enabled toggles in fixed order (timer_pause, backlog, goal_radius, gift_slot); empty when none is on.
func active_ids() -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	if timer_pause_enabled:
		ids.append(String(ID_TIMER_PAUSE))
	if backlog_enabled:
		ids.append(String(ID_BACKLOG))
	if goal_radius_enabled:
		ids.append(String(ID_GOAL_RADIUS))
	if gift_slot_enabled:
		ids.append(String(ID_GIFT_SLOT))
	return ids


## A copy of `base` (all numeric parameters kept) with the four enable flags set
## to the given values. A null `base` starts from the defaults. `base` is never modified.
static func with_toggles(base: QolExperiments, timer_pause: bool, backlog: bool,
		goal_radius: bool, gift_slot: bool) -> QolExperiments:
	var qol: QolExperiments = QolExperiments.new() if base == null else base.duplicate() as QolExperiments
	qol.timer_pause_enabled = timer_pause
	qol.backlog_enabled = backlog
	qol.goal_radius_enabled = goal_radius
	qol.gift_slot_enabled = gift_slot
	return qol


## Longest continuous pause in force (seconds); a non-finite value reads as the default.
func effective_pause_max_s() -> float:
	if not is_finite(pause_max_s):
		return PAUSE_MAX_DEFAULT_S
	return clampf(pause_max_s, PAUSE_MAX_MIN_S, PAUSE_MAX_MAX_S)


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


## Gift slot capacity in force (0 when the toggle is off).
func effective_gift_slot_capacity() -> int:
	if not gift_slot_enabled:
		return 0
	return clampi(gift_slot_capacity, 1, GIFT_SLOT_CAPACITY_CEILING)


## Minimum post-activation window in force (seconds).
func effective_gift_min_window_s() -> float:
	return clampf(gift_slot_min_window_s, 0.0, GIFT_MIN_WINDOW_MAX_S)


## Clamps every value into a sane range; the host calls it on a received dict.
func sanitize() -> void:
	pause_event_s = clampf(pause_event_s, 0.0, 30.0)
	topple_moving_blocks_min = clampi(topple_moving_blocks_min, 1, 64)
	topple_speed_threshold_mps = clampf(topple_speed_threshold_mps, 0.1, 50.0)
	pause_tail_s = clampf(pause_tail_s, 0.0, 30.0)
	topple_scan_interval_s = clampf(topple_scan_interval_s, 0.05, 2.0)
	pause_max_s = effective_pause_max_s()
	backlog_max = clampi(backlog_max, 1, BACKLOG_MAX_CEILING)
	goal_radius_multiplier = clampf(goal_radius_multiplier, 1.0, GOAL_RADIUS_MULTIPLIER_MAX)
	gift_slot_capacity = clampi(gift_slot_capacity, 1, GIFT_SLOT_CAPACITY_CEILING)
	gift_slot_min_window_s = clampf(gift_slot_min_window_s, 0.0, GIFT_MIN_WINDOW_MAX_S)


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
		"gift_slot_enabled": gift_slot_enabled,
		"gift_slot_capacity": gift_slot_capacity,
		"gift_slot_min_window_s": gift_slot_min_window_s,
		"pause_max_s": pause_max_s,
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
	qol.gift_slot_enabled = _bool(data, "gift_slot_enabled", qol.gift_slot_enabled)
	qol.gift_slot_capacity = int(_num(data, "gift_slot_capacity", float(qol.gift_slot_capacity)))
	qol.gift_slot_min_window_s = _num(data, "gift_slot_min_window_s", qol.gift_slot_min_window_s)
	qol.pause_max_s = _num(data, "pause_max_s", qol.pause_max_s)
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
