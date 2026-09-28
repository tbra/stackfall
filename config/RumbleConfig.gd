class_name RumbleConfig
extends Resource
## Controller rumble tunables (spec 2.5 gamepad parity), driven by
## autoload/Rumble.gd's Events listeners. Keeps Rumble.gd free of magic
## numbers per CLAUDE.md, the same role config/CameraShakeConfig.gd plays for
## game/CameraRig.gd's own Events.block_impacted reaction.
##
## DECISION (config/RumbleConfig.gd): enabled_by_default/global_strength_scale
## are the SEED values autoload/Settings.gd's own persisted rumble_enabled()/
## rumble_strength() read the first time user://settings.cfg has no
## [gamepad] section yet (Settings._load()) -- a single source of truth for
## "what a fresh install feels like" rather than a second hardcoded default
## living in Settings.gd too. Once a player has an opinion, Settings.gd's own
## persisted value wins on every later boot; this file is never re-read for
## that after the first run.

## Whether a fresh install starts with rumble on.
@export var enabled_by_default: bool = true

## Whether a fresh install starts at full rumble strength (0..1, the same
## range Settings.set_rumble_strength() clamps a user value into).
@export var global_strength_scale: float = 1.0

# --- Block impact (game/CameraRig.gd's shake_config precedent: scales with
# how far impact speed is above a threshold, not a plain on/off) ------------

## Minimum impact speed (Block.gd's deceleration magnitude, same value
## Events.block_impacted already carries for camera shake/thuds) that
## triggers any rumble at all.
@export var impact_speed_threshold: float = 4.0

## Impact speed at which the rumble reaches its full configured magnitude;
## anything at or above this feels the same as anything harder.
@export var impact_speed_max: float = 10.0

## Weak (low-frequency) motor magnitude, 0..1, at impact_speed_max.
@export var impact_weak_magnitude: float = 0.35
## Strong (high-frequency) motor magnitude, 0..1, at impact_speed_max.
@export var impact_strong_magnitude: float = 0.55
@export var impact_duration_s: float = 0.12

# --- Local block placed/dropped: a light tick ------------------------------

@export var block_placed_weak_magnitude: float = 0.2
@export var block_placed_strong_magnitude: float = 0.0
@export var block_placed_duration_s: float = 0.06

# --- Local placement refused: a short single tap ---------------------------

@export var placement_refused_weak_magnitude: float = 0.0
@export var placement_refused_strong_magnitude: float = 0.5
@export var placement_refused_duration_s: float = 0.08

# --- A special triggered/exploded (global, like camera shake: the event
# carries a world position but no owning slot) ------------------------------

@export var special_triggered_weak_magnitude: float = 0.6
@export var special_triggered_strong_magnitude: float = 0.9
@export var special_triggered_duration_s: float = 0.35

# --- Local home beacon lost/eliminated: strong and long --------------------

@export var player_eliminated_weak_magnitude: float = 0.8
@export var player_eliminated_strong_magnitude: float = 1.0
@export var player_eliminated_duration_s: float = 0.6

# --- Match end: medium, distinguished by win vs. loss for the local slot ---

@export var match_won_weak_magnitude: float = 0.5
@export var match_won_strong_magnitude: float = 0.5
@export var match_won_duration_s: float = 0.5

@export var match_lost_weak_magnitude: float = 0.4
@export var match_lost_strong_magnitude: float = 0.3
@export var match_lost_duration_s: float = 0.4
