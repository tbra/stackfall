class_name CameraRig
extends Node3D
## Orbit/zoom/pan/snap camera rig (spec 2.5 camera row), driven only by the
## Input Map actions bootstrap_project.gd defines. CLAUDE.md: no raw keycodes
## and no deep node paths — this rig only ever reaches its own Camera3D child.

@export var tuning: CameraTuning = preload("res://config/camera_tuning.tres")
@export var map_def: MapDef = preload("res://config/maps/round_medium.tres")

## Set by PlayerController each frame: true while the player holds a ghost
## block. Spec 2.5 scopes wheel/trigger zoom to "while not holding a block";
## the dedicated Z/X keys always zoom regardless (see _unhandled_input).
var block_held: bool = false

var _yaw: float = 0.0
var _pitch: float = 0.0
var _distance: float = 0.0
var _target: Vector3 = Vector3.ZERO

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	_distance = tuning.snap_distance
	_pitch = deg_to_rad(tuning.snap_pitch_deg)
	_update_transform()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		if Input.is_action_pressed(&"camera_orbit_hold"):
			_yaw -= motion.relative.x * tuning.mouse_orbit_speed
			_pitch -= motion.relative.y * tuning.mouse_orbit_speed
			_clamp_pitch()
			_update_transform()
		elif Input.is_action_pressed(&"camera_modifier"):
			_target += _pan_offset(Vector2(-motion.relative.x, motion.relative.y)) * tuning.mouse_pan_speed
			_update_transform()
		return

	# DECISION (game/CameraRig.gd): camera_zoom_in/out are bound to Z/X keys
	# AND to the mouse wheel/gamepad triggers, which also mean rotate_yaw or
	# throw_aim/rotate_free_hold while a block is held (spec 2.5 scopes wheel/
	# trigger zoom to "while not holding a block"). Checking the event's class
	# (key vs. wheel/trigger) distinguishes the two without reading a raw
	# keycode: Z/X always zoom, the shared inputs only zoom when free.
	if event.is_action_pressed(&"camera_zoom_in"):
		if event is InputEventKey or not block_held:
			_zoom(-1.0)
	elif event.is_action_pressed(&"camera_zoom_out"):
		if event is InputEventKey or not block_held:
			_zoom(1.0)
	elif event.is_action_pressed(&"camera_snap_home"):
		_snap_to(_home_point())
	elif event.is_action_pressed(&"camera_snap_goal"):
		_snap_to(Vector3.ZERO)


func _process(delta: float) -> void:
	var look_x: float = Input.get_action_strength(&"camera_look_right") - Input.get_action_strength(&"camera_look_left")
	var look_y: float = Input.get_action_strength(&"camera_look_down") - Input.get_action_strength(&"camera_look_up")
	if look_x != 0.0 or look_y != 0.0:
		_yaw -= look_x * tuning.pad_orbit_speed * delta
		_pitch -= look_y * tuning.pad_orbit_speed * delta
		_clamp_pitch()

	# DECISION (game/CameraRig.gd): camera_pan_* shares its gamepad axis with
	# ghost_move_* (both read the left stick). PlayerController suppresses
	# ghost movement while camera_modifier is held so the player can pan
	# cleanly; this rig applies pan from the action strength unconditionally,
	# so nudging the stick to move the ghost also pans the camera a little.
	# That's a minor, documented side effect rather than a hard bug for M1.
	var pan_x: float = Input.get_action_strength(&"camera_pan_right") - Input.get_action_strength(&"camera_pan_left")
	var pan_z: float = Input.get_action_strength(&"camera_pan_back") - Input.get_action_strength(&"camera_pan_forward")
	if pan_x != 0.0 or pan_z != 0.0:
		_target += _pan_offset(Vector2(pan_x, pan_z)) * tuning.pan_speed * delta

	_update_transform()


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
