class_name CameraRig
extends Node3D
## Orbit/zoom/pan/snap camera rig (spec 1.3 camera row), driven only by the
## Input Map actions bootstrap_project.gd defines. CLAUDE.md: no raw keycodes
## and no deep node paths — this rig only ever reaches its own Camera3D child.
##
## Original-style block-locked camera, spec 1.5: by default
## (CameraTuning.follow_block) this rig's pivot (_target) tracks whatever position
## PlayerController reports through set_follow_position() every frame, smoothed by
## tuning.follow_lag_seconds. Orbit (camera_mode + mouse, or the gamepad's right
## stick, unconditionally) and zoom work in both modes; pan and the snap-to-home/goal
## actions are no-ops in follow mode, since there is no free target to move -- see
## the DECISION comments below. follow_block = false gives the free camera (manual
## pan, snap-to actions).
##
## While rotate_drag (MMB) is held the rig freezes completely -- target, yaw, pitch
## and distance (see _rotate_drag_frozen()) -- because the held ghost's geometric
## centre slides under MMB rotation for shapes whose mass is not symmetric about the
## rotation axis, and the camera would visibly move. It resumes following on release
## through the same follow_lag lerp/snap _process() runs every other frame.

@export var tuning: CameraTuning = preload("res://config/player/camera_tuning.tres")
@export var map_def: MapDef = preload("res://config/match/maps/round.tres")

## Spec 1.10 "camera shake": tunables for the decaying
## offset _update_transform() adds on top of the normal orbit position
## whenever Events.block_impacted fires hard enough. See shake_offset().
@export var shake_config: CameraShakeConfig = preload("res://config/physics/camera_shake.tres")
## which specials trigger a shake (disc-shaking/toppling only).
@export var disc_shake: DiscShakeConfig = preload("res://config/physics/disc_shake.tres")

## F4 tuning panel live-apply: every CameraRig adds itself
## to this group in _ready(), the same idea as game/blocks/Block.gd's TUNING_GROUP,
## so ui/debug/TuningPanel.gd can push a live camera_tuning edit onto whichever rig
## is actually in the tree (get_tree().get_nodes_in_group(TUNING_GROUP))
## without needing its own set_camera_rig() wiring to have run first.
const TUNING_GROUP: StringName = &"tuning_camera"

## Process order: this rig is a static child of game/main/Main.tscn, created before
## the PlayerController that the local player scene and Sandbox add at runtime, and _process() runs in
## ascending process_priority order with tree position only breaking ties. Both
## defaulted to 0, so this rig's _process() ran before PlayerController's every
## frame and read last frame's ghost position (set_follow_position() is only called
## from PlayerController._process()), which shows as jitter under mouse motion and
## on the height wheel.
## DECISION (game/player/CameraRig.gd): not a gameplay tunable (a fixed
## processing-order fact, like GhostPreview's _CORNER_SIGNS table), so it stays a
## local const rather than a CameraTuning field. Any positive value works: it only
## needs to exceed every default-priority (0) node's, chiefly PlayerController's.
const _PROCESS_PRIORITY_AFTER_GHOST: int = 1

## How close (meters) _target must get to _follow_position before
## begin_follow_transition()'s easing is considered finished. Not a gameplay
## tunable: it is only "close enough to be imperceptible", the same category as
## the shake epsilon (0.0001), sized in meters.
const _DROP_RECOVER_CONVERGED_M: float = 0.001

## Sandbox's own sandbox_next_slot hotkey is gamepad Back, which camera_snap_home
## also binds.
## DECISION (game/player/CameraRig.gd): game/sandbox/Sandbox.gd sets this
## true so a *gamepad* Back press there stays next-slot only; keyboard 1/2 and
## gamepad X (focus goal) keep working in the sandbox, where the owner tests
## most. Sandbox's Back+X comparison chord is already excluded by
## _goal_focus_chord_blocked() (Back is camera_snap_home).
@export var suppress_pad_home_focus: bool = false

var _yaw: float = 0.0
var _pitch: float = 0.0
var _distance: float = 0.0
var _target: Vector3 = Vector3.ZERO
## Where PlayerController says the held ghost's own rotated centre is
## (GhostPreview.rotated_center_world(), not its node
## origin -- see that method's doc comment), updated by set_follow_position()
## every frame. Only read when tuning.follow_block.
var _follow_position: Vector3 = Vector3.ZERO

## True while _process() eases _target into _follow_position over
## tuning.drop_recover_seconds instead of hard-snapping to it (see
## begin_follow_transition()). Clears itself once _target has caught up rather than
## on a fixed timer, so it never flips back to hard-snap mode with a residual gap
## still showing.
var _drop_recovering: bool = false

## camera shake: the amplitude (meters) of the shake impulse
## currently decaying, and how long it has been decaying for. A fresh, harder
## Events.block_impacted while one is still decaying replaces the amplitude
## outright rather than stacking (spec 1.10 asks for a shake reaction per
## impact, not compounding shakes from a rapid string of small settling
## impacts) and restarts the decay clock, so the strongest recent hit always
## governs.
var _shake_amplitude_m: float = 0.0
var _shake_elapsed_s: float = 0.0
## Last sampled disc tilt, for the disc-motion shake (earthquake).
var _prev_disc_tilt: Vector2 = Vector2.ZERO
var _has_prev_disc_tilt: bool = false
var _disc_sample_elapsed_s: float = 0.0
var _sampled_field: Field = null
var _decay_elapsed_s: float = 0.0

## which slot's home beacon Focus home should target -- pushed
## every frame by game/player/PlayerController.gd's own _acting_slot() (the same
## "local/acting slot" the local player scene and Sandbox already resolve for it), never read
## from here. -1 (the default) means "no local slot known yet"; _resolve_
## home_target() below falls back to the disk center in that case, same as
## an eliminated or missing flag.
var _local_slot: int = -1


## camera_snap_home/camera_snap_goal's tap-vs-hold state, tracked
## only while tuning.follow_block (the free camera keeps its old
## single-press _snap_to() below, unchanged). `_focus_action` is `&""` when
## neither is currently held, or the StringName of whichever Input Map action
## is being held (&"camera_snap_home" / &"camera_snap_goal") -- see
## _on_focus_pressed()/_on_focus_released()/_update_focus_hold().
var _focus_action: StringName = &""
## The real world-space target (a beacon's global_position, or the disk
## center fallback) resolved once at press time -- see _resolve_home_target()/
## _resolve_goal_target() -- and reused by both the TURN tap and the PEEK
## hold this same press produces, so a goal cycle only advances once per
## press, not every frame it's held.
var _focus_target_point: Vector3 = Vector3.ZERO
var _focus_hold_elapsed_s: float = 0.0
## True for exactly as long as PEEK is actively holding the camera on
## _focus_target_point (past tuning.focus_hold_threshold_s, still held).
## game/player/PlayerController.gd reads this through is_peeking() to suppress
## ghost-cursor movement and placement while it's true.
var _peek_active: bool = false
## True while _process() is gliding _target/_distance/_pitch back to the
## normal follow framing after a PEEK release, until it converges (the same
## _DROP_RECOVER_CONVERGED_M-gated pattern _drop_recovering already uses).
var _peek_returning: bool = false
## "each new goal press/tap cycles to the next goal": advanced
## once per fresh camera_snap_goal press by _resolve_goal_target() below, not
## every frame -- so holding through a PEEK doesn't itself keep cycling.
var _goal_cycle_index: int = 0
## the in-flight _snap_to()/_turn_to_face() tweens, so reset_view()
## can stop one before it keeps writing _yaw/_target/_distance/_pitch into the
## next match.
var _view_tweens: Array[Tween] = []
## returns the held piece's camera anchor at its spawn pose
## (game/player/PlayerController.gd spawn_camera_anchor(), registered through
## set_camera_rig()). begin_start_framing() pivots on it; empty means "no
## controller", and the home beacon is used instead.
var _start_anchor_source: Callable = Callable()
## the match-start pose (yaw/pitch/distance/target) recorded by
## begin_start_framing(), which camera_reset restores. Cleared by reset_view().
var _has_start_pose: bool = false
var _start_yaw: float = 0.0
var _start_pitch: float = 0.0
var _start_distance: float = 0.0
var _start_target: Vector3 = Vector3.ZERO

@onready var _camera: Camera3D = $Camera3D


## Shared with PlayerController (set_camera_rig hands it over); this rig outlives matches.
var input_gate: InputGate = InputGate.new()


func _ready() -> void:
	add_to_group(TUNING_GROUP)
	Events.special_triggered.connect(_on_special_triggered)
	process_priority = _PROCESS_PRIORITY_AFTER_GHOST
	# This rig's global_position and its Camera3D child's transform are fully
	# re-derived every rendered _process() frame from mouse/gamepad input, never from
	# _physics_process, so with physics/common/physics_interpolation on the
	# RenderingServer's smoothing only adds lag and logs "Interpolated Camera3D
	# triggered from outside physics process". OFF makes both show their latest
	# logical transform.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera.fov = effective_fov_deg()
	if not Settings.fov_override_changed.is_connected(_on_fov_override_changed):
		Settings.fov_override_changed.connect(_on_fov_override_changed)
	_apply_default_view()


## The launch framing: _ready() and reset_view() both end here, so a rig that
## was reset is the same as a freshly instanced one by construction.
func _apply_default_view() -> void:
	# DECISION (game/player/CameraRig.gd): the initial view scales with the map's
	# field_radius (a close-in fixed default looked fine on a small map but
	# was nose-to-the-glass on a medium/large one, since the disk fills most
	# of the frame at any distance shorter than roughly its own radius).
	# tuning.snap_distance is still used as-is for camera_snap_home/goal,
	# which are deliberately closer-in views.
	if tuning.follow_block:
		# Following the held block: a close, shallow view like the original's
		# (config/CameraTuning.follow_distance / follow_pitch_deg), not the
		# whole-disk overview the free camera starts from.
		apply_follow_tuning()
	else:
		_distance = clampf(map_def.field_radius * 1.4, tuning.zoom_min, _zoom_max())
		_pitch = deg_to_rad(tuning.snap_pitch_deg)
		_update_transform()


## True while either orbit hold (RMB camera_orbit, or the C alias camera_mode) is down.
func is_orbiting() -> bool:
	return Input.is_action_pressed(&"camera_mode") or Input.is_action_pressed(&"camera_orbit")


func _unhandled_input(event: InputEvent) -> void:
	if input_gate.is_blocked():
		return
	if _rotate_drag_frozen():
		# The freeze consumes every camera input (orbit, pan, zoom keys, snap actions)
		# while rotate_drag is held; see _rotate_drag_frozen(). PlayerController has
		# its own _unhandled_input() and still receives this event (Godot dispatches
		# it to every listening node), so the ghost keeps rotating.
		return
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		if is_orbiting():
			# camera_orbit (RMB) is the primary hold (spec 1.3 "Camera orbit (hold +
			# drag)"); camera_mode (C) stays wired as the keyboard alias for the same
			# gesture.
			_yaw -= motion.relative.x * tuning.mouse_orbit_speed
			_pitch -= motion.relative.y * tuning.mouse_orbit_speed
			_clamp_pitch()
			_update_transform()
		elif not tuning.follow_block and Input.is_action_pressed(&"camera_modifier"):
			# DECISION (game/player/CameraRig.gd): manual pan only makes sense for the
			# free-orbit camera (follow_block = false) -- follow mode re-centers _target on the
			# ghost every frame (see _process()), so a pan offset here would be
			# overwritten within a frame or two anyway.
			_target += _pan_offset(Vector2(-motion.relative.x, motion.relative.y)) * tuning.mouse_pan_speed
			_update_transform()
		return

	# camera_zoom_in/out are keyboard-only (Z/X; tools/bootstrap_project.gd), so both
	# always zoom. The gamepad's zoom gesture (LT + left
	# stick, continuous) is PlayerController._drive_gamepad_zoom() ->
	# zoom_continuous(), driven every frame rather than through this handler. The
	# wheel is block height only (ghost_tuning's hover_raise/hover_lower), so it is
	# not bound to this action.
	if event.is_action_pressed(&"camera_zoom_in"):
		_zoom(-1.0)
	elif event.is_action_pressed(&"camera_zoom_out"):
		_zoom(1.0)
	# snap is off while tuning.snap_enabled is false.
	elif tuning.snap_enabled and event.is_action_pressed(&"camera_snap_home"):
		# camera_snap_home's own press/release needs no block_held gate either -- see
		# _on_focus_pressed()'s own
		# DECISION for the one gate that IS still needed (goal's shared X).
		if not (suppress_pad_home_focus and event is InputEventJoypadButton):
			_on_focus_pressed(&"camera_snap_home")
	elif event.is_action_released(&"camera_snap_home") and _focus_action == &"camera_snap_home":
		_on_focus_released()
	elif tuning.snap_enabled and event.is_action_pressed(&"camera_snap_goal"):
		_on_focus_pressed(&"camera_snap_goal")
	elif event.is_action_released(&"camera_snap_goal") and _focus_action == &"camera_snap_goal":
		_on_focus_released()
	elif event.is_action_pressed(&"camera_reset"):
		# Back is shared with camera_snap_home (see
		# tools/bootstrap_project.gd). Snap owns the pad press while enabled, and
		# the sandbox uses Back for its own chords.
		if not (event is InputEventJoypadButton and (tuning.snap_enabled or suppress_pad_home_focus)):
			reset_to_start_pose()


func _process(delta: float) -> void:
	if _rotate_drag_frozen():
		# Returning here before touching _target/_yaw/_pitch/_distance or calling
		# _update_transform() leaves global_transform bit-for-bit as last frame,
		# whatever PlayerController's set_follow_position() reports (the ghost's
		# rotated centre moves during a drag for asymmetric shapes) or what the
		# height wheel/gamepad stick did. Releasing rotate_drag needs no resume code:
		# the next non-frozen _process() lerps _target toward _follow_position at the
		# normal follow_lag_seconds rate (an instant snap at the shipped default of 0).
		return
	# The gamepad's right stick always free-orbits (spec 1.3's camera row has
	# no gamepad hold requirement; see test_project_setup.gd's DEVICE_EXCEPTIONS
	# for camera_mode). The left stick belongs to rotation_mode
	# (PlayerController._accumulate_rotation_drag), so the right stick has no
	# second job to gate against.
	var look_x: float = 0.0
	var look_y: float = 0.0
	if not input_gate.is_blocked():
		look_x = Input.get_action_strength(&"camera_look_right") - Input.get_action_strength(&"camera_look_left")
		look_y = Input.get_action_strength(&"camera_look_down") - Input.get_action_strength(&"camera_look_up")
	if look_x != 0.0 or look_y != 0.0:
		_yaw -= look_x * tuning.pad_orbit_speed * delta
		_pitch -= look_y * tuning.pad_orbit_speed * delta
		_clamp_pitch()

	if tuning.follow_block:
		# spec 1.5, "the camera is attached to the held block": smoothly close the
		# distance to wherever PlayerController last reported the ghost, an
		# exponential approach so a sudden large motion (e.g. a mode switch) does not
		# jerk the camera. follow_lag_seconds == 0 degrades to an exact snap.
		# While _drop_recovering (see begin_follow_transition()),
		# tuning.drop_recover_seconds is the time constant instead, even when
		# follow_lag_seconds is 0: the one discontinuous re-target this eases into
		# must not hard-snap just because ordinary movement is tuned to.
		# PEEK and its return glide own _target/_distance/_pitch outright while either
		# is active, so the ordinary follow lerp below (and _drop_recovering) must not
		# fight them for those fields. _update_focus_hold() only starts a PEEK while
		# tuning.follow_block, so this branch is the only place that needs to know
		# about it.
		_update_focus_hold(delta)
		if _peek_active:
			_approach_focus(_focus_target_point, tuning.focus_peek_distance, tuning.focus_peek_pitch_deg, tuning.focus_peek_transition_s, delta)
		elif _peek_returning:
			_approach_focus(_follow_position, tuning.follow_distance, tuning.follow_pitch_deg, tuning.focus_peek_transition_s, delta)
			if _target.distance_to(_follow_position) <= _DROP_RECOVER_CONVERGED_M:
				_peek_returning = false
		else:
			var lag_seconds: float = tuning.drop_recover_seconds if _drop_recovering else tuning.follow_lag_seconds
			var weight: float = 1.0
			if lag_seconds > 0.0:
				weight = 1.0 - exp(-delta / lag_seconds)
			_target = _target.lerp(_follow_position, clampf(weight, 0.0, 1.0))
			if _drop_recovering and _target.distance_to(_follow_position) <= _DROP_RECOVER_CONVERGED_M:
				_drop_recovering = false
	else:
		# DECISION (game/player/CameraRig.gd): camera_pan_* shares its gamepad axis
		# with ghost_move_* (both read the left stick). PlayerController
		# suppresses ghost movement while camera_modifier is held so the
		# player can pan cleanly; this rig applies pan from the action
		# strength unconditionally, so nudging the stick to move the ghost
		# also pans the camera a little in the free-orbit (follow_block = false)
		# mode. That's a minor, documented side effect, not a hard bug.
		var pan_x: float = Input.get_action_strength(&"camera_pan_right") - Input.get_action_strength(&"camera_pan_left")
		var pan_z: float = Input.get_action_strength(&"camera_pan_back") - Input.get_action_strength(&"camera_pan_forward")
		if input_gate.is_blocked_by(InputGate.Blocker.CHAT):
			# typed W/A/S/D must not pan the free-orbit camera.
			pan_x = 0.0
			pan_z = 0.0
		if pan_x != 0.0 or pan_z != 0.0:
			_target += _pan_offset(Vector2(pan_x, pan_z)) * tuning.pan_speed * delta

	_update_shake(delta)
	_update_transform()


## called by PlayerController every frame with the held
## ghost's world position (its rotated geometric centre, not
## its node origin, so a pitch/roll spins the block in place instead of
## dragging the camera's framing). Only used while tuning.follow_block is
## true; the free-orbit camera ignores it.
func set_follow_position(pos: Vector3) -> void:
	_follow_position = pos


## debug Watch bots: puts the rig on a spectator pose -- the pivot, distance and
## pitch (clamped like the orbit/zoom input) -- without touching the yaw, so the spectator controller
## (game/player/SpectatorController.gd) can frame the arena overview or a followed bot. Follow-mode rigs keep
## easing onto set_follow_position() afterwards, which is how that controller pans and follows.
func set_spectator_pose(pivot: Vector3, distance: float, pitch_deg: float) -> void:
	_target = pivot
	_follow_position = pivot
	_distance = clampf(distance, tuning.zoom_min, _zoom_max())
	_pitch = deg_to_rad(pitch_deg)
	_clamp_pitch()
	_drop_recovering = false
	_update_transform()


## Eases the next several set_follow_position() updates toward the ghost over
## tuning.drop_recover_seconds instead of snapping. With follow_lag_seconds at its
## shipped 0 this rig hard-snaps _target to the reported position every frame, which
## suits small continuous ghost motion but not the one discontinuous re-target
## PlayerController._apply_spawn_clearance() produces when it raises the new ghost's
## manual_hover_offset in a single frame (building on your own stack): snapping
## there is a visible camera jump. PlayerController calls this at exactly that call
## site, so follow_lag_seconds and the continuous cursor-driven motion are
## untouched.
func begin_follow_transition() -> void:
	_drop_recovering = true


## Called once by PlayerController.set_home_position() when a controller binds to
## a real slot. Points this rig's yaw so its offset (see _update_transform()) sits
## on the `home_position` side of `look_at_position`, i.e. the camera looks toward
## the centre from behind the block, and seeds both _target and _follow_position at
## the home flag so there is no one-frame jump before PlayerController's
## set_follow_position() takes over.
func set_home_view(home_position: Vector3, look_at_position: Vector3 = Vector3.ZERO) -> void:
	var away: Vector2 = Vector2(home_position.x - look_at_position.x, home_position.z - look_at_position.z)
	if away.length() > 0.0001:
		_yaw = atan2(away.x, away.y)
	_target = home_position
	_follow_position = home_position
	_update_transform()


## This rig is a static child of game/main/Main.tscn that outlives every match, and
## a match start only re-aims yaw/target (begin_start_framing()/set_home_view()), so
## the previous match's zoom distance, pitch, peek/focus state, shake and queued
## snap/turn tweens would carry over. game/main/Main.gd calls this when a match
## world is built and torn down; it puts every field back to what _ready() leaves on
## a fresh launch. That includes suppress_pad_home_focus, which only
## game/sandbox/Sandbox.gd sets (and re-sets in its own set_camera_rig() on the next
## sandbox start), so a lobby match after a sandbox session has gamepad Back =
## focus home again.
func reset_view() -> void:
	input_gate.clear_match_scope()
	suppress_pad_home_focus = false
	for tween: Tween in _view_tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_view_tweens.clear()
	_start_anchor_source = Callable()
	_has_start_pose = false
	_yaw = 0.0
	_target = Vector3.ZERO
	_follow_position = Vector3.ZERO
	_local_slot = -1
	_drop_recovering = false
	_peek_active = false
	_peek_returning = false
	_focus_action = &""
	_focus_target_point = Vector3.ZERO
	_focus_hold_elapsed_s = 0.0
	_goal_cycle_index = 0
	_shake_amplitude_m = 0.0
	_shake_elapsed_s = 0.0
	_decay_elapsed_s = 0.0
	_has_prev_disc_tilt = false
	_camera.fov = effective_fov_deg()
	_apply_default_view()


## Match-start entry point, called when the ready gate opens. There is no separate
## countdown camera: this sets the FINAL gameplay view at once (yaw from the home
## beacon via set_home_view(); pitch and distance from CameraTuning's start_*
## values, the low, wide angle) and the ordinary ghost-follow takes over from the
## first frame, so nothing eases or shifts at GO. Player orbit and zoom work as
## normal afterwards.
## The pivot is the held piece's follow anchor at its spawn pose (_start_pivot()),
## the point the follow tracks on the first PLAYING frame, not the bare beacon
## (~2 m nearer the centre and ~3.5 m lower), which would make the view jump by that
## much at GO. PlayerController keeps feeding that same anchor through the
## countdown (its _present_countdown_hold()).
## Returns false, leaving the camera alone, when the slot has no beacon.
func begin_start_framing(slot_id: int) -> bool:
	_local_slot = slot_id
	var home: Vector3 = _resolve_home_target()
	if home == Vector3.ZERO:
		return false
	set_home_view(home, Vector3.ZERO)
	var pivot: Vector3 = _start_pivot(home)
	_target = pivot
	_follow_position = pivot
	_drop_recovering = false
	# CameraTuning's start_* pitch/distance (the low wide start angle), held from the
	# ready gate through PLAYING with no shift; the follow keeps it until the player
	# moves the camera.
	_distance = clampf(tuning.start_distance_m, tuning.zoom_min, _zoom_max())
	_pitch = deg_to_rad(tuning.start_pitch_deg)
	_has_start_pose = true
	_start_yaw = _yaw
	_start_pitch = _pitch
	_start_distance = _distance
	_start_target = _target
	_update_transform()
	return true


## camera_reset: puts the camera back on the match-start pose
## recorded by begin_start_framing(). In follow mode the target keeps tracking
## the held block (only yaw/pitch/distance are restored); the free camera also
## gets its start target back. Before any match start (no recorded pose) it
## falls back to the launch framing. Cancels PEEK and in-flight snap tweens.
func reset_to_start_pose() -> void:
	for tween: Tween in _view_tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_view_tweens.clear()
	_peek_active = false
	_peek_returning = false
	_focus_action = &""
	_focus_hold_elapsed_s = 0.0
	if not _has_start_pose:
		_apply_default_view()
		return
	_yaw = _start_yaw
	_pitch = _start_pitch
	_distance = _start_distance
	if not tuning.follow_block:
		_target = _start_target
	_update_transform()


## registered by PlayerController.set_camera_rig(); see
## _start_anchor_source. Cleared by reset_view().
func set_start_anchor_source(source: Callable) -> void:
	_start_anchor_source = source


## The match-start pivot: the held piece's spawn anchor when a controller is
## wired, else the home beacon `home`.
func _start_pivot(home: Vector3) -> Vector3:
	if _start_anchor_source.is_valid():
		var anchor: Variant = _start_anchor_source.call()
		if anchor is Vector3:
			return anchor as Vector3
	return home


## pushed every frame by game/player/PlayerController.gd's own
## _acting_slot() (the same "local/acting slot" the local player scene and
## Sandbox's own active-slot cycling already resolve) so Focus home can find
## the right beacon among Field.home_flags() without this rig needing its own
## copy of that resolution logic. -1 is the "not known yet" default;
## _resolve_home_target() below treats that the same as a missing flag.
func set_local_slot(slot_id: int) -> void:
	_local_slot = slot_id


## True only while PEEK is actively holding the camera on a focus target (past
## tuning.focus_hold_threshold_s, camera_snap_home/goal still held) -- not
## during the brief return glide after release. game/player/PlayerController.gd
## reads this every frame to suppress ghost-cursor movement and placement.
func is_peeking() -> bool:
	return _peek_active


## the lens in use: the player's Options value when set, else CameraTuning.fov_deg.
func effective_fov_deg() -> float:
	var chosen: float = Settings.fov_override_deg()
	if chosen > 0.0:
		return clampf(chosen, tuning.fov_min_deg, tuning.fov_max_deg)
	return tuning.fov_deg


func _on_fov_override_changed(_degrees: float) -> void:
	_camera.fov = effective_fov_deg()


## F4 tuning panel live-apply: re-snapshots _distance/_pitch
## from tuning.follow_distance/follow_pitch_deg, clamped exactly as _ready()
## does. Called once by _ready() and again by ui/debug/TuningPanel.gd's
## _apply_camera_tuning_live() whenever camera_tuning changes on the F4 panel
## -- never every frame, so a manual orbit/zoom the player already did (see
## _unhandled_input()/_process() above) is only overwritten by an explicit
## tuning push, not silently fought every tick. A no-op while
## tuning.follow_block is false: the free-orbit camera has its own fixed
## target/distance and these two fields mean nothing to it.
func apply_follow_tuning() -> void:
	# DECISION (game/player/CameraRig.gd): fov_deg applies here unconditionally (unlike
	# distance/pitch below) because it isn't a follow-only concept -- the panel
	# calls this hook for any camera_tuning edit, and the free-orbit camera
	# should get a live fov change too.
	_camera.fov = effective_fov_deg()
	if not tuning.follow_block:
		return
	_distance = clampf(tuning.follow_distance, tuning.zoom_min, _zoom_max())
	_pitch = deg_to_rad(tuning.follow_pitch_deg)
	_update_transform()


## Used by PlayerController to scale gamepad ghost-cursor speed with zoom
## (spec 1.3: "speed scales with camera zoom").
func get_distance() -> float:
	return _distance


## Used by PlayerController to move the ghost cursor relative to the
## camera's current facing (both mouse and gamepad).
func get_yaw() -> float:
	return _yaw


## Test/inspection seam: the rig's current pitch, in
## radians, the same units get_yaw() already uses.
func get_pitch() -> float:
	return _pitch


func get_camera() -> Camera3D:
	return _camera


## For tests: where the rig's pivot currently sits (its "look at" point).
func get_target() -> Vector3:
	return _target


## Spec 1.10 "camera shake": the current shake offset
## _update_transform() adds to the camera's local position, in meters -- zero
## when no impact has happened yet, when the last shake has fully decayed, or
## when Settings.camera_shake_enabled() is false. Exposed as its own getter
## (rather than only being visible through get_camera().position) so
## tests/unit/player/test_camera_shake.gd can assert on it directly without also
## depending on the rig's current orbit distance/yaw/pitch.
func shake_offset() -> Vector3:
	if not Settings.camera_shake_enabled():
		return Vector3.ZERO
	var current_amplitude: float = _current_shake_amplitude()
	if current_amplitude <= 0.0001:
		return Vector3.ZERO
	# DECISION (game/player/CameraRig.gd): a fixed, arbitrary-looking but
	# deterministic 3-axis phase offset (not a random per-impact direction)
	# so the same impact always shakes the same way in a test and in a real
	# run, and so the three axes don't all peak in lockstep (which would read
	# as a single up-down bounce rather than a shake).
	var t: float = _shake_elapsed_s * shake_config.frequency_hz * TAU
	return Vector3(
		sin(t) * current_amplitude,
		sin(t * 1.3 + 1.0) * current_amplitude,
		sin(t * 0.7 + 2.0) * current_amplitude
	)


func _clamp_pitch() -> void:
	_pitch = clampf(_pitch, deg_to_rad(tuning.min_pitch_deg), deg_to_rad(tuning.max_pitch_deg))


## True for exactly as long
## as rotate_drag is held, on whichever device -- Input.is_action_pressed()
## already reads every binding the Input Map has for the action (mouse and
## gamepad alike; tools/bootstrap_project.gd), so a pad binding added there
## later needs no change here. Read by _process(), _unhandled_input() and
## zoom_by_orbit_step() (the one mutator PlayerController can reach directly,
## bypassing this rig's own _unhandled_input) so the freeze is total: no
## target/yaw/pitch/distance mutation anywhere while true.
## DECISION (game/player/CameraRig.gd): camera_orbit (RMB) is bound to a different
## action than rotate_drag (MMB), so both can physically be held at once.
## The simplest consistent rule is that rotate_drag always wins outright --
## _unhandled_input()'s early return above fires before it ever checks
## camera_orbit/camera_mode, so starting or continuing an RMB-orbit drag
## while MMB is already down does nothing until MMB is released, and holding
## RMB first and then also pressing MMB freezes the rig mid-orbit exactly
## like any other frozen frame, without a second precedence rule to test and explain.
func _rotate_drag_frozen() -> bool:
	return Input.is_action_pressed(&"rotate_drag")


## the match's own (possibly disc-size scaled) map; the rig frames and
## zooms relative to it. Called by Main whenever the field is rebuilt.
func set_map_def(new_map_def: MapDef) -> void:
	if new_map_def != null:
		map_def = new_map_def


## The farthest zoom: tuning.zoom_max, grown in proportion when the disc is larger than the
## default medium map so a whole enormous disc still fits in view (never shrunk).
func _zoom_max() -> float:
	var growth: float = maxf(map_def.field_radius / MapDef.RADIUS_MEDIUM, 1.0) if map_def != null else 1.0
	return tuning.zoom_max * growth


func _zoom(direction: float) -> void:
	_distance = clampf(_distance + direction * tuning.zoom_step, tuning.zoom_min, _zoom_max())


## spec 1.4 "mouse wheel zooms while held": called by PlayerController when the
## wheel fires while camera_mode/camera_orbit is held, using its own tunable
## (orbit_zoom_step) instead of zoom_step, which the dedicated Z/X zoom keys use
## via _zoom() -- letting the held-orbit wheel feel be tuned independently.
func zoom_by_orbit_step(direction: float) -> void:
	if _rotate_drag_frozen():
		# PlayerController calls this directly (not through this rig's
		# _unhandled_input, which guards itself above) when camera_orbit/camera_mode
		# is held and the wheel fires; if rotate_drag is also held, freeze wins --
		# see the DECISION on _rotate_drag_frozen().
		return
	_distance = clampf(_distance + direction * tuning.orbit_zoom_step, tuning.zoom_min, _zoom_max())


## Called every frame by PlayerController._drive_gamepad_zoom() while
## camera_zoom_modifier (LT) is held and not aiming a throw (LT + left stick
## up/down = zoom in/out, continuous), with `amount` already scaled by
## tuning.gamepad_trigger_zoom_speed and the frame's delta. Unlike
## zoom_by_orbit_step's fixed per-notch step, this is a continuous analog rate.
## Frozen like zoom_by_orbit_step while rotate_drag is held (see
## _rotate_drag_frozen()).
func zoom_continuous(amount: float) -> void:
	if _rotate_drag_frozen():
		return
	_distance = clampf(_distance + amount, tuning.zoom_min, _zoom_max())


func _pan_offset(input_2d: Vector2) -> Vector3:
	var forward: Vector3 = Vector3(sin(_yaw), 0.0, cos(_yaw))
	var right: Vector3 = Vector3(forward.z, 0.0, -forward.x)
	return right * input_2d.x + forward * input_2d.y


## Remembers `tween` for reset_view() (finished ones are dropped on the way).
func _track_view_tween(tween: Tween) -> void:
	for index: int in range(_view_tweens.size() - 1, -1, -1):
		if not _view_tweens[index].is_valid():
			_view_tweens.remove_at(index)
	_view_tweens.append(tween)


func _snap_to(point: Vector3) -> void:
	var tween: Tween = create_tween()
	_track_view_tween(tween)
	tween.set_parallel(true)
	tween.tween_property(self, ^"_target", point, tuning.snap_duration)
	tween.tween_property(self, ^"_distance", tuning.snap_distance, tuning.snap_duration)
	tween.tween_property(self, ^"_pitch", deg_to_rad(tuning.snap_pitch_deg), tuning.snap_duration)


# --- Focus home/goal's
# tap-to-TURN / hold-to-PEEK gesture --------------------------------------

## Handles a fresh camera_snap_home/camera_snap_goal press: resolves the real
## target once (so a goal cycle advances exactly once per press, not once per
## frame it's held -- see _resolve_goal_target()'s own doc comment), then
## either fires the free camera's single instant _snap_to() (follow_block
## false) or starts this press's tap/hold tracking for _update_focus_hold()
## to pick up next frame.
func _on_focus_pressed(action: StringName) -> void:
	# DECISION (game/player/CameraRig.gd): camera_snap_goal's gamepad half (X,
	# tools/bootstrap_project.gd) doubles as ui/debug/TuningPanel.gd's Start+X
	# tuning_panel_toggle chord and, in game/sandbox/Sandbox.gd, sandbox_physics_
	# comparison's Back+X chord -- checked here directly (rather than relying
	# on _unhandled_input dispatch order against those other nodes' own
	# handlers) so it's robust regardless of tree order, the same defensive
	# style PlayerController._camera_orbit_held() already uses for its own
	# shared-wheel gating.
	if action == &"camera_snap_goal" and _goal_focus_chord_blocked():
		return
	var target: Vector3 = _resolve_home_target() if action == &"camera_snap_home" else _resolve_goal_target()
	if not tuning.follow_block:
		_snap_to(target)
		return
	_focus_action = action
	_focus_target_point = target
	_focus_hold_elapsed_s = 0.0


func _goal_focus_chord_blocked() -> bool:
	return Input.is_action_pressed(&"pause_menu") or Input.is_action_pressed(&"camera_snap_home")


## The release half of _on_focus_pressed() above: a still-tapping hold (never
## crossed tuning.focus_hold_threshold_s, so PEEK never engaged) becomes a
## TURN; a hold that was already PEEKing starts the glide back to the normal
## follow framing instead (_process()'s own _peek_returning branch).
func _on_focus_released() -> void:
	var target: Vector3 = _focus_target_point
	var was_peeking: bool = _peek_active
	_focus_action = &""
	_focus_hold_elapsed_s = 0.0
	_peek_active = false
	if was_peeking:
		_peek_returning = true
		return
	_turn_to_face(target)


## advances _focus_hold_elapsed_s while camera_snap_home/goal is
## still held and flips into PEEK the frame it crosses tuning.focus_hold_
## threshold_s. Polls Input.is_action_pressed() rather than waiting only for
## the matching is_action_released() event in _unhandled_input() -- a
## defensive fallback for a hold that ends some other way (e.g. input_enabled
## toggling off mid-hold) so this can never get stuck waiting for a release
## event that will never come.
func _update_focus_hold(delta: float) -> void:
	if _focus_action == &"":
		return
	if not Input.is_action_pressed(_focus_action):
		_on_focus_released()
		return
	_focus_hold_elapsed_s += delta
	if not _peek_active and _focus_hold_elapsed_s >= tuning.focus_hold_threshold_s:
		_peek_active = true


## The exponential-approach shape _process()'s ordinary follow_lag_seconds
## branch already uses, reused for both PEEK's glide onto a target and its
## own glide back afterward -- unlike that branch, this also eases _distance/
## _pitch, since PEEK reframes the whole shot rather than just re-centering
## on a moving block.
func _approach_focus(target_point: Vector3, distance_val: float, pitch_deg: float, lag_s: float, delta: float) -> void:
	var weight: float = 1.0
	if lag_s > 0.0:
		weight = 1.0 - exp(-delta / lag_s)
	weight = clampf(weight, 0.0, 1.0)
	_target = _target.lerp(target_point, weight)
	_distance = lerpf(_distance, clampf(distance_val, tuning.zoom_min, _zoom_max()), weight)
	_pitch = lerpf(_pitch, deg_to_rad(pitch_deg), weight)


## TURN ("tween camera yaw so the target lies straight ahead
## of the held block"): the same away-vector convention set_home_view() uses
## (home/block on one side, look-at target on the other) with the held
## block's own followed position standing in for "home" -- so the camera ends
## up positioned on the block's own far side from `target`, looking through
## the block toward it. Tweens through the shortest angular path (wrapf) so a
## turn never spins the long way around past +/-180 degrees.
func _turn_to_face(target: Vector3) -> void:
	var away: Vector2 = Vector2(_follow_position.x - target.x, _follow_position.z - target.z)
	if away.length() <= 0.0001:
		return
	var new_yaw: float = atan2(away.x, away.y)
	var target_yaw: float = _yaw + wrapf(new_yaw - _yaw, -PI, PI)
	var tween: Tween = create_tween()
	_track_view_tween(tween)
	tween.tween_property(self, ^"_yaw", target_yaw, tuning.focus_turn_duration_s)


## Focus home's real target: the
## local/acting slot's own home beacon, resolved from the live Field's
## Field.home_flags() (see set_local_slot()'s own doc comment for how this
## rig learns the slot). Falls back to the disk center -- gracefully, not an
## error -- when there's no Field yet, no local slot known, or that slot's
## flag can't be found (e.g. an eliminated slot's flag node was never
## actually freed by Field._clear_flags(), only rebuilt on the next match, so
## this should only miss between matches).
func _resolve_home_target() -> Vector3:
	var field: Field = Match.field()
	if field == null:
		return Vector3.ZERO
	for flag: HomeFlag in field.home_flags():
		if is_instance_valid(flag) and flag.slot_id() == _local_slot:
			return flag.global_position
	return Vector3.ZERO


## Focus goal's real target: the live Field's Field.goal_flags(), cycling to
## the next one on every fresh press ("each new goal press/
## tap cycles to the next goal") -- called exactly once per press by
## _on_focus_pressed() above, never per frame, so holding through a PEEK
## doesn't itself keep advancing the cycle. Falls back to the disk center
## when there's no Field yet or no goals at all.
func _resolve_goal_target() -> Vector3:
	var field: Field = Match.field()
	if field == null:
		return Vector3.ZERO
	var flags: Array[GoalFlag] = field.goal_flags()
	if flags.is_empty():
		return Vector3.ZERO
	_goal_cycle_index = _goal_cycle_index % flags.size()
	var target: Vector3 = flags[_goal_cycle_index].global_position
	_goal_cycle_index = (_goal_cycle_index + 1) % flags.size()
	return target


## The camera shakes only for gift specials that shake the disc or risk toppling
## towers (DiscShakeConfig). Rides the replicated special_triggered, so every peer
## shakes. Block landings, volcano spew and other cosmetic events do not shake it.
func _on_special_triggered(_net_id: int, def_id: StringName, position: Vector3, _chain_depth: int) -> void:
	if not Settings.camera_shake_enabled():
		return
	if disc_shake.impulse_special_ids.has(def_id) and _near_disc(position):
		_start_shake(shake_config.max_offset_m)


## True within max_distance_field_factor field radii of the disc centre; with
## no field (isolated tests) every position counts as near.
func _near_disc(position: Vector3) -> bool:
	var field: Field = Match.field()
	if field == null or field.map_def == null:
		return true
	var offset: Vector3 = position - field.global_position
	offset.y = 0.0
	return offset.length() <= field.map_def.field_radius * disc_shake.max_distance_field_factor


## Keeps the shake alive while the disc tilts faster than the threshold
## (earthquake): re-arms the decay without restarting the oscillation phase.
func _sample_disc_motion(delta: float) -> void:
	var field: Field = Match.field()
	if field == null or delta <= 0.0 or not Settings.camera_shake_enabled():
		_has_prev_disc_tilt = false
		return
	var tilt: Vector2 = field.tilt_vector()
	if not _has_prev_disc_tilt or field != _sampled_field:
		_prev_disc_tilt = tilt
		_has_prev_disc_tilt = true
		_sampled_field = field
		_disc_sample_elapsed_s = 0.0
		return
	# The tilt only changes once per physics tick, so measure over a window of
	# at least one tick: frame-rate independent (no 2-4x spikes at 144/240 fps).
	_disc_sample_elapsed_s += delta
	var window_s: float = 1.0 / float(Engine.physics_ticks_per_second)
	if _disc_sample_elapsed_s < window_s - 0.0001:
		return
	var rate: float = (tilt - _prev_disc_tilt).length() / _disc_sample_elapsed_s
	_prev_disc_tilt = tilt
	_disc_sample_elapsed_s = 0.0
	if rate < disc_shake.disc_tilt_rate_threshold:
		return
	var amplitude: float = shake_config.max_offset_m * disc_shake.disc_tilt_amplitude_fraction
	if _shake_amplitude_m <= 0.0:
		_shake_elapsed_s = 0.0
	if amplitude >= _current_shake_amplitude():
		_shake_amplitude_m = amplitude
		_decay_elapsed_s = 0.0


func _start_shake(amplitude: float) -> void:
	if amplitude >= _current_shake_amplitude():
		_shake_amplitude_m = amplitude
		_shake_elapsed_s = 0.0
		_decay_elapsed_s = 0.0


func _current_shake_amplitude() -> float:
	if _shake_amplitude_m <= 0.0:
		return 0.0
	var decay: float = 1.0
	if shake_config.decay_seconds > 0.0:
		decay = exp(-_decay_elapsed_s / shake_config.decay_seconds)
	return _shake_amplitude_m * decay


func _update_shake(delta: float) -> void:
	_sample_disc_motion(delta)
	if _shake_amplitude_m <= 0.0:
		return
	_shake_elapsed_s += delta
	_decay_elapsed_s += delta
	if _current_shake_amplitude() <= 0.0001:
		_shake_amplitude_m = 0.0
		_shake_elapsed_s = 0.0
		_decay_elapsed_s = 0.0


func _update_transform() -> void:
	var offset: Vector3 = Vector3(
		sin(_yaw) * cos(_pitch),
		-sin(_pitch),
		cos(_yaw) * cos(_pitch)
	) * _distance
	global_position = _target
	_camera.position = offset + shake_offset()
	_camera.look_at(_target, Vector3.UP)
