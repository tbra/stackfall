class_name DiscForceTuning
extends Resource
## Tuning parameters for disc tilt effects (Anvil, Propeller, Earthquake).
##
## Controls tilt strength, shake amplitude and frequency, and effect duration.
## All values are in SI units (degrees, meters, seconds).

## Tilt impulse strength applied per unit distance per frame.
@export var strength: float = 0.02

## Amplitude of oscillation for shake effects in meters of tilt travel.
@export var shake_amplitude_m: float = 0.1

## Tilt oscillation frequency in degrees per cycle.
@export var shake_tilt_deg: float = 5.0

## Effect duration in seconds from trigger.
@export var duration_s: float = 3.0
