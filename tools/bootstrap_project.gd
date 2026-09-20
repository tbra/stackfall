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


## Every action in spec 2.5, each with a mouse/keyboard binding and a gamepad
## binding (CLAUDE.md, "All input goes through the Input Map").
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

	# Yaw keeps the original game's A/S (spec 1.5, ORIGINAL).
	a["rotate_yaw_ccw"] = [_key(KEY_A), _mouse(MOUSE_BUTTON_WHEEL_UP), _pad(JOY_BUTTON_LEFT_SHOULDER)]
	a["rotate_yaw_cw"] = [_key(KEY_S), _mouse(MOUSE_BUTTON_WHEEL_DOWN), _pad(JOY_BUTTON_RIGHT_SHOULDER)]

	# Pitch and roll: middle click / Shift+wheel on mouse, D-pad on gamepad.
	# A middle-click tap rotates; holding it orbits the camera (spec 1.5, 2.5),
	# which PlayerController separates by hold duration.
	a["rotate_pitch_fwd"] = [
		_mouse(MOUSE_BUTTON_MIDDLE),
		_mouse(MOUSE_BUTTON_WHEEL_UP, KEY_MASK_SHIFT),
		_pad(JOY_BUTTON_DPAD_UP),
	]
	a["rotate_pitch_back"] = [
		_mouse(MOUSE_BUTTON_WHEEL_DOWN, KEY_MASK_SHIFT),
		_pad(JOY_BUTTON_DPAD_DOWN),
	]
	# DECISION: the spec gives no keyboard key for roll, so roll uses the
	# bracket keys, which sit next to the wheel hand and are otherwise unbound.
	a["rotate_roll_left"] = [_key(KEY_BRACKETLEFT), _pad(JOY_BUTTON_DPAD_LEFT)]
	a["rotate_roll_right"] = [_key(KEY_BRACKETRIGHT), _pad(JOY_BUTTON_DPAD_RIGHT)]

	a["rotate_free_hold"] = [_key(KEY_R), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)]
	a["rotate_reset"] = [_key(KEY_HOME), _key(KEY_F), _pad(JOY_BUTTON_Y)]

	# DECISION: the spec leaves the gamepad hover bindings blank. The stick
	# clicks and the face button left over after place/reset are the only free
	# inputs while a block is held, so hover uses RS click and X.
	a["hover_raise"] = [
		_mouse(MOUSE_BUTTON_WHEEL_UP, KEY_MASK_CTRL),
		_key(KEY_PAGEUP),
		_pad(JOY_BUTTON_RIGHT_STICK),
	]
	a["hover_lower"] = [
		_mouse(MOUSE_BUTTON_WHEEL_DOWN, KEY_MASK_CTRL),
		_key(KEY_PAGEDOWN),
		_pad(JOY_BUTTON_X),
	]

	a["throw_aim"] = [_mouse(MOUSE_BUTTON_RIGHT), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)]

	# --- Camera -------------------------------------------------------------
	# Held to orbit with the mouse. The gamepad orbits with the right stick
	# directly, so it needs no hold modifier.
	a["camera_orbit_hold"] = [_mouse(MOUSE_BUTTON_MIDDLE)]
	a["camera_look_left"] = [_axis(JOY_AXIS_RIGHT_X, -1.0)]
	a["camera_look_right"] = [_axis(JOY_AXIS_RIGHT_X, 1.0)]
	a["camera_look_up"] = [_axis(JOY_AXIS_RIGHT_Y, -1.0)]
	a["camera_look_down"] = [_axis(JOY_AXIS_RIGHT_Y, 1.0)]

	# DECISION: spec 2.5 lists WASD for camera pan, but 1.5 (ORIGINAL) gives
	# A and S to block rotation. Rather than change an ORIGINAL binding, pan
	# moves to the arrow keys; Space-and-drag from the spec still works.
	# On gamepad, pan is the left stick while camera_modifier is held, so the
	# pan actions share the left stick axes with ghost_move_*.
	a["camera_pan_left"] = [_key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)]
	a["camera_pan_right"] = [_key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)]
	a["camera_pan_forward"] = [_key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)]
	a["camera_pan_back"] = [_key(KEY_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)]
	a["camera_modifier"] = [_key(KEY_SPACE), _pad(JOY_BUTTON_LEFT_STICK)]

	# DECISION: the triggers double as zoom, as spec 2.5 asks ("Triggers"),
	# while also being throw_aim and rotate_free_hold. The spec already scopes
	# zoom to "while not holding a block", so CameraRig ignores zoom whenever a
	# block is held and the trigger means throw or free-rotate instead.
	a["camera_zoom_in"] = [_key(KEY_Z), _mouse(MOUSE_BUTTON_WHEEL_UP), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)]
	a["camera_zoom_out"] = [_key(KEY_X), _mouse(MOUSE_BUTTON_WHEEL_DOWN), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)]

	a["camera_snap_home"] = [_key(KEY_1), _pad(JOY_BUTTON_BACK)]
	a["camera_snap_goal"] = [_key(KEY_2), _pad(JOY_BUTTON_B)]

	# --- Shell --------------------------------------------------------------
	a["pause_menu"] = [_key(KEY_ESCAPE), _pad(JOY_BUTTON_START)]

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
