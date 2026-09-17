class_name PlayerController
extends Node
## Local input -> placement intents (spec 2.5, 3.2; docs/M2_PLAN.md P4).
## Every action goes through the Input Map (bootstrap_project.gd); nothing
## here reads a raw keycode.
##
## M2 makes placement intent-only (spec 3.4, "clients send intents; the host
## checks every intent before acting on it"): this script never builds a
## Block itself. It raycasts the ghost, tracks whose turn it is in hot-seat
## (docs/M2_PLAN.md owner decision 1: strict alternation), and calls
## Match.request_place(); Match alone decides what happens next and answers
## on the Events bus.

const BLOCKS_DIR: String = "res://config/blocks/"

@export var camera_rig_path: NodePath
@export var ghost_path: NodePath
## DECISION (game/PlayerController.gd): M2 makes placement intent-only, so
## this controller no longer spawns blocks itself and has no real use for a
## spawn parent. The export stays so the still-M1-shaped game/Main.tscn (only
## the integrator may touch Main.*, per docs/M2_PLAN.md) keeps loading without
## an "unknown property" warning until step 3 of the plan's integration order
## rewires it to Match.register_world().
@export var spawn_parent_path: NodePath

@export var tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
@export var ghost_tuning: GhostTuning = preload("res://config/ghost_tuning.tres")
@export var camera_tuning: CameraTuning = preload("res://config/camera_tuning.tres")

var _camera_rig: CameraRig
var _ghost: GhostPreview

## DECISION (game/PlayerController.gd): Match is a global autoload (like
## Events), so gameplay code normally calls `Match.foo()` directly with full
## static type-checking. This one field breaks that pattern on purpose: GUT
## cannot double a plain autoload the way it doubles engine singletons (see
## addons/gut/test.gd's double_singleton — it only recognizes Godot's own
## engine singletons), so tests need a seam to inject a fake Match ahead of
## P2 landing the real one. `Variant` keeps the declaration explicit (not
## "untyped" under CLAUDE.md's error-on-warning rule) while allowing dynamic
## dispatch to whatever object is assigned.
var _match: Variant = null

var _shapes_by_id: Dictionary = {}

## Hot-seat: which slot this controller currently acts for (spec M2 owner
## decision 1: strict alternation, only the active slot's timer/controls do
## anything). -1 until the first Events.turn_changed.
var _active_slot: int = -1

var _using_gamepad_cursor: bool = false
var _gamepad_cursor: Vector3 = Vector3.ZERO
var _gamepad_cursor_velocity: Vector3 = Vector3.ZERO
var _mmb_press_time: float = 0.0


func _ready() -> void:
	_camera_rig = get_node_or_null(camera_rig_path) as CameraRig
	_ghost = get_node_or_null(ghost_path) as GhostPreview
	_match = Match
	_shapes_by_id = _load_shapes_by_id()
	Events.turn_changed.connect(_on_turn_changed)
	Events.feed_block_issued.connect(_on_feed_block_issued)
	Events.feed_timer_expired.connect(_on_feed_timer_expired)
	Events.placement_rejected.connect(_on_placement_rejected)


## HotSeat.gd calls this after Main builds the shared CameraRig: HotSeat.tscn
## is self-contained (docs/M2_PLAN.md), but the camera rig lives in Main's
## tree, so it can't be wired by NodePath at scene-author time.
func set_camera_rig(rig: CameraRig) -> void:
	_camera_rig = rig


func _process(delta: float) -> void:
	_update_gamepad_cursor(delta)
	_update_ghost_transform()
	_update_ghost_tint()
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

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		# Spec 2.5: MMB is both rotate_pitch_fwd (a tap) and camera_orbit_hold
		# (a hold, handled continuously in CameraRig). Split by how long the
		# button was down instead of firing rotate_pitch_fwd the instant it's
		# pressed, which would make a deliberate orbit also rotate the block.
		var mouse_button: InputEventMouseButton = event
		if mouse_button.pressed:
			_mmb_press_time = Time.get_ticks_msec() / 1000.0
		else:
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


# --- Placement intent (spec 3.4) --------------------------------------------

## ghost_place: send exactly one intent to Match and let it decide. Never
## builds a Block itself (spec 3.4; docs/M2_PLAN.md P4 "intent-only
## placement").
func _place_ghost_block() -> void:
	if _ghost == null or _match == null or _active_slot < 0:
		return
	if _ghost.get_shape() == null:
		return
	if _is_active_slot_eliminated():
		return
	_request_place(false)


func _request_place(auto_drop: bool) -> StringName:
	var reason: StringName = _match.request_place(
		_active_slot, _ghost.global_position, _ghost.orientation_index, _ghost.free_quaternion, auto_drop
	)
	return reason


## Spec M2 owner decision 3: a slot whose home flag is gone is effectively
## eliminated. Match.slot(id).home_flag_alive is the one already-documented
## source of truth for this — no dedicated Events signal exists for it, so
## rather than inventing one on a stub I don't own, both the controller and
## the HUD just read PlayerSlot.home_flag_alive off Match.slot() (see
## ui/HUD.gd's matching DECISION).
func _is_active_slot_eliminated() -> bool:
	if _match == null or _active_slot < 0:
		return false
	var slot: PlayerSlot = _match.slot(_active_slot)
	return slot != null and not slot.home_flag_alive


# --- Events reactions (spec 3.7, M2 owner decision 1) -----------------------

func _on_turn_changed(slot_id: int) -> void:
	_active_slot = slot_id
	if _match == null:
		return
	var slot: PlayerSlot = _match.slot(slot_id)
	if _ghost == null:
		return
	if slot != null:
		_ghost.set_player_color(slot.color)
	var shape: BlockShape = _match.held_shape(slot_id)
	if shape != null:
		_ghost.set_shape(shape)


func _on_feed_block_issued(slot_id: int, shape_id: StringName, _next_shape_id: StringName) -> void:
	if slot_id != _active_slot or _ghost == null:
		return
	var shape: BlockShape = _shapes_by_id.get(shape_id) as BlockShape
	if shape != null:
		_ghost.set_shape(shape)


func _on_feed_timer_expired(slot_id: int) -> void:
	if slot_id != _active_slot or _ghost == null or _is_active_slot_eliminated():
		return
	_ghost.play_auto_drop_flash()
	_request_place(true)


func _on_placement_rejected(slot_id: int, _reason: StringName) -> void:
	if slot_id != _active_slot or _ghost == null:
		return
	_ghost.play_reject_animation()


## Every frame: the read-only, advisory preview (spec 2.5) that tints the
## ghost before the click. request_place() re-validates from scratch and
## never trusts this (spec 3.4).
func _update_ghost_tint() -> void:
	if _ghost == null or _match == null or _active_slot < 0:
		return
	if _ghost.get_shape() == null:
		return
	var result: PlacementRules.Result = _match.preview_placement(
		_active_slot, _ghost.global_position, _ghost.orientation_index, _ghost.free_quaternion
	)
	_ghost.apply_validity(result)


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
		hit_point = point if point != null else Vector3.ZERO
		hit_normal = Vector3.UP
	else:
		hit_point = hit["position"]
		hit_normal = hit["normal"]

	_ghost.update_placement(hit_point, hit_normal)


func _raycast(origin: Vector3, direction: Vector3) -> Dictionary:
	var space_state: PhysicsDirectSpaceState3D = get_viewport().world_3d.direct_space_state
	var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		origin, origin + direction.normalized() * ghost_tuning.placement_ray_length
	)
	return space_state.intersect_ray(params)


func _load_shapes_by_id() -> Dictionary:
	var shapes: Dictionary = {}
	var dir: DirAccess = DirAccess.open(BLOCKS_DIR)
	if dir == null:
		return shapes
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var shape: BlockShape = load(BLOCKS_DIR + file_name)
			if shape != null:
				shapes[shape.id] = shape
		file_name = dir.get_next()
	dir.list_dir_end()
	return shapes
