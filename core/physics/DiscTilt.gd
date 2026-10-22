class_name DiscTilt
extends RefCounted
## The disc's tilt spring (spec 1.7, 1.2, 2.7): impulses from specials and the
## PHYSICAL_BALANCE torque from settled blocks drive one spring, and step()
## reports whether the disc transform must be rewritten. No scene tree.

## How step() treats the physical-balance torque for this tick.
## OFF: PHYSICAL_BALANCE is off, torque is zero.
## EMPTY: no registry or no tracked blocks; the latched torque is zeroed.
## HOLD: blocks not all settled; the latched torque is kept.
## SAMPLED: the torque is recomputed from the samples passed to step().
enum Balance { OFF, EMPTY, HOLD, SAMPLED }


var _tuning: TiltTuning = null
## The 2-axis tilt vector the critically damped spring integrates: x is the
## rotation (radians) about the disk's local X axis, y about its local Z axis.
var _tilt: Vector2 = Vector2.ZERO
var _velocity: Vector2 = Vector2.ZERO
var _at_rest: bool = false
var _rest_timer: float = 0.0
## Last tilt reported through mark_applied(); step()'s change gate.
var _last_applied: Vector2 = Vector2.ZERO
## Set by set_pose(): the spring is then driven from outside and step() stops.
var _mirrored: bool = false
## Latched torque: kept through HOLD ticks so a wake that the tilt itself causes
## cannot start a limit cycle that never lets the spring converge.
var _torque: Vector2 = Vector2.ZERO


func _init(tuning: TiltTuning) -> void:
	_tuning = tuning


## direction is a disk-local XZ vector; magnitude is a velocity kick into the
## spring (Vector2(dz, -dx) * magnitude: the side hit dips). Ignored when mirroring.
func impulse(direction: Vector2, magnitude: float) -> void:
	if _mirrored:
		return
	var dir: Vector2 = direction.normalized()
	if dir == Vector2.ZERO or magnitude == 0.0:
		return
	_velocity += Vector2(dir.y, -dir.x) * magnitude
	_wake()


## Advances the spring by delta. Returns true when the disc transform must be
## rewritten (tilt changed since the last mark_applied()).
func step(delta: float, balance: Balance, samples: PackedVector3Array) -> bool:
	if _mirrored:
		return false
	var stiffness: float = _tuning.spring_stiffness()
	var damping: float = _tuning.spring_damping()
	var forcing_accel: Vector2 = _forcing_accel(balance, samples)
	# at rest the disc stays bit-static (no write) until the spring's
	# target moves clear of the tilt, so balance-torque noise cannot keep it moving.
	var rest_target: Vector2 = Vector2.ZERO
	if stiffness > 0.0:
		rest_target = forcing_accel / stiffness
	if _at_rest:
		if (rest_target - _tilt).length() < _tuning.rest_wake_position_rad:
			return false
		_wake()
	var accel: Vector2 = (-stiffness * _tilt) - (damping * _velocity) + forcing_accel
	_velocity += accel * delta
	# Snap the velocity to zero once velocity and position error are both within
	# tilt_settle_relative_epsilon of the spring's target: a critically damped
	# spring only asymptotes, and a different transform every tick would keep Jolt
	# and every block resting on the disc active. The scale is the driving target,
	# not the live tilt (scaling off a clamped tilt froze the disc at the ceiling).
	var target_tilt: Vector2 = Vector2.ZERO
	if stiffness > 0.0:
		target_tilt = forcing_accel / stiffness
	var settle_scale: float = maxf(target_tilt.length(), _tuning.tilt_settle_floor_rad)
	var epsilon: float = _tuning.tilt_settle_relative_epsilon
	var velocity_settled: bool = (
		_velocity.length() < epsilon * _tuning.angular_frequency() * settle_scale
	)
	var position_settled: bool = (target_tilt - _tilt).length() < epsilon * settle_scale
	if velocity_settled and position_settled:
		_velocity = Vector2.ZERO
	_tilt += _velocity * delta
	_clamp()
	if (
		_velocity.length() < _tuning.rest_velocity_rad_s
		and (rest_target - _tilt).length() < _tuning.rest_position_rad
	):
		_rest_timer += delta
		if _rest_timer >= _tuning.rest_hold_s:
			_velocity = Vector2.ZERO
			_at_rest = true
	else:
		_rest_timer = 0.0
	# Once the snap has zeroed the velocity the tilt is bit-for-bit unchanged;
	# rewriting the same kinematic transform would keep resting blocks awake.
	return _tilt != _last_applied


## The caller wrote the transform for tilt().
func mark_applied() -> void:
	_last_applied = _tilt


## Mirror mode: the tilt is read off the replicated pose and step() stops.
func set_pose(tilt: Quaternion) -> void:
	_mirrored = true
	_tilt = _vector_from_quaternion(tilt)
	_velocity = Vector2.ZERO
	_wake()


func tilt() -> Vector2:
	return _tilt


## Rx(tilt.x) * Rz(tilt.y): two independent small-angle rotations in a fixed
## order, the exact inverse of the impulse decomposition and set_pose().
func basis() -> Basis:
	return Basis(Vector3.RIGHT, _tilt.x) * Basis(Vector3.BACK, _tilt.y)


## Field drops sync_to_physics when this is true.
func is_at_rest() -> bool:
	return _at_rest


## Level, still, spring live again (mirror mode dropped), torque unlatched.
func reset() -> void:
	_tilt = Vector2.ZERO
	_velocity = Vector2.ZERO
	_wake()
	_mirrored = false
	_torque = Vector2.ZERO


func _wake() -> void:
	_at_rest = false
	_rest_timer = 0.0


## The torque acceleration for this tick; SAMPLED sums mass * lever arm
## (Vector2(z, -x) * mass per sample = (x, mass, z)) into the latch, and an
## empty sample set keeps the latch like HOLD.
func _forcing_accel(balance: Balance, samples: PackedVector3Array) -> Vector2:
	match balance:
		Balance.OFF:
			return Vector2.ZERO
		Balance.EMPTY:
			_torque = Vector2.ZERO
			return Vector2.ZERO
		Balance.SAMPLED:
			if not samples.is_empty():
				var torque: Vector2 = Vector2.ZERO
				for sample: Vector3 in samples:
					torque += Vector2(sample.z, -sample.x) * sample.y
				_torque = torque
	return _torque * _tuning.physical_balance_torque_gain


## Clamps the tilt magnitude to max_tilt_deg and drops the outward part of the
## velocity, so a saturated hit does not re-clamp every tick while it decays.
func _clamp() -> void:
	var max_rad: float = _tuning.max_tilt_rad()
	var magnitude: float = _tilt.length()
	if magnitude <= max_rad or magnitude <= 0.0:
		return
	var outward: Vector2 = _tilt / magnitude
	var radial_speed: float = _velocity.dot(outward)
	if radial_speed > 0.0:
		_velocity -= outward * radial_speed
	_tilt = outward * max_rad


func _vector_from_quaternion(tilt: Quaternion) -> Vector2:
	var b: Basis = Basis(tilt)
	return Vector2(atan2(-b.z.y, b.z.z), atan2(-b.y.x, b.x.x))
