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
##
## Bontago-mv0.29 (owner: "the mmb rotation issue persists, can the camera
## just be locked in place while mmb is pressed?" -- feedback/rotation-issue.png):
## mv0.28 made the follow target track the held ghost's rotated geometric
## centre instead of its node origin, but any shape whose mass isn't
## symmetric about its own rotation axis still slides that centre while
## rotate_drag (MMB) spins it, so the camera still visibly moved. This rig
## now freezes completely -- target, yaw, pitch and distance -- for as long
## as rotate_drag is held (see _rotate_drag_frozen()), and resumes following
## on release through the same follow_lag lerp/snap _process() already runs
## every other frame.

@export var tuning: CameraTuning = preload("res://config/camera_tuning.tres")
@export var map_def: MapDef = preload("res://config/maps/round_medium.tres")

## Bontago-xtq.29 (M7 P4, spec 2.10 "camera shake"): tunables for the decaying
## offset _update_transform() adds on top of the normal orbit position
## whenever Events.block_impacted fires hard enough. See shake_offset().
@export var shake_config: CameraShakeConfig = preload("res://config/camera_shake.tres")

## Bontago-mv0.20b (F4 tuning panel live-apply): every CameraRig adds itself
## to this group in _ready(), the same idea as game/Block.gd's TUNING_GROUP,
## so ui/TuningPanel.gd can push a live camera_tuning edit onto whichever rig
## is actually in the tree (get_tree().get_nodes_in_group(TUNING_GROUP))
## without needing its own set_camera_rig() wiring to have run first.
const TUNING_GROUP: StringName = &"tuning_camera"

## Bontago-mv0.26 (owner test 2026-09-22: "the ghost block is a bit jittery
## when I'm moving around and especially when scrolling and it moves up and
## down"). ROOT CAUSE: this rig is a static child of game/Main.tscn (created
## before HotSeat/Sandbox, whose PlayerController is add_child()'d afterward
## at runtime), and Godot calls _process() in ascending process_priority order
## with tree position only as the tie-break for equal priority (both default
## to 0 here) -- so this rig's _process() ran BEFORE PlayerController's every
## single frame, in every mode (hot-seat, sandbox, networked host and client;
## same HotSeat.tscn/Main.gd structure in each). set_follow_position() below
## is only ever called from PlayerController._process(), after it has already
## moved the ghost for this frame -- so this rig's own _process() was reading
## last frame's ghost position, one whole render frame stale, then never
## catching up until the *next* frame reads the value PlayerController is
## about to write this one. Under constant mouse motion at a variable
## renderer frame rate that stale gap itself varies frame to frame, which
## reads as jitter rather than a fixed lag; it is worst on the wheel
## (_step_hover's one-shot manual_hover_offset jump lands on the ghost
## immediately but the camera doesn't see it for a full frame), matching
## "especially when scrolling and it moves up and down" exactly.
## DECISION (game/CameraRig.gd): not a gameplay tunable (CLAUDE.md's
## Resource/no-magic-numbers rule is about tunables a designer retunes; this
## is a fixed processing-order fact, the same category as e.g. GhostPreview's
## _CORNER_SIGNS table), so it stays a local const rather than moving into
## CameraTuning. Any positive value works -- it only needs to be greater than
## every other default-priority (0) node's, chiefly PlayerController's -- so
## this rig's _target always reflects the *same* frame's ghost position,
## regardless of where either node sits in the tree.
const _PROCESS_PRIORITY_AFTER_GHOST: int = 1

## Bontago-pt-4: how close (meters) _target must get to _follow_position
## before begin_follow_transition()'s easing is considered finished (see
## _process()'s own use of this below). Not a gameplay tunable in the
## CameraTuning sense -- CLAUDE.md's Resource/no-magic-numbers rule is about
## values a designer would retune for feel; this is only "close enough to be
## imperceptible", the same category as this file's own shake_offset()
## epsilon (0.0001) and _current_shake_amplitude()'s, just sized in meters
## rather than a unit amplitude fraction.
const _DROP_RECOVER_CONVERGED_M: float = 0.001

## Bontago-b7r (owner decision 2026-09-28, Bontago-aem): game/Sandbox.gd's own
## sandbox_next_slot hotkey is gamepad Back, which camera_snap_home also binds.
## DECISION (game/CameraRig.gd, orchestrator review): game/Sandbox.gd sets this
## true so a *gamepad* Back press there stays next-slot only; keyboard 1/2 and
## gamepad X (focus goal) keep working in the sandbox, where the owner tests
## most. Sandbox's Back+X comparison chord is already excluded by
## _goal_focus_chord_blocked() (Back is camera_snap_home).
@export var suppress_pad_home_focus: bool = false

## Set by PlayerController each frame: true while the player holds a ghost
## block. Spec 2.5 scopes trigger zoom to "while not holding a block"; the
## dedicated Z/X keys always zoom regardless (see _unhandled_input).
var block_held: bool = false

var _yaw: float = 0.0
var _pitch: float = 0.0
var _distance: float = 0.0
var _target: Vector3 = Vector3.ZERO
## Where PlayerController says the held ghost's own rotated centre is
## (Bontago-mv0.28: GhostPreview.rotated_center_world(), not its node
## origin -- see that method's doc comment), updated by set_follow_position()
## every frame. Only read when tuning.follow_block.
var _follow_position: Vector3 = Vector3.ZERO

## Bontago-pt-4 (owner playtest: "Camera always jumps up after block drops or
## when clicking the drop button"): true for as long as _process() is easing
## _target into _follow_position over tuning.drop_recover_seconds instead of
## hard-snapping to it -- see begin_follow_transition()'s own doc comment for
## why, and _process()'s follow_block branch for how it clears itself once
## _target has actually caught up (rather than on a fixed timer, so it never
## flips back to hard-snap mode with a residual gap still showing).
var _drop_recovering: bool = false

## Bontago-xtq.29 (camera shake): the amplitude (meters) of the shake impulse
## currently decaying, and how long it has been decaying for. A fresh, harder
## Events.block_impacted while one is still decaying replaces the amplitude
## outright rather than stacking (spec 2.10 asks for a shake reaction per
## impact, not compounding shakes from a rapid string of small settling
## impacts) and restarts the decay clock, so the strongest recent hit always
## governs.
var _shake_amplitude_m: float = 0.0
var _shake_elapsed_s: float = 0.0

## Bontago-b7r: which slot's home beacon Focus home should target -- pushed
## every frame by game/PlayerController.gd's own _acting_slot() (the same
## "local/acting slot" HotSeat/Sandbox already resolve for it), never read
## from here. -1 (the default) means "no local slot known yet"; _resolve_
## home_target() below falls back to the disk center in that case, same as
## an eliminated or missing flag.
var _local_slot: int = -1

## Bontago-b7r: camera_snap_home/camera_snap_goal's tap-vs-hold state, tracked
## only while tuning.follow_block (the legacy free camera keeps its old
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
## game/PlayerController.gd reads this through is_peeking() to suppress
## ghost-cursor movement and placement while it's true (owner decision:
## "the ghost/cursor never moves during peek").
var _peek_active: bool = false
## True while _process() is gliding _target/_distance/_pitch back to the
## normal follow framing after a PEEK release, until it converges (the same
## _DROP_RECOVER_CONVERGED_M-gated pattern _drop_recovering already uses).
var _peek_returning: bool = false
## Bontago-b7r ("each new goal press/tap cycles to the next goal"): advanced
## once per fresh camera_snap_goal press by _resolve_goal_target() below, not
## every frame -- so holding through a PEEK doesn't itself keep cycling.
var _goal_cycle_index: int = 0

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	add_to_group(TUNING_GROUP)
	Events.block_impacted.connect(_on_block_impacted)
	process_priority = _PROCESS_PRIORITY_AFTER_GHOST
	# Bontago-1bt (owner log: "Interpolated Camera3D triggered from outside
	# physics process" -- the same warning game/DiscMirror.gd's own class doc
	# already root-caused and fixed for its mirror camera, xtq.21): this rig's
	# own global_position (_update_transform() below sets it every frame via
	# `global_position = _target`) and its Camera3D child's position/rotation
	# (_camera.look_at()) are both fully re-derived every rendered _process()
	# frame from mouse/gamepad input, never from _physics_process -- so with
	# project.godot's physics/common/physics_interpolation on, the
	# RenderingServer's physics-tick smoothing only ever adds lag on top of a
	# pose that is already correct for this frame, and logs this same warning
	# for both nodes. OFF makes both always show their latest logical
	# transform with no server-side smoothing between physics ticks.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera.fov = tuning.fov_deg
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
		apply_follow_tuning()
	else:
		_distance = clampf(map_def.field_radius * 1.4, tuning.zoom_min, tuning.zoom_max)
		_pitch = deg_to_rad(tuning.snap_pitch_deg)
		_update_transform()


func _unhandled_input(event: InputEvent) -> void:
	if _rotate_drag_frozen():
		# Bontago-mv0.29: freeze consumes every camera input this rig would
		# otherwise react to (orbit motion, pan motion, zoom keys, snap
		# actions) while rotate_drag is held -- see this method's own
		# doc comment on _rotate_drag_frozen() for why. PlayerController has
		# its own separate _unhandled_input() and still receives this same
		# event undisturbed (Godot dispatches _unhandled_input to every
		# listening node, not just the first), so the ghost keeps rotating.
		return
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		if Input.is_action_pressed(&"camera_mode") or Input.is_action_pressed(&"camera_orbit"):
			# Bontago-mv0.22 (spec 2.5 "Camera orbit (hold + drag)" [ORIGINAL,
			# owner test 2026-09-22]): camera_orbit (RMB) is now the primary
			# hold; camera_mode (C) stays wired as the keyboard alias for the
			# exact same gesture.
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

	# Owner controller update (feedback/controller-update.md, re-confirmed
	# 2026-09-28): camera_zoom_in/out are keyboard-only now (Z/X) -- the
	# gamepad triggers no longer fire them at all (tools/bootstrap_project.gd),
	# so both always zoom regardless of block_held; the old "trigger zoom only
	# while free" scoping is moot now that no trigger binds these actions.
	# The gamepad's own zoom gesture (LT + left stick, continuous) is
	# PlayerController._drive_gamepad_zoom() -> zoom_continuous() below, driven
	# every frame rather than through this event handler.
	# Bontago-mv0.14: the wheel used to double as zoom too; it is now block
	# height only (ghost_tuning's hover_raise/hover_lower), so it is out of
	# this action entirely (see tools/bootstrap_project.gd).
	if event.is_action_pressed(&"camera_zoom_in"):
		_zoom(-1.0)
	elif event.is_action_pressed(&"camera_zoom_out"):
		_zoom(1.0)
	elif event.is_action_pressed(&"camera_snap_home"):
		# Bontago-b7r: camera_snap_goal no longer shares B with rotate_snap
		# (tools/bootstrap_project.gd), so camera_snap_home's own press/release
		# needs no block_held gate either -- see _on_focus_pressed()'s own
		# DECISION for the one gate that IS still needed (goal's shared X).
		if not (suppress_pad_home_focus and event is InputEventJoypadButton):
			_on_focus_pressed(&"camera_snap_home")
	elif event.is_action_released(&"camera_snap_home") and _focus_action == &"camera_snap_home":
		_on_focus_released()
	elif event.is_action_pressed(&"camera_snap_goal"):
		_on_focus_pressed(&"camera_snap_goal")
	elif event.is_action_released(&"camera_snap_goal") and _focus_action == &"camera_snap_goal":
		_on_focus_released()


func _process(delta: float) -> void:
	if _rotate_drag_frozen():
		# Bontago-mv0.29 (owner: "the mmb rotation issue persists, can the
		# camera just be locked in place while mmb is pressed?"): returning
		# here before touching _target/_yaw/_pitch/_distance or calling
		# _update_transform() leaves global_transform bit-for-bit whatever it
		# was last frame, regardless of what PlayerController's own
		# set_follow_position() reports this frame (the ghost's rotated
		# centre moves during a drag whenever the held shape isn't symmetric
		# about its rotation axis -- mv0.28 alone did not stop that) or what
		# the height wheel/gamepad stick/right-stick orbit did. Releasing
		# rotate_drag needs no special "resume" code: the very next
		# non-frozen _process() lerps _target toward whatever
		# _follow_position has meanwhile become, at the normal
		# follow_lag_seconds rate (an instant snap when that tuning is 0, the
		# shipped default) -- exactly the same path every other frame already
		# takes.
		return
	# The gamepad's right stick always free-orbits (spec 2.5's camera row has
	# no gamepad hold requirement; see test_project_setup.gd's DEVICE_EXCEPTIONS
	# for camera_mode). Bontago-mv0.14 removed the previous rotate_free_hold
	# conflict here: that action is now rotation_mode, which reuses the *left*
	# stick (PlayerController._accumulate_rotation_drag), so the right stick no
	# longer has a second job to gate against.
	# M4 P2e (docs/M4_P2_PACKAGES.md P2e): throw_aim shares its gamepad binding
	# (the left trigger) with nothing on the right stick, but the right stick
	# is also the player's own aim-drag gesture while throw_aim is held
	# (game/PlayerController.gd._accumulate_gamepad_throw_drag()) -- reading
	# it here too would spin the camera under the player mid-aim. Suppressed
	# outright rather than consumed/shared, same as _rotate_drag_frozen()
	# above freezes the whole rig for a different hold.
	var look_x: float = 0.0
	var look_y: float = 0.0
	if not Input.is_action_pressed(&"throw_aim"):
		look_x = Input.get_action_strength(&"camera_look_right") - Input.get_action_strength(&"camera_look_left")
		look_y = Input.get_action_strength(&"camera_look_down") - Input.get_action_strength(&"camera_look_up")
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
		# Bontago-pt-4: while _drop_recovering (see begin_follow_transition()),
		# use tuning.drop_recover_seconds as the approach's time constant
		# instead of follow_lag_seconds, even when the latter is 0 -- the one
		# discontinuous re-target this eases into must not hard-snap just
		# because ordinary movement is tuned to.
		# Bontago-b7r: PEEK and its own return glide own _target/_distance/
		# _pitch outright while either is active -- the ordinary follow lerp
		# below (and _drop_recovering, a discontinuous re-target of the same
		# kind PEEK's own return glide already handles) must not fight them
		# for the same three fields. _update_focus_hold() only ever starts a
		# PEEK while tuning.follow_block, so this branch is the only place
		# that needs to know about it.
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
				# Bontago-pt-4: clears itself the moment _target has actually
				# caught up, rather than on a fixed timer -- so flipping back to
				# hard-snap mode (follow_lag_seconds, usually 0) never leaves a
				# visible residual gap to snap across.
				_drop_recovering = false
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

	_update_shake(delta)
	_update_transform()


## Bontago-mv0.14: called by PlayerController every frame with the held
## ghost's world position (Bontago-mv0.28: its rotated geometric centre, not
## its node origin, so a pitch/roll spins the block in place instead of
## dragging the camera's framing). Only used while tuning.follow_block is
## true; the legacy free-orbit camera ignores it.
func set_follow_position(pos: Vector3) -> void:
	_follow_position = pos


## Bontago-pt-4 (owner playtest: "Camera always jumps up after block drops or
## when clicking the drop button"). ROOT CAUSE: this rig's follow-block mode
## hard-snaps _target to whatever set_follow_position() reports every frame
## whenever tuning.follow_lag_seconds is 0 (the shipped default since mv0.21,
## "matches the original's feel best" for ordinary, small, continuous
## per-frame ghost motion). game/PlayerController.gd's own
## _apply_spawn_clearance() (Bontago-mv0.30/mv0.33) raises the newly issued
## ghost's manual_hover_offset -- and so its followed rotated_center_world()
## height -- in one single frame, the instant the next piece would otherwise
## spawn inside the block just placed: the ordinary case of building on your
## own stack. That is a genuinely discontinuous re-target, not the ghost
## sliding under the cursor, but this rig's _process() had no way to tell the
## two apart -- both are just "a new set_follow_position() value" -- so it
## hard-snapped to that new height exactly like any other frame, which is the
## reported jump.
##
## game/PlayerController.gd calls this once, at the exact call site that
## produces that discontinuous re-target (_apply_spawn_clearance(), right
## where it raises manual_hover_offset), so this rig eases its next several
## set_follow_position() updates toward the ghost over tuning.
## drop_recover_seconds instead of snapping (_process()'s own follow_block
## branch) -- without touching follow_lag_seconds or softening the
## always-continuous cursor-driven motion the owner already tuned to feel
## instant.
func begin_follow_transition() -> void:
	_drop_recovering = true


## Bontago-mv0.17 item 4 (owner feel report: match start should look from the
## player's home flag toward the disk centre, not the generic yaw = 0
## default): called once by PlayerController.set_home_position() when a
## controller binds to a real slot. Points this rig's yaw so its offset (see
## _update_transform()) sits on the `home_position` side of `look_at_position`
## -- i.e. the camera looks *toward* the centre from behind the block, the
## same framing docs/original_in-game.png shows -- and seeds both _target and
## _follow_position at the home flag so there is no one-frame jump back to
## wherever the target used to sit before PlayerController's own
## set_follow_position() call this same frame takes over.
func set_home_view(home_position: Vector3, look_at_position: Vector3 = Vector3.ZERO) -> void:
	var away: Vector2 = Vector2(home_position.x - look_at_position.x, home_position.z - look_at_position.z)
	if away.length() > 0.0001:
		_yaw = atan2(away.x, away.y)
	_target = home_position
	_follow_position = home_position
	_update_transform()


## Bontago-mp0.27: match-start entry point. Puts the camera at `slot_id`'s own
## home beacon looking at the disc centre (set_home_view's framing). Returns
## false, leaving the camera alone, when that slot has no beacon in the Field.
func place_at_home_beacon(slot_id: int) -> bool:
	_local_slot = slot_id
	var home: Vector3 = _resolve_home_target()
	if home == Vector3.ZERO:
		return false
	set_home_view(home, Vector3.ZERO)
	return true


## Bontago-b7r: pushed every frame by game/PlayerController.gd's own
## _acting_slot() (the same "local/acting slot" HotSeat.bind_local_slot()/
## Sandbox's own active-slot cycling already resolve) so Focus home can find
## the right beacon among Field.home_flags() without this rig needing its own
## copy of that resolution logic. -1 is the "not known yet" default;
## _resolve_home_target() below treats that the same as a missing flag.
func set_local_slot(slot_id: int) -> void:
	_local_slot = slot_id


## True only while PEEK is actively holding the camera on a focus target (past
## tuning.focus_hold_threshold_s, camera_snap_home/goal still held) -- not
## during the brief return glide after release. game/PlayerController.gd
## reads this every frame to suppress ghost-cursor movement and placement
## (owner decision 2026-09-28, Bontago-aem: "the ghost/cursor never moves
## during peek").
func is_peeking() -> bool:
	return _peek_active


## Bontago-mv0.20b (F4 tuning panel live-apply): re-snapshots _distance/_pitch
## from tuning.follow_distance/follow_pitch_deg, clamped exactly as _ready()
## does. Called once by _ready() and again by ui/TuningPanel.gd's
## apply_camera_tuning_live() whenever camera_tuning changes on the F4 panel
## -- never every frame, so a manual orbit/zoom the player already did (see
## _unhandled_input()/_process() above) is only overwritten by an explicit
## tuning push, not silently fought every tick. A no-op while
## tuning.follow_block is false: the free-orbit camera has its own fixed
## target/distance and these two fields mean nothing to it.
func apply_follow_tuning() -> void:
	# DECISION (game/CameraRig.gd): fov_deg applies here unconditionally (unlike
	# distance/pitch below) because it isn't a follow-only concept -- the panel
	# calls this hook for any camera_tuning edit, and the free-orbit camera
	# should get a live fov change too.
	_camera.fov = tuning.fov_deg
	if not tuning.follow_block:
		return
	_distance = clampf(tuning.follow_distance, tuning.zoom_min, tuning.zoom_max)
	_pitch = deg_to_rad(tuning.follow_pitch_deg)
	_update_transform()


## Used by PlayerController to scale gamepad ghost-cursor speed with zoom
## (spec 2.5: "speed scales with camera zoom").
func get_distance() -> float:
	return _distance


## Used by PlayerController to move the ghost cursor relative to the
## camera's current facing (both mouse and gamepad -- Bontago-mv0.14).
func get_yaw() -> float:
	return _yaw


## Test/inspection seam (Bontago-mv0.20b): the rig's current pitch, in
## radians, the same units get_yaw() already uses.
func get_pitch() -> float:
	return _pitch


func get_camera() -> Camera3D:
	return _camera


## For tests: where the rig's pivot currently sits (its "look at" point).
func get_target() -> Vector3:
	return _target


## Bontago-xtq.29 (M7 P4, spec 2.10 "camera shake"): the current shake offset
## _update_transform() adds to the camera's local position, in meters -- zero
## when no impact has happened yet, when the last shake has fully decayed, or
## when Settings.camera_shake_enabled() is false. Exposed as its own getter
## (rather than only being visible through get_camera().position) so
## tests/unit/test_camera_shake.gd can assert on it directly without also
## depending on the rig's current orbit distance/yaw/pitch.
func shake_offset() -> Vector3:
	if not Settings.camera_shake_enabled():
		return Vector3.ZERO
	var current_amplitude: float = _current_shake_amplitude()
	if current_amplitude <= 0.0001:
		return Vector3.ZERO
	# DECISION (game/CameraRig.gd): a fixed, arbitrary-looking but
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


## Bontago-mv0.29 (owner: "the mmb rotation issue persists, can the camera
## just be locked in place while mmb is pressed?"): true for exactly as long
## as rotate_drag is held, on whichever device -- Input.is_action_pressed()
## already reads every binding the Input Map has for the action (mouse and
## gamepad alike; tools/bootstrap_project.gd), so a pad binding added there
## later needs no change here. Read by _process(), _unhandled_input() and
## zoom_by_orbit_step() (the one mutator PlayerController can reach directly,
## bypassing this rig's own _unhandled_input) so the freeze is total: no
## target/yaw/pitch/distance mutation anywhere while true.
## DECISION (game/CameraRig.gd): camera_orbit (RMB) is bound to a different
## action than rotate_drag (MMB), so both can physically be held at once.
## The simplest consistent rule is that rotate_drag always wins outright --
## _unhandled_input()'s early return above fires before it ever checks
## camera_orbit/camera_mode, so starting or continuing an RMB-orbit drag
## while MMB is already down does nothing until MMB is released, and holding
## RMB first and then also pressing MMB freezes the rig mid-orbit exactly
## like any other frozen frame. This matches the plain-language brief ("the
## camera just be locked in place while mmb is pressed") without a second
## precedence rule to test and explain.
func _rotate_drag_frozen() -> bool:
	return Input.is_action_pressed(&"rotate_drag")


func _zoom(direction: float) -> void:
	_distance = clampf(_distance + direction * tuning.zoom_step, tuning.zoom_min, tuning.zoom_max)


## Bontago-mv0.22 (spec 2.5 "mouse wheel zooms while held" [ORIGINAL, owner
## test 2026-09-22]): called by PlayerController when the wheel fires while
## camera_mode/camera_orbit is held, using its own tunable (orbit_zoom_step)
## instead of zoom_step, which the dedicated Z/X zoom keys and gamepad
## triggers already use via _zoom() -- letting the held-orbit wheel feel be
## tuned independently.
func zoom_by_orbit_step(direction: float) -> void:
	if _rotate_drag_frozen():
		# Bontago-mv0.29: PlayerController calls this directly (not through
		# this rig's own _unhandled_input, which already guards itself above)
		# whenever camera_orbit/camera_mode is held and the wheel fires; if
		# the player also holds rotate_drag at the same time, freeze wins --
		# see the DECISION on _rotate_drag_frozen().
		return
	_distance = clampf(_distance + direction * tuning.orbit_zoom_step, tuning.zoom_min, tuning.zoom_max)


## Owner controller update (feedback/controller-update.md, re-confirmed
## 2026-09-28: "LT held + left stick up/down = zoom camera in/out,
## continuous"): called every frame by PlayerController._drive_gamepad_zoom()
## while camera_zoom_modifier (LT) is held and not aiming a throw, with
## `amount` already scaled by tuning.gamepad_trigger_zoom_speed and the
## frame's delta -- unlike zoom_by_orbit_step's fixed per-notch step, this is
## a continuous analog rate that tracks how far the stick is pushed. Frozen
## exactly like zoom_by_orbit_step while rotate_drag is held, for the same
## reason (see _rotate_drag_frozen()'s own doc comment).
func zoom_continuous(amount: float) -> void:
	if _rotate_drag_frozen():
		return
	_distance = clampf(_distance + amount, tuning.zoom_min, tuning.zoom_max)


func _pan_offset(input_2d: Vector2) -> Vector3:
	var forward: Vector3 = Vector3(sin(_yaw), 0.0, cos(_yaw))
	var right: Vector3 = Vector3(forward.z, 0.0, -forward.x)
	return right * input_2d.x + forward * input_2d.y


func _snap_to(point: Vector3) -> void:
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, ^"_target", point, tuning.snap_duration)
	tween.tween_property(self, ^"_distance", tuning.snap_distance, tuning.snap_duration)
	tween.tween_property(self, ^"_pitch", deg_to_rad(tuning.snap_pitch_deg), tuning.snap_duration)


# --- Bontago-b7r (owner decision 2026-09-28, Bontago-aem): Focus home/goal's
# tap-to-TURN / hold-to-PEEK gesture --------------------------------------

## Handles a fresh camera_snap_home/camera_snap_goal press: resolves the real
## target once (so a goal cycle advances exactly once per press, not once per
## frame it's held -- see _resolve_goal_target()'s own doc comment), then
## either fires the legacy camera's single instant _snap_to() (follow_block
## false) or starts this press's tap/hold tracking for _update_focus_hold()
## to pick up next frame.
func _on_focus_pressed(action: StringName) -> void:
	# DECISION (game/CameraRig.gd): camera_snap_goal's gamepad half (X,
	# tools/bootstrap_project.gd) doubles as ui/TuningPanel.gd's Start+X
	# tuning_panel_toggle chord and, in game/Sandbox.gd, sandbox_physics_
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


## Bontago-b7r: advances _focus_hold_elapsed_s while camera_snap_home/goal is
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
	_distance = lerpf(_distance, clampf(distance_val, tuning.zoom_min, tuning.zoom_max), weight)
	_pitch = lerpf(_pitch, deg_to_rad(pitch_deg), weight)


## TURN (owner decision: "tween camera yaw so the target lies straight ahead
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
	tween.tween_property(self, ^"_yaw", target_yaw, tuning.focus_turn_duration_s)


## Focus home's real target (owner decision 2026-09-28, Bontago-aem): the
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
## the next one on every fresh press (owner decision: "each new goal press/
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


## Bontago-xtq.29 (camera shake): Events.block_impacted carries only the
## scalar deceleration magnitude (Block.gd's own emit site never passes the
## block or its position -- confirmed by reading Block.gd directly), so this
## can only start an undirected shake impulse, never one aimed at the impact
## site. Below shake_config.impact_speed_threshold, the hit is too soft to
## react to at all.
func _on_block_impacted(speed: float) -> void:
	if not Settings.camera_shake_enabled():
		return
	if speed < shake_config.impact_speed_threshold:
		return
	var over_threshold: float = speed - shake_config.impact_speed_threshold
	var amplitude: float = clampf(over_threshold / maxf(shake_config.impact_speed_threshold, 0.0001), 0.0, 1.0) * shake_config.max_offset_m
	if amplitude >= _current_shake_amplitude():
		_shake_amplitude_m = amplitude
		_shake_elapsed_s = 0.0


func _current_shake_amplitude() -> float:
	if _shake_amplitude_m <= 0.0:
		return 0.0
	var decay: float = 1.0
	if shake_config.decay_seconds > 0.0:
		decay = exp(-_shake_elapsed_s / shake_config.decay_seconds)
	return _shake_amplitude_m * decay


func _update_shake(delta: float) -> void:
	if _shake_amplitude_m <= 0.0:
		return
	_shake_elapsed_s += delta
	if _current_shake_amplitude() <= 0.0001:
		_shake_amplitude_m = 0.0
		_shake_elapsed_s = 0.0


func _update_transform() -> void:
	var offset: Vector3 = Vector3(
		sin(_yaw) * cos(_pitch),
		-sin(_pitch),
		cos(_yaw) * cos(_pitch)
	) * _distance
	global_position = _target
	_camera.position = offset + shake_offset()
	_camera.look_at(_target, Vector3.UP)
