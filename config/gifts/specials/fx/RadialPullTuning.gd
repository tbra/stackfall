class_name RadialPullTuning
extends Resource
## Tuning parameters for radial pull effects (Magnet, Black hole).
##
## Controls pull radius, acceleration, falloff curve, and friction compensation. All values are in SI units (meters, m/s^2).

## Pull radius in meters from center.
@export var radius_m: float = 8.0

## Peak acceleration toward center at the edge in m/s^2.
@export var accel_mps2: float = 18.0

## Falloff curve exponent (1.0 = linear, 2.0 = quadratic).
@export var falloff_exponent: float = 1.0

## Friction compensation acceleration in m/s^2, added to the falloff pull so a resting
## block actually slides. MEASURED on the real disc (block_friction 0.85, disk_friction 0.9,
## gravity_multiplier 1.4, resting cube): sliding deceleration is 14.4 m/s^2 but a RESTING block
## breaks away only above about 22.5 m/s^2 (at compensation 14.4/18/22 a cube 6 m out moved
## 0.03/0.06/0.2 m in 0.5 s; at 25 it moved 1.0 m). The plan's 8.3 (block_friction * 9.8) is
## far too low. Keep this above the breakaway value.
@export var friction_compensation: float = 24.0
