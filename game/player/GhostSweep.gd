class_name GhostSweep
extends RefCounted
## Slides the held shape's collision boxes through the physics space without passing a placed
## block: the full motion, then its X-only and Z-only remainders. Stub: returns `to` unchanged
## until PlayerController's sweep moves here.

var _tuning: GhostTuning


func _init(tuning: GhostTuning) -> void:
	_tuning = tuning


## Furthest point from `from` towards `to` that keeps every box (centre offsets `centres`
## rotated by `basis`, cube half-edge `half`, inflated by the collision skin) clear of every
## placed block. Max skipped non-block colliders per cast: tuning.collision_probe_max_bodies.
func sweep(
	_space: PhysicsDirectSpaceState3D, _centres: Array[Vector3], _half: float, _basis: Basis,
	_from: Vector3, to: Vector3
) -> Vector3:
	return to
