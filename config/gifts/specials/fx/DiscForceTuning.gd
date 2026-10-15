class_name DiscForceTuning
extends Resource
## Tuning parameters for disc tilt effects (Anvil, Propeller, Earthquake).
##
## Consumed by DiscForce. Units noted per field.

## Tilt impulse per metre of disc-local distance (Field.apply_tilt_impulse
## units). Per-tick callers pass a delta, making this "per metre per second".
@export var strength: float = 0.02

## Shake kick size in tilt-impulse units per second (DiscForce.shake multiplies
## by the tick delta).
@export var shake_amplitude_m: float = 3.0

## Degrees per second the shake axis sweeps around the disc.
@export var shake_tilt_deg: float = 720.0

## Effect duration in seconds from trigger (shake stops after it).
@export var duration_s: float = 3.0
