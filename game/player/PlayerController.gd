class_name PlayerController
extends Node
## Local input -> placement intents (spec 1.4, 2.2).
## Every action goes through the Input Map (bootstrap_project.gd); nothing
## here reads a raw keycode.
##
## Placement is intent-only (spec 2.6, "clients send intents; the host checks
## every intent before acting on it"): this script never builds a Block itself.
## It positions the ghost, tracks which slot it acts for, and sends an intent; the host alone decides what happens next
## and answers on the Events bus. Every intent goes through match_context.submit_*
## (Match directly offline and on the host, a reliable RPC on a client): offline for
## Events.turn_changed's slot; networked always for
## Net.local_slot(), because one instance drives one player.
##
## Controls are block-locked (spec 1.5): the mouse positions the block directly
## and the camera follows it, rather than an on-screen cursor raycasting onto the
## field. A single world-space cursor (_cursor), moved by both mouse motion and
## the gamepad stick (camera-relative), is reported to CameraRig every frame
## (CameraRig.set_follow_position()), and the placement ray is cast straight down
## from above it. The mouse wheel is block height (hover_raise/hover_lower).
## Rotation is a discrete 90 degree tap (rotate_yaw/pitch/roll_*, rotate_snap), a
## snap-by-90-degrees drag while rotation_mode is held (_accumulate_rotation_drag),
## or a continuous free rotation while rotate_drag (MMB) is held.
##
## _on_feed_block_issued() seeds the newly issued ghost's hover height above
## whatever this controller's last accepted placement spawned
## (SpawnClearance, GhostTuning.spawn_clearance), so the new piece is
## not left exactly where the old one just landed.

## Divisor floor (seconds) so a zero hover_wheel_ramp_seconds cannot divide by zero; not a
## gameplay tunable.
const _WHEEL_RAMP_MIN_SECONDS: float = 0.001

@export var camera_rig_path: NodePath
@export var ghost_path: NodePath
## The same NodePath pattern as
## ghost_path above, wired in game/main/LocalPlayer.tscn / game/sandbox/Sandbox.tscn to a
## sibling ThrowArcPreview instance. Null on a bare unit-test controller
## (no scene wiring) -- every call site below guards for that.
@export var arc_preview_path: NodePath
@export var tuning: PhysicsTuning = preload("res://config/physics/physics_tuning.tres")
@export var ghost_tuning: GhostTuning = preload("res://config/blocks/tuning/ghost_tuning.tres")
@export var camera_tuning: CameraTuning = preload("res://config/player/camera_tuning.tres")
@export var net_config: NetConfig = preload("res://config/net/net_config.tres")
## the home beacon's own extents, read only to clear its top
## with the match's first held piece (set_home_position()).
@export var beacon_visuals: BeaconVisualTuning = preload("res://config/territory/beacon_visual_tuning.tres")
## Spec 1.4 "Throw (specials only)": throw_drag_min_distance_m/
## throw_drag_min_speed_mps gate a release between an ordinary place and a
## throw; throw_speed_per_meter/throw_max_speed turn the drag into a launch
## velocity. Same @export-a-preloaded-Resource pattern as ghost_tuning/
## camera_tuning above.
@export var special_tuning: SpecialTuning = preload("res://config/gifts/special_tuning.tres")

var _camera_rig: CameraRig
var _ghost: GhostPreview
## Resolved from arc_preview_path in _ready(); null (and every driver
## below no-ops) when the scene doesn't wire one, exactly like _camera_rig.
var _arc_preview: ThrowArcPreview

## The match this controller reads and sends intents through. Defaults to the installed
## MatchContext in _ready(), which covers LocalPlayer, Sandbox and Tutorial; tests set a
## FakeMatchContext before add_child.
var match_context: MatchContext = null

## The session seam: the parent binds it (LocalPlayer binds a port over the Net autoload);
## null until then and a bare controller builds the same port on first use (see _session()).
## Offline Net.is_offline() is true and every branch below collapses to the offline behaviour.
var _session_port: SessionPort = null

var _shapes_by_id: Dictionary = {}

## Seconds this controller's ghost stays locked after sending an intent, so a
## second click inside one round trip cannot spend a second block. Only a
## client ever sets it: the host's intent resolves inline, in the same frame.
var _intent_lock_left: float = 0.0

## Which slot this controller currently acts for (only that slot's timer/controls
## do anything). -1 until set_acting_slot() or the first Events.turn_changed.
var _active_slot: int = -1

## World-space cursor the ghost's placement ray casts down from. Both mouse
## motion (_move_cursor_from_mouse) and the gamepad's left stick
## (_update_gamepad_cursor) move it directly -- "the mouse positions the
## block" (spec 1.5).
var _cursor: Vector3 = Vector3.ZERO
## Gamepad-only: the stick drives an accelerating velocity rather than a
## direct offset (spec 1.4 "acceleration and a small dead zone"); the mouse
## has no equivalent since its deltas are already analog-instant.
var _cursor_velocity: Vector3 = Vector3.ZERO
## Accumulated camera-relative drag (x = yaw, y = pitch) while rotation_mode
## is held, in GhostTuning's "drag units" (see _accumulate_rotation_drag()).
var _rotation_drag: Vector2 = Vector2.ZERO
## Total unscaled mouse-pixel motion accumulated since the current rotate_drag
## (MMB) press, reset on every press. Below ghost_tuning.rotate_tap_max_motion_px
## this whole hold is a tap -- no continuous free rotation is applied at all, and
## release fires a single BlockOrientations.step_yaw_cw() snap (the same fixed
## pattern rotate_snap/rotate_yaw_cw use). Once it crosses the threshold this hold
## is a drag -- rotate_drag's InputEventMouseMotion branch below starts applying
## apply_free_rotation_delta() every frame, and release no longer snaps.
var _rotate_drag_motion_px: float = 0.0
## Set by LocalPlayer.gd/Sandbox.gd via enable_mouse_capture(); left false for
## bare unit-test instances so GUT never captures a test runner's real mouse.
var _mouse_capture_enabled: bool = false

## spec 1.4 "Held-block behaviour" [ORIGINAL]: the last cursor position the
## collision sweep accepted --
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

## The held ghost's clearance machine (post-placement raise, release lift, home raise); built
## for the current ghost and tuning by _clearance().
var _clearance_machine: SpawnClearance
var _clearance_ghost: GhostPreview
var _clearance_tuning: GhostTuning

## In-game tuning panel: ui/debug/TuningPanel.gd sets this false
## while it is open, so dragging a slider or clicking Reset/Save/Copy can't
## also move the ghost, rotate it, or spend a placement underneath the panel.
## Defaults true so a bare controller (no panel involved) is enabled.
var input_enabled: bool = true
## set by Events.match_results_ready; this controller is freed
## with the match world, so it never needs clearing.
var _results_open: bool = false
## tracked beside input_enabled so closing one blocker never re-enables input under another.
var _pause_open: bool = false
var _chat_open: bool = false

## gift release is camera-aimed and automatic (no LT/drag state); the held
## throwable's arc preview is simply driven every frame by _drive_throw_visuals().

## seconds the current held raise/lower input has been down,
## for _handle_hover_adjust()'s acceleration ramp (GhostTuning.
## hover_hold_acceleration/hover_hold_max_speed). Reset to 0 whenever no
## held raise/lower is active.
var _hover_hold_seconds: float = 0.0
## continuous wheel-scroll time and time since the last notch,
## for _wheel_step_multiplier() (GhostTuning.hover_wheel_*). Idle starts past
## any gap so the first notch is always a plain step.
var _wheel_scroll_seconds: float = 0.0
var _wheel_idle_seconds: float = INF
## Sign of the last wheel notch; reversing direction restarts the ramp.
var _wheel_last_direction: float = 0.0


func _ready() -> void:
	_camera_rig = get_node_or_null(camera_rig_path) as CameraRig
	_ghost = get_node_or_null(ghost_path) as GhostPreview
	_arc_preview = get_node_or_null(arc_preview_path) as ThrowArcPreview
	# lets ui/hud/HUD.gd read the local held block's own height
	# (GhostPreview.height_above_surface()) without a node path -- see
	# GhostPreview.LOCAL_HELD_GROUP.
	if _ghost != null:
		_ghost.add_to_group(GhostPreview.LOCAL_HELD_GROUP)
		# _process() moves the local ghost every render frame and
		# CameraRig turns interpolation off, so an interpolated ghost jitters
		# against the camera. Remote ghosts are not touched.
		_ghost.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if match_context == null:
		match_context = MatchContext.current()
	_shapes_by_id = _load_shapes_by_id()
	Events.turn_changed.connect(_on_turn_changed)
	Events.player_eliminated.connect(_on_player_eliminated)
	Events.feed_block_issued.connect(_on_feed_block_issued)
	Events.feed_timer_expired.connect(_on_feed_timer_expired)
	Events.placement_rejected.connect(_on_placement_rejected)
	Events.placement_relocated.connect(_on_placement_relocated)
	# ui/menus/PauseMenu.gd is the only thing that reads the pause_menu action
	# (its own _unhandled_input) -- this controller only reacts to the Events it
	# emits, the same "gate input, don't touch the scene tree" contract
	# input_enabled already has for ui/debug/TuningPanel.gd's toggle.
	Events.pause_menu_opened.connect(_on_pause_menu_opened)
	Events.pause_menu_closed.connect(_on_pause_menu_closed)
	# the results screen blocks gameplay input like the pause menu.
	Events.chat_input_opened.connect(_on_chat_input_opened)
	Events.chat_input_closed.connect(_on_chat_input_closed)
	Events.match_results_ready.connect(_on_match_results_ready)
	Events.match_scope_reset.connect(_on_match_scope_reset)


## LocalPlayer.gd calls this after Main builds the shared CameraRig: LocalPlayer.tscn
## is self-contained, but the camera rig lives in Main's
## tree, so it can't be wired by NodePath at scene-author time.
func set_camera_rig(rig: CameraRig) -> void:
	_camera_rig = rig
	# the rig's match-start framing pivots on the held piece's
	# spawn anchor (see spawn_camera_anchor()), not on the bare home beacon.
	if rig != null:
		rig.set_start_anchor_source(spawn_camera_anchor)
	if _clearance_machine != null:
		_clearance_machine.set_camera(rig)


## The clearance machine for the current ghost and tuning, rebuilt when either was swapped.
## Call only with a ghost wired.
func _clearance() -> SpawnClearance:
	if _clearance_machine == null or _clearance_ghost != _ghost or _clearance_tuning != ghost_tuning:
		_clearance_ghost = _ghost
		_clearance_tuning = ghost_tuning
		_clearance_machine = SpawnClearance.new(
			_ghost, _ghost_overlapping_bodies, _camera_rig, ghost_tuning, tuning, _hover_offset_ceiling
		)
		_clearance_machine.set_surface(_last_hit_point, _last_hit_normal)
	return _clearance_machine


## Places the ghost at the current cursor -- at match start, the held piece's
## spawn pose behind the home beacon (set_home_position()) -- and returns the
## camera anchor the ordinary follow uses there (_camera_follow_anchor()).
## CameraRig.begin_start_framing() calls it when the ready gate opens, so the
## very first start view already pivots on the held piece exactly as the first
## PLAYING frame does. Falls back to the cursor when no ghost is wired.
func spawn_camera_anchor() -> Vector3:
	if _ghost == null:
		return _cursor
	_update_ghost_transform()
	return _camera_follow_anchor()


## Called once by LocalPlayer.bind_local_slot()/Sandbox's own turn-changed handler
## with that slot's home-flag world position (Match.default_ghost_origin(slot_id),
## a read-only API). Seeds _cursor there (so the first frame's ghost/footprint
## sit at the home flag, not the world origin) and points the camera rig the same
## way, if one is already wired.
func set_home_position(home_position: Vector3) -> void:
	_cursor = home_position
	_last_safe_cursor = home_position
	_collision_cursor_seeded = true
	_seed_home_spawn_raise()
	if _camera_rig != null:
		_camera_rig.set_home_view(home_position)


## The first held piece is seeded on the home flag, but the ghost anchors at the
## bare disc surface plus tuning.hover_height, and neither the placement ray nor
## the spawn-clearance query sees the beacon (FieldBody.PLACEMENT_QUERY_MASK; the
## clearance never runs for the first piece), so the piece would sit inside the
## beacon's socket and crystal. Raises the hover offset so the shape's lowest
## point clears the beacon top by GhostTuning.home_spawn_beacon_margin; a no-op
## if the hover already clears it. The ghost is placed from this offset on its
## next _update_ghost_transform(), and the host spawns a released block at the
## pose the ghost sends, so no host-side rule changes.
## DECISION: tracked apart from the player's own hover (SpawnClearance.seed_home()) so it
## is dropped at the next spawn / when the player scrolls, and later pieces
## hover exactly as before.
func _seed_home_spawn_raise() -> void:
	if _ghost == null:
		return
	# the same rule the host's no-cursor AFK auto-drop uses.
	_clearance().seed_home(ghost_tuning.home_spawn_clear_hover(beacon_visuals))


## called once by LocalPlayer.gd/Sandbox.gd (never by a bare unit
## test) so a real play session hides/captures the OS cursor -- the original's
## mouse only ever positions the held block, there is nothing on screen for a
## free system cursor to point at. ui/menus/PauseMenu.gd releases it
## back to visible via Events.pause_menu_opened so the pause overlay's buttons
## can be clicked; see _on_pause_menu_opened()/_on_pause_menu_closed().
## Restores the OS cursor when this controller leaves the tree (match teardown
## in Main._end_match_world()). Otherwise the cursor stays captured on the main
## menu after leaving a match, soft-locking mouse users. Only undoes a capture
## this controller itself enabled, so headless runs and tests are unaffected.
func _exit_tree() -> void:
	match_context.local_held().clear()
	if _mouse_capture_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func enable_mouse_capture() -> void:
	_mouse_capture_enabled = true
	AgentProbe.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


## gates every other input handler in this file (input_enabled
## already guards _process()/_unhandled_input(), the same seam ui/TuningPanel.
## gd's own toggle uses) and releases the OS cursor so the overlay's buttons
## are reachable -- physics/simulation itself is never paused (CLAUDE.md's
## host-authority model); this only stops the *local* player from acting.
func _on_pause_menu_opened() -> void:
	_pause_open = true
	input_enabled = false
	if _mouse_capture_enabled:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## the chat input line owns the keyboard, so every gameplay handler here stops
## (the same gate pause uses); mouse capture is left alone so the ghost still follows the cursor.
func _on_chat_input_opened() -> void:
	_chat_open = true
	input_enabled = false


## Input returns only when neither pause nor the results screen still hold it.
func _on_chat_input_closed() -> void:
	_chat_open = false
	input_enabled = not _pause_open and not _results_open


func _on_match_results_ready(_results: Dictionary) -> void:
	_results_open = true
	input_enabled = false


## Play again / sandbox reset reuse this controller: the results screen is gone,
## so gameplay input comes back.
func _on_match_scope_reset() -> void:
	_chat_open = false
	if not _results_open:
		return
	_results_open = false
	input_enabled = true


## Mirrors _on_pause_menu_opened() above: restores input and, if this session
## ever had mouse capture on, re-captures it exactly as enable_mouse_capture()
## originally set it up.


func _on_pause_menu_closed() -> void:
	_pause_open = false
	input_enabled = not _results_open and not _chat_open
	if _mouse_capture_enabled:
		AgentProbe.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


## During the pre-match 3-2-1 this controller ignores all gameplay input
## (cursor, rotate, place, throw); camera look is CameraRig's own separate
## listener and keeps working. The host also refuses every intent outside
## PLAYING, so this is feedback, not the rule.
func _countdown_blocks_input() -> bool:
	return match_context.state() == MatchPhase.State.COUNTDOWN


func _process(delta: float) -> void:
	_process_input(delta)
	_push_ghost_timers()
	_publish_held_view()


## Feeds the held ghost's glow timer and glue shell every frame, input gates or not.
func _push_ghost_timers() -> void:
	if _ghost == null:
		return
	var slot: int = _acting_slot()
	var timed: bool = slot >= 0 and _ghost.get_shape() != null and match_context.feed_timer_enabled()
	_ghost.set_drop_time_left(match_context.feed_time_left(slot) if timed else -1.0)
	_ghost.set_glue_charges(match_context.glue_drops_left(slot) if slot >= 0 else 0)


## Publishes the held pose after every early return of _process_input(), so an input gate,
## the countdown or a peek never hides the held piece from readers.
func _publish_held_view() -> void:
	if _ghost == null:
		return
	match_context.local_held().publish(_acting_slot(), _ghost.get_shape(), _ghost.global_position,
			_ghost.orientation_index, _ghost.free_quaternion, _ghost.visible,
			_ghost.height_above_surface(), Time.get_ticks_msec())


func _process_input(delta: float) -> void:
	_sync_ghost_elimination_visibility()
	if not input_enabled:
		return
	if _countdown_blocks_input():
		_present_countdown_hold()
		return
	_tick_wheel_ramp(delta)
	if _camera_rig != null:
		# kept current every frame (harmless while peeking, too)
		# so a Focus home press right after a turn hand-off or a sandbox slot
		# cycle always resolves the beacon for whichever slot this controller
		# is acting for right now -- see CameraRig.set_local_slot()'s own doc
		# comment for who reads it.
		_camera_rig.set_local_slot(_acting_slot())
		if _camera_rig.is_peeking():
			# The ghost/cursor never moves during peek and placing must not happen
			# while peeking, so every other per-frame gameplay input this controller
			# drives is suppressed while PEEK holds the camera on a focus target,
			# like input_enabled's gate above but without touching mouse
			# capture/OS cursor visibility. CameraRig's own _unhandled_input still
			# ends the peek via camera_snap_home/goal's release event.
			return
	_intent_lock_left = maxf(_intent_lock_left - delta, 0.0)
	_update_gamepad_cursor(delta)
	_drive_throw_visuals()
	_clamp_cursor_collision()
	_update_ghost_transform()
	# Must run after _update_ghost_transform() above (so the overlap test sees the
	# *new* piece's shape at the *current* cursor, not a stale pose), and not
	# synchronously inside the placement's own Events.feed_block_issued handler:
	# the block that was just spawned has not been through a physics step yet at
	# that point, so a physics query cannot see it. SpawnClearance no-ops while no
	# placement is pending.
	if _ghost != null:
		_clearance().step(delta, true)
	_update_ghost_tint()
	_handle_hover_adjust(delta)
	_publish_cursor()
	_publish_cat_target()
	_follow_held_piece()


## Keeps the held piece at its spawn pose and the camera on it through the 3-2-1
## without reading any input. Otherwise the camera would pivot on the bare home
## beacon for the whole countdown, and the first PLAYING frame would place the
## piece at its spawn pose (pushed back from the beacon and raised clear of it)
## and snap the follow ~4 m to it; this way the countdown view is the first play
## view.
func _present_countdown_hold() -> void:
	if _camera_rig != null:
		_camera_rig.set_local_slot(_acting_slot())
	_update_ghost_transform()
	_follow_held_piece()


## Feeds the camera rig the held piece's follow anchor (every processed frame,
## countdown included).
func _follow_held_piece() -> void:
	if _camera_rig != null and _ghost != null:
		# Follow the rotated shape's own centre in X/Z, not this node's fixed local
		# origin (see GhostPreview.rotated_center_world()). Placement
		# intents/cursor publishing below keep sending _ghost.global_position (the
		# node origin), matching what MatchPlacement._spawn_block() actually
		# spawns the block at. Y comes from _camera_follow_anchor() instead, not
		# rotated_center_world()'s own Y (the held shape's own geometry must not
		# move the camera).
		_camera_rig.set_follow_position(_camera_follow_anchor())


## The camera follow anchor: X/Z from GhostPreview.rotated_center_world() (so
## orbiting/pitching the block doesn't swing the camera's horizontal framing),
## Y from _last_hit_point.y (the cursor's surface hit, cached by
## _update_ghost_transform()) plus the current hover height
## (tuning.hover_height + _ghost.manual_hover_offset) -- the anchor
## GhostPreview.update_placement() positions the ghost's bottom from, which
## depends only on the cursor's surface hit and the hover wheel/raise input,
## never on which shape is held or how it is rotated. rotated_center_world()'s
## own Y is global_position.y plus roughly half the *held shape's* height
## (config/blocks/*.tres shapes range from 1 cell tall to 3), so following it
## would move the camera on every shape swap even when the hover never changed.
## A genuine hover change (the wheel, a held raise/lower, or
## SpawnClearance's raise) still moves this; an ordinary shape swap
## gives zero movement, so CameraRig.begin_follow_transition() only needs
## calling for that genuine raise (see SpawnClearance).
func _camera_follow_anchor() -> Vector3:
	var center: Vector3 = _ghost.rotated_center_world()
	# The camera is tied to the held block, raise included.
	var anchor_y: float = _last_hit_point.y + tuning.hover_height + _ghost.manual_hover_offset
	return Vector3(center.x, anchor_y, center.z)


func _session() -> SessionPort:
	if _session_port == null:
		_session_port = SessionPort.new(Net)
	return _session_port


## Binds the session port this controller asks for host/client/offline and its slot.
## Returns false (and binds nothing) for a null or invalid port.
func bind_session(port: SessionPort) -> bool:
	if port == null or not port.is_valid():
		return false
	_session_port = port
	return true


## Which slot this controller acts for. Offline that is whoever
## Events.turn_changed last named (strict alternation).
## Networked, one instance drives exactly one player: the slot Net gave it.
func _acting_slot() -> int:
	if _session().is_offline():
		return _active_slot
	return _session().local_slot()


## Lets the integrator bind this controller to a slot directly; an
## unbound offline controller keeps using Events.turn_changed instead.
func set_acting_slot(slot_id: int) -> void:
	_active_slot = slot_id


## Spec 2.6's update_cursor, every frame. MatchNet keeps the local record and
## throttles the send to NetConfig.cursor_hz, so calling it per frame is both
## correct and cheap; offline there is nobody to tell.
func _publish_cursor() -> void:
	if _ghost == null or _session().is_offline():
		return
	match_context.submit_cursor(
		_acting_slot(), _ghost.global_position, _ghost.orientation_index, _ghost.free_quaternion, _camera_forward()
	)


func _publish_cat_target() -> void:
	var cat: CatController = _session_cat()
	if cat == null or cat.owner_slot != _acting_slot():
		return
	# The placement cursor is controlled by mouse and gamepad even while
	# the gift has moved on to the next feed. The cat input is independent
	# of whether a ghost is currently held.
	match_context.submit_cat_target(_acting_slot(), _cursor)


func _session_cat() -> CatController:
	return match_context.active_cat()


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or _countdown_blocks_input():
		return
	if _camera_rig != null and _camera_rig.is_peeking():
		# Same PEEK gate _process() applies above -- mouse/gamepad motion,
		# rotation, and ghost_place must not reach the ghost while the camera is
		# peeking at a focus target. CameraRig's own _unhandled_input is a
		# separate listener and still gets camera_snap_home/goal's release event
		# undisturbed (Godot dispatches to every listening node), so the peek
		# itself can still end normally.
		return
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		if Input.is_action_pressed(&"rotate_drag"):
			# A continuous rotation, unlike rotation_mode's 90 degree snap grid below
			# (spec 1.4 "Rotate block (hold + drag)" [ORIGINAL]).
			# GhostPreview.free_quaternion already travels the wire untouched
			# (net/MatchNet.gd submit_cursor/submit_place) and
			# MatchPlacement.request_place() composes the spawned block's basis from
			# Basis(free_quat) * orientation basis (autoload/match/MatchPlacement.gd),
			# with is_pose_well_formed() accepting any finite unit quaternion, not
			# only the 24-entry table -- so this needs no wire-format change.
			#
			# Full 3-DOF, like the RMB orbit but for the block: horizontal motion
			# yaws about world up, vertical motion pitches about the camera's current
			# right axis (_camera_right_axis()), the same axis CameraRig's own orbit
			# turns about. DECISION: signs are an easily-flipped feel choice, not a
			# rule.
			#
			# Motion accumulates toward the tap/drag threshold
			# (_rotate_drag_motion_px) before anything is applied: while the whole
			# hold is still under ghost_tuning.rotate_tap_max_motion_px, no free
			# rotation is applied at all, so a plain MMB tap reads as no rotation
			# while held and exactly one 90 degree snap on release (below), never a
			# barely-visible micro-drag.
			_rotate_drag_motion_px += motion.relative.length()
			if _ghost != null and _rotate_drag_motion_px >= ghost_tuning.rotate_tap_max_motion_px:
				var yaw_delta: float = -motion.relative.x * ghost_tuning.rotate_drag_sensitivity
				var pitch_delta: float = -motion.relative.y * ghost_tuning.rotate_drag_sensitivity
				_ghost.apply_free_rotation_delta(yaw_delta, pitch_delta, _camera_right_axis())
		elif Input.is_action_pressed(&"rotation_mode"):
			# Original tutorial: "while holding
			# the rotation-mode key, the movement keys change the orientation
			# of the block" -- mouse motion is this device's "movement keys".
			_accumulate_rotation_drag(motion.relative, ghost_tuning.block_rotation_sensitivity)
		elif _camera_orbit_held():
			pass  # CameraRig._unhandled_input consumes this motion to orbit (either hold works).
		elif Input.is_action_pressed(&"lock_vertical"):
			pass  # "Locks block to vertical movement only": ignore XZ motion; the wheel still changes height.
		else:
			_move_cursor_from_mouse(motion.relative)
		return

	if event is InputEventMouseButton and event.pressed:
		# The wheel is block height, not zoom or yaw
		# (tools/bootstrap_project.gd). Wheel notches are momentary --
		# InputEventMouseButton fires a press then an immediate release for
		# each one -- so they get one fixed step here rather than
		# _handle_hover_adjust()'s per-frame rate, which is for the genuinely
		# holdable PageUp/PageDown keys and gamepad buttons on the same
		# actions.
		if event.is_action_pressed(&"hover_raise"):
			if _camera_orbit_held():
				# spec 1.3 "Camera orbit ... mouse wheel zooms
				# while held": route the wheel to CameraRig's own zoom step
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
		# Every MMB press starts a fresh tap/drag measurement -- see
		# _rotate_drag_motion_px's own doc comment and the InputEventMouseMotion
		# branch above that accumulates into it.
		_rotate_drag_motion_px = 0.0
	elif event.is_action_released(&"rotate_drag"):
		# DECISION (game/player/PlayerController.gd): reusing
		# rotate_drag's own press/release here, rather than rebinding
		# rotate_snap back onto MMB (tools/bootstrap_project.gd's fix
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
		# default rotation"). Gamepad-only (RB): MMB's own tap does the
		# same 90 degree yaw via rotate_drag's release branch above; see
		# test_project_setup.gd's DEVICE_EXCEPTIONS for why rotate_snap itself
		# carries no desktop binding.
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
	elif event.is_action_pressed(&"use_gift_slot"):
		_use_gift_slot()
	elif event.is_action_pressed(&"ghost_place"):
		# a held throwable is released by the same plain click/A press as any
		# placement (_request_place sends the camera aim).
		_place_ghost_block()

## QoL gift slot: asks the host to spend this slot's
## slotted gift. A no-op unless the toggle is on and a gift is waiting; the host
## validates everything again (MatchGifts.request_use_gift_slot).
func _use_gift_slot() -> void:
	var slot_id: int = _acting_slot()
	if match_context.gift_slot_head(slot_id) == &"":
		return
	match_context.submit_use_gift_slot(slot_id)


func _orientation_index() -> int:
	return _ghost.orientation_index if _ghost != null else 0


func _apply_step(new_index: int) -> void:
	if _ghost != null:
		_ghost.set_orientation_index(new_index)


## True while either orbit hold is down (spec 1.3: the mouse wheel zooms while
## orbiting), so the wheel handler above routes to _zoom_camera() instead of
## _step_hover().
func _camera_orbit_held() -> bool:
	return _camera_rig != null and _camera_rig.is_orbiting()


func _zoom_camera(direction: float) -> void:
	if _camera_rig != null:
		_camera_rig.zoom_by_orbit_step(direction)


## advances the continuous-scroll clock. Scroll time only
## accrues while notches keep arriving within hover_wheel_gap_seconds.
func _tick_wheel_ramp(delta: float) -> void:
	_wheel_idle_seconds += delta
	if _wheel_idle_seconds <= ghost_tuning.hover_wheel_gap_seconds:
		_wheel_scroll_seconds += delta
	else:
		_wheel_scroll_seconds = 0.0


## Step multiplier for the notch being handled now (1.0 .. max), then marks
## the notch so the gap timer restarts.
func _wheel_step_multiplier(direction: float) -> float:
	if _wheel_idle_seconds > ghost_tuning.hover_wheel_gap_seconds or signf(direction) != _wheel_last_direction:
		_wheel_scroll_seconds = 0.0
	_wheel_last_direction = signf(direction)
	_wheel_idle_seconds = 0.0
	var ramp: float = clampf(_wheel_scroll_seconds / maxf(ghost_tuning.hover_wheel_ramp_seconds, _WHEEL_RAMP_MIN_SECONDS), 0.0, 1.0)
	return lerpf(1.0, maxf(ghost_tuning.hover_wheel_max_multiplier, 1.0), ramp)


func _step_hover(direction: float) -> void:
	if _ghost == null:
		return
	var desired: float = clampf(
		_ghost.manual_hover_offset + direction * ghost_tuning.hover_wheel_step * _wheel_step_multiplier(direction),
		0.0,
		_hover_offset_ceiling()
	)
	_clearance().absorb()
	_ghost.manual_hover_offset = _clamp_hover_offset(desired)
	_refresh_ghost_pose()


## re-poses the ghost right after a hover change instead of
## waiting for next frame's _update_ghost_transform(), so a fast wheel spin
## (several notches delivered in one frame) has each notch's collision sweep
## and _hover_offset_ceiling() start from where the previous notch actually
## left the ghost, not from a stale pose -- otherwise several notches in one
## frame could overshoot the wire-band ceiling or the sweep's start point.
func _refresh_ghost_pose() -> void:
	if _ghost != null:
		_ghost.update_placement(_last_hit_point, _last_hit_normal)


## The highest manual_hover_offset the held ghost may reach right now. The
## binding limit is the wire band -- the ghost's own origin may rise to
## NetConfig.pos_max_y minus GhostTuning.hover_ceiling_margin, the band
## core/net/Quantize.gd can replicate and MatchIntentGateway.pose_is_acceptable()
## accepts from a client -- with GhostTuning.hover_manual_max only an optional
## extra cap on top (its default, 200 m, sits above anything the band allows).
## DECISION (game/player/PlayerController.gd): derived from the ghost's *current*
## origin height and offset (origin Y moves 1:1 with the offset along the
## surface normal's Y), rather than re-deriving GhostPreview's private
## rotated-bottom pivot math here -- both values are the same frame's pose.
func _hover_offset_ceiling() -> float:
	var ceiling: float = ghost_tuning.hover_manual_max
	if _ghost == null:
		return ceiling
	var rise_per_meter: float = maxf(_last_hit_normal.y, 0.0)
	if rise_per_meter <= 0.0:
		return ceiling
	var origin_limit: float = net_config.pos_max_y - ghost_tuning.hover_ceiling_margin
	var band_ceiling: float = (
		_ghost.manual_hover_offset + (origin_limit - _ghost.global_position.y) / rise_per_meter
	)
	return maxf(minf(ceiling, band_ceiling), 0.0)


## spec 1.5/1.7: rotation_mode turns "movement" (mouse motion or the gamepad's
## left stick) into 90 degree orientation snaps; the continuous free rotation of
## rotate_drag is separate. `relative` is in GhostTuning's un-scaled input units
## (mouse pixels or gamepad stick-seconds); `sensitivity` converts it into "drag
## units" where a magnitude of 1.0 is exactly one 90 degree step -- see
## block_rotation_sensitivity/pad_rotation_speed's doc comments in
## config/blocks/tuning/GhostTuning.gd.
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


## The gamepad's path onto GhostPreview.apply_free_rotation_delta() (RT held +
## left stick = continuous free rotation of the held block, like holding MMB and
## moving the mouse), mirroring rotate_drag's own InputEventMouseMotion branch in
## _unhandled_input() above: X yaws about world up, Y pitches about the camera's
## right axis (_camera_right_axis()). `stick` is the camera-relative Vector2
## _update_gamepad_cursor() builds for cursor movement (x =
## ghost_move_right-left, y = ghost_move_back-forward), whose sign convention
## already matches InputEventMouseMotion.relative's (stick up == mouse motion up
## == negative y), so negating both axes as the mouse branch does keeps "drag the
## stick like the mouse" true in both directions, not just yaw.
func _accumulate_gamepad_rotate_drag(stick: Vector2, delta: float) -> void:
	if _ghost == null:
		return
	var rate: float = ghost_tuning.pad_free_rotation_speed * delta
	var yaw_delta: float = -stick.x * rate
	var pitch_delta: float = -stick.y * rate
	_ghost.apply_free_rotation_delta(yaw_delta, pitch_delta, _camera_right_axis())


## LT + left stick's continuous zoom, called from _update_gamepad_cursor() once
## camera_zoom_modifier is confirmed held. `stick_y` is the same camera-relative
## vertical stick value _update_gamepad_cursor() already reads (negative = stick
## pushed up), and CameraRig._zoom()'s own convention is "positive direction =
## zoom out" -- so pushing the stick up (negative y) shrinks distance (zooms in)
## and pushing it down (positive y) grows distance (zooms out) with no extra sign
## flip needed here.
func _drive_gamepad_zoom(stick_y: float, delta: float) -> void:
	if _camera_rig == null:
		return
	_camera_rig.zoom_continuous(stick_y * camera_tuning.gamepad_trigger_zoom_speed * delta)


# --- Placement intent (spec 2.6) --------------------------------------------

## ghost_place: send exactly one intent to the match context and let the host decide. Never
## builds a Block itself (spec 2.6: intent-only placement).
func _place_ghost_block() -> void:
	if _ghost == null or _acting_slot() < 0:
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


func _request_place(auto_drop: bool) -> StringName:
	# every throwable/aimed gift (Bomb, Magnet, Jumping Bean, Rocket,
	# Paintball) is released along the camera forward (the throw intent carries it); every
	# other release is an ordinary place.
	if not auto_drop and _held_gift_mode() != GiftThrow.Mode.NONE:
		return _request_throw(_camera_forward())
	# at timer expiry the host throws a held throwable gift along the last
	# aim it knows (MatchPlacement.request_place); a seat this instance controls reports its
	# own camera first (MatchNet only ever hears remote seats' aim from their cursor packets).
	if auto_drop and _held_gift_mode() != GiftThrow.Mode.NONE:
		match_context.note_aim(_acting_slot(), _camera_forward())
	var slot_id: int = _acting_slot()
	_clearance().lift_for_release()
	# record what this request is about to occupy *before*
	# sending it -- on the host this resolves synchronously inside the call
	# below (Events.placement_rejected/placement_relocated/feed_block_issued
	# all fire before match_context.submit_place() returns), so this has to be set
	# first or _on_feed_block_issued() below would see a stale flag.
	_clearance().begin_pending()
	if _session().is_client():
		_intent_lock_left = net_config.intent_ack_timeout
	return match_context.submit_place(
		slot_id,
		_ghost.global_position,
		_ghost.orientation_index,
		_ghost.free_quaternion,
		auto_drop
	)


## The one door a throw goes through, mirroring _request_place() above: same
## slot/pose arguments, same door (match_context.submit_throw: the wire on a client, Match directly otherwise), same
## spawn-clearance bookkeeping for the next ghost. DECISION (game/
## PlayerController.gd): a thrown special's shape does not actually stay
## where the throw is aimed -- it flies off with `velocity` --
## so the next ghost's spawn-clearance nudge is only ever approximate for a
## throw (it clears the aim spot, not wherever physics finally lands the
## piece). An approximate clearance is still strictly better than none, and
## SpawnClearance already tolerates being wrong (it just
## reseeds hover height, never blocks anything).
func _request_throw(velocity: Vector3) -> StringName:
	var slot_id: int = _acting_slot()
	_clearance().lift_for_release()
	_clearance().begin_pending()
	if _session().is_client():
		_intent_lock_left = net_config.intent_ack_timeout
	return match_context.submit_throw(
		slot_id,
		_ghost.global_position,
		_ghost.orientation_index,
		_ghost.free_quaternion,
		velocity
	)


# --- Camera-aimed gift throw ---------------------------------------

## how the gift in hand leaves it (NONE for an ordinary piece).
func _held_gift_mode() -> GiftThrow.Mode:
	var slot_id: int = _acting_slot()
	if slot_id < 0:
		return GiftThrow.Mode.NONE
	var special_id: StringName = match_context.held_special(slot_id)
	if special_id == &"":
		return GiftThrow.Mode.NONE
	return GiftThrow.mode_for(SpecialDef.find_by_id(special_id))


## the activating player's camera forward (unit), sent as the aim of a
## Rocket/Paintball launch. The host validates and normalises it again.
func _camera_forward() -> Vector3:
	var camera: Camera3D = _camera_rig.get_camera() if _camera_rig != null else null
	if camera != null and camera.is_inside_tree():
		return -camera.global_transform.basis.z
	var yaw: float = _camera_rig.get_yaw() if _camera_rig != null else 0.0
	return Vector3(sin(yaw), 0.0, cos(yaw))


## no state machine -- called every frame from _process(). While a throwable
## or aimed gift is held, the arc starts at the held gift and follows the camera forward (no LT,
## no drag) for gifts whose GiftThrow.shows_preview() is true; Rocket and
## Paintball draw none. The previewed launch comes from the same GiftAim
## functions the host uses, so the line equals the real flight.
func _drive_throw_visuals() -> void:
	if _ghost != null:
		_ghost.set_held_aim(_held_gift_aim_direction())
	if _arc_preview == null:
		return
	if not _can_preview_gift_aim():
		_arc_preview.clear_arc()
		return
	var launch: Dictionary = gift_launch_preview()
	if launch.is_empty():
		_arc_preview.clear_arc()
		return
	_arc_preview.update_arc(
		launch["origin"] as Vector3,
		launch["velocity"] as Vector3,
		match_context.field() as Field,
		float(launch["gravity_scale"]),
		_throw_range_scale()
	)


func _can_preview_gift_aim() -> bool:
	if _ghost == null or _acting_slot() < 0:
		return false
	if _ghost.get_shape() == null or _is_active_slot_eliminated():
		return false
	return GiftThrow.shows_preview(_held_gift_mode())


## The arc the held gift would fly right now: {origin, velocity, gravity_scale}, or an empty
## Dictionary when nothing is held/aimable. Read-only; shared by the preview and the tests.
func gift_launch_preview() -> Dictionary:
	if _ghost == null or special_tuning == null:
		return {}
	var mode: GiftThrow.Mode = _held_gift_mode()
	if mode == GiftThrow.Mode.NONE:
		return {}
	var forward: Vector3 = _camera_forward()
	var field: FieldBody = match_context.field()
	var surface_y: float = field.surface_y() if field != null else _ghost.global_position.y
	# the arc starts at the held model's visual centre, not the ghost's
	# bottom-face pivot (which sits below the model).
	var origin: Vector3 = GiftAim.spawn_point(_held_model_centre(), forward, surface_y, special_tuning)
	if mode == GiftThrow.Mode.THROW:
		return {
			"origin": origin,
			"velocity": GiftAim.throw_velocity(forward, special_tuning, _throw_range_scale()),
			"gravity_scale": 1.0,
		}
	var direction: Vector3 = forward
	if not _held_gift_flies_upward():
		direction = GiftAim.sanitize_downward_direction(forward)
	return {
		"origin": origin,
		"velocity": GiftAim.straight_velocity(direction, special_tuning.gift_throw_speed_mps),
		"gravity_scale": 0.0,
	}


## the active field's thrown-gift range scale (same GiftAim rule the host
## applies); 1.0 with no field.
func _throw_range_scale() -> float:
	var field: FieldBody = match_context.field()
	if field == null or field.map_definition() == null or special_tuning == null:
		return 1.0
	return GiftAim.range_scale(field.map_definition().field_radius, special_tuning)


## World centre of the held gift model (the ghost origin when no model is shown).
func _held_model_centre() -> Vector3:
	var box: AABB = _ghost.gift_visual_world_aabb()
	if box.size == Vector3.ZERO and box.position == Vector3.ZERO:
		return _ghost.global_position
	return box.get_center()


## Direction the held gift will leave in (the held Rocket/Magnet model points
## its nose along it); ZERO when nothing aimable is held.
func _held_gift_aim_direction() -> Vector3:
	if _ghost == null or special_tuning == null or _acting_slot() < 0:
		return Vector3.ZERO
	var mode: GiftThrow.Mode = _held_gift_mode()
	var forward: Vector3 = _camera_forward()
	if mode == GiftThrow.Mode.THROW:
		return GiftAim.throw_velocity(forward, special_tuning, _throw_range_scale()).normalized()
	if mode == GiftThrow.Mode.AIMED:
		if _held_gift_flies_upward():
			return GiftAim.sanitize_launch_direction(forward)
		return GiftAim.sanitize_downward_direction(forward)
	return Vector3.ZERO


## Whether the held aimed gift may fly upward (Rocket, Q3); Paintball may not.
func _held_gift_flies_upward() -> bool:
	var def: SpecialDef = SpecialDef.find_by_id(match_context.held_special(_acting_slot()))
	return def != null and def.effect != null and def.effect.may_aim_upward()


## A slot whose home flag is gone is effectively eliminated.
## Match.slot(id).home_flag_alive is the one source of truth for this -- no
## dedicated Events signal exists for it, so both the controller and the HUD just
## read PlayerSlot.home_flag_alive off Match.slot() (ui/hud/HUD.gd does the same).
func _is_active_slot_eliminated() -> bool:
	if _acting_slot() < 0:
		return false
	var slot: PlayerSlot = match_context.slot(_acting_slot())
	return slot != null and not slot.home_flag_alive


# --- Events reactions (spec 2.4) -----------------------

## An eliminated slot holds nothing, so its ghost (and the
## footprint, projection and decal that are its children) is hidden. Reads the
## same replicated home_flag_alive as _is_active_slot_eliminated(), so host and
## ENet clients agree; runs every frame (also covers a new match or slot swap)
## and only touches `visible` on a change, so Sandbox's own toggling is kept.
var _ghost_hidden_by_elimination: bool = false


func _sync_ghost_elimination_visibility() -> void:
	if _ghost == null:
		return
	var eliminated: bool = _is_active_slot_eliminated()
	if eliminated and not _ghost_hidden_by_elimination:
		_ghost_hidden_by_elimination = true
		_ghost.visible = false
	elif not eliminated and _ghost_hidden_by_elimination:
		_ghost_hidden_by_elimination = false
		_ghost.visible = true


func _on_player_eliminated(_slot_id: int, _team_id: int) -> void:
	_sync_ghost_elimination_visibility()


func _on_turn_changed(slot_id: int) -> void:
	_active_slot = slot_id
	var slot: PlayerSlot = match_context.slot(slot_id)
	if _ghost == null:
		return
	if slot != null:
		_ghost.set_player_color(slot.color)
	var shape: BlockShape = match_context.held_shape(slot_id)
	if shape != null:
		_ghost.set_shape(shape)
		_sync_ghost_gift(slot_id)
		# The camera needs no call here: an ordinary shape swap does not move the
		# followed height (see _camera_follow_anchor()).


## show the held-gift presentation on the ghost while the
## slot's current piece is a claimed gift (Match.held_special is set before
## feed_block_issued fires), the plain block ghost otherwise.
func _sync_ghost_gift(slot_id: int) -> void:
	if _ghost == null:
		return
	_ghost.set_held_gift(match_context.held_special(slot_id))


## the staged windowed build issues the first block (host) or
## receives its replicated feed (client) before this controller and its ghost
## exist, so a bind pulls whatever the acting slot already holds -- shape,
## colour and gift -- instead of waiting for the next feed signal.
func pull_current_held() -> void:
	if _ghost == null:
		return
	var slot_id: int = _acting_slot()
	var shape: BlockShape = match_context.held_shape(slot_id)
	if shape != null:
		_on_feed_block_issued(slot_id, shape.id, &"")


func _on_feed_block_issued(slot_id: int, shape_id: StringName, _next_shape_id: StringName) -> void:
	if slot_id != _acting_slot() or _ghost == null:
		return
	# The host answered, so whatever intent was in flight has resolved.
	_intent_lock_left = 0.0
	# Networked there is no Events.turn_changed to colour the ghost from, so
	# the first feed this slot receives does it instead.
	var slot: PlayerSlot = match_context.slot(slot_id)
	if slot != null:
		_ghost.set_player_color(slot.color)
	var shape: BlockShape = _shapes_by_id.get(shape_id) as BlockShape
	if shape != null:
		_ghost.set_shape(shape)
		_sync_ghost_gift(slot_id)
	_clearance().mark_fed()
	# Does not resolve the clearance here: this handler runs synchronously
	# inside the placement request that spawned the block (Events dispatch is not
	# deferred), before this frame's physics step has run, so a physics query here
	# could never see the block that was just placed. The pending spawn
	# (begun by _request_place()) is left alone;
	# _process() resolves it next, once the physics world has actually caught up.


## The placed bodies the held ghost's release pose touches right now, for SpawnClearance.
## A stationary (zero-motion) overlap query at the pose the host would test the ghost's
## release at (_release_pose()), with the boxes the host tests for the held piece
## (BlockFactory.overlap_probe_centers()/overlap_probe_size(), shared with
## MatchPlacement). No ghost_collision_skin inflation here (unlike
## GhostSweep's clearance gap): this asks "does it overlap right now", not
## "how much gap should be kept while sliding", so the boxes are used at their
## true size.
func _ghost_overlapping_bodies() -> Array[RigidBody3D]:
	var bodies: Array[RigidBody3D] = []
	var gift_id: StringName = _held_gift_id()
	var physics: PhysicsTuning = _ghost.tuning
	var centers: Array[Vector3] = BlockFactory.overlap_probe_centers(_ghost.get_shape(), physics, gift_id) if _ghost.get_shape() != null else []
	if centers.is_empty():
		return bodies
	var world: World3D = get_viewport().world_3d
	if world == null:
		return bodies
	var pose: Transform3D = _release_pose(gift_id)
	var space_state: PhysicsDirectSpaceState3D = world.direct_space_state
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = Vector3.ONE * BlockFactory.overlap_probe_size(physics, gift_id)
	for local_center: Vector3 in centers:
		var params: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
		params.shape = box_shape
		params.transform = Transform3D(pose.basis, pose.origin + pose.basis * local_center)
		params.collide_with_bodies = true
		params.collide_with_areas = false
		params.collision_mask = FieldBody.PLACEMENT_QUERY_MASK
		var overlaps: Array[Dictionary] = space_state.intersect_shape(params, ghost_tuning.collision_probe_max_bodies)
		for overlap: Dictionary in overlaps:
			var body: RigidBody3D = overlap.get("collider") as RigidBody3D
			if body != null:
				bodies.append(body)
	return bodies


## The held gift's id (&"" for an ordinary piece).
func _held_gift_id() -> StringName:
	if _acting_slot() < 0:
		return &""
	return match_context.held_special(_acting_slot())


## The pose the host overlap-tests this release at: the ghost's, except that an aimed gift
## spawns on the camera line (GiftAim.spawn_point) and one launched facing its flight line
## (Rocket, Paintball, Magnet) is tested in that faced basis at the muzzle-matched origin, as
## MatchPlacement.request_throw() does.
func _release_pose(gift_id: StringName) -> Transform3D:
	var pose: Transform3D = Transform3D(_ghost.basis, _ghost.global_position)
	var def: SpecialDef = SpecialDef.find_by_id(gift_id) if gift_id != &"" else null
	var mode: GiftThrow.Mode = GiftThrow.mode_for(def)
	if def == null or mode == GiftThrow.Mode.NONE:
		return pose
	var aim: Vector3 = _camera_forward()
	var field: FieldBody = match_context.field()
	pose.origin = GiftAim.spawn_point(pose.origin, aim, field.surface_y() if field != null else pose.origin.y, special_tuning)
	var velocity: Vector3 = GiftAim.throw_velocity(aim, special_tuning, _throw_range_scale()) if mode == GiftThrow.Mode.THROW else Vector3.ZERO
	var faced: Variant = MatchPlacement.launch_facing_basis(def, mode, aim, velocity)
	if faced == null:
		return pose
	pose.basis = faced as Basis
	if mode == GiftThrow.Mode.AIMED:
		pose.origin = BlockFactory.muzzle_matched_origin(pose.origin, pose.basis, _ghost.get_shape(), _ghost.tuning, gift_id)
	return pose


## Spec 1.4's auto-drop is [ORIGINAL]: the held block drops from its current
## ghost position. On the host -- and offline -- that is
## this ghost, exactly, and it costs nothing. On a client the host has
## already dropped it from the last cursor it received (see MatchNet), so
## sending anything from here would risk the duplicate the whole design
## exists to prevent. The flash still plays, because that is feedback.
func _on_feed_timer_expired(slot_id: int) -> void:
	if slot_id != _acting_slot() or _ghost == null or _is_active_slot_eliminated():
		return
	_ghost.play_auto_drop_flash()
	if not _session().is_host():
		return
	_request_place(true)


func _on_placement_rejected(slot_id: int, _reason: StringName) -> void:
	if slot_id != _acting_slot() or _ghost == null:
		return
	_intent_lock_left = 0.0
	_clearance().undo_release_lift()
	# neither refusal branch spawned anything near the cursor
	# (a manual refusal spawns nothing at all; an auto-drop burn spawns
	# something, but throws it off the map).
	_clearance().cancel_pending()
	_ghost.play_reject_animation()


## spec 1.4's auto-drop [ORIGINAL]: the host relocated this
## slot's auto-dropped block to `point` (disk-local x, z) because its own
## ghost position wasn't valid. Only ever acted on for this controller's own
## slot -- another slot's relocation is none of this instance's business, the
## same filter every other per-slot Events reaction here uses.
func _on_placement_relocated(slot_id: int, point: Vector2) -> void:
	if slot_id != _acting_slot() or _ghost == null:
		return
	var field: FieldBody = match_context.field()
	if field == null:
		return
	_cursor = field.to_global(Vector3(point.x, 0.0, point.y))
	# The relocation is a teleport the host already validated, so it must not
	# be swept against placed blocks: re-seed the collision
	# sweep's last safe point here, or a tower between the old cursor and the
	# zone would clamp the jump on the next frame.
	_last_safe_cursor = _cursor
	_collision_cursor_seeded = true
	_update_ghost_transform()
	if _camera_rig != null:
		# see _camera_follow_anchor()'s own doc comment.
		_camera_rig.set_follow_position(_camera_follow_anchor())


## Every frame: the read-only, advisory preview (spec 1.4) that tints the
## ghost before the click. request_place() re-validates from scratch and
## never trusts this (spec 2.6).
func _update_ghost_tint() -> void:
	if _ghost == null or _acting_slot() < 0:
		return
	if _ghost.get_shape() == null:
		return
	var result: PlacementRules.Result = match_context.preview_placement(
		_acting_slot(), _ghost.global_position, _ghost.orientation_index, _ghost.free_quaternion
	)
	_ghost.apply_validity(result)
	# spec 1.4: "A distinct timer-locked state must remain
	# visible even at a legal location" -- release-locked overrides whatever
	# apply_validity() just set, since the interval lock is about *when* this
	# piece may drop, not *where*.
	_ghost.set_locked(match_context.is_release_locked(_acting_slot()))


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
		_hover_hold_seconds = 0.0
		return
	# a held input accelerates (see GhostTuning.
	# hover_hold_acceleration's own doc comment) -- speed is evaluated from
	# the time held *before* this frame, so the first frame of any hold still
	# moves at exactly hover_manual_adjust_speed.
	var speed: float = minf(
		ghost_tuning.hover_manual_adjust_speed + ghost_tuning.hover_hold_acceleration * _hover_hold_seconds,
		maxf(ghost_tuning.hover_hold_max_speed, ghost_tuning.hover_manual_adjust_speed)
	)
	_hover_hold_seconds += delta
	var desired: float = clampf(
		_ghost.manual_hover_offset + change * speed * delta,
		0.0,
		_hover_offset_ceiling()
	)
	_clearance().absorb()
	_ghost.manual_hover_offset = _clamp_hover_offset(desired)
	_refresh_ghost_pose()


## spec 1.5: the mouse "positions the block" directly, camera-relative.
## `relative` is the InputEventMouseMotion's raw pixel delta, scaled by
## Settings.mouse_move_speed_scale() (the Options menu's "Mouse speed" slider)
## on top of the tuning Resource's own block_move_sensitivity baseline.
func _move_cursor_from_mouse(relative: Vector2) -> void:
	_cursor += _camera_relative_dir(relative) * ghost_tuning.block_move_sensitivity * Settings.mouse_move_speed_scale()


## Moves the gamepad's world-space cursor (spec 1.3), relative to the camera,
## with acceleration and speed scaling with zoom -- unless rotation_mode,
## rotate_drag_pad or camera_zoom_modifier is held, in which case the same
## left stick drives one of those instead (spec 1.5: "the movement keys
## change the orientation of the block"; RT/LT + stick rotate/zoom), and the
## cursor doesn't move at all while any of them is held.
func _update_gamepad_cursor(delta: float) -> void:
	var stick: Vector2 = Vector2(
		Input.get_action_strength(&"ghost_move_right") - Input.get_action_strength(&"ghost_move_left"),
		Input.get_action_strength(&"ghost_move_back") - Input.get_action_strength(&"ghost_move_forward")
	)
	# DECISION (game/player/PlayerController.gd): ghost_move_* shares the left stick
	# with camera_pan_* (see CameraRig's DECISION comment). Suppressing ghost
	# movement while camera_modifier is held is the half of that conflict
	# this script controls, so panning with the stick doesn't drag the ghost.
	if Input.is_action_pressed(&"camera_modifier"):
		stick = Vector2.ZERO
	if stick.length() > 1.0:
		stick = stick.normalized()

	# RT (rotate_drag_pad) + left stick free-rotates the held
	# block continuously, exactly like rotate_drag (MMB) + mouse motion --
	# NOT rotation_mode's 90 degree snap grid below. Checked before
	# rotation_mode so RT always wins over R if somehow both are held at once
	# (RT is a gamepad-only gesture and R a keyboard-only one, so that overlap
	# never happens on a single physical device in practice).
	if Input.is_action_pressed(&"rotate_drag_pad"):
		if stick.length() > 0.0:
			_accumulate_gamepad_rotate_drag(stick, delta)
		return

	# LT (camera_zoom_modifier) + left stick zooms the camera continuously, for
	# every held piece.
	if Input.is_action_pressed(&"camera_zoom_modifier"):
		if stick.y != 0.0:
			_drive_gamepad_zoom(stick.y, delta)
		return

	if Input.is_action_pressed(&"rotation_mode"):
		if stick.length() > 0.0:
			_accumulate_rotation_drag(stick, ghost_tuning.pad_rotation_speed * delta)
		return

	# scaled by Settings.stick_move_speed_scale() --
	# the Options menu's "Stick speed" slider (Controls tab) -- on top of the
	# tuning Resource's own gamepad_cursor_base_speed baseline.
	var max_speed: float = ghost_tuning.gamepad_cursor_base_speed * Settings.stick_move_speed_scale()
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


## spec 1.4 rotate_drag's vertical axis:
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
## ghost. Both devices move the same world-space _cursor (spec 1.5, "the mouse
## positions the block"), so there is only one path. Public so tests can
## exercise it without going through real input devices.
##
## The probe below skips over any RigidBody3D (a placed block) so it always
## reports the disk surface itself, never a tower: the ghost's height comes only
## from that disk surface plus hover_height plus the wheel (GhostPreview.
## update_placement()), while its XZ still comes straight from the cursor.
## Match.preview_placement()/request_place() do their own independent
## straight-down raycast against the real, unfiltered world (autoload/Match.gd,
## Field.raycast_down_disk_local()), so placement validity is unaffected.
func _update_ghost_transform() -> void:
	if _ghost == null:
		return
	var origin: Vector3 = _cursor + Vector3.UP * ghost_tuning.cursor_ray_height

	var hit: Dictionary = _ghost.raycast_disk_surface(origin)
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
	_clearance().set_surface(hit_point, hit_normal)
	_ghost.update_placement(hit_point, hit_normal)


# --- Ghost-vs-placed-block collision (spec 1.4 "Held-block
# behaviour" [ORIGINAL]) ------------------------------
#
# The held ghost collides with an already placed block -- it cannot pass
# through a tower -- but never pushes or knocks one. This runs a shape cast
# each frame against the real physics world instead of giving the ghost its
# own physics body, so a placed RigidBody3D is only ever read from
# (cast_motion/intersect_shape), never written to.
#
# DECISION (game/player/PlayerController.gd): placed blocks are told apart by
# node type (`is RigidBody3D`), not by collision_mask: nothing in this project
# sets a distinguishing physics layer (BlockFactory/Block.gd never call
# collision_layer/collision_mask, so every body -- block, disk, future goal
# zone -- defaults to Godot's layer 1, and project.godot has no [layer_names]
# section), and adding one would mean editing the project's physics layers
# (tools/bootstrap_project.gd owns project settings) and rippling into
# BlockFactory/Field. This is the technique GhostPreview.raycast_disk_surface() uses
# to skip a block when it wants the disk, inverted: skip anything that ISN'T a
# RigidBody3D (the disk, a future goal-zone Area3D) and only stop for one that
# is. A dedicated layer would be a follow-up.


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
## any one axis is blocked). Height is assumed constant across the sweep (a
## tilted disk is not accounted for). A no-op -- and keeps _last_safe_cursor in
## sync so re-enabling collision later never sweeps across a stale gap -- when
## collision is disabled,
## nothing is held, or the cursor didn't move this frame.
##
## _cursor is the aim point the
## *rotated* held shape's own centre sits over (GhostPreview.
## update_placement()), not this node's own origin -- so the boxes
## GhostSweep places at `position + basis * local_center` have to
## be built from the same cursor-minus-centre-offset point update_placement()
## will actually put the ghost's node origin at, or a pitched/rolled shape's
## swept boxes would land somewhere the render then doesn't match (this
## sweep would validate one position, update_placement() would show a
## different one). `center_offset` is zero for a yaw-only or unrotated pose
## (rotated_center_offset()'s own doc comment).
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


## The shared box-sweep behind both clamps above: GhostSweep slides the held shape's own
## collision boxes (built the way BlockFactory.build() would, so the ghost matches the block
## that will spawn) from `from_position` to `to_position` at the ghost's current rotation.
func _sweep_ghost_position(from_position: Vector3, to_position: Vector3) -> Vector3:
	var world: World3D = get_viewport().world_3d
	var boxes: Array[Vector3] = _ghost.collision_box_local_centers()
	if world == null or boxes.is_empty():
		return to_position
	return GhostSweep.new(ghost_tuning).sweep(
		world.direct_space_state, boxes, _ghost.collision_half_size(), _ghost.basis,
		from_position, to_position
	)


## Match names the shape it issues by id (Events.feed_block_issued); the ghost
## needs the resource. BlockShape.load_all_shapes() is the one directory scan
## in the project, so this only has to index its result.
func _load_shapes_by_id() -> Dictionary:
	var shapes: Dictionary = {}
	for shape: BlockShape in BlockShape.load_all_shapes():
		shapes[shape.id] = shape
	return shapes
