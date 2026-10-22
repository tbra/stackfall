class_name DiscTilt
extends RefCounted
## The disc's tilt spring (spec 1.7, 1.2, 2.7): impulses from specials and the
## PHYSICAL_BALANCE torque from settled blocks drive one spring, and step()
## reports whether the disc transform must be rewritten. No scene tree.
## Interface stub: P4-Itilt fills the bodies from Field.gd:194-500.

## How step() treats the physical-balance torque for this tick.
## OFF: PHYSICAL_BALANCE is off, torque is zero.
## EMPTY: no registry or no tracked blocks; the latched torque is zeroed.
## HOLD: blocks not all settled; the latched torque is kept.
## SAMPLED: the torque is recomputed from the samples passed to step().
enum Balance { OFF, EMPTY, HOLD, SAMPLED }


func _init(_tuning: TiltTuning) -> void:
	pass


func impulse(_direction: Vector2, _magnitude: float) -> void:
	pass


## Advances the spring by delta. Returns true when the disc transform must be
## rewritten (tilt changed since the last mark_applied()).
# STUB: filled by P4-Itilt
func step(_delta: float, _balance: Balance, _samples: PackedVector3Array) -> bool:
	return false


func mark_applied() -> void:
	pass


## Mirror mode: step() then ignores impulses.
func set_pose(_tilt: Quaternion) -> void:
	pass


func tilt() -> Vector2:
	return Vector2.ZERO


func basis() -> Basis:
	return Basis.IDENTITY


## Field drops sync_to_physics when this is true.
func is_at_rest() -> bool:
	return true


func reset() -> void:
	pass
