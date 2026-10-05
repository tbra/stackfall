class_name ExplosionTuning
extends Resource
## Tuning parameters for blast effects (Bomb, Rocket, Volcano orbs).
##
## Controls explosion radius, peak speed, falloff curve, upward bias,
## and per-body delta-v cap. All values are in SI units (meters, m/s).

## Radius of the explosion sphere in meters.
@export var radius_m: float = 5.0

## Peak delta-v at the center of the explosion in m/s.
@export var peak_speed_mps: float = 12.0

## Falloff curve exponent (1.0 = linear, 2.0 = quadratic).
@export var falloff_exponent: float = 1.5

## Vertical bias applied to the blast direction (0.0 = radial only, 1.0 = half upward).
@export var upward_bias: float = 0.35

## Hard clamp on delta-v per body in m/s (not kg*m/s).
@export var max_delta_v_mps: float = 16.0
