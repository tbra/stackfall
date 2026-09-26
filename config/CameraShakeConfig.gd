class_name CameraShakeConfig
extends Resource
## Camera shake tunables (spec 2.10 effects + camera shake), driven by
## Events.block_impacted. Keeps game/CameraRig.gd free of magic numbers per
## CLAUDE.md.

## Minimum impact speed (Block.gd's deceleration magnitude passed to
## Events.block_impacted) that triggers any shake at all -- a soft landing
## should not visibly move the camera.
@export var impact_speed_threshold: float = 4.0

## Shake offset in meters once impact speed reaches roughly double the
## threshold (amplitude scales linearly with how far above threshold the
## impact was, clamped to this).
@export var max_offset_m: float = 0.35

## Seconds for a single shake impulse to decay back to (approximately) zero,
## an exponential falloff independent of amplitude.
@export var decay_seconds: float = 0.25

## Oscillation frequency in Hz of the decaying shake offset.
@export var frequency_hz: float = 18.0
