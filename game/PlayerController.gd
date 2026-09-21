class_name PlayerController
extends Node
## Local input -> placement intents (spec 2.5, 3.2; docs/M2_PLAN.md P4).
## Every action goes through the Input Map (bootstrap_project.gd); nothing
## here reads a raw keycode.
##
## M2 makes placement intent-only (spec 3.4, "clients send intents; the host
## checks every intent before acting on it"): this script never builds a
## Block itself. It positions the ghost, tracks whose turn it is in hot-seat
## (docs/M2_PLAN.md owner decision 1: strict alternation), and sends an
## intent; the host alone decides what happens next and answers on the Events
## bus.
##
## M3a changes only where the intent goes and which slot it is for. Offline it
## is still Match.request_place() and still Events.turn_changed's slot, so
## hot-seat behaves exactly as it did. Networked, it goes through
## net/MatchNet.gd -- inline to Match on the host, a reliable RPC on a client
## -- and always for Net.local_slot(), because one instance drives one player.
##
## Bontago-mv0.14 (original-style block-locked controls, spec 1.5,
## docs/ORIGINAL_BONTAGO_NOTES.md "Controls"): the original's mouse "positions
## the block" directly and the camera is attached to it, rather than the
## on-screen cursor raycasting onto the field. This script now keeps a single
## world-space cursor (_cursor) that both mouse motion and the gamepad stick
## move directly (camera-relative), reports it to CameraRig every frame
## (CameraRig.set_follow_position()) so the camera can follow, and casts the
## placement ray straight down from above it -- the screen-space mouse ray is
## gone. The mouse wheel is now block height (hover_raise/hover_lower); rotation
## is either a discrete 90 degree tap (rotate_yaw/pitch/roll_*, rotate_snap) or
## a continuous snap-by-90-degrees drag while rotation_mode is held
## (_accumulate_rotation_drag) -- the old free/quaternion-drift rotation is
## gone (spec 1.7 flagged that drift as a reported original problem; "do not
## keep two rotation systems").

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

## Bontago-mv0.14: bookkeeping only now -- both mouse and gamepad move the
## same _cursor, and _update_ghost_transform() always raycasts straight down
## from above it (the screen-space mouse ray is gone). Tests and any future
## "which device last moved you" UI still read this.
var _using_gamepad_cursor: bool = false
## World-space cursor the ghost's placement ray casts down from. Both mouse
## motion (_move_cursor_from_mouse) and the gamepad's left stick
## (_update_gamepad_cursor) move it directly -- "the mouse positions the
## block" (spec 1.5).
var _cursor: Vector3 = Vector3.ZERO
## Gamepad-only: the stick drives an accelerating velocity rather than a
## direct offset (spec 2.5 "acceleration and a small dead zone"); the mouse
## has no equivalent since its deltas are already analog-instant.
var _cursor_velocity: Vector3 = Vector3.ZERO
## Accumulated camera-relative drag (x = yaw, y = pitch) while rotation_mode
## is held, in GhostTuning's "drag units" (see _accumulate_rotation_drag()).
var _rotation_drag: Vector2 = Vector2.ZERO
## Set by HotSeat.gd/Sandbox.gd via enable_mouse_capture(); left false for
## bare unit-test instances so GUT never captures a test runner's real mouse.
var _mouse_capture_enabled: bool = false


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


## Bontago-mv0.17 item 4 (owner feel report: "the camera starts looking from
## the player's home flag toward the disk centre, and the initial cursor
## should start at the home flag"): called once by HotSeat.bind_local_slot()/
## Sandbox's own turn-changed handler with that slot's home-flag world
## position (Match.default_ghost_origin(slot_id) -- see those callers' own
## DECISION comments for why that read-only API, not a new one, supplies it).
## Seeds _cursor there (so the first frame's ghost/footprint sit at the home
## flag, not the world origin) and points the camera rig the same way, if one
## is already wired.
func set_home_position(home_position: Vector3) -> void:
	_cursor = home_position
	if _camera_rig != null:
		_camera_rig.set_home_view(home_position)


## Bontago-mv0.14: called once by HotSeat.gd/Sandbox.gd (never by a bare unit
## test) so a real play session hides/captures the OS cursor -- the original's
## mouse only ever positions the held block, there is nothing on screen for a
## free system cursor to point at. pause_menu (Esc/Start) toggles it back to
## visible so a future menu can use the mouse normally; see _unhandled_input().
func enable_mouse_capture() -> void:
	_mouse_capture_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	_intent_lock_left = maxf(_intent_lock_left - delta, 0.0)
	_update_gamepad_cursor(delta)
	_update_ghost_transform()
	_update_ghost_tint()
	_handle_hover_adjust(delta)
	_publish_cursor()
	if _camera_rig != null and _ghost != null:
		_camera_rig.block_held = _ghost.get_shape() != null
		_camera_rig.set_follow_position(_ghost.global_position)


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
		if Input.is_action_pressed(&"rotation_mode"):
			# Original tutorial (docs/ORIGINAL_BONTAGO_NOTES.md): "while holding
			# the rotation-mode key, the movement keys change the orientation
			# of the block" -- mouse motion is this device's "movement keys".
			_accumulate_rotation_drag(motion.relative, ghost_tuning.block_rotation_sensitivity)
		elif Input.is_action_pressed(&"camera_mode"):
			pass  # CameraRig._unhandled_input consumes this motion to orbit.
		elif Input.is_action_pressed(&"lock_vertical"):
			pass  # "Locks block to vertical movement only": ignore XZ motion; the wheel still changes height.
		else:
			_move_cursor_from_mouse(motion.relative)
		return

	if event is InputEventMouseButton and event.pressed:
		# Bontago-mv0.14: the wheel is block height now, not zoom or yaw
		# (tools/bootstrap_project.gd). Wheel notches are momentary --
		# InputEventMouseButton fires a press then an immediate release for
		# each one -- so they get one fixed step here rather than
		# _handle_hover_adjust()'s per-frame rate, which is for the genuinely
		# holdable PageUp/PageDown keys and gamepad buttons on the same
		# actions.
		if event.is_action_pressed(&"hover_raise"):
			_step_hover(1.0)
			return
		elif event.is_action_pressed(&"hover_lower"):
			_step_hover(-1.0)
			return

	if event.is_action_pressed(&"rotate_snap"):
		# Original tutorial: "a key snap-rotates the block" -- a plain 90
		# degree yaw tap, distinct from rotate_reset ("returns it to its
		# default rotation"). Bound to MMB (tools/bootstrap_project.gd); no
		# separate gamepad button since rotate_yaw_cw (RB) already does the
		# same 90 degree yaw there (see test_project_setup.gd's
		# DEVICE_EXCEPTIONS).
		_apply_step(BlockOrientations.step_yaw_cw(_orientation_index()))
	elif event.is_action_pressed(&"rotate_yaw_ccw"):
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
		_rotation_drag = Vector2.ZERO
	elif event.is_action_pressed(&"ghost_place"):
		_place_ghost_block()
	elif event.is_action_pressed(&"pause_menu"):
		# Bontago-mv0.14 DECISION (game/PlayerController.gd): there is no
		# pause-menu UI yet (out of scope for this task), but the mouse
		# capture this same key is meant to release ("release in menus/Esc")
		# has to go somewhere -- toggle it here so Esc/Start already does the
		# right thing once a real pause menu lands and calls into this.
		if _mouse_capture_enabled:
			Input.mouse_mode = (
				Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
				else Input.MOUSE_MODE_CAPTURED
			)


func _orientation_index() -> int:
	return _ghost.orientation_index if _ghost != null else 0


func _apply_step(new_index: int) -> void:
	if _ghost != null:
		_ghost.set_orientation_index(new_index)


func _step_hover(direction: float) -> void:
	if _ghost == null:
		return
	_ghost.manual_hover_offset = clampf(
		_ghost.manual_hover_offset + direction * ghost_tuning.hover_wheel_step,
		0.0,
		ghost_tuning.hover_manual_max
	)


## Bontago-mv0.14 (spec 1.5/1.7): rotation_mode turns "movement" (mouse motion
## or the gamepad's left stick) into 90 degree orientation snaps instead of
## the old continuous free/quaternion rotation, so there is exactly one
## rotation system and it can never drift. `relative` is in GhostTuning's
## un-scaled input units (mouse pixels or gamepad stick-seconds);
## `sensitivity` converts it into "drag units" where a magnitude of 1.0 is
## exactly one 90 degree step -- see block_rotation_sensitivity/
## pad_rotation_speed's doc comments in config/GhostTuning.gd.
func _accumulate_rotation_drag(relative: Vector2, sensitivity: float) -> void:
	if _ghost == null:
		return
	_rotation_drag += relative * sensitivity
	while _rotation_drag.x >= 1.0:
		_apply_step(BlockOrientations.step_yaw_cw(_orientation_index()))
		_rotation_drag.x -= 1.0
	while _rotation_drag.x <= -1.0:
		_apply_step(BlockOrientations.step_yaw_ccw(_orientation_index()))
		_rotation_drag.x += 1.0
	while _rotation_drag.y >= 1.0:
		_apply_step(BlockOrientations.step_pitch_back(_orientation_index()))
		_rotation_drag.y -= 1.0
	while _rotation_drag.y <= -1.0:
		_apply_step(BlockOrientations.step_pitch_fwd(_orientation_index()))
		_rotation_drag.y += 1.0


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


## Continuous, per-frame height adjustment for genuinely holdable inputs
## (PageUp/PageDown keys, gamepad RS click/X). The wheel's own notch is a
## separate, momentary, one-step adjustment -- see _step_hover(), called from
## _unhandled_input() instead, since Input.is_action_pressed() on a wheel
## binding is only ever true for the single frame Godot processes that notch.
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


## Bontago-mv0.14 (spec 1.5): the mouse "positions the block" directly,
## camera-relative, instead of the old screen-space raycast. `relative` is the
## InputEventMouseMotion's raw pixel delta.
func _move_cursor_from_mouse(relative: Vector2) -> void:
	_cursor += _camera_relative_dir(relative) * ghost_tuning.block_move_sensitivity


## Moves the gamepad's world-space cursor (spec 2.5), relative to the camera,
## with acceleration and speed scaling with zoom -- unless rotation_mode is
## held, in which case the same left stick drives _accumulate_rotation_drag()
## instead (spec 1.5: "the movement keys change the orientation of the
## block"), and the cursor doesn't move.
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

	if Input.is_action_pressed(&"rotation_mode"):
		if stick.length() > 0.0:
			_using_gamepad_cursor = true
			_accumulate_rotation_drag(stick, ghost_tuning.pad_rotation_speed * delta)
		return

	if stick.length() > 0.0:
		_using_gamepad_cursor = true

	var max_speed: float = ghost_tuning.gamepad_cursor_base_speed
	if _camera_rig != null and ghost_tuning.gamepad_cursor_zoom_reference_distance > 0.0:
		max_speed *= _camera_rig.get_distance() / ghost_tuning.gamepad_cursor_zoom_reference_distance

	var desired_velocity: Vector3 = _camera_relative_dir(stick) * max_speed
	var velocity_delta: Vector3 = desired_velocity - _cursor_velocity
	var max_change: float = ghost_tuning.gamepad_cursor_acceleration * delta
	if velocity_delta.length() > max_change and max_change > 0.0:
		velocity_delta = velocity_delta.normalized() * max_change
	_cursor_velocity += velocity_delta
	_cursor += _cursor_velocity * delta


func _camera_relative_dir(input_2d: Vector2) -> Vector3:
	var yaw: float = _camera_rig.get_yaw() if _camera_rig != null else 0.0
	var forward: Vector3 = Vector3(sin(yaw), 0.0, cos(yaw))
	var right: Vector3 = Vector3(forward.z, 0.0, -forward.x)
	return right * input_2d.x + forward * input_2d.y


## Casts the placement ray straight down from above _cursor and updates the
## ghost. Bontago-mv0.14: this used to branch between a screen-space mouse
## ray and a straight-down gamepad-cursor ray; now both devices move the same
## world-space _cursor (spec 1.5, "the mouse positions the block"), so there
## is only one path. Public so tests can exercise it without going through
## real input devices.
##
## Bontago-mv0.17 item 5 (owner feel report: "the block's height changes ONLY
## via the wheel", not whatever is directly underneath it): the probe below
## skips over any RigidBody3D (a placed block) so it always reports the disk
## surface itself, never a tower. The ghost's own height then comes only from
## that disk surface plus hover_height plus the wheel (GhostPreview.
## update_placement()) -- the ghost's XZ still comes straight from the
## cursor, only its Y stops tracking whatever is below it. Match.
## preview_placement()/request_place() do their own independent straight-down
## raycast against the real, unfiltered world (autoload/Match.gd,
## Field.raycast_down_disk_local()), so placement validity is unaffected.
func _update_ghost_transform() -> void:
	if _ghost == null:
		return
	var origin: Vector3 = _cursor + Vector3.UP * ghost_tuning.cursor_ray_height

	var hit: Dictionary = _raycast_disk_surface(origin)
	var hit_point: Vector3
	var hit_normal: Vector3
	if hit.is_empty():
		# Fallback so the ghost has somewhere to go even if the ray misses
		# every physics body (e.g. aimed at the sky before Field is ready) or
		# runs out of blocks to skip past.
		var plane: Plane = Plane(Vector3.UP, 0.0)
		var point: Variant = plane.intersects_ray(origin, Vector3.DOWN)
		hit_point = (point as Vector3) if point != null else Vector3.ZERO
		hit_normal = Vector3.UP
	else:
		hit_point = hit["position"] as Vector3
		hit_normal = hit["normal"] as Vector3

	_ghost.update_placement(hit_point, hit_normal)


## Straight down from `origin`, skipping any RigidBody3D (a placed block) so
## the first hit reported is the disk's own collision (a StaticBody3D, or an
## AnimatableBody3D once M4 tilt lands) -- never a tower underneath the
## cursor. Bounded by ghost_tuning.surface_probe_max_blocks so a very tall (or
## adversarially deep) stack can't spin this loop forever; past that many
## skips it just reports a miss, same as an empty query.
func _raycast_disk_surface(origin: Vector3) -> Dictionary:
	var space_state: PhysicsDirectSpaceState3D = get_viewport().world_3d.direct_space_state
	var exclude: Array[RID] = []
	var attempts: int = 0
	while attempts <= ghost_tuning.surface_probe_max_blocks:
		var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			origin, origin + Vector3.DOWN * ghost_tuning.placement_ray_length
		)
		params.exclude = exclude
		var hit: Dictionary = space_state.intersect_ray(params)
		if hit.is_empty():
			return {}
		if hit["collider"] is RigidBody3D:
			exclude.append(hit["rid"] as RID)
			attempts += 1
			continue
		return hit
	return {}


## Match names the shape it issues by id (Events.feed_block_issued); the ghost
## needs the resource. BlockShape.load_all_shapes() is the one directory scan
## in the project, so this only has to index its result.
func _load_shapes_by_id() -> Dictionary:
	var shapes: Dictionary = {}
	for shape: BlockShape in BlockShape.load_all_shapes():
		shapes[shape.id] = shape
	return shapes
