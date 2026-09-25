extends SceneTree
## Writes the project settings and Input Map that the spec requires, then saves
## project.godot.
##
## Keeping this in source instead of clicking through the editor means the
## settings that gameplay depends on (spec 3.1 stack, 3.5 physics tuning, 2.5
## controls) are reviewable in a diff. Re-runnable and idempotent.
##
## Run:  godot --headless --path . -s tools/bootstrap_project.gd
##
## DECISION: tools/ is not in the spec 3.2 layout. It holds build-time scripts
## that are not part of the running game, so it sits outside the gameplay
## folders rather than being squeezed into core/ or game/.

## Stick actions want a small dead zone (spec 2.5, gamepad ghost movement).
const STICK_DEADZONE: float = 0.15
## Triggers rest at 0.0 and are also read as analog values, so they only need
## enough dead zone to avoid a twitchy digital "pressed".
const TRIGGER_DEADZONE: float = 0.3
const BUTTON_DEADZONE: float = 0.5


func _init() -> void:
	_apply_settings()
	_apply_input_map()
	_apply_autoloads()
	var err: Error = ProjectSettings.save()
	if err != OK:
		push_error("Could not save project.godot: %s" % error_string(err))
		quit(1)
		return
	print("bootstrap_project: wrote project settings and %d input actions." % _actions().size())
	quit(0)


func _apply_settings() -> void:
	var settings: Dictionary = {
		# Spec 3.1 - stack.
		"application/config/features": PackedStringArray(["4.4", "Forward Plus"]),
		"rendering/renderer/rendering_method": "forward_plus",
		"physics/3d/physics_engine": "Jolt Physics",

		# Spec 3.5 - physics tuning.
		"physics/common/physics_ticks_per_second": 60,
		"physics/common/physics_interpolation": true,
		# Jolt solver iterations. Spec 3.5: "Start at 10 and 4, and tune using
		# a benchmark scene with a 40-block tower." The position count is
		# still the spec's 4; the velocity count had to go much higher, and
		# the reason is worth writing down because the number looks absurd.
		#
		# Jolt's velocity solver is iterative (Gauss-Seidel): each iteration
		# propagates a contact impulse across roughly one contact. A column
		# of N cubes is a chain of N contacts, and the bottom one carries N
		# times the load of the top one, so the support force needs several
		# full sweeps of the chain before it is distributed correctly.
		# Measured on tests/bench/bench_tower.tscn, the iteration count a
		# single-file column needs is about 4-5x its height:
		#
		#   height 15 -> converges at ~48    height 40 -> converges at ~192
		#
		# Below that the solver leaves a residual velocity in every block.
		# The stack then never gets under Jolt's sleep velocity threshold, it
		# rings indefinitely, and above ~15 blocks the residual feeds a lean
		# that grows at sqrt(3g/2L) - the free inverted-pendulum rate - until
		# the tower topples. Raising the iteration count removes the residual
		# at the source: at 192 a 40-cube tower sags 12 mm on spawn and is
		# asleep at 0.52 s (the earliest Jolt's 0.5 s sleep timer allows),
		# with zero per-block damping. Earlier M1 revisions hid this behind
		# linear damping of 4.0, which only slowed the topple enough for the
		# tower to fall asleep first - and made blocks drift down like
		# feathers. See config/PhysicsTuning.gd and test_project_setup.gd.
		#
		# Cost, measured on bench_rain (300 blocks all colliding at once, the
		# worst case this project has): ~2.8 ms per physics step at the old
		# 20/10, ~5.0 ms at 192/4, against spec 3.5's 8.33 ms budget for
		# 120 fps. So it still passes, with the headroom cut from ~3x to
		# ~1.6x. That is the real price of this setting and it is worth
		# re-checking whenever bench_rain is touched. Settled towers sleep and
		# cost nothing, and spec 3.5's stable-block freeze (blocks asleep for
		# 20 s become freeze_mode = STATIC) will take more out of the solver
		# again once it lands.
		#
		# DECISION: position_steps stays at the spec's starting 4. Raising it
		# to 80 changed this benchmark's output by literally nothing (the
		# stack never penetrates past penetration_slop, so the position
		# solver has no work to do), so there is no evidence for spending
		# more there.
		"physics/jolt_physics_3d/simulation/velocity_steps": 192,
		"physics/jolt_physics_3d/simulation/position_steps": 4,
		# DECISION (Bontago-ddz, 2026-09-22): Jolt's body-pair contact cache
		# reuses the previous frame's contacts while a touching pair has moved
		# less than this distance (default 0.001 m) and turned less than ~2
		# degrees. Every joint in a tall block column creeps far less than
		# 1 mm per step, so the column keeps solving against stale contacts
		# and never settles; whether it eventually leans over or sleeps then
		# depends on body creation order (adding unrelated far-away static
		# bodies flipped the 40-block tower between drift 0.02 m / asleep at
		# 0.52 s and a collapse at ~23 s). At 0.0001 m the tower is 8/8 clean
		# on the trimesh disk, the old per-cell boxes and a plain cylinder, at
		# offsets 0/0, 0.25/0.25 and 0.5/0 -- and bench_rain's step cost is
		# unchanged within noise (~5 ms). Turning the cache off entirely gives
		# the same result; the tighter threshold keeps the cache for resting
		# piles. velocity_steps below 100 collapses even with this fix, so 192
		# stays.
		"physics/jolt_physics_3d/simulation/body_pair_contact_cache_distance_threshold": 0.0001,
		# Bodies sleep after 0.5 s below threshold (spec 3.5, "Sleep").
		"physics/jolt_physics_3d/simulation/sleep_time_threshold": 0.5,

		# CLAUDE.md - untyped declarations are errors, not warnings. Godot 4.7
		# exempts res://addons through debug/gdscript/warnings/directory_rules,
		# so third-party code such as GUT still compiles.
		"debug/gdscript/warnings/enable": true,
		"debug/gdscript/warnings/untyped_declaration": 2,
		"debug/gdscript/warnings/inferred_declaration": 1,
	}
	for key: String in settings:
		ProjectSettings.set_setting(key, settings[key])


func _apply_input_map() -> void:
	var actions: Dictionary = _actions()
	# Clear any stale actions from an earlier run before rewriting them.
	for setting: Dictionary in ProjectSettings.get_property_list():
		var setting_name: String = str(setting.get("name", ""))
		if setting_name.begins_with("input/") and not actions.has(setting_name.substr(6)):
			ProjectSettings.set_setting(setting_name, null)

	for action: String in actions:
		var events: Array[InputEvent] = []
		events.assign(actions[action])
		ProjectSettings.set_setting("input/%s" % action, {
			"deadzone": _deadzone_for(events),
			"events": events,
		})


## Autoload singletons (spec 3.2). DECISION (Bontago-02u): every autoload
## before this one (Events, Settings, Net, Match, SnapshotSync, MatchNet,
## Sfx) was registered by hand directly in project.godot's [autoload]
## section over the project's history; this script never managed that
## section before now. Registering Screenshots here instead keeps the
## "regenerate, then `git diff project.godot` should show only the new
## lines" gate (CLAUDE.md, "never hand-edit project.godot") honest for
## autoloads too, rather than adding another hand-edited exception.
func _apply_autoloads() -> void:
	ProjectSettings.set_setting("autoload/Screenshots", "*res://autoload/Screenshots.gd")


## Every action in spec 2.5/1.5 (Bontago-mv0.14 rewrites the mouse/keyboard
## half toward the original's block-locked scheme -- see
## docs/ORIGINAL_BONTAGO_NOTES.md "Controls"), each with a mouse/keyboard
## binding and a gamepad binding (CLAUDE.md, "All input goes through the
## Input Map").
func _actions() -> Dictionary:
	var a: Dictionary = {}

	# --- Held block (ghost) -------------------------------------------------
	# DECISION: ghost_move_* is gamepad-only. Godot cannot bind
	# InputEventMouseMotion to an action, so the mouse path reads relative
	# motion directly in PlayerController. That is still device input rather
	# than a raw keycode check, so it does not break the Input Map rule.
	a["ghost_move_left"] = [_axis(JOY_AXIS_LEFT_X, -1.0)]
	a["ghost_move_right"] = [_axis(JOY_AXIS_LEFT_X, 1.0)]
	a["ghost_move_forward"] = [_axis(JOY_AXIS_LEFT_Y, -1.0)]
	a["ghost_move_back"] = [_axis(JOY_AXIS_LEFT_Y, 1.0)]

	a["ghost_place"] = [_mouse(MOUSE_BUTTON_LEFT), _pad(JOY_BUTTON_A)]

	# Yaw keeps the original game's A/S (spec 1.5, ORIGINAL). Bontago-mv0.14:
	# the wheel used to double as yaw too; it is now block height only (see
	# hover_raise/hover_lower below), so it comes off every other action.
	a["rotate_yaw_ccw"] = [_key(KEY_A), _pad(JOY_BUTTON_LEFT_SHOULDER)]
	a["rotate_yaw_cw"] = [_key(KEY_S), _pad(JOY_BUTTON_RIGHT_SHOULDER)]

	# Pitch: W/D on keyboard, D-pad on gamepad. Bontago-mv0.14 DECISION: this
	# used to be middle click / Shift+wheel; the wheel is height now and the
	# middle button is rotate_snap (below), so pitch needs its own plain keys.
	# W/D sit next to yaw's A/S without colliding with rotation_mode (R),
	# lock_vertical (Ctrl) or camera_mode (C).
	a["rotate_pitch_fwd"] = [_key(KEY_W), _pad(JOY_BUTTON_DPAD_UP)]
	a["rotate_pitch_back"] = [_key(KEY_D), _pad(JOY_BUTTON_DPAD_DOWN)]
	# DECISION: the spec gives no keyboard key for roll, so roll uses the
	# bracket keys, which sit next to the wheel hand and are otherwise unbound.
	a["rotate_roll_left"] = [_key(KEY_BRACKETLEFT), _pad(JOY_BUTTON_DPAD_LEFT)]
	a["rotate_roll_right"] = [_key(KEY_BRACKETRIGHT), _pad(JOY_BUTTON_DPAD_RIGHT)]

	# Bontago-mv0.14 (original tutorial: "while holding the rotation-mode key,
	# the movement keys change the orientation of the block"): replaces the
	# old rotate_free_hold's continuous quaternion drift with a 90 degree snap
	# grid (PlayerController._accumulate_rotation_drag) driven by the same
	# mouse motion / left stick that normally moves the ghost. Same physical
	# bindings the old rotate_free_hold used.
	a["rotation_mode"] = [_key(KEY_R), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)]
	# Bontago-iry (owner feedback/controller-update.md, "Q or Home resets ghost
	# block rotation back to default"): spec 1.5 (ORIGINAL) already names Q for
	# this -- "Q levels the block" -- so it joins Home/F rather than replacing
	# either; KEY_Q is otherwise unbound in this map (grepped before adding).
	a["rotate_reset"] = [_key(KEY_HOME), _key(KEY_F), _key(KEY_Q), _pad(JOY_BUTTON_Y)]
	# Original tutorial: "a key snap-rotates the block" -- a plain 90 degree
	# yaw tap, distinct from rotate_reset. Bontago-mv0.22 fix (coordinator,
	# 2026-09-22): this used to double up on MMB with rotate_drag below, so
	# every drag started with an unwanted extra 90 degree step on the initial
	# press. MMB now belongs to rotate_drag alone. DECISION: rotate_snap keeps
	# only its gamepad RB binding -- the identical single-tap 90 degree yaw
	# rotate_yaw_cw (KEY_S / RB) already gives on both devices makes a
	# dedicated desktop key for this action pure duplication, not a missing
	# feature, so it is a documented "mouse" DEVICE_EXCEPTION
	# (tests/unit/test_project_setup.gd) rather than hunting for a spare key.
	a["rotate_snap"] = [_pad(JOY_BUTTON_RIGHT_SHOULDER)]

	# Bontago-mv0.22 (spec 2.5 "Rotate block (hold + drag)" [ORIGINAL, owner
	# test 2026-09-22]): holding MMB and dragging continuously spins the held
	# block's yaw (PlayerController._unhandled_input, GhostPreview.
	# free_quaternion) -- the original's real behaviour. MMB is this action's
	# alone now (see rotate_snap's fix above): a bare press with no drag does
	# nothing here (free_quaternion only changes with actual mouse motion),
	# so it no longer also fires rotate_snap's old single tap.
	# DECISION: no gamepad binding. rotate_yaw_cw (RB) already gives a 90
	# degree yaw tap on gamepad, and the right stick is already the gamepad's
	# own always-on orbit (see camera_orbit below), so there is no spare
	# gamepad gesture to spend on a drag-rotate -- a documented "pad"
	# DEVICE_EXCEPTION (tests/unit/test_project_setup.gd).
	a["rotate_drag"] = [_mouse(MOUSE_BUTTON_MIDDLE)]

	# Bontago-mv0.14 (original tutorial: "the mouse wheel raises and lowers
	# the block"): PageUp/PageDown and the gamepad buttons are held
	# continuously (PlayerController._handle_hover_adjust); the wheel notches
	# are momentary and step once per notch (PlayerController._step_hover).
	# DECISION: the spec left the gamepad hover bindings blank; RS click and X
	# are the button budget left over after placement/camera/rotation claim
	# everything else on a standard pad.
	a["hover_raise"] = [
		_mouse(MOUSE_BUTTON_WHEEL_UP),
		_key(KEY_PAGEUP),
		_pad(JOY_BUTTON_RIGHT_STICK),
	]
	a["hover_lower"] = [
		_mouse(MOUSE_BUTTON_WHEEL_DOWN),
		_key(KEY_PAGEDOWN),
		_pad(JOY_BUTTON_X),
	]

	# Original tutorial: "Locks block to vertical movement only" -- while
	# held, mouse XZ motion is ignored so only the wheel changes height
	# (PlayerController._unhandled_input). DECISION: no gamepad binding
	# (DEVICE_EXCEPTIONS) -- the gamepad already keeps ghost movement (left
	# stick) and height (RS click/X) on separate physical inputs, so there is
	# nothing to lock there.
	a["lock_vertical"] = [_key(KEY_CTRL)]

	# Bontago-1en.14 (M4 P2d, owner decision 2026-09-22 Bontago-mvl (a): "hold
	# left mouse on the held special, drag, flick-release; drag distance/speed
	# sets the arc. Right mouse stays camera orbit"): moved off MOUSE_BUTTON_
	# RIGHT (this used to share camera_orbit's own button, an [OPEN] overlap
	# spec 2.5 flagged pending this exact owner decision -- see camera_orbit's
	# own comment below, which no longer needs to mention throw_aim at all)
	# onto MOUSE_BUTTON_LEFT instead, the same physical button ghost_place
	# already uses -- game/PlayerController.gd's ghost_place handler tells
	# the two apart by whether the piece in hand is a throwable special.
	a["throw_aim"] = [_mouse(MOUSE_BUTTON_LEFT), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)]

	# --- Camera -------------------------------------------------------------
	# Bontago-mv0.14 (original tutorial: "while holding the camera-mode key,
	# movement keys change where the camera is facing"): renamed from
	# camera_orbit_hold and moved off MMB (now rotate_snap) onto its own key.
	# The gamepad orbits with the right stick directly regardless of this
	# hold (test_project_setup.gd's DEVICE_EXCEPTIONS), so it needs no
	# gamepad binding.
	a["camera_mode"] = [_key(KEY_C)]

	# Bontago-mv0.22 (spec 2.5 "Camera orbit (hold + drag)" [ORIGINAL, owner
	# test 2026-09-22]): RMB held + drag is now the primary orbit gesture;
	# camera_mode (C) above stays wired as the keyboard alias for the exact
	# same gesture (CameraRig._unhandled_input checks both actions). The wheel
	# also zooms instead of changing block height while either is held
	# (PlayerController._camera_orbit_held()/_zoom_camera(),
	# CameraRig.zoom_by_orbit_step()). Bontago-1en.14 (M4 P2d): this used to
	# share MOUSE_BUTTON_RIGHT with throw_aim, an [OPEN] overlap spec 2.5
	# flagged pending an owner decision -- throw_aim moved to MOUSE_BUTTON_LEFT
	# instead (Bontago-mvl (a), see throw_aim's own comment above), so
	# camera_orbit keeps MOUSE_BUTTON_RIGHT to itself now with no remaining
	# conflict. No gamepad binding either, for the same reason camera_mode has
	# none: the right stick already orbits unconditionally, with no hold
	# required -- a documented "pad" DEVICE_EXCEPTION
	# (tests/unit/test_project_setup.gd), same as camera_mode's own entry
	# there.
	a["camera_orbit"] = [_mouse(MOUSE_BUTTON_RIGHT)]

	a["camera_look_left"] = [_axis(JOY_AXIS_RIGHT_X, -1.0)]
	a["camera_look_right"] = [_axis(JOY_AXIS_RIGHT_X, 1.0)]
	a["camera_look_up"] = [_axis(JOY_AXIS_RIGHT_Y, -1.0)]
	a["camera_look_down"] = [_axis(JOY_AXIS_RIGHT_Y, 1.0)]

	# DECISION: spec 2.5 lists WASD for camera pan, but 1.5 (ORIGINAL) gives
	# A and S to block rotation. Rather than change an ORIGINAL binding, pan
	# moves to the arrow keys; Space-and-drag from the spec still works.
	# On gamepad, pan is the left stick while camera_modifier is held, so the
	# pan actions share the left stick axes with ghost_move_*. Bontago-mv0.14:
	# pan and snap-home/goal below are only live while
	# CameraTuning.follow_block is false (see game/CameraRig.gd) -- the
	# default block-locked camera has nothing to pan away from.
	a["camera_pan_left"] = [_key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)]
	a["camera_pan_right"] = [_key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)]
	a["camera_pan_forward"] = [_key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)]
	a["camera_pan_back"] = [_key(KEY_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)]
	a["camera_modifier"] = [_key(KEY_SPACE), _pad(JOY_BUTTON_LEFT_STICK)]

	# DECISION: the triggers double as zoom, as spec 2.5 asks ("Triggers"),
	# while also being throw_aim and rotation_mode. The spec already scopes
	# trigger zoom to "while not holding a block", so CameraRig ignores zoom
	# whenever a block is held and the trigger means throw or rotate instead.
	# Bontago-mv0.14: the wheel used to double as zoom too; it is block height
	# only now (hover_raise/hover_lower above).
	a["camera_zoom_in"] = [_key(KEY_Z), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)]
	a["camera_zoom_out"] = [_key(KEY_X), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)]

	a["camera_snap_home"] = [_key(KEY_1), _pad(JOY_BUTTON_BACK)]
	a["camera_snap_goal"] = [_key(KEY_2), _pad(JOY_BUTTON_B)]

	# --- Shell --------------------------------------------------------------
	a["pause_menu"] = [_key(KEY_ESCAPE), _pad(JOY_BUTTON_START)]

	# Bontago-02u (owner request, 2026-09-23: "add a button to take in-game
	# screenshots which automatically saves to the docs"). F12 is the
	# conventional desktop screenshot key and was still free. DECISION: every
	# face/shoulder/stick/D-pad/Back/Start button a standard pad exposes is
	# already claimed by placement, camera or shell controls above; MISC1
	# (JOY_BUTTON_MISC1 -- the extra button modern Xbox Series and DualSense
	# pads expose, e.g. Xbox's "Share" button) is unused anywhere else in this
	# file and isn't the Guide/Home button (JOY_BUTTON_GUIDE), which the OS
	# itself typically intercepts rather than passing to the game.
	a["screenshot_capture"] = [_key(KEY_F12), _pad(JOY_BUTTON_MISC1)]

	# DECISION (tools/bootstrap_project.gd): docs/M3a_PLAN.md specifies
	# net_debug_toggle as "F3 + gamepad Back+Y". Every face/shoulder/stick
	# button on the pad is already claimed by placement and camera controls
	# (spec 2.5), so there is no free single button left for a debug-only
	# feature. The Input Map action itself can only bind single events, not a
	# two-button chord, so its gamepad half is bound to Y (already
	# rotate_reset's button — two actions sharing one physical event is normal
	# in Godot) and ui/NetDebugOverlay.gd requires camera_snap_home (Back) to
	# be held at the same time before it treats the press as the toggle. That
	# keeps CLAUDE.md's "never check raw keycodes" rule intact: the chord is
	# built entirely from two Input Map actions, not a JOY_BUTTON_* literal
	# outside this file.
	a["net_debug_toggle"] = [_key(KEY_F3), _pad(JOY_BUTTON_Y)]

	# DECISION (tools/bootstrap_project.gd, Bontago-mv0.18 -- owner request:
	# "add a settings menu with sliders so I can play around and adjust the
	# camera in-game"): unlike net_debug_toggle/the sandbox hotkeys above,
	# this one has to work in the real, shipped game (offline and online), not
	# only a debug entry point, so it can't reach for the Xbox
	# Elite/DualSense-only paddle buttons sandbox_reset_field etc. use. Same
	# technique as net_debug_toggle's own Back+Y chord though: every
	# face/shoulder/stick/D-pad button is already claimed, so the gamepad half
	# binds to X (already hover_lower) and ui/TuningPanel.gd requires
	# pause_menu (Start) to be held at the same time before it treats the
	# press as the toggle -- a Start+X chord, distinct from net_debug_toggle's
	# own Back+Y one, built entirely from existing Input Map actions rather
	# than a raw JOY_BUTTON_* literal outside this file.
	a["tuning_panel_toggle"] = [_key(KEY_F4), _pad(JOY_BUTTON_X)]

	# --- Sandbox debug hotkeys (Bontago-mv0.8) -------------------------------
	# Unlisted like net_debug_toggle above: only reachable through
	# `godot --path . -- --sandbox` (game/Main.gd), never seen in the shipped
	# hot-seat or networked flows. Every face/shoulder/stick/D-pad button is
	# already claimed by placement and camera controls (spec 2.5) or by
	# net_debug_toggle's own Back+Y chord, so these reach for the buttons
	# nothing else uses: BACK for the one binding the brief asked for by name
	# (accepting that it doubles up with camera_snap_home — a debug-only
	# overlap, not a shipped one, the same tolerance net_debug_toggle already
	# established for sharing Y with rotate_reset) and the PADDLE1-4 buttons
	# (JOY_BUTTON_PADDLE1..4, only present on Xbox Elite/DualSense-class pads)
	# for the rest, rather than "Y+Back" for sandbox_toggle_timer as first
	# suggested — that chord is literally net_debug_toggle's own trigger
	# condition and would fire both actions from one press.
	a["sandbox_next_slot"] = [_key(KEY_TAB), _pad(JOY_BUTTON_BACK)]
	a["sandbox_reset_field"] = [_key(KEY_F5), _pad(JOY_BUTTON_PADDLE1)]
	a["sandbox_toggle_timer"] = [_key(KEY_F6), _pad(JOY_BUTTON_PADDLE3)]
	a["sandbox_spawn_tower"] = [_key(KEY_F7), _pad(JOY_BUTTON_PADDLE2)]
	a["sandbox_toggle_overlay"] = [_key(KEY_F8), _pad(JOY_BUTTON_PADDLE4)]

	# DECISION (tools/bootstrap_project.gd, Bontago-1en.24): sandbox_force_
	# special (game/Sandbox.gd's F9) is the fifth sandbox-only hotkey, but
	# PADDLE1-4 above already claim every Xbox Elite/DualSense-class paddle,
	# and every face/shoulder/stick/D-pad/Back/Start/MISC1 button on a
	# standard pad is claimed by placement, camera, shell or another sandbox
	# hotkey (see this block's own opening comment). JOY_BUTTON_TOUCHPAD
	# (DualSense's touchpad click) is the one JoyButton value still free
	# anywhere in this file -- same debug-only, uncommon-pad tolerance the
	# PADDLE buttons above already established, not a shipped-game binding.
	a["sandbox_force_special"] = [_key(KEY_F9), _pad(JOY_BUTTON_TOUCHPAD)]

	# DECISION (tools/bootstrap_project.gd, M6 B2): sandbox_slow_motion and
	# sandbox_pause_physics are the sixth and seventh sandbox-only hotkeys --
	# every JoyButton value this file can bind (every face/shoulder/stick/
	# D-pad/Back/Start/MISC1/PADDLE1-4/TOUCHPAD button; JOY_BUTTON_GUIDE stays
	# off-limits for the same reason screenshot_capture's own comment gives)
	# is already claimed above. Rather than a cross-script chord like net_
	# debug_toggle's Back+Y (a different node's _unhandled_input), these reuse
	# PADDLE1/PADDLE2 -- already sandbox_reset_field's and sandbox_spawn_
	# tower's own buttons, checked in this same file's game/Sandbox.gd
	# _unhandled_input -- gated on sandbox_toggle_overlay (PADDLE4) / sandbox_
	# force_special (TOUCHPAD) being held at the same time. Keeping both
	# halves of each chord inside one script (rather than splitting the
	# button and its modifier across two different nodes' input handlers, as
	# net_debug_toggle/tuning_panel_toggle do) means there is only ever one
	# place that decides which of the two actions a shared PADDLE press means,
	# with no risk of Godot's viewport input order deciding it differently.
	# F10/F11 (the desktop keyboard halves) are unclaimed and need no chord.
	a["sandbox_slow_motion"] = [_key(KEY_F10), _pad(JOY_BUTTON_PADDLE1)]
	a["sandbox_pause_physics"] = [_key(KEY_F11), _pad(JOY_BUTTON_PADDLE2)]

	return a


func _deadzone_for(events: Array[InputEvent]) -> float:
	for event: InputEvent in events:
		var motion: InputEventJoypadMotion = event as InputEventJoypadMotion
		if motion == null:
			continue
		if motion.axis == JOY_AXIS_TRIGGER_LEFT or motion.axis == JOY_AXIS_TRIGGER_RIGHT:
			return TRIGGER_DEADZONE
		return STICK_DEADZONE
	return BUTTON_DEADZONE


## All bindings use device -1 (InputEvent's "all devices") so any connected
## gamepad works without the player picking a slot.
const ALL_DEVICES: int = -1


func _key(keycode: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.device = ALL_DEVICES
	event.physical_keycode = keycode
	return event


func _mouse(button: MouseButton, modifier_mask: int = 0) -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.device = ALL_DEVICES
	event.button_index = button
	event.shift_pressed = (modifier_mask & KEY_MASK_SHIFT) != 0
	event.ctrl_pressed = (modifier_mask & KEY_MASK_CTRL) != 0
	event.alt_pressed = (modifier_mask & KEY_MASK_ALT) != 0
	return event


func _pad(button: JoyButton) -> InputEventJoypadButton:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = ALL_DEVICES
	event.button_index = button
	return event


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	event.device = ALL_DEVICES
	event.axis = axis
	event.axis_value = value
	return event
