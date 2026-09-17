class_name PlayerController
extends Node
## Local input -> ghost placement intents (spec 2.5, 3.2). Every action goes
## through the Input Map (bootstrap_project.gd); nothing here reads a raw
## keycode. M1 has no territory rules yet, so every placement is valid and
## the feed is a plain random pick (core/feed/SimpleBlockFeed.gd) — the
## weighted bag and placement validation arrive in M2.

@export var camera_rig_path: NodePath
@export var ghost_path: NodePath
@export var spawn_parent_path: NodePath

@export var tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
@export var ghost_tuning: GhostTuning = preload("res://config/ghost_tuning.tres")
@export var camera_tuning: CameraTuning = preload("res://config/camera_tuning.tres")

var _camera_rig: CameraRig
var _ghost: GhostPreview
var _spawn_parent: Node
var _feed: SimpleBlockFeed

var _using_gamepad_cursor: bool = false
var _gamepad_cursor: Vector3 = Vector3.ZERO
var _gamepad_cursor_velocity: Vector3 = Vector3.ZERO
var _mmb_press_time: float = 0.0


func _ready() -> void:
	_camera_rig = get_node_or_null(camera_rig_path) as CameraRig
	_ghost = get_node_or_null(ghost_path) as GhostPreview
	_spawn_parent = get_node_or_null(spawn_parent_path)
	_feed = SimpleBlockFeed.new(BlockShape.load_all_shapes())
	if _ghost != null:
		_ghost.set_shape(_feed.next())


func _process(delta: float) -> void:
	_update_gamepad_cursor(delta)
	_update_ghost_transform()
	_handle_hover_adjust(delta)
	_handle_gamepad_free_rotate(delta)
	if _camera_rig != null and _ghost != null:
		_camera_rig.block_held = _ghost.get_shape() != null


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		_using_gamepad_cursor = false
		if _ghost != null and Input.is_action_pressed(&"rotate_free_hold"):
			_ghost.apply_free_rotation_delta(
				-motion.relative.x * ghost_tuning.free_rotate_mouse_speed,
				-motion.relative.y * ghost_tuning.free_rotate_mouse_speed
			)
		return

	if event.is_action_pressed(&"camera_orbit_hold"):
		# Spec 2.5: MMB is both rotate_pitch_fwd (a tap) and camera_orbit_hold
		# (a hold, handled continuously in CameraRig). Split by how long the
		# button was down instead of firing rotate_pitch_fwd the instant it's
		# pressed, which would make a deliberate orbit also rotate the block.
		# camera_orbit_hold is bound only to MMB (tools/bootstrap_project.gd),
		# so keying the tap/hold split off it — instead of a raw middle-mouse
		# button check — can't collide with rotate_pitch_fwd's other
		# bindings (shift+wheel-up, D-pad up), which fire immediately through
		# the dispatch chain below.
		_mmb_press_time = Time.get_ticks_msec() / 1000.0
		return

	if event.is_action_released(&"camera_orbit_hold"):
		var held_duration: float = Time.get_ticks_msec() / 1000.0 - _mmb_press_time
		if held_duration < camera_tuning.mmb_tap_max_duration:
			_apply_step(BlockOrientations.step_pitch_fwd(_orientation_index()))
		return

	if event.is_action_pressed(&"rotate_yaw_ccw"):
		_apply_step(BlockOrientations.step_yaw_ccw(_orientation_index()))
	elif event.is_action_pressed(&"rotate_yaw_cw"):
		_apply_step(BlockOrientations.step_yaw_cw(_orientation_index()))
	elif event.is_action_pressed(&"rotate_pitch_fwd"):
		_apply_step(BlockOrientations.step_pitch_fwd(_orientation_index()))
	elif event.is_action_pressed(&"rotate_pitch_back"):
		_apply_step(BlockOrientations.step_pitch_back(_orientation_index()))
	elif event.is_action_pressed(&"rotate_roll_left"):
		_apply_step(BlockOrientations.step_roll_left(_orientation_index()))
	elif event.is_action_pressed(&"rotate_roll_right"):
		_apply_step(BlockOrientations.step_roll_right(_orientation_index()))
	elif event.is_action_pressed(&"rotate_reset"):
		if _ghost != null:
			_ghost.reset_rotation()
	elif event.is_action_pressed(&"ghost_place"):
		_place_ghost_block()


func _orientation_index() -> int:
	return _ghost.orientation_index if _ghost != null else 0


func _apply_step(new_index: int) -> void:
	if _ghost != null:
		_ghost.set_orientation_index(new_index)


func _place_ghost_block() -> void:
	if _ghost == null:
		return
	var shape: BlockShape = _ghost.get_shape()
	if shape == null:
		return
	var block: Block = BlockFactory.build(shape, tuning)
	var parent: Node = _spawn_parent if _spawn_parent != null else get_tree().current_scene
	parent.add_child(block)
	block.global_transform = _ghost.global_transform
	Events.block_placed.emit(block, shape.id)
	_ghost.set_shape(_feed.next())


func _handle_hover_adjust(delta: float) -> void:
	if _ghost == null:
		return
	var change: float = 0.0
	if Input.is_action_pressed(&"hover_raise"):
		change += 1.0
	if Input.is_action_pressed(&"hover_lower"):
		change -= 1.0
	if change == 0.0:
		return
	_ghost.manual_hover_offset = clampf(
		_ghost.manual_hover_offset + change * ghost_tuning.hover_manual_adjust_speed * delta,
		0.0,
		ghost_tuning.hover_manual_max
	)


func _handle_gamepad_free_rotate(delta: float) -> void:
	if _ghost == null or not Input.is_action_pressed(&"rotate_free_hold"):
		return
	var look_x: float = Input.get_action_strength(&"camera_look_right") - Input.get_action_strength(&"camera_look_left")
	var look_y: float = Input.get_action_strength(&"camera_look_down") - Input.get_action_strength(&"camera_look_up")
	if look_x == 0.0 and look_y == 0.0:
		return
	_ghost.apply_free_rotation_delta(
		-look_x * ghost_tuning.free_rotate_pad_speed * delta,
		-look_y * ghost_tuning.free_rotate_pad_speed * delta
	)


## Moves the gamepad's world-space cursor (spec 2.5), relative to the camera,
## with acceleration and speed scaling with zoom.
func _update_gamepad_cursor(delta: float) -> void:
	var stick: Vector2 = Vector2(
		Input.get_action_strength(&"ghost_move_right") - Input.get_action_strength(&"ghost_move_left"),
		Input.get_action_strength(&"ghost_move_back") - Input.get_action_strength(&"ghost_move_forward")
	)
	# DECISION (game/PlayerController.gd): ghost_move_* shares the left stick
	# with camera_pan_* (see CameraRig's DECISION comment). Suppressing ghost
	# movement while camera_modifier is held is the half of that conflict
	# this script controls, so panning with the stick doesn't drag the ghost.
	if Input.is_action_pressed(&"camera_modifier"):
		stick = Vector2.ZERO
	if stick.length() > 1.0:
		stick = stick.normalized()
	if stick.length() > 0.0:
		_using_gamepad_cursor = true

	var max_speed: float = ghost_tuning.gamepad_cursor_base_speed
	if _camera_rig != null and ghost_tuning.gamepad_cursor_zoom_reference_distance > 0.0:
		max_speed *= _camera_rig.get_distance() / ghost_tuning.gamepad_cursor_zoom_reference_distance

	var desired_velocity: Vector3 = _camera_relative_dir(stick) * max_speed
	var velocity_delta: Vector3 = desired_velocity - _gamepad_cursor_velocity
	var max_change: float = ghost_tuning.gamepad_cursor_acceleration * delta
	if velocity_delta.length() > max_change and max_change > 0.0:
		velocity_delta = velocity_delta.normalized() * max_change
	_gamepad_cursor_velocity += velocity_delta
	_gamepad_cursor += _gamepad_cursor_velocity * delta


func _camera_relative_dir(input_2d: Vector2) -> Vector3:
	var yaw: float = _camera_rig.get_yaw() if _camera_rig != null else 0.0
	var forward: Vector3 = Vector3(sin(yaw), 0.0, cos(yaw))
	var right: Vector3 = Vector3(forward.z, 0.0, -forward.x)
	return right * input_2d.x + forward * input_2d.y


## Casts the placement ray (mouse projection, or straight down over the
## gamepad cursor) and updates the ghost. Public so tests can exercise it
## without going through real input devices.
func _update_ghost_transform() -> void:
	if _ghost == null:
		return
	var origin: Vector3
	var direction: Vector3
	if _using_gamepad_cursor:
		origin = _gamepad_cursor + Vector3.UP * 200.0
		direction = Vector3.DOWN
	else:
		if _camera_rig == null:
			return
		var camera: Camera3D = _camera_rig.get_camera()
		if camera == null:
			return
		var mouse_pos: Vector2 = get_viewport().get_mouse_position()
		origin = camera.project_ray_origin(mouse_pos)
		direction = camera.project_ray_normal(mouse_pos)

	var hit: Dictionary = _raycast(origin, direction)
	var hit_point: Vector3
	var hit_normal: Vector3
	if hit.is_empty():
		# Fallback so the ghost has somewhere to go even if the ray misses
		# every physics body (e.g. aimed at the sky before Field is ready).
		var plane: Plane = Plane(Vector3.UP, 0.0)
		var point: Variant = plane.intersects_ray(origin, direction)
		hit_point = (point as Vector3) if point != null else Vector3.ZERO
		hit_normal = Vector3.UP
	else:
		hit_point = hit["position"] as Vector3
		hit_normal = hit["normal"] as Vector3

	_ghost.update_placement(hit_point, hit_normal)


func _raycast(origin: Vector3, direction: Vector3) -> Dictionary:
	var space_state: PhysicsDirectSpaceState3D = get_viewport().world_3d.direct_space_state
	var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		origin, origin + direction.normalized() * ghost_tuning.placement_ray_length
	)
	return space_state.intersect_ray(params)
