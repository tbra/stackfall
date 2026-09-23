class_name SpecialTuning
extends Resource
## Match-wide tunables for specials that aren't per-SpecialDef (spec 2.6,
## 1.5's "mouse flick throws a special"). CLAUDE.md: "No magic numbers...
## every tunable value belongs in a Resource under res://config/". Loaded
## once as config/special_tuning.tres.
##
## DECISION (config/specials/SpecialTuning.gd): deviates from the old M4 plan
## by not pre-declaring `max_explosion_impulse` etc. -- nothing in P2a reads
## them; P3/P4 add what they need when those concrete specials land
## (docs/M4_P2_PACKAGES.md P2a).

## Chain reactions are capped at this depth (spec 2.6: "Cap them at
## max_chain_depth = 4 as a remake performance choice"). A special triggered
## at `chain_depth >= max_chain_depth` still detonates but does not extend
## the chain further (game/specials/SpecialBehavior.gd).
@export var max_chain_depth: int = 4

## Hard clamp on a thrown special's launch speed in m/s (P2d/P2c: the throw
## drag/release gesture never launches faster than this, regardless of drag
## distance).
@export var throw_max_speed: float = 25.0

## Below this drag distance in meters, a throw-aim release is treated as an
## ordinary place instead of a throw (P2d).
@export var throw_drag_min_distance_m: float = 0.15

## Below this release speed in m/s, a throw-aim release is treated as an
## ordinary place instead of a throw (P2d).
@export var throw_drag_min_speed_mps: float = 1.0

## Throw launch speed in m/s per meter of aim drag, before the
## throw_max_speed clamp above (P2d).
@export var throw_speed_per_meter: float = 12.0
