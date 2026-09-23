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
##
## Bontago-mv0.30 (owner test 2026-09-23, "when you place a block and the
## next block loads it gets displaced so it doesn't spawn directly within the
## placed block"): _on_feed_block_issued() now seeds the newly issued ghost's
## hover height above whatever this controller's own last accepted placement
## actually spawned (_apply_spawn_clearance(), config/GhostTuning.gd's
## spawn_clearance) instead of leaving the new piece exactly where the old one
## just landed.

@export var camera_rig_path: NodePath
@export var ghost_path: NodePath
## M4 P2e (docs/M4_P2_PACKAGES.md P2e): the same NodePath pattern as
## ghost_path above, wired in game/HotSeat.tscn / game/Sandbox.tscn to a
## sibling ThrowArcPreview instance. Null on a bare unit-test controller
## (no scene wiring) -- every call site below guards for that.
@export var arc_preview_path: NodePath
@export var tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
@export var ghost_tuning: GhostTuning = preload("res://config/ghost_tuning.tres")
@export var camera_tuning: CameraTuning = preload("res://config/camera_tuning.tres")
@export var net_config: NetConfig = preload("res://config/net_config.tres")
## M4 P2d (spec 2.5 "Throw (specials only)"): throw_drag_min_distance_m/
## throw_drag_min_speed_mps gate a release between an ordinary place and a
## throw; throw_speed_per_meter/throw_max_speed turn the drag into a launch
## velocity. Same @export-a-preloaded-Resource pattern as ghost_tuning/
## camera_tuning above.
@export var special_tuning: SpecialTuning = preload("res://config/special_tuning.tres")

var _camera_rig: CameraRig
var _ghost: GhostPreview
## M4 P2e: resolved from arc_preview_path in _ready(); null (and every driver
## below no-ops) when the scene doesn't wire one, exactly like _camera_rig.
var _arc_preview: ThrowArcPreview

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
## Bontago-iry (owner feedback/controller-update.md, "clicking mmb rotates
## the ghost block ... Q or Home resets"): total unscaled mouse-pixel motion
## accumulated since the current rotate_drag (MMB) press, reset on every
## press. Below ghost_tuning.rotate_tap_max_motion_px this whole hold is a
## tap -- no continuous free rotation is applied at all, and release fires a
## single BlockOrientations.step_yaw_cw() snap (the same fixed pattern
## rotate_snap/rotate_yaw_cw use). Once it crosses the threshold this hold is
## a drag -- rotate_drag's InputEventMouseMotion branch below starts applying
## apply_free_rotation_delta() every frame (mv0.22/mv0.25's continuous
## behaviour, unchanged), and release no longer snaps.
var _rotate_drag_motion_px: float = 0.0
## Set by HotSeat.gd/Sandbox.gd via enable_mouse_capture(); left false for
## bare unit-test instances so GUT never captures a test runner's real mouse.
var _mouse_capture_enabled: bool = false

## Bontago-mv0.23 (spec 2.5 "Held-block behaviour" [ORIGINAL], owner test
## 2026-09-22): the last cursor position the collision sweep accepted --
## _clamp_cursor_collision() sweeps from here to the frame's new _cursor
## every frame and only advances this once the (possibly clamped) result is
## known, so a block held against a wall keeps being tested from where it
## actually stopped, not from wherever the raw input tried to drag it.
var _last_safe_cursor: Vector3 = Vector3.ZERO
## True once _last_safe_cursor has been seeded from a real _cursor value
## (set_home_position() or the first collision check) -- avoids a spurious
## sweep across the whole map from the pre-spawn Vector3.ZERO default.
var _collision_cursor_seeded: bool = false
## The disk-surface hit this frame's _update_ghost_transform() last saw,
## cached so _clamp_hover_offset() (called from the wheel/held-key handlers,
## not from _update_ghost_transform() itself) knows which world direction
## "up" is for the vertical collision sweep without re-raycasting.
var _last_hit_point: Vector3 = Vector3.ZERO
var _last_hit_normal: Vector3 = Vector3.UP

## Bontago-mv0.30 (owner test 2026-09-23, "when you place a block and the
## next block loads it gets displaced so it doesn't spawn directly within the
## placed block"): true from the moment this controller's own _request_place()
## call is sent (a deliberate click, or a host-only auto-drop) until the
## outcome is known -- lets _on_feed_block_issued() tell "this feed follows a
## placement I actually just asked for" apart from the match's very first
## feed (never preceded by any _request_place() call here) or any other
## unrelated one. Cleared by _on_placement_rejected() (a manual refusal
## spawns nothing at all; an auto-drop burn spawns something, but far off the
## map, not near the cursor -- neither needs the next ghost displaced), and
## consumed (cleared again) the moment _apply_spawn_clearance() actually uses
## it, so it can never fire twice for one placement or leak into the next.
var _pending_spawn_active: bool = false
## The world-space Y of the *top* of the shape this controller's pending
## placement is about to occupy -- captured from the held ghost's own
## GhostPreview.projection_span_y() (already exactly "the shape's own current
## highest point in world space", Bontago-xtq.9) at the moment the intent is
## sent, so _apply_spawn_clearance() can seed the next ghost's hover height
## just above it once the feed confirms the placement actually happened.
## Re-captured by _on_placement_relocated() at the relocated spot for an
## auto-drop the host moved, so this always reflects where the block actually
## ended up, not just wherever this controller last aimed.
var _pending_spawn_top_y: float = 0.0

## Bontago-mv0.18 (in-game tuning panel): ui/TuningPanel.gd sets this false
## while it is open, so dragging a slider or clicking Reset/Save/Copy can't
## also move the ghost, rotate it, or spend a placement underneath the panel.
## Defaults true so every existing bare-controller test (no panel involved)
## keeps behaving exactly as before.
var input_enabled: bool = true

## Bontago-1en.14 (M4 P2d, spec 2.5 "Throw (specials only)", owner decision
## Bontago-mvl (a)): true from the moment `throw_aim` (LMB, shared with
## ghost_place; gamepad LT) is held down over a held special until the
## matching release, whichever this controller decides it is: submit_throw()
## once the drag clears both thresholds, or an ordinary _request_place(false)
## for a negligible one. Lifecycle lives entirely in _update_throw_aim()'s
## per-frame Input.is_action_pressed(&"throw_aim") poll -- exactly how every
## other hold in this file (rotate_drag, rotation_mode, camera_mode/orbit)
## already tracks its own state -- rather than event-based press/release
## dispatch, so mouse and gamepad share one code path with no per-device
## branching for start/stop.
var _aiming_throw: bool = false
## World-space drag accumulated since aiming began -- always ground-plane
## (both accumulators below feed it through _camera_relative_dir(), which
## never has a Y component), summed separately from _cursor so aiming a
## throw never also drags the ghost around (mirrors rotate_drag's own
## "accumulate, don't move the cursor" pattern). _commit_throw_aim() reads
## this once, on release, and clears it either way.
var _throw_drag: Vector3 = Vector3.ZERO
## Seconds _aiming_throw has been true, accumulated by _update_throw_aim()'s
## own delta -- used only to turn _throw_drag's distance into a release
## speed (distance / elapsed) for throw_drag_min_speed_mps's gate. A bare
## unit test that never calls _update_throw_aim() leaves this at 0, and
## _commit_throw_aim() treats that as "speed unknown, don't gate on it" (see
## its own comment) rather than a divide-by-zero.
var _throw_aim_elapsed: float = 0.0


func _ready() -> void:
	_camera_rig = get_node_or_null(camera_rig_path) as CameraRig
	_ghost = get_node_or_null(ghost_path) as GhostPreview
	_arc_preview = get_node_or_null(arc_preview_path) as ThrowArcPreview
	_match = Match
	_shapes_by_id = _load_shapes_by_id()
	Events.turn_changed.connect(_on_turn_changed)
	Events.feed_block_issued.connect(_on_feed_block_issued)
	Events.feed_timer_expired.connect(_on_feed_timer_expired)
	Events.placement_rejected.connect(_on_placement_rejected)
	Events.placement_relocated.connect(_on_placement_relocated)


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
	_last_safe_cursor = home_position
	_collision_cursor_seeded = true
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
	if not input_enabled:
		return
	_intent_lock_left = maxf(_intent_lock_left - delta, 0.0)
	_update_gamepad_cursor(delta)
	_update_throw_aim(delta)
	_clamp_cursor_collision()
	_update_ghost_transform()
	# Bontago-mv0.33: must run after _update_ghost_transform() above (so the
	# overlap test below sees the *new* piece's shape at the *current* cursor,
	# not a stale pose) and, just as importantly, not any earlier than this --
	# see _apply_spawn_clearance()'s own header DECISION for why doing this
	# synchronously inside the placement's own Events.feed_block_issued
	# handler (this package's first attempt) does not work: the block that
	# was just spawned has not been through a physics step yet at that point,
	# so a physics query cannot see it. Self-guards on _pending_spawn_active,
	# so this is a no-op on every ordinary frame.
	_apply_spawn_clearance()
	_update_ghost_tint()
	_handle_hover_adjust(delta)
	_publish_cursor()
	if _camera_rig != null and _ghost != null:
		_camera_rig.block_held = _ghost.get_shape() != null
		# Bontago-mv0.28 (owner test 2026-09-22): follow the rotated shape's own
		# centre, not this node's fixed local origin -- see GhostPreview.
		# rotated_center_world()'s own doc comment. Placement intents/cursor
		# publishing below keep sending _ghost.global_position unchanged (the
		# node origin), matching what MatchPlacement._spawn_block() actually
		# spawns the block at.
		_camera_rig.set_follow_position(_ghost.rotated_center_world())


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
	if not input_enabled:
		return
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		_using_gamepad_cursor = false
		if _aiming_throw:
			# Bontago-1en.14 (M4 P2d): while aiming a throw, mouse motion is the
			# drag gesture itself -- accumulate it into _throw_drag instead of
			# any of the other holds below (they are different physical
			# buttons anyway, but this keeps the priority explicit and matches
			# every other hold branch here returning instead of falling
			# through to _move_cursor_from_mouse).
			_accumulate_throw_drag(motion.relative)
		elif Input.is_action_pressed(&"rotate_drag"):
			# Bontago-mv0.22 (spec 2.5 "Rotate block (hold + drag)" [ORIGINAL,
			# owner test 2026-09-22]): a genuine continuous rotation, unlike
			# rotation_mode's 90 degree snap grid below -- GhostPreview.
			# free_quaternion already travels the wire untouched
			# (net/MatchNet.gd submit_cursor/submit_place) and
			# MatchPlacement.request_place() composes the spawned block's
			# basis from Basis(free_quat) * orientation basis
			# (autoload/match/MatchPlacement.gd), with is_pose_well_formed()
			# accepting any finite unit quaternion, not only the 24-entry
			# table -- so this needs no wire-format change, just a fresh
			# continuous input for a field that already carries one safely.
			#
			# Bontago-mv0.25 (docs/rotation-issue.png, owner test 2026-09-22,
			# "like the RMB orbit but for the block"): full 3-DOF now, not
			# yaw-only -- horizontal motion yaws about world up, vertical
			# motion pitches about the camera's current right axis
			# (_camera_right_axis()), the same axis CameraRig's own orbit
			# turns about. DECISION: signs are an easily-flipped feel choice,
			# not a rule -- see this package's manual owner test step.
			#
			# Bontago-iry (owner feedback/controller-update.md, "clicking mmb
			# rotates the ghost block ... follows a set pattern"): accumulate
			# this event's motion toward the tap/drag threshold
			# (_rotate_drag_motion_px) before applying anything -- while the
			# whole hold is still under ghost_tuning.rotate_tap_max_motion_px,
			# no free rotation is applied at all, so a plain MMB tap reads as
			# no rotation while held and exactly one 90 degree snap on release
			# (below), never a barely-visible micro-drag.
			_rotate_drag_motion_px += motion.relative.length()
			if _ghost != null and _rotate_drag_motion_px >= ghost_tuning.rotate_tap_max_motion_px:
				var yaw_delta: float = -motion.relative.x * ghost_tuning.rotate_drag_sensitivity
				var pitch_delta: float = -motion.relative.y * ghost_tuning.rotate_drag_sensitivity
				_ghost.apply_free_rotation_delta(yaw_delta, pitch_delta, _camera_right_axis())
		elif Input.is_action_pressed(&"rotation_mode"):
			# Original tutorial (docs/ORIGINAL_BONTAGO_NOTES.md): "while holding
			# the rotation-mode key, the movement keys change the orientation
			# of the block" -- mouse motion is this device's "movement keys".
			_accumulate_rotation_drag(motion.relative, ghost_tuning.block_rotation_sensitivity)
		elif Input.is_action_pressed(&"camera_mode") or Input.is_action_pressed(&"camera_orbit"):
			pass  # CameraRig._unhandled_input consumes this motion to orbit (mv0.22: either hold works).
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
			if _camera_orbit_held():
				# Bontago-mv0.22 (spec 2.5 "Camera orbit ... mouse wheel zooms
				# while held"): route the wheel to CameraRig's own zoom step
				# instead of block height while orbiting.
				_zoom_camera(-1.0)
			else:
				_step_hover(1.0)
			return
		elif event.is_action_pressed(&"hover_lower"):
			if _camera_orbit_held():
				_zoom_camera(1.0)
			else:
				_step_hover(-1.0)
			return

	if event.is_action_pressed(&"rotate_drag"):
		# Bontago-iry (owner feedback/controller-update.md, "clicking mmb
		# rotates the ghost block, seems to follow a set pattern"): every MMB
		# press starts a fresh tap/drag measurement -- see
		# _rotate_drag_motion_px's own doc comment and the
		# InputEventMouseMotion branch above that accumulates into it.
		_rotate_drag_motion_px = 0.0
	elif event.is_action_released(&"rotate_drag"):
		# DECISION (game/PlayerController.gd, Bontago-iry): reusing
		# rotate_drag's own press/release here, rather than rebinding
		# rotate_snap back onto MMB (tools/bootstrap_project.gd's mv0.22 fix
		# removed that exact binding because a bare press fired both actions
		# from one physical button) -- this way MMB stays one action end to
		# end and there is only one place that decides tap vs. drag.
		if _rotate_drag_motion_px < ghost_tuning.rotate_tap_max_motion_px:
			# Below the threshold means the motion branch above never applied
			# any continuous rotation this hold (it gates on the same
			# accumulator) -- a bare tap, so apply the one 90 degree snap now.
			_apply_step(BlockOrientations.step_yaw_cw(_orientation_index()))
		_rotate_drag_motion_px = 0.0
	elif event.is_action_pressed(&"rotate_snap"):
		# Original tutorial: "a key snap-rotates the block" -- a plain 90
		# degree yaw tap, distinct from rotate_reset ("returns it to its
		# default rotation"). Gamepad-only now (RB) -- MMB's own tap does the
		# same 90 degree yaw via rotate_drag's release branch above
		# (Bontago-iry); see test_project_setup.gd's DEVICE_EXCEPTIONS for why
		# rotate_snap itself carries no desktop binding.
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
		# Bontago-1en.14 (M4 P2d, owner decision Bontago-mvl (a)): on mouse,
		# throw_aim is bound to the same left-mouse button as ghost_place
		# (tools/bootstrap_project.gd), so this same press event also
		# satisfies throw_aim's own is_action_pressed() -- that is the "same
		# LMB event fires both actions" case. When it does, and the piece in
		# hand is a special ready to aim, do NOT place here: _update_throw_aim()
		# 's per-frame poll (already true by the time _process() next runs,
		# since input is dispatched before _process() each frame) starts
		# aiming instead, and the eventual release decides place-vs-throw
		# (_commit_throw_aim()). On gamepad, ghost_place (A) and throw_aim
		# (LT) are different physical inputs, so a bare A press here never
		# also satisfies throw_aim -- gamepad places a held special exactly
		# as before unless LT is separately held, matching spec 2.5's
		# independent "Place (drop): A" / "Throw: Hold LT" gamepad rows.
		if not (event.is_action_pressed(&"throw_aim") and _can_begin_throw_aim()):
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


## Bontago-mv0.22 (spec 2.5 "Camera orbit (hold + drag) ... mouse wheel zooms
## while held"): true while either orbit hold is down, so the wheel handler
## above routes to _zoom_camera() instead of _step_hover().
func _camera_orbit_held() -> bool:
	return Input.is_action_pressed(&"camera_mode") or Input.is_action_pressed(&"camera_orbit")


func _zoom_camera(direction: float) -> void:
	if _camera_rig != null:
		_camera_rig.zoom_by_orbit_step(direction)


func _step_hover(direction: float) -> void:
	if _ghost == null:
		return
	var desired: float = clampf(
		_ghost.manual_hover_offset + direction * ghost_tuning.hover_wheel_step,
		0.0,
		ghost_tuning.hover_manual_max
	)
	_ghost.manual_hover_offset = _clamp_hover_offset(desired)


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
	# Bontago-mv0.30: record what this request is about to occupy *before*
	# sending it -- on the host this resolves synchronously inside the call
	# below (Events.placement_rejected/placement_relocated/feed_block_issued
	# all fire before _match.request_place() returns), so this has to be set
	# first or _on_feed_block_issued() below would see a stale flag.
	_pending_spawn_active = true
	_pending_spawn_top_y = _ghost.projection_span_y().x
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


## The one door a throw goes through, mirroring _request_place() above
## (Bontago-1en.14, M4 P2d): same slot/pose arguments, same membrane
## (net/MatchNet.gd's submit_throw on the wire, or the offline/test-double
## Match.request_throw()/FakeMatch.request_throw() directly), same
## spawn-clearance bookkeeping for the next ghost. DECISION (game/
## PlayerController.gd): a thrown special's shape does not actually stay
## where _pending_spawn_top_y is captured -- it flies off with `velocity` --
## so the next ghost's spawn-clearance nudge is only ever approximate for a
## throw (it clears the aim spot, not wherever physics finally lands the
## piece). Filed under this package's Unresolved rather than skipped
## entirely: an approximate clearance is still strictly better than none,
## and _apply_spawn_clearance() already tolerates being wrong (it just
## reseeds hover height, never blocks anything).
func _request_throw(velocity: Vector3) -> StringName:
	var slot_id: int = _acting_slot()
	var membrane: Variant = _intent_target()
	_pending_spawn_active = true
	_pending_spawn_top_y = _ghost.projection_span_y().x
	if membrane == null:
		return _match.request_throw(
			slot_id, _ghost.global_position, _ghost.orientation_index, _ghost.free_quaternion, velocity
		)
	if bool(_session().is_client()):
		_intent_lock_left = net_config.intent_ack_timeout
	return membrane.submit_throw(
		slot_id,
		_ghost.global_position,
		_ghost.orientation_index,
		_ghost.free_quaternion,
		velocity,
		int(_match.feed_seq(slot_id))
	)


# --- Throw-aim state machine (M4 P2d, spec 2.5 "Throw (specials only)",
# owner decision Bontago-mvl (a): "hold LMB on a held special, drag, release
# throws; negligible drag = ordinary place") -----------------------------

## Whether this controller could start aiming right now: guards both the
## ghost_place-elif's suppression above and _update_throw_aim()'s own poll
## below with the identical rule, so a press that is refused for one reason
## (e.g. the interval lock) never starts an aim the poll would immediately
## refuse anyway. Deliberately does NOT read Input at all -- only whether the
## piece in hand is a throwable special right now; the caller decides which
## input state (the event, or the per-frame poll) triggers it.
func _can_begin_throw_aim() -> bool:
	if _ghost == null or _match == null or _acting_slot() < 0:
		return false
	if _ghost.get_shape() == null:
		return false
	if _is_active_slot_eliminated():
		return false
	if _intent_lock_left > 0.0:
		return false
	return StringName(_match.held_special(_acting_slot())) != &""


## Bontago-1en.14: the whole start/stop lifecycle for aiming, driven by
## Input.is_action_pressed(&"throw_aim") every frame -- the same continuous-
## hold convention rotate_drag/rotation_mode/camera_mode/camera_orbit already
## use elsewhere in this file (Input.is_action_pressed() polled per frame),
## rather than one-shot press/release event dispatch. That one convention
## covers both devices identically: throw_aim is bound to the left mouse
## button (shared with ghost_place) and the gamepad's left trigger
## (tools/bootstrap_project.gd) -- Input.is_action_pressed() reports "is
## either bound input currently held" regardless of which fired it.
func _update_throw_aim(delta: float) -> void:
	var throw_held: bool = Input.is_action_pressed(&"throw_aim")
	if not _aiming_throw:
		if throw_held and _can_begin_throw_aim():
			_aiming_throw = true
			_throw_drag = Vector3.ZERO
			_throw_aim_elapsed = 0.0
		# M4 P2e: unchanged control flow above (still one early return per the
		# original P2d state machine) -- only this observer call is new, so it
		# runs on both "just started aiming" and "still not aiming" alike.
		_drive_throw_visuals()
		return
	_throw_aim_elapsed += delta
	_accumulate_gamepad_throw_drag(delta)
	if not throw_held:
		_commit_throw_aim()
	# M4 P2e: runs after a possible _commit_throw_aim() above, so the hint/arc
	# disappear the same frame _aiming_throw goes false on release, not one
	# frame late.
	_drive_throw_visuals()


## M4 P2e (docs/M4_P2_PACKAGES.md P2e, presentation only): the ghost's throw
## tint and the arc preview both track _aiming_throw every frame, called from
## both branches of the state machine above -- the "just started aiming"
## branch above (so the very first frame already shows the hint) and the
## normal per-frame branch, and once more from the exact frame
## _commit_throw_aim() clears _aiming_throw (so the hint/arc disappear the
## same frame the throw/place actually fires, not one frame late).
func _drive_throw_visuals() -> void:
	if _ghost != null:
		_ghost.show_throw_hint(_aiming_throw)
	if _arc_preview == null:
		return
	# DECISION (game/PlayerController.gd, M4 P2e): while aiming, the ghost's
	# throw tint stays on for the whole hold (a "you are aiming a throw" cue),
	# but the arc itself only appears once the drag would actually commit as a
	# throw rather than an ordinary place -- _commit_throw_aim()'s own
	# distance/speed gate, mirrored here read-only against the *live* drag
	# rather than the release snapshot it uses. A drag below the threshold
	# shows the tint alone, not a misleading arc for a gesture that would
	# really just place the block where it stands.
	if _aiming_throw and _is_throw_drag_committable():
		# Bontago-1en.25: Match.field() (read-only, same accessor
		# _on_placement_relocated() already uses) so the preview lands where
		# it actually would rather than always sampling out to
		# GhostTuning.throw_arc_max_time_s -- null in a bare unit test (no
		# Field wired to the Match autoload), which update_arc()/sample_arc()
		# both already treat as "no landing cutoff, safety cap only".
		_arc_preview.update_arc(_ghost.global_position, current_throw_velocity(), Match.field())
	else:
		_arc_preview.clear_arc()


## Read-only mirror of _commit_throw_aim()'s own distance/speed gate, against
## the live _throw_drag/_throw_aim_elapsed instead of the release snapshot --
## see _drive_throw_visuals()'s own DECISION for why this duplicates the gate
## rather than the velocity math (current_throw_velocity() below shares that
## part instead).
func _is_throw_drag_committable() -> bool:
	var distance: float = _throw_drag.length()
	var speed: float = (distance / _throw_aim_elapsed) if _throw_aim_elapsed > 0.0 else INF
	return distance >= special_tuning.throw_drag_min_distance_m and speed >= special_tuning.throw_drag_min_speed_mps


## Mouse's half of the drag accumulation, called from _unhandled_input's
## InputEventMouseMotion branch while _aiming_throw is true. `relative` is
## the same raw pixel delta _move_cursor_from_mouse() converts for ordinary
## cursor movement; this mirrors that exact conversion (camera-relative
## direction times the same block_move_sensitivity) into _throw_drag instead
## of _cursor, so "how far you dragged" means the same number of world
## meters whichever the drag is for.
func _accumulate_throw_drag(relative: Vector2) -> void:
	_throw_drag += _camera_relative_dir(relative) * ghost_tuning.block_move_sensitivity


## Gamepad's half, called every frame from _update_throw_aim() while aiming
## (a no-op on a mouse-only setup: camera_look_* has no mouse binding at all,
## tests/unit/test_project_setup.gd's DEVICE_EXCEPTIONS, so its strengths are
## always 0 there). DECISION (game/PlayerController.gd): reads camera_look_*
## directly as a velocity (stick strength * ghost_tuning.gamepad_cursor_base_
## speed * delta) rather than _update_gamepad_cursor()'s acceleration ramp --
## an aim drag is a deliberate analog gesture the player is already holding
## at some deflection, not a cursor that needs smoothing away from a standing
## start, and reusing gamepad_cursor_base_speed rather than inventing a
## dedicated speed keeps this package from needing a tuning Resource of its
## own (SpecialTuning/GhostTuning both belong to other M4 P2 packages).
func _accumulate_gamepad_throw_drag(delta: float) -> void:
	var look: Vector2 = Vector2(
		Input.get_action_strength(&"camera_look_right") - Input.get_action_strength(&"camera_look_left"),
		Input.get_action_strength(&"camera_look_down") - Input.get_action_strength(&"camera_look_up")
	)
	if look.length() > 1.0:
		look = look.normalized()
	if look.length() <= 0.0:
		return
	_throw_drag += _camera_relative_dir(look) * ghost_tuning.gamepad_cursor_base_speed * delta


## Fires once on the release that ends _update_throw_aim()'s hold, deciding
## between an ordinary place and a throw (owner decision Bontago-mvl (a)).
## Always clears the aim state first, so a refused/guarded outcome below
## never leaves _aiming_throw stuck true.
func _commit_throw_aim() -> void:
	var drag: Vector3 = _throw_drag
	var elapsed: float = _throw_aim_elapsed
	_aiming_throw = false
	_throw_drag = Vector3.ZERO
	_throw_aim_elapsed = 0.0
	if _ghost == null or _match == null or _acting_slot() < 0 or _is_active_slot_eliminated():
		return
	if _intent_lock_left > 0.0:
		return
	var distance: float = drag.length()
	# DECISION (game/PlayerController.gd): "release speed" is this whole
	# gesture's average speed (total drag distance / seconds aiming), not an
	# instantaneous final-frame flick speed -- simpler to compute from state
	# this controller already tracks, and throw_drag_min_speed_mps's own doc
	# comment ("below this release speed") does not demand the fancier
	# instantaneous measure. A bare unit test that drives _unhandled_input
	# directly without ever calling _update_throw_aim() leaves `elapsed` at
	# 0; treating that as "speed unknown, don't gate on it" (INF) rather than
	# a divide-by-zero means such a test is judged on drag distance alone,
	# which is exactly what this package's own acceptance tests exercise.
	var speed: float = (distance / elapsed) if elapsed > 0.0 else INF
	if distance < special_tuning.throw_drag_min_distance_m or speed < special_tuning.throw_drag_min_speed_mps:
		_request_place(false)
		return
	_request_throw(_throw_velocity_for_drag(drag))


## The one place that turns a ground-plane drag vector into a launch
## velocity -- shared by _commit_throw_aim() above (the actual throw) and
## current_throw_velocity() below (P2e's read-only preview of what that same
## throw would be *right now*, mid-drag, before release). DECISION (game/
## PlayerController.gd, M4 P2e: "the arc must use the SAME formula ... share
## the implementation ... rather than duplicating the math"): both callers
## pass a snapshot of _throw_drag (the release copy, or the live one) rather
## than reading the field directly, so this stays a pure function of its
## argument.
## _throw_drag is already ground-plane only (both accumulators build it from
## _camera_relative_dir(), which never has a Y component) -- "the drag vector
## projected onto the ground plane" needs no extra step. The "plus an upward
## component" half lofts it; the loft is SpecialTuning.throw_loft_ratio
## (default 1.0 = 45 degrees).
func _throw_velocity_for_drag(drag: Vector3) -> Vector3:
	var distance: float = drag.length()
	if distance <= 0.0:
		return Vector3.ZERO
	var direction: Vector3 = (drag + Vector3.UP * distance * special_tuning.throw_loft_ratio).normalized()
	var speed_mps: float = minf(distance * special_tuning.throw_speed_per_meter, special_tuning.throw_max_speed)
	return direction * speed_mps


## Cancels an in-progress aim with no side effect other than clearing state --
## called when the piece in hand has already changed or been resolved out
## from under the player mid-drag (Events.feed_block_issued/
## placement_rejected below), so a stale _aiming_throw can never survive into
## the next held piece or fire _commit_throw_aim() against it later.
func _cancel_throw_aim() -> void:
	_aiming_throw = false
	_throw_drag = Vector3.ZERO
	_throw_aim_elapsed = 0.0


## P2e's own read-only seam (docs/M4_P2_PACKAGES.md P2e: "reads only
## PlayerController.gd's P2d-added getters, no edit needed there") for the
## arc preview's visibility.
func is_aiming_throw() -> bool:
	return _aiming_throw


## P2e's own read-only seam for the arc preview's start point/direction.
func current_throw_drag() -> Vector3:
	return _throw_drag


## P2e's own read-only seam for the arc preview's launch velocity -- the
## live drag's would-be throw velocity, computed by the exact same formula
## _commit_throw_aim() uses on release (see _throw_velocity_for_drag()'s own
## doc comment). Vector3.ZERO before any drag has accumulated.
func current_throw_velocity() -> Vector3:
	return _throw_velocity_for_drag(_throw_drag)


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
	# Bontago-1en.14 (M4 P2d): the piece this controller was aiming a throw
	# for is gone the moment a new one is fed -- whether this feed follows
	# this controller's own placement/throw or an unrelated auto-drop makes
	# no difference, a stale drag must never carry over onto whatever shape
	# just arrived.
	_cancel_throw_aim()
	# Networked there is no Events.turn_changed to colour the ghost from, so
	# the first feed this slot receives does it instead.
	if _match != null:
		var slot: PlayerSlot = _match.slot(slot_id)
		if slot != null:
			_ghost.set_player_color(slot.color)
	var shape: BlockShape = _shapes_by_id.get(shape_id) as BlockShape
	if shape != null:
		_ghost.set_shape(shape)
	# Bontago-mv0.33: does NOT call _apply_spawn_clearance() here anymore --
	# see that function's own header DECISION. This handler runs synchronously
	# inside the placement request that spawned the block (Events dispatch is
	# not deferred), before this frame's physics step has run, so a physics
	# query here could never see the block that was just placed.
	# _pending_spawn_active (already true from _request_place(), still true
	# here) is left alone; _process() resolves it next, once the physics
	# world has actually caught up.


## Bontago-mv0.30 (owner test 2026-09-23, "when you place a block and the next
## block loads it gets displaced so it doesn't spawn directly within the
## placed block"): seeds the newly issued ghost's manual_hover_offset just
## high enough that its own lowest point clears the top of the shape this
## controller's own last accepted placement actually spawned (spawn_clearance
## on top of it), so the next held block floats above it instead of rendering
## inside it -- the existing hover wheel and ghost-vs-placed-block collision
## sweep (_clamp_hover_offset()) take over normally from there. A no-op on the
## match's very first feed and after a placement that did not actually spawn
## anything near the cursor (see _pending_spawn_active's own field comment,
## both cleared there before this ever runs).
##
## Bontago-mv0.33 (owner playtest 2026-09-23, "the displace-outward thing
## should only happen when the block would spawn inside another block, not
## all the time"): mv0.30's own version above raised (or reset) the offset on
## *every* feed unconditionally, even when the new piece's cursor had moved
## somewhere the old block was nowhere near. This now only touches
## manual_hover_offset when _would_overlap_a_placed_block_at_baseline_hover()
## says the new shape, at its normal (unraised) hover height, would actually
## intersect a placed block -- otherwise it is a complete no-op, leaving
## whatever manual_hover_offset the ghost already had (0, or wherever the
## player had last wheeled it) exactly alone.
##
## DECISION (game/PlayerController.gd, Bontago-mv0.30, still true after
## mv0.33's gating): raises hover height rather than nudging the cursor
## sideways (this package's other offered option) -- the disk-surface probe
## already reports the bare disk under any tower (Bontago-mv0.17 item 5), so
## the only thing wrong with today's spawn point is its Y, and reusing that
## same, already-tested hover path keeps this a one-field change with no new
## footprint/geometry math.
func _apply_spawn_clearance() -> void:
	if not _pending_spawn_active:
		return
	_pending_spawn_active = false
	if _ghost == null or _ghost.get_shape() == null:
		return
	if not _would_overlap_a_placed_block_at_baseline_hover():
		return
	var required_bottom_y: float = _pending_spawn_top_y + ghost_tuning.spawn_clearance
	var desired_offset: float = required_bottom_y - _last_hit_point.y - tuning.hover_height
	_ghost.manual_hover_offset = clampf(desired_offset, 0.0, ghost_tuning.hover_manual_max)
	# Bontago-mv0.33: re-applies immediately rather than waiting for next
	# frame's own _update_ghost_transform() call -- _would_overlap_a_placed_
	# block_at_baseline_hover() above already left global_position restored to
	# the *old* offset (its own "restore" step), so without this the ghost
	# would render one visible frame overlapping the block it was just raised
	# to clear.
	_ghost.update_placement(_last_hit_point, _last_hit_normal)


## Bontago-mv0.33: whether the ghost's new shape, positioned at its normal
## ("baseline") hover height -- manual_hover_offset temporarily 0, i.e.
## exactly PhysicsTuning.hover_height above the last surface point/normal
## _update_ghost_transform() saw (_last_hit_point/_last_hit_normal) -- would
## intersect any already-placed block right now. _apply_spawn_clearance()
## above only raises the offset when this is true.
##
## DECISION (game/PlayerController.gd, Bontago-mv0.33): reuses
## GhostPreview.update_placement() (the same call _update_ghost_transform()
## makes every frame) to compute that baseline pose, rather than re-deriving
## GhostPreview's private rotated-bottom-pivot math here -- it is called
## twice (baseline, then restore) with no frame boundary between either call
## and the read of collision_box_local_centers()/collision_half_size() below,
## so nothing ever renders the intermediate baseline pose; the ghost ends this
## function exactly where it was, with only manual_hover_offset possibly
## changed by the caller above. Tests the *baseline* height specifically --
## not whatever manual_hover_offset the ghost already carries -- because the
## question this answers is "would an ordinary, un-raised spawn land inside a
## block", independent of any earlier manual raise still sitting on the ghost
## from a previous piece.
func _would_overlap_a_placed_block_at_baseline_hover() -> bool:
	var saved_offset: float = _ghost.manual_hover_offset
	_ghost.manual_hover_offset = 0.0
	_ghost.update_placement(_last_hit_point, _last_hit_normal)
	var overlaps: bool = _ghost_overlaps_a_placed_block()
	_ghost.manual_hover_offset = saved_offset
	_ghost.update_placement(_last_hit_point, _last_hit_normal)
	return overlaps


## Bontago-mv0.33: a stationary (zero-motion) overlap query at the ghost's
## *current* global_position/basis, using the same collision boxes
## _sweep_motion() below builds for the swept collision test (Bontago-mv0.23)
## -- collision_box_local_centers()/collision_half_size(), matching what
## game/BlockFactory.gd would actually give the spawned Block. No
## ghost_collision_skin inflation here (unlike _sweep_motion()'s clearance
## gap): this asks "does it overlap right now", not "how much gap should be
## kept while sliding", so the boxes are used at their true size.
func _ghost_overlaps_a_placed_block() -> bool:
	var boxes: Array[Vector3] = _ghost.collision_box_local_centers()
	if boxes.is_empty():
		return false
	var world: World3D = get_viewport().world_3d
	if world == null:
		return false
	var space_state: PhysicsDirectSpaceState3D = world.direct_space_state
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = Vector3.ONE * (_ghost.collision_half_size() * 2.0)
	for local_center: Vector3 in boxes:
		var world_center: Vector3 = _ghost.global_position + _ghost.basis * local_center
		var params: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
		params.shape = box_shape
		params.transform = Transform3D(_ghost.basis, world_center)
		params.collide_with_bodies = true
		params.collide_with_areas = false
		var overlaps: Array[Dictionary] = space_state.intersect_shape(params, ghost_tuning.collision_probe_max_bodies)
		for overlap: Dictionary in overlaps:
			if overlap.get("collider") is RigidBody3D:
				return true
	return false


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
	# Bontago-1en.14 (M4 P2d): a refused throw/place leaves the same piece in
	# hand (spec 2.5 "an invalid manual click does not drop and does not
	# consume the piece"), but this controller's own in-flight aim (if any)
	# already resolved into the request that got refused -- nothing is still
	# being dragged, so clear it rather than leave a stale _aiming_throw the
	# next _update_throw_aim() poll could reuse.
	_cancel_throw_aim()
	# Bontago-mv0.30: neither refusal branch spawned anything near the cursor
	# (a manual refusal spawns nothing at all; an auto-drop burn spawns
	# something, but throws it off the map) -- see _pending_spawn_active's own
	# field comment.
	_pending_spawn_active = false
	_ghost.play_reject_animation()


## Bontago-mv0.24 (spec 2.5's auto-drop [ORIGINAL]): the host relocated this
## slot's auto-dropped block to `point` (disk-local x, z) because its own
## ghost position wasn't valid. Only ever acted on for this controller's own
## slot -- another slot's relocation is none of this instance's business, the
## same filter every other per-slot Events reaction here uses.
##
## DECISION (game/PlayerController.gd): guarded by `_match != Match` like
## _intent_target() -- this only ever runs against the real Match autoload
## (which alone has field()); a test driving a FakeMatch never reaches this
## far since nothing there emits placement_relocated.
func _on_placement_relocated(slot_id: int, point: Vector2) -> void:
	if slot_id != _acting_slot() or _ghost == null or _match != Match:
		return
	var field: Field = Match.field()
	if field == null:
		return
	_cursor = field.to_global(Vector3(point.x, 0.0, point.y))
	# The relocation is a teleport the host already validated, so it must not
	# be swept against placed blocks (Bontago-mv0.23): re-seed the collision
	# sweep's last safe point here, or a tower between the old cursor and the
	# zone would clamp the jump on the next frame.
	_last_safe_cursor = _cursor
	_collision_cursor_seeded = true
	_update_ghost_transform()
	if _pending_spawn_active:
		# Bontago-mv0.30: the block actually landed here, not at whatever spot
		# _request_place() captured before the host relocated it -- re-capture
		# the top height at the now-updated ghost position (still the shape
		# that was just placed; _on_feed_block_issued() hasn't swapped it yet)
		# so _apply_spawn_clearance() displaces the next ghost from where the
		# block truly is.
		_pending_spawn_top_y = _ghost.projection_span_y().x
	if _camera_rig != null:
		_camera_rig.set_follow_position(_ghost.rotated_center_world())


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
	var desired: float = clampf(
		_ghost.manual_hover_offset + change * ghost_tuning.hover_manual_adjust_speed * delta,
		0.0,
		ghost_tuning.hover_manual_max
	)
	_ghost.manual_hover_offset = _clamp_hover_offset(desired)


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


## Bontago-mv0.25 (spec 2.5 rotate_drag's vertical axis, docs/rotation-issue.png):
## the world-space "right" axis of whatever way the camera currently faces --
## the same forward/right construction _camera_relative_dir() above already
## uses for cursor movement, factored out so rotate_drag's pitch axis tracks
## the camera exactly the same way. No rig wired (bare unit tests) falls back
## to yaw 0, i.e. world +X, same fallback _camera_relative_dir() uses.
func _camera_right_axis() -> Vector3:
	var yaw: float = _camera_rig.get_yaw() if _camera_rig != null else 0.0
	var forward: Vector3 = Vector3(sin(yaw), 0.0, cos(yaw))
	return Vector3(forward.z, 0.0, -forward.x)


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

	_last_hit_point = hit_point
	_last_hit_normal = hit_normal
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


# --- Ghost-vs-placed-block collision (Bontago-mv0.23, spec 2.5 "Held-block
# behaviour" [ORIGINAL], owner test 2026-09-22) ------------------------------
#
# The held ghost collides with an already placed block -- it cannot pass
# through a tower -- but never pushes or knocks one. This runs a shape cast
# each frame against the real physics world instead of giving the ghost its
# own physics body, so a placed RigidBody3D is only ever read from
# (cast_motion/intersect_shape), never written to.
#
# DECISION (game/PlayerController.gd): the brief for this package expected a
# collision_mask naming "placed blocks' own layer", but nothing in this
# project sets a distinguishing physics layer -- BlockFactory/Block.gd never
# call collision_layer/collision_mask, so every body (block, disk, future
# goal zone) still defaults to Godot's layer 1 (confirmed by grep across
# game/, config/, core/; project.godot has no [layer_names] section at all).
# Adding one would mean editing project.godot's physics layers, which this
# package does not own (tools/bootstrap_project.gd owns project settings) and
# would ripple into BlockFactory/Field, also out of scope. This filters by
# node type instead (`is RigidBody3D`), exactly the technique
# _raycast_disk_surface() above already uses to skip a block when it wants
# the disk -- here it is inverted: skip anything that ISN'T a RigidBody3D
# (the disk, a future goal-zone Area3D) and only stop for one that is. Filed
# under this package's Unresolved for a follow-up dedicated layer.


## Ensures _last_safe_cursor tracks a real, already-seeded value before the
## first sweep -- otherwise the very first frame would sweep from the
## pre-spawn Vector3.ZERO default across the whole map.
func _seed_collision_cursor_if_needed() -> void:
	if not _collision_cursor_seeded:
		_last_safe_cursor = _cursor
		_collision_cursor_seeded = true


## Clamps _cursor's horizontal motion this frame so the held shape's own
## collision boxes cannot sweep into an already placed block (pushing the
## cursor into a tower stops it at the surface; sliding along one is fine --
## DECISION: tries the full motion, then its X-only and Z-only components, so
## a block dragged along a wall keeps sliding instead of sticking the instant
## any one axis is blocked). Height is assumed constant across the sweep (the
## disk is flat through M3; a tilted disk is this package's Unresolved). A
## no-op -- and keeps _last_safe_cursor in sync so re-enabling collision
## later never sweeps across a stale gap -- when collision is disabled,
## nothing is held, or the cursor didn't move this frame.
##
## Bontago-mv0.28 (owner test 2026-09-22): _cursor is the aim point the
## *rotated* held shape's own centre sits over (GhostPreview.
## update_placement()), not this node's own origin -- so the boxes
## _sweep_motion() below places at `position + basis * local_center` have to
## be built from the same cursor-minus-centre-offset point update_placement()
## will actually put the ghost's node origin at, or a pitched/rolled shape's
## swept boxes would land somewhere the render then doesn't match (this
## sweep would validate one position, update_placement() would show a
## different one). `center_offset` is zero for a yaw-only or unrotated pose
## (rotated_center_offset()'s own doc comment), so this is a no-op change for
## every pre-mv0.28 test that never pitches/rolls the held shape.
func _clamp_cursor_collision() -> void:
	_seed_collision_cursor_if_needed()
	if not ghost_tuning.ghost_collision_enabled or _ghost == null or _ghost.get_shape() == null:
		_last_safe_cursor = _cursor
		return
	var motion: Vector3 = _cursor - _last_safe_cursor
	if motion.length() <= 0.0:
		return
	var height: float = _ghost.global_position.y
	var center_offset: Vector3 = _ghost.rotated_center_offset()
	var from_position: Vector3 = Vector3(
		_last_safe_cursor.x - center_offset.x, height, _last_safe_cursor.z - center_offset.z
	)
	var to_position: Vector3 = Vector3(_cursor.x - center_offset.x, height, _cursor.z - center_offset.z)
	var clamped: Vector3 = _sweep_ghost_position(from_position, to_position)
	_cursor = Vector3(clamped.x + center_offset.x, _cursor.y, clamped.z + center_offset.z)
	_last_safe_cursor = _cursor


## Clamps a manual_hover_offset change (from the wheel notch or a held
## raise/lower key) so raising/lowering the held shape can't sweep it through
## a placed block above or below it -- same box-sweep technique as the
## horizontal clamp, just along the disk's own surface normal
## (_last_hit_normal, cached by _update_ghost_transform()) instead of the XZ
## plane. `desired` is the value the caller would otherwise commit after its
## own hover_manual_max clamp.
func _clamp_hover_offset(desired: float) -> float:
	if not ghost_tuning.ghost_collision_enabled or _ghost == null or _ghost.get_shape() == null:
		return desired
	var current: float = _ghost.manual_hover_offset
	var delta: float = desired - current
	if is_equal_approx(delta, 0.0):
		return desired
	var from_position: Vector3 = _ghost.global_position
	var to_position: Vector3 = from_position + _last_hit_normal * delta
	var clamped_position: Vector3 = _sweep_ghost_position(from_position, to_position)
	var achieved_delta: float = (clamped_position - from_position).dot(_last_hit_normal)
	return current + achieved_delta


## The shared box-sweep behind both clamps above: moves the held shape's own
## collision boxes (GhostPreview.collision_box_local_centers()/
## collision_half_size(), built the same way BlockFactory.build() would, so
## the ghost matches the block that will actually spawn) from `from_position`
## to `to_position` at the ghost's current rotation, and returns the furthest
## point along that straight line that keeps every box clear of every placed
## block. DECISION: tries the full motion first, then the X-only and Z-only
## components of whatever remains, so horizontal motion blocked on one axis
## still slides along the other; a purely vertical motion (the hover clamp)
## has zero X/Z remainder, so the slide attempts are a no-op there and it
## correctly just stops.
func _sweep_ghost_position(from_position: Vector3, to_position: Vector3) -> Vector3:
	var result: Vector3 = from_position + _sweep_motion(from_position, to_position - from_position)
	var remainder: Vector3 = to_position - result
	if remainder.length() > 0.0:
		result += _sweep_motion(result, Vector3(remainder.x, 0.0, 0.0))
		remainder = to_position - result
		result += _sweep_motion(result, Vector3(0.0, 0.0, remainder.z))
	return result


## One shape cast per collision box of the held shape, in one direction,
## returning the safe portion of `motion` (Vector3.ZERO if none of it is
## clear, unchanged `motion` if all of it is). The swept box is inflated by
## ghost_tuning.ghost_collision_skin on every side so the returned motion
## always leaves that much of a gap, rather than letting the ghost visually
## touch a placed block exactly.
func _sweep_motion(position: Vector3, motion: Vector3) -> Vector3:
	if motion.length() <= 0.0 or _ghost == null:
		return Vector3.ZERO
	var boxes: Array[Vector3] = _ghost.collision_box_local_centers()
	if boxes.is_empty():
		return motion
	var world: World3D = get_viewport().world_3d
	if world == null:
		return motion
	var space_state: PhysicsDirectSpaceState3D = world.direct_space_state
	var inflated_half: float = _ghost.collision_half_size() + ghost_tuning.ghost_collision_skin
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = Vector3.ONE * (inflated_half * 2.0)
	var min_safe_fraction: float = 1.0
	for local_center: Vector3 in boxes:
		var world_center: Vector3 = position + _ghost.basis * local_center
		min_safe_fraction = minf(
			min_safe_fraction, _cast_one_box(space_state, box_shape, world_center, motion)
		)
	return motion * clampf(min_safe_fraction, 0.0, 1.0)


## Casts `box_shape` (already inflated by the caller) from `world_center`
## along `motion`, skipping any collider that isn't a placed block -- see this
## section's top-of-file DECISION for why type, not collision_mask, is the
## filter here. Bounded by ghost_tuning.collision_probe_max_bodies, the same
## bounded-skip idea _raycast_disk_surface() uses, so a pathological pile of
## non-block colliders in the way can't spin this loop forever. Returns the
## safe fraction of `motion` (1.0 = fully clear).
##
## Bontago-mv0.35 (owner regression report, 2026-09-23, "there is still a
## maximum height the block cannot be raised or placed above"): if `box_shape`
## already overlaps a placed block right at `world_center` -- zero motion --
## this returns 1.0 (the full requested motion) without ever calling
## cast_motion(). The ghost's own baseline hover height
## (_update_ghost_transform(), mv0.17 item 5) deliberately ignores whatever
## tower sits under the cursor, so a freshly spawned or freshly rotated ghost
## routinely starts a frame already embedded in a placed block -- raising past
## it is the only way out, by design (mv0.30/mv0.33's own spawn-clearance
## logic already relies on manual_hover_offset being able to lift the ghost
## clear of exactly this state). cast_motion() itself, called from a shape
## that already overlaps a body, reports collisions to a shallow query depth
## and can come back permanently "unsafe" (0.0) even when `motion` is carrying
## the box further along its own way out -- reproduced by this package's own
## tests/unit/test_playercontroller_hover_cap.gd fixture (a 4-cube tower with
## a domino held above it froze at manual_hover_offset ~0.6 m forever, nowhere
## near the tower's own ~3.4 m top or GhostTuning.hover_manual_max's 60 m
## ceiling, even though every notch kept requesting more upward motion).
## DECISION (game/PlayerController.gd, Bontago-mv0.35): exempting an
## already-overlapping box from this frame's block entirely, rather than
## trying to compute a partial "depenetration" distance, keeps the fix to the
## one case that regressed (a box that starts this query already embedded)
## without touching the geometry every already-passing
## test_ghost_collision.gd case depends on: each of those starts its query
## from a position that is *not* already overlapping (the ghost approaches a
## placed block from clear space and this same function's normal cast_motion
## path below still stops it right at the collision skin's gap), so none of
## them take this new branch. An embedded box instead now advances by exactly
## the caller's requested `motion` once per query (one wheel notch, or one
## frame's worth of a held raise/lower key) -- the same rate free space would
## have given it -- until it re-checks from its new position next call and
## finds itself finally clear, at which point ordinary blocking resumes.
func _cast_one_box(
	space_state: PhysicsDirectSpaceState3D, box_shape: BoxShape3D, world_center: Vector3, motion: Vector3
) -> float:
	var start_probe: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	start_probe.shape = box_shape
	start_probe.transform = Transform3D(_ghost.basis, world_center)
	start_probe.collide_with_bodies = true
	start_probe.collide_with_areas = false
	for start_overlap: Dictionary in space_state.intersect_shape(start_probe, 8):
		if start_overlap.get("collider") is RigidBody3D:
			return 1.0

	var params: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	params.shape = box_shape
	params.transform = Transform3D(_ghost.basis, world_center)
	params.motion = motion
	params.collide_with_bodies = true
	params.collide_with_areas = false
	var exclude: Array[RID] = []
	var attempts: int = 0
	while attempts <= ghost_tuning.collision_probe_max_bodies:
		params.exclude = exclude
		var cast_result: PackedFloat32Array = space_state.cast_motion(params)
		var safe_fraction: float = cast_result[0] if cast_result.size() > 0 else 1.0
		if safe_fraction >= 1.0:
			return 1.0
		# DECISION (game/PlayerController.gd): probe at cast_motion's *unsafe*
		# fraction, not its safe one -- `safe_fraction` is deliberately the
		# point just *before* any contact (zero penetration, often not even
		# touching yet), so intersect_shape() there can come back empty even
		# when something genuinely blocked the cast. `unsafe_fraction` is
		# where the shapes actually first overlap, which is what identifying
		# the blocker needs.
		var unsafe_fraction: float = cast_result[1] if cast_result.size() > 1 else safe_fraction
		var probe: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
		probe.shape = box_shape
		probe.transform = Transform3D(_ghost.basis, world_center + motion * unsafe_fraction)
		probe.collide_with_bodies = true
		probe.collide_with_areas = false
		probe.exclude = exclude
		var overlaps: Array[Dictionary] = space_state.intersect_shape(probe, 8)
		var non_block_rids: Array[RID] = []
		for overlap: Dictionary in overlaps:
			if overlap.get("collider") is RigidBody3D:
				return safe_fraction
			non_block_rids.append(overlap["rid"] as RID)
		if non_block_rids.is_empty():
			return 1.0
		exclude.append_array(non_block_rids)
		attempts += 1
	return 0.0


## Match names the shape it issues by id (Events.feed_block_issued); the ghost
## needs the resource. BlockShape.load_all_shapes() is the one directory scan
## in the project, so this only has to index its result.
func _load_shapes_by_id() -> Dictionary:
	var shapes: Dictionary = {}
	for shape: BlockShape in BlockShape.load_all_shapes():
		shapes[shape.id] = shape
	return shapes
