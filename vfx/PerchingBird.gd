class_name PerchingBird
extends Node3D
## Bontago-adt.3: one cosmetic cel-shaded low-poly bird (procedurally lofted
## meshes, see PerchingBirdModel; no assets). Owned and steered by vfx/PerchingBirds.gd, which decides
## when it spawns, where it lands and when it must flee; this class only knows
## how to fly a given path, land, idle and escape. Purely visual: no physics
## body, no collision, never networked.
##
## The model points along local +X with +Y up; its origin is the body centre,
## `perch_height()` above whatever surface it stands on.

enum State { CIRCLE, GLIDE, PERCHED, FLEE }

## Emitted when a glide ends with the bird standing at its spot.
signal landed
## Emitted when a fleeing bird has flown far enough away and is about to free itself.
signal departed

# Flight animation.
const FLAP_UP_CENTRE_DEG: float = 12.0
const FLAP_AMPLITUDE_DEG: float = 48.0
const GLIDE_WING_UP_DEG: float = 18.0
const FLARE_FLAP_MULT: float = 1.6
const FLARE_START: float = 0.8
const FLARE_PITCH_DEG: float = 28.0
const BANK_PER_TURN: float = 0.5
const BANK_MAX_RAD: float = 0.6
const CIRCLE_BOB_M: float = 0.6
const CIRCLE_BOB_HZ: float = 0.31
const LAND_EASE_POWER: float = 1.7
const GLIDE_SPEED_FACTOR: float = 0.8
const GLIDE_START_TANGENT: float = 0.4
const GLIDE_END_TANGENT: float = 0.35
const GLIDE_END_LIFT: float = 0.1
const FLEE_MAX_LIFETIME_S: float = 40.0
const FLEE_PITCH_LERP: float = 6.0
const FLEE_MAX_ALTITUDE_M: float = 260.0

# Perched animation.
const HEAD_TURN_MAX_DEG: float = 75.0
const HEAD_LERP: float = 9.0
const PECK_DOWN_DEG: float = 58.0
const PECK_HZ: float = 2.6
const PECK_COUNT_MAX: int = 3
const LOOK_HOLD_MIN_S: float = 0.5
const LOOK_HOLD_MAX_S: float = 1.3
const HOP_TIME_S: float = 0.32
const TURN_TO_HOP_LERP: float = 14.0
const TAIL_WAG_HZ: float = 0.9
const TAIL_WAG_DEG: float = 6.0

enum Idle { NONE, LOOK, PECK, HOP }

var state: State = State.CIRCLE
var length_m: float = 0.8
var config: AmbientLifeConfig = null

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _flap_phase: float = 0.0

var _head: Node3D = null
var _tail: Node3D = null
var _left_wing: Node3D = null
var _right_wing: Node3D = null
var _legs: Node3D = null

# Circle state.
var _circle_centre: Vector3 = Vector3.ZERO
var _circle_radius: float = 60.0
var _circle_altitude: float = 20.0
var _circle_angle: float = 0.0
var _circle_dir: float = 1.0
var _circle_time_left: float = 0.0

# Glide state.
var _bezier: Array[Vector3] = []
var _glide_time: float = 1.0
var _glide_elapsed: float = 0.0
var _glide_heading: Vector3 = Vector3.RIGHT

# Flee state.
var _flee_dir: Vector3 = Vector3.RIGHT
var _flee_speed: float = 0.0
var _flee_turn_sign: float = 1.0
var _flee_age: float = 0.0
var _flee_centre: Vector3 = Vector3.ZERO
var _prev_yaw: float = 0.0
var _turn_rate: float = 0.0
var _pitch_smoothed: float = 0.0

# Perched state.
var _heading: Vector3 = Vector3.RIGHT
var _idle: Idle = Idle.NONE
var _idle_timer: float = 0.0
var _idle_elapsed: float = 0.0
var _head_yaw_target: float = 0.0
var _head_yaw: float = 0.0
var _peck_count: int = 0
var _hop_from: Vector3 = Vector3.ZERO
var _hop_to: Vector3 = Vector3.ZERO
var _hop_valid: Callable = Callable()
var allow_hop: bool = true

## Surface point the bird stands on while perched (world).
var perch_surface: Vector3 = Vector3.ZERO


func setup(
	life: AmbientLifeConfig,
	length: float,
	body_color: Color,
	material: Material,
	seed_value: int
) -> void:
	config = life
	length_m = length
	_rng.seed = seed_value
	_build_model(body_color, material)
	_flap_phase = _rng.randf() * TAU


## Height of the body centre above the surface the bird stands on.
func perch_height() -> float:
	return PerchingBirdModel.STAND_HEIGHT * length_m


func is_perched() -> bool:
	return state == State.PERCHED


func is_flying_in() -> bool:
	return state == State.CIRCLE or state == State.GLIDE


## The world point the bird is heading to / standing on (perch surface point).
func target_surface() -> Vector3:
	return perch_surface


func begin_circle(centre: Vector3, radius: float, altitude: float, angle: float, direction: float, duration: float) -> void:
	state = State.CIRCLE
	_circle_centre = centre
	_circle_radius = radius
	_circle_altitude = altitude
	_circle_angle = angle
	_circle_dir = 1.0 if direction >= 0.0 else -1.0
	_circle_time_left = duration
	_apply_circle_pose(0.0)


## Keeps circling for `duration` more seconds (no landing spot was available).
func extend_circle(duration: float) -> void:
	_circle_time_left = duration


func circle_time_left() -> float:
	return _circle_time_left


## Starts the glide to `surface` (the standing surface point). `hop_valid` is
## Callable(Vector3 world) -> bool that vets hop targets while perched.
func begin_glide(surface: Vector3, hop_check: Callable, hop_allowed: bool) -> void:
	state = State.GLIDE
	perch_surface = surface
	_hop_valid = hop_check
	allow_hop = hop_allowed
	var start: Vector3 = global_position
	var target: Vector3 = surface + Vector3.UP * perch_height()
	var flat: Vector3 = Vector3(target.x - start.x, 0.0, target.z - start.z)
	var flat_dir: Vector3 = flat.normalized() if flat.length() > 0.001 else _current_heading()
	var start_heading: Vector3 = _current_heading()
	start_heading.y = 0.0
	start_heading = start_heading.normalized() if start_heading.length() > 0.001 else flat_dir
	var span: float = start.distance_to(target)
	_bezier = [
		start,
		start + start_heading * span * GLIDE_START_TANGENT,
		target - flat_dir * span * GLIDE_END_TANGENT + Vector3.UP * span * GLIDE_END_LIFT,
		target,
	]
	var speed: float = maxf(config.flight_speed_mps * GLIDE_SPEED_FACTOR, 0.5)
	_glide_time = maxf(span / speed, 0.5)
	_glide_elapsed = 0.0
	_glide_heading = flat_dir


## Escape: climbs away from `threat` (world point) along a curved path.
func begin_flee(threat: Vector3, curve_centre: Vector3) -> void:
	var was_perched: bool = state == State.PERCHED
	state = State.FLEE
	_flee_centre = curve_centre
	var away: Vector3 = Vector3(global_position.x - threat.x, 0.0, global_position.z - threat.z)
	if away.length() < 0.05:
		away = _current_heading()
		away.y = 0.0
	_flee_dir = away.normalized()
	_flee_speed = 0.0 if was_perched else config.flight_speed_mps
	_flee_turn_sign = 1.0 if _rng.randf() < 0.5 else -1.0
	_flee_age = 0.0
	_prev_yaw = atan2(-_flee_dir.z, _flee_dir.x)
	_heading = _flee_dir
	_pitch_smoothed = 0.0
	_idle = Idle.NONE
	_set_legs_visible(was_perched)


func update(delta: float) -> void:
	match state:
		State.CIRCLE:
			_update_circle(delta)
		State.GLIDE:
			_update_glide(delta)
		State.PERCHED:
			_update_perched(delta)
		State.FLEE:
			_update_flee(delta)


# --- Circle ----------------------------------------------------------------------

func _update_circle(delta: float) -> void:
	_circle_time_left -= delta
	_apply_circle_pose(delta)


func _apply_circle_pose(delta: float) -> void:
	var angular_speed: float = config.flight_speed_mps / maxf(_circle_radius, 1.0)
	_circle_angle += _circle_dir * angular_speed * delta
	var bob: float = sin(Time.get_ticks_msec() * 0.001 * TAU * CIRCLE_BOB_HZ + _circle_angle * 3.0) * CIRCLE_BOB_M
	var radial: Vector3 = Vector3(cos(_circle_angle), 0.0, sin(_circle_angle))
	global_position = _circle_centre + radial * _circle_radius + Vector3(0.0, _circle_altitude + bob, 0.0)
	var tangent: Vector3 = Vector3(-radial.z, 0.0, radial.x) * _circle_dir
	var bank: float = -_circle_dir * clampf(angular_speed * BANK_PER_TURN * 6.0, 0.0, BANK_MAX_RAD)
	_orient(tangent, 0.0, bank)
	_animate_flight(delta, 1.0, false)


# --- Glide / landing ---------------------------------------------------------------

func _update_glide(delta: float) -> void:
	_glide_elapsed += delta
	var t: float = clampf(_glide_elapsed / _glide_time, 0.0, 1.0)
	var eased: float = 1.0 - pow(1.0 - t, LAND_EASE_POWER)
	global_position = _bezier_point(eased)
	var tangent: Vector3 = _bezier_tangent(eased)
	var flat_len: float = Vector2(tangent.x, tangent.z).length()
	var pitch: float = atan2(tangent.y, maxf(flat_len, 0.001))
	if t > FLARE_START:
		var flare: float = (t - FLARE_START) / (1.0 - FLARE_START)
		pitch = lerpf(pitch, deg_to_rad(FLARE_PITCH_DEG), flare)
	_orient(Vector3(tangent.x, 0.0, tangent.z), pitch, 0.0)
	var flare_amount: float = clampf((t - FLARE_START) / (1.0 - FLARE_START), 0.0, 1.0)
	_animate_flight(delta, lerpf(0.5, FLARE_FLAP_MULT, flare_amount), t < FLARE_START * 0.6)
	_set_legs_visible(t > FLARE_START)
	if t >= 1.0:
		_land()


func _bezier_point(t: float) -> Vector3:
	var u: float = 1.0 - t
	return (
		_bezier[0] * u * u * u
		+ _bezier[1] * 3.0 * u * u * t
		+ _bezier[2] * 3.0 * u * t * t
		+ _bezier[3] * t * t * t
	)


func _bezier_tangent(t: float) -> Vector3:
	var u: float = 1.0 - t
	var d: Vector3 = (
		(_bezier[1] - _bezier[0]) * 3.0 * u * u
		+ (_bezier[2] - _bezier[1]) * 6.0 * u * t
		+ (_bezier[3] - _bezier[2]) * 3.0 * t * t
	)
	return d if d.length() > 0.0001 else _glide_heading


func _land() -> void:
	state = State.PERCHED
	global_position = perch_surface + Vector3.UP * perch_height()
	_heading = Vector3(_glide_heading.x, 0.0, _glide_heading.z).normalized()
	_orient(_heading, 0.0, 0.0)
	_set_legs_visible(true)
	_idle = Idle.NONE
	_idle_timer = _rng.randf_range(config.idle_action_min_s, config.idle_action_max_s)
	_head_yaw = 0.0
	_head_yaw_target = 0.0
	landed.emit()


# --- Perched idle ------------------------------------------------------------------

func _update_perched(delta: float) -> void:
	_pose_wings(0.0, 1.0, 1.0)
	_idle_timer -= delta
	_idle_elapsed += delta
	match _idle:
		Idle.NONE:
			_head_yaw_target = 0.0
			_head.rotation.z = lerpf(_head.rotation.z, 0.0, clampf(HEAD_LERP * delta, 0.0, 1.0))
			if _idle_timer <= 0.0:
				_start_idle_action()
		Idle.LOOK:
			_head.rotation.z = lerpf(_head.rotation.z, 0.0, clampf(HEAD_LERP * delta, 0.0, 1.0))
			if _idle_timer <= 0.0:
				_end_idle_action()
		Idle.PECK:
			var cycle: float = _idle_elapsed * PECK_HZ
			if cycle >= float(_peck_count):
				_end_idle_action()
			else:
				var dip: float = sin(fposmod(cycle, 1.0) * PI)
				_head.rotation.z = -deg_to_rad(PECK_DOWN_DEG) * dip
		Idle.HOP:
			_update_hop()
	_head_yaw = lerpf(_head_yaw, _head_yaw_target, clampf(HEAD_LERP * delta, 0.0, 1.0))
	_head.rotation.y = _head_yaw
	_tail.rotation.z = deg_to_rad(TAIL_WAG_DEG) * sin(Time.get_ticks_msec() * 0.001 * TAU * TAIL_WAG_HZ) + PerchingBirdModel.TAIL_PITCH_RAD


func _start_idle_action() -> void:
	_idle_elapsed = 0.0
	var roll: float = _rng.randf()
	var hop_chance: float = config.idle_hop_chance if allow_hop else 0.0
	if roll < hop_chance and _try_start_hop():
		return
	if _rng.randf() < 0.5:
		_idle = Idle.LOOK
		_idle_timer = _rng.randf_range(LOOK_HOLD_MIN_S, LOOK_HOLD_MAX_S)
		_head_yaw_target = deg_to_rad(_rng.randf_range(-HEAD_TURN_MAX_DEG, HEAD_TURN_MAX_DEG))
	else:
		_idle = Idle.PECK
		_peck_count = _rng.randi_range(1, PECK_COUNT_MAX)
		_idle_timer = float(_peck_count) / PECK_HZ


func _try_start_hop() -> bool:
	var angle: float = _rng.randf() * TAU
	var offset: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * config.idle_hop_distance_m
	var target: Vector3 = perch_surface + offset
	if _hop_valid.is_valid() and not bool(_hop_valid.call(target)):
		return false
	_idle = Idle.HOP
	_hop_from = perch_surface
	_hop_to = target
	_heading = offset.normalized()
	_idle_timer = HOP_TIME_S
	return true


func _update_hop() -> void:
	var t: float = clampf(1.0 - _idle_timer / HOP_TIME_S, 0.0, 1.0)
	var ground: Vector3 = _hop_from.lerp(_hop_to, t)
	var lift: float = sin(t * PI) * config.idle_hop_height_m
	global_position = ground + Vector3.UP * (perch_height() + lift)
	_orient(_heading, 0.0, 0.0)
	_pose_wings(deg_to_rad(20.0) * sin(t * PI), 1.0, 1.0 - sin(t * PI))
	if _idle_timer <= 0.0:
		perch_surface = _hop_to
		global_position = perch_surface + Vector3.UP * perch_height()
		_end_idle_action()


func _end_idle_action() -> void:
	_idle = Idle.NONE
	_head_yaw_target = 0.0
	_idle_timer = _rng.randf_range(config.idle_action_min_s, config.idle_action_max_s)


# --- Flee ------------------------------------------------------------------------

func _update_flee(delta: float) -> void:
	_flee_age += delta
	var accel_t: float = clampf(_flee_age / maxf(config.flee_accel_time_s, 0.05), 0.0, 1.0)
	var target_speed: float = config.flee_speed_mps
	_flee_speed = lerpf(_flee_speed, target_speed, accel_t * clampf(6.0 * delta, 0.0, 1.0))
	# Curved path: the horizontal heading keeps turning, more so early on.
	var turn: float = deg_to_rad(config.flee_turn_rate_deg) * _flee_turn_sign * lerpf(1.0, 0.35, accel_t)
	_flee_dir = _flee_dir.rotated(Vector3.UP, turn * delta)
	var climb: float = deg_to_rad(config.flee_climb_deg) * clampf(_flee_age / maxf(config.flee_accel_time_s, 0.05) * 1.5, 0.0, 1.0)
	var velocity: Vector3 = (_flee_dir * cos(climb) + Vector3.UP * sin(climb)) * _flee_speed
	global_position += velocity * delta
	var pitch: float = atan2(velocity.y, maxf(Vector2(velocity.x, velocity.z).length(), 0.001))
	_pitch_smoothed = lerpf(_pitch_smoothed, pitch, clampf(FLEE_PITCH_LERP * delta, 0.0, 1.0))
	var yaw: float = atan2(-_flee_dir.z, _flee_dir.x)
	_turn_rate = wrapf(yaw - _prev_yaw, -PI, PI) / maxf(delta, 0.0001)
	_prev_yaw = yaw
	_orient(_flee_dir, _pitch_smoothed, clampf(-_turn_rate * BANK_PER_TURN, -BANK_MAX_RAD, BANK_MAX_RAD))
	_animate_flight(delta, 1.4, false)
	_set_legs_visible(_flee_age < 0.25)
	var away: float = Vector2(global_position.x - _flee_centre.x, global_position.z - _flee_centre.z).length()
	if away > config.despawn_distance_m or global_position.y > FLEE_MAX_ALTITUDE_M or _flee_age > FLEE_MAX_LIFETIME_S:
		departed.emit()


# --- Pose helpers ----------------------------------------------------------------

func _current_heading() -> Vector3:
	var forward: Vector3 = global_transform.basis.x
	return forward.normalized() if forward.length() > 0.001 else Vector3.RIGHT


## Points local +X along `direction` (horizontal part), pitched by `pitch` (rad,
## nose up positive) and banked by `bank` (rad about the forward axis).
func _orient(direction: Vector3, pitch: float, bank: float) -> void:
	var flat: Vector3 = Vector3(direction.x, 0.0, direction.z)
	if flat.length() < 0.0001:
		flat = _heading if _heading.length() > 0.0001 else Vector3.RIGHT
	flat = flat.normalized()
	var yaw: float = atan2(-flat.z, flat.x)
	var oriented: Basis = Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, pitch) * Basis(Vector3.RIGHT, bank)
	global_transform = Transform3D(oriented, global_position)


func _animate_flight(delta: float, rate_mult: float, glide_pose: bool) -> void:
	_head.rotation = Vector3.ZERO
	_tail.rotation.z = PerchingBirdModel.TAIL_PITCH_RAD
	if glide_pose:
		_pose_wings(deg_to_rad(GLIDE_WING_UP_DEG), 1.0, 0.0)
		return
	_flap_phase += TAU * config.flap_rate_hz * rate_mult * delta
	var angle: float = deg_to_rad(FLAP_UP_CENTRE_DEG + sin(_flap_phase) * FLAP_AMPLITUDE_DEG)
	_pose_wings(angle, 1.0, 0.0)


## `up_angle` lifts the wing tips (rad), `span_scale` lengthens/shortens the
## wing, `fold` (0..1) sweeps it back along the flank into the resting pose.
func _pose_wings(up_angle: float, span_scale: float, fold: float) -> void:
	PerchingBirdModel.pose_wings(_left_wing, _right_wing, up_angle, span_scale, fold)


func _set_legs_visible(shown: bool) -> void:
	if _legs != null:
		_legs.visible = shown


# --- Model -----------------------------------------------------------------------

func _build_model(body_color: Color, material: Material) -> void:
	var nodes: Dictionary = PerchingBirdModel.build(self, length_m, body_color, config, material)
	_head = nodes["head"] as Node3D
	_tail = nodes["tail"] as Node3D
	_left_wing = nodes["left"] as Node3D
	_right_wing = nodes["right"] as Node3D
	_legs = nodes["legs"] as Node3D
	_pose_wings(0.0, 1.0, 1.0)
