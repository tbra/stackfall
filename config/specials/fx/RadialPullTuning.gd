class_name RadialPullTuning
extends Resource
## Tuning parameters for radial pull effects (Magnet, Black hole).
##
## Controls pull radius, acceleration, falloff curve, friction compensation,
## and capture core radius. All values are in SI units (meters, m/s^2).

## Pull radius in meters from center.
@export var radius_m: float = 8.0

## Peak acceleration toward center at the edge in m/s^2.
@export var accel_mps2: float = 18.0

## Falloff curve exponent (1.0 = linear, 2.0 = quadratic).
@export var falloff_exponent: float = 1.0

## Friction compensation acceleration in m/s^2 (typically block_friction * g).
@export var friction_compensation: float = 8.3

## Capture core radius in meters (blocks entering this radius trigger on_captured).
@export var core_radius_m: float = 0.8
