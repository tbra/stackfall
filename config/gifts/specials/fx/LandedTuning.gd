class_name LandedTuning
extends Resource
## Tuning parameters for landing detection probes.
##
## Controls speed and time thresholds for detecting when a block has settled.
## All values are in SI units (m/s, seconds).

## Linear speed below which a block is considered settling in m/s.
@export var landed_speed_mps: float = 0.5

## Time the block must stay below landed_speed_mps to be considered landed in seconds.
@export var landed_hold_s: float = 0.2

## Hard timeout ceiling for landing detection in seconds (e.g., for continuous tilt).
@export var landed_timeout_s: float = 5.0

## Downward test-motion distance in meters used to detect that the block touches something.
@export var contact_probe_m: float = 0.05
