class_name PlayerController
extends Node
## Local input -> placement intents (spec 2.5, 3.2; docs/M2_PLAN.md P4).
## Every action goes through the Input Map (bootstrap_project.gd); nothing
## here reads a raw keycode.
##
## M2 makes placement intent-only (spec 3.4, "clients send intents; the host
## checks every intent before acting on it"): this script never builds a
## Block itself. It raycasts the ghost, tracks whose turn it is in hot-seat
## (docs/M2_PLAN.md owner decision 1: strict alternation), and sends an
## intent; the host alone decides what happens next and answers on the Events
## bus.
##
## M3a changes only where the intent goes and which slot it is for. Offline it
## is still Match.request_place() and still Events.turn_changed's slot, so
## hot-seat behaves exactly as it did. Networked, it goes through
## net/MatchNet.gd -- inline to Match on the host, a reliable RPC on a client
## -- and always for Net.local_slot(), because one instance drives one player.

@export var camera_rig_path: NodePath
@export var ghost_path: NodePath
@export var tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
@export var ghost_tuning: GhostTuning = preload("res://config/ghost_tuning.tres")
@export var camera_tuning: CameraTuning = preload("res://config/camera_tuning.tres")
@export var net_config: NetConfig = preload("res://config/net_config.tres")

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

## DECISION (game/PlayerController.gd): Net is an autoload for the same
## reason Match is, and needs the same seam for the same reason; null means
## the real one. Offline Net.is_offline() is true and every branch below
## collapses to exactly M2's behaviour.
var _session_provider: Variant = null

var _shapes_by_id: Dictionary = {}

## Seconds this controller's ghost stays locked after sending an intent, so a
## second click inside one round trip cannot spend a second block
## (docs/M3a_PLAN.md, "Never duplicated, never lost", defence 2). Only a
## client ever sets it: the host's intent resolves inline, in the same frame.
var _intent_lock_left: float = 0.0

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
	_intent_lock_left = maxf(_intent_lock_left - delta, 0.0)
	_update_gamepad_cursor(delta)
	_update_ghost_transform()
	_update_ghost_tint()
	_handle_hover_adjust(delta)
	_handle_gamepad_free_rotate(delta)
	_publish_cursor()
	if _camera_rig != null and _ghost != null:
		_camera_rig.block_held = _ghost.get_shape() != null


func _session() -> Variant:
	return _session_provider if _session_provider != null else Net


## Test seam for the Net autoload; null restores the real one.
func set_session_provider(provider: Variant) -> void:
	_session_provider = provider


## Which slot this controller acts for. Offline that is whoever
## Events.turn_changed last named -- M2's strict alternation, unchanged.
## Networked, one instance drives exactly one player: the slot Net gave it.
func _acting_slot() -> int:
	if bool(_session().is_offline()):
		return _active_slot
	return int(_session().local_slot())


## Lets the integrator bind this controller to a slot directly. Hot-seat
## under --hot-seat keeps using Events.turn_changed instead.
func set_acting_slot(slot_id: int) -> void:
	_active_slot = slot_id


## Bontago-mv0.8: game/Sandbox.gd's own typed name for the same seam, called
## from its sandbox_next_slot hotkey handler. A thin alias over
## set_acting_slot() rather than a second field — offline, _acting_slot()
## already reads _active_slot regardless of which caller last set it
## (HotSeat.bind_local_slot(), Events.turn_changed, or this), so giving
## sandbox its own field here would just be two sources of truth that could
## disagree. Naming it separately still keeps the call site readable as "the
## sandbox is choosing this" rather than "this is a hot-seat turn hand-off".
func set_sandbox_slot(slot_id: int) -> void:
	set_acting_slot(slot_id)


## Spec 3.4's update_cursor, every frame. MatchNet keeps the local record and
## throttles the send to NetConfig.cursor_hz, so calling it per frame is both
## correct and cheap; offline there is nobody to tell.
func _publish_cursor() -> void:
	if _ghost == null or bool(_session().is_offline()):
		return
	var membrane: Variant = _intent_target()
	if membrane == null:
		return
	membrane.submit_cursor(
		_acting_slot(), _ghost.global_position, _ghost.orientation_index, _ghost.free_quaternion
	)


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


# --- Placement intent (spec 3.4) --------------------------------------------

## ghost_place: send exactly one intent to Match and let it decide. Never
## builds a Block itself (spec 3.4; docs/M2_PLAN.md P4 "intent-only
## placement").
func _place_ghost_block() -> void:
	if _ghost == null or _match == null or _acting_slot() < 0:
		return
	if _ghost.get_shape() == null:
		return
	if _is_active_slot_eliminated():
		return
	if _intent_lock_left > 0.0:
		# An intent for this block is already with the host. Clicking again
		# before it answers must not spend the next block; Match's feed_seq
		# would refuse it anyway, but not sending is cheaper and keeps the
		# ghost from pretending the second click did something.
		return
	_request_place(false)


## The one door every intent goes through: net/MatchNet.gd, which calls
## Match.request_place() inline on the host and sends the reliable intent RPC
## on a client (docs/M3a_PLAN.md P3). It exists only once the MatchNet
## autoload has installed itself on Match, and only for the real Match -- a
## test that injects a FakeMatch into _match is asking for that object's
## calls and gets them directly, which is exactly what MatchNet's host path
## would have done with it.
func _intent_target() -> Variant:
	if _match != Match:
		return null
	return Match.replicator()


func _request_place(auto_drop: bool) -> StringName:
	var slot_id: int = _acting_slot()
	var membrane: Variant = _intent_target()
	if membrane == null:
		return _match.request_place(
			slot_id, _ghost.global_position, _ghost.orientation_index, _ghost.free_quaternion, auto_drop
		)
	if bool(_session().is_client()):
		_intent_lock_left = net_config.intent_ack_timeout
	return membrane.submit_place(
		slot_id,
		_ghost.global_position,
		_ghost.orientation_index,
		_ghost.free_quaternion,
		auto_drop,
		int(_match.feed_seq(slot_id))
	)


## Spec M2 owner decision 3: a slot whose home flag is gone is effectively
## eliminated. Match.slot(id).home_flag_alive is the one already-documented
## source of truth for this — no dedicated Events signal exists for it, so
## rather than inventing one on a stub I don't own, both the controller and
## the HUD just read PlayerSlot.home_flag_alive off Match.slot() (see
## ui/HUD.gd's matching DECISION).
func _is_active_slot_eliminated() -> bool:
	if _match == null or _acting_slot() < 0:
		return false
	var slot: PlayerSlot = _match.slot(_acting_slot())
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
	if slot_id != _acting_slot() or _ghost == null:
		return
	# The host answered, so whatever intent was in flight has resolved.
	_intent_lock_left = 0.0
	# Networked there is no Events.turn_changed to colour the ghost from, so
	# the first feed this slot receives does it instead.
	if _match != null:
		var slot: PlayerSlot = _match.slot(slot_id)
		if slot != null:
			_ghost.set_player_color(slot.color)
	var shape: BlockShape = _shapes_by_id.get(shape_id) as BlockShape
	if shape != null:
		_ghost.set_shape(shape)


## Spec 2.5's auto-drop is [ORIGINAL]: the held block drops from its current
## ghost position. On the host -- and offline, which is all of M2 -- that is
## this ghost, exactly, and it costs nothing. On a client the host has
## already dropped it from the last cursor it received (see MatchNet), so
## sending anything from here would risk the duplicate the whole design
## exists to prevent. The flash still plays, because that is feedback.
func _on_feed_timer_expired(slot_id: int) -> void:
	if slot_id != _acting_slot() or _ghost == null or _is_active_slot_eliminated():
		return
	_ghost.play_auto_drop_flash()
	if not bool(_session().is_host()):
		return
	_request_place(true)


func _on_placement_rejected(slot_id: int, _reason: StringName) -> void:
	if slot_id != _acting_slot() or _ghost == null:
		return
	_intent_lock_left = 0.0
	_ghost.play_reject_animation()


## Every frame: the read-only, advisory preview (spec 2.5) that tints the
## ghost before the click. request_place() re-validates from scratch and
## never trusts this (spec 3.4).
func _update_ghost_tint() -> void:
	if _ghost == null or _match == null or _acting_slot() < 0:
		return
	if _ghost.get_shape() == null:
		return
	var result: PlacementRules.Result = _match.preview_placement(
		_acting_slot(), _ghost.global_position, _ghost.orientation_index, _ghost.free_quaternion
	)
	_ghost.apply_validity(result)
	# Bontago-mv0.10 (spec 2.5): "A distinct timer-locked state must remain
	# visible even at a legal location" -- release-locked overrides whatever
	# apply_validity() just set, since the interval lock is about *when* this
	# piece may drop, not *where*.
	_ghost.set_locked(bool(_match.is_release_locked(_acting_slot())))


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
		origin = _gamepad_cursor + Vector3.UP * ghost_tuning.gamepad_cursor_ray_height
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


## Match names the shape it issues by id (Events.feed_block_issued); the ghost
## needs the resource. BlockShape.load_all_shapes() is the one directory scan
## in the project, so this only has to index its result.
func _load_shapes_by_id() -> Dictionary:
	var shapes: Dictionary = {}
	for shape: BlockShape in BlockShape.load_all_shapes():
		shapes[shape.id] = shape
	return shapes
