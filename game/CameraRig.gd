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

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	add_to_group(TUNING_GROUP)
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
## ghost's world position (Bontago-mv0.28: its rotated geometric centre, not
## its node origin, so a pitch/roll spins the block in place instead of
## dragging the camera's framing). Only used while tuning.follow_block is
## true; the legacy free-orbit camera ignores it.
func set_follow_position(pos: Vector3) -> void:
	_follow_position = pos


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
