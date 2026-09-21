class_name CameraRig
extends Node3D
## Orbit/zoom/pan/snap camera rig (spec 2.5 camera row), driven only by the
## Input Map actions bootstrap_project.gd defines. CLAUDE.md: no raw keycodes
## and no deep node paths — this rig only ever reaches its own Camera3D child.
##
## Bontago-mv0.14 (original-style block-locked camera, spec 1.5,
## docs/ORIGINAL_BONTAGO_NOTES.md "Controls"): the original's camera is
## attached to the held block, so by default (CameraTuning.follow_block) this
## rig's pivot (_target) tracks whatever position PlayerController reports
## through set_follow_position() every frame, smoothed by
## tuning.follow_lag_seconds, instead of sitting still until panned. Orbit
## (camera_mode + mouse, or the gamepad's right stick, unconditionally) and
## zoom still work the same as before; pan and the snap-to-home/goal actions
## are no-ops in follow mode, since there is no free target to move -- see
## the DECISION comments below. Setting follow_block = false on the
## CameraTuning resource restores the exact pre-mv0.14 free-orbit behaviour
## (manual pan, snap-to actions), so a test can still pin it deliberately.

@export var tuning: CameraTuning = preload("res://config/camera_tuning.tres")
@export var map_def: MapDef = preload("res://config/maps/round_medium.tres")

## Set by PlayerController each frame: true while the player holds a ghost
## block. Spec 2.5 scopes trigger zoom to "while not holding a block"; the
## dedicated Z/X keys always zoom regardless (see _unhandled_input).
var block_held: bool = false

var _yaw: float = 0.0
var _pitch: float = 0.0
var _distance: float = 0.0
var _target: Vector3 = Vector3.ZERO
## Where PlayerController says the held ghost is, updated by
## set_follow_position() every frame. Only read when tuning.follow_block.
var _follow_position: Vector3 = Vector3.ZERO

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	# DECISION (game/CameraRig.gd): the initial view scales with the map's
	# field_radius (a close-in fixed default looked fine on a small map but
	# was nose-to-the-glass on a medium/large one, since the disk fills most
	# of the frame at any distance shorter than roughly its own radius).
	# tuning.snap_distance is still used as-is for camera_snap_home/goal,
	# which are deliberately closer-in views.
	if tuning.follow_block:
		# Following the held block: a close, shallow view like the original's
		# (config/CameraTuning.follow_distance / follow_pitch_deg), not the
		# whole-disk overview the free camera starts from.
		_distance = clampf(tuning.follow_distance, tuning.zoom_min, tuning.zoom_max)
		_pitch = deg_to_rad(tuning.follow_pitch_deg)
	else:
		_distance = clampf(map_def.field_radius * 1.4, tuning.zoom_min, tuning.zoom_max)
		_pitch = deg_to_rad(tuning.snap_pitch_deg)
	_update_transform()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		if Input.is_action_pressed(&"camera_mode"):
			_yaw -= motion.relative.x * tuning.mouse_orbit_speed
			_pitch -= motion.relative.y * tuning.mouse_orbit_speed
			_clamp_pitch()
			_update_transform()
		elif not tuning.follow_block and Input.is_action_pressed(&"camera_modifier"):
			# DECISION (game/CameraRig.gd): manual pan only makes sense for the
			# legacy free-orbit camera -- follow mode re-centers _target on the
			# ghost every frame (see _process()), so a pan offset here would be
			# overwritten within a frame or two anyway.
			_target += _pan_offset(Vector2(-motion.relative.x, motion.relative.y)) * tuning.mouse_pan_speed
			_update_transform()
		return

	# DECISION (game/CameraRig.gd): camera_zoom_in/out are bound to Z/X keys
	# AND to the gamepad triggers, which also mean throw_aim/rotation_mode
	# while a block is held (spec 2.5 scopes trigger zoom to "while not
	# holding a block"). Checking the event's class (key vs. trigger)
	# distinguishes the two without reading a raw keycode: Z/X always zoom,
	# the shared trigger inputs only zoom when free. Bontago-mv0.14: the wheel
	# used to double as zoom too; it is now block height only (ghost_tuning's
	# hover_raise/hover_lower), so it is out of this action entirely (see
	# tools/bootstrap_project.gd).
	if event.is_action_pressed(&"camera_zoom_in"):
		if event is InputEventKey or not block_held:
			_zoom(-1.0)
	elif event.is_action_pressed(&"camera_zoom_out"):
		if event is InputEventKey or not block_held:
			_zoom(1.0)
	elif not tuning.follow_block and event.is_action_pressed(&"camera_snap_home"):
		_snap_to(_home_point())
	elif not tuning.follow_block and event.is_action_pressed(&"camera_snap_goal"):
		_snap_to(Vector3.ZERO)


func _process(delta: float) -> void:
	# The gamepad's right stick always free-orbits (spec 2.5's camera row has
	# no gamepad hold requirement; see test_project_setup.gd's DEVICE_EXCEPTIONS
	# for camera_mode). Bontago-mv0.14 removed the previous rotate_free_hold
	# conflict here: that action is now rotation_mode, which reuses the *left*
	# stick (PlayerController._accumulate_rotation_drag), so the right stick no
	# longer has a second job to gate against.
	var look_x: float = Input.get_action_strength(&"camera_look_right") - Input.get_action_strength(&"camera_look_left")
	var look_y: float = Input.get_action_strength(&"camera_look_down") - Input.get_action_strength(&"camera_look_up")
	if look_x != 0.0 or look_y != 0.0:
		_yaw -= look_x * tuning.pad_orbit_speed * delta
		_pitch -= look_y * tuning.pad_orbit_speed * delta
		_clamp_pitch()

	if tuning.follow_block:
		# Bontago-mv0.14 (spec 1.5, "the camera is attached to the held
		# block"): smoothly close the distance to wherever PlayerController
		# last reported the ghost, rather than a hard snap -- an exponential
		# approach so a sudden large motion (e.g. a mode switch) doesn't jerk
		# the camera. follow_lag_seconds == 0 degrades to an exact snap.
		var weight: float = 1.0
		if tuning.follow_lag_seconds > 0.0:
			weight = 1.0 - exp(-delta / tuning.follow_lag_seconds)
		_target = _target.lerp(_follow_position, clampf(weight, 0.0, 1.0))
	else:
		# DECISION (game/CameraRig.gd): camera_pan_* shares its gamepad axis
		# with ghost_move_* (both read the left stick). PlayerController
		# suppresses ghost movement while camera_modifier is held so the
		# player can pan cleanly; this rig applies pan from the action
		# strength unconditionally, so nudging the stick to move the ghost
		# also pans the camera a little in this legacy (follow_block = false)
		# mode. That's a minor, documented side effect, not a hard bug.
		var pan_x: float = Input.get_action_strength(&"camera_pan_right") - Input.get_action_strength(&"camera_pan_left")
		var pan_z: float = Input.get_action_strength(&"camera_pan_back") - Input.get_action_strength(&"camera_pan_forward")
		if pan_x != 0.0 or pan_z != 0.0:
			_target += _pan_offset(Vector2(pan_x, pan_z)) * tuning.pan_speed * delta

	_update_transform()


## Bontago-mv0.14: called by PlayerController every frame with the held
## ghost's world position. Only used while tuning.follow_block is true; the
## legacy free-orbit camera ignores it.
func set_follow_position(pos: Vector3) -> void:
	_follow_position = pos


## Used by PlayerController to scale gamepad ghost-cursor speed with zoom
## (spec 2.5: "speed scales with camera zoom").
func get_distance() -> float:
	return _distance


## Used by PlayerController to move the ghost cursor relative to the
## camera's current facing (both mouse and gamepad -- Bontago-mv0.14).
func get_yaw() -> float:
	return _yaw


func get_camera() -> Camera3D:
	return _camera


## For tests: where the rig's pivot currently sits (its "look at" point).
func get_target() -> Vector3:
	return _target


func _clamp_pitch() -> void:
	_pitch = clampf(_pitch, deg_to_rad(tuning.min_pitch_deg), deg_to_rad(tuning.max_pitch_deg))


func _zoom(direction: float) -> void:
	_distance = clampf(_distance + direction * tuning.zoom_step, tuning.zoom_min, tuning.zoom_max)


func _pan_offset(input_2d: Vector2) -> Vector3:
	var forward: Vector3 = Vector3(sin(_yaw), 0.0, cos(_yaw))
	var right: Vector3 = Vector3(forward.z, 0.0, -forward.x)
	return right * input_2d.x + forward * input_2d.y


func _home_point() -> Vector3:
	# DECISION (game/CameraRig.gd): M1 has no players or flags yet (those
	# arrive in M2), so "snap to home" targets the disk edge nearest the
	# current yaw instead of a real player flag.
	var direction: Vector3 = Vector3(sin(_yaw), 0.0, cos(_yaw))
	return direction * (map_def.field_radius * 0.85)


func _snap_to(point: Vector3) -> void:
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, ^"_target", point, tuning.snap_duration)
	tween.tween_property(self, ^"_distance", tuning.snap_distance, tuning.snap_duration)
	tween.tween_property(self, ^"_pitch", deg_to_rad(tuning.snap_pitch_deg), tuning.snap_duration)


func _update_transform() -> void:
	var offset: Vector3 = Vector3(
		sin(_yaw) * cos(_pitch),
		-sin(_pitch),
		cos(_yaw) * cos(_pitch)
	) * _distance
	global_position = _target
	_camera.position = offset
	_camera.look_at(_target, Vector3.UP)
