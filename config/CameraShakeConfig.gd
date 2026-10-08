class_name CameraShakeConfig
extends Resource
## Camera shake tunables (spec 2.10 effects + camera shake), driven by
## Events.block_impacted. Keeps game/CameraRig.gd free of magic numbers per
## CLAUDE.md.

## Maximum shake offset in meters (anvil/bomb/rocket impacts; the disc
## tilt shake scales it by DiscShakeConfig.disc_tilt_amplitude_fraction).
@export var max_offset_m: float = 0.35

## Seconds for a single shake impulse to decay back to (approximately) zero,
## an exponential falloff independent of amplitude.
@export var decay_seconds: float = 0.25

## Oscillation frequency in Hz of the decaying shake offset.
@export var frequency_hz: float = 18.0
