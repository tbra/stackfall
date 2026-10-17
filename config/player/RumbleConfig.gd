class_name RumbleConfig
extends Resource
## Controller rumble tunables (spec 1.3 gamepad parity), driven by
## autoload/Rumble.gd's Events listeners (the counterpart of CameraShakeConfig for
## the camera).
##
## DECISION: enabled_by_default/global_strength_scale are the SEED values
## autoload/Settings.gd's rumble_enabled()/rumble_strength() read when
## user://settings.cfg has no [gamepad] section yet (Settings._load()), so "what a
## fresh install feels like" has one source. Once a player has a persisted value it
## wins on every later boot.

## DECISION: the Options slider is 0..1 and Rumble._trigger() multiplies by it, so
## felt strength is set by the per-event magnitudes below. The events a player feels
## all session (block impacts, which are also the Options "test pulse", and the light
## placed/refused ticks) are scaled so the strongest motor of each reaches or nears
## 1.0 at 100%, keeping each event's weak:strong shape; match won/lost are scaled
## less so end-of-match pulses stay below the special/eliminated tier. Pulses under
## ~0.08 s do not give a pad's motors time to spin up, so tick durations are at least
## 0.1 s. Every *_magnitude stays within 0..1 and at least one reaches exactly 1.0
## (tests/unit/player/test_rumble.gd guards both, plus a duration floor).

## Whether a fresh install starts with rumble on.
@export var enabled_by_default: bool = true

## Whether a fresh install starts at full rumble strength (0..1, the same
## range Settings.set_rumble_strength() clamps a user value into).
@export var global_strength_scale: float = 1.0

# --- Block impact (scales with how far impact speed is above a threshold, like
# camera shake, not a plain on/off) ------------

## Minimum impact speed (Block.gd's deceleration magnitude, same value
## Events.block_impacted already carries for camera shake/thuds) that
## triggers any rumble at all.
@export var impact_speed_threshold: float = 4.0

## Impact speed at which the rumble reaches its full configured magnitude;
## anything at or above this feels the same as anything harder.
@export var impact_speed_max: float = 10.0

## Weak (low-frequency) motor magnitude, 0..1, at impact_speed_max.
@export var impact_weak_magnitude: float = 0.65
## Strong (high-frequency) motor magnitude, 0..1, at impact_speed_max.
@export var impact_strong_magnitude: float = 1.0
@export var impact_duration_s: float = 0.12

# --- Local block placed/dropped: a light tick ------------------------------

@export var block_placed_weak_magnitude: float = 0.36
@export var block_placed_strong_magnitude: float = 0.0
@export var block_placed_duration_s: float = 0.1

# --- Local placement refused: a short single tap ---------------------------

@export var placement_refused_weak_magnitude: float = 0.0
@export var placement_refused_strong_magnitude: float = 0.9
@export var placement_refused_duration_s: float = 0.1

# --- A special triggered/exploded (global, like camera shake: the event
# carries a world position but no owning slot) ------------------------------

@export var special_triggered_weak_magnitude: float = 0.67
@export var special_triggered_strong_magnitude: float = 1.0
@export var special_triggered_duration_s: float = 0.35

# --- Local home beacon lost/eliminated: strong and long --------------------

@export var player_eliminated_weak_magnitude: float = 0.8
@export var player_eliminated_strong_magnitude: float = 1.0
@export var player_eliminated_duration_s: float = 0.6

# --- Match end: medium, distinguished by win vs. loss for the local slot ---

@export var match_won_weak_magnitude: float = 0.65
@export var match_won_strong_magnitude: float = 0.65
@export var match_won_duration_s: float = 0.5

@export var match_lost_weak_magnitude: float = 0.52
@export var match_lost_strong_magnitude: float = 0.39
@export var match_lost_duration_s: float = 0.4
