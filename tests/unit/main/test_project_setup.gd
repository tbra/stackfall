extends GutTest
## M0 acceptance, checked by machine rather than by eye.
##
## The project settings and the Input Map are the whole deliverable of M0, so
## they get a test: if someone changes the physics engine, drops physics
## interpolation, or adds a control with no gamepad binding, this fails.

## Spec 1.3, plus the pause action the shell needs. Every one of these must have
## a mouse/keyboard binding and a gamepad binding (CLAUDE.md, "Tech rules").
const REQUIRED_ACTIONS: PackedStringArray = [
	"ghost_move_left",
	"ghost_move_right",
	"ghost_move_forward",
	"ghost_move_back",
	"ghost_place",
	"rotate_yaw_ccw",
	"rotate_yaw_cw",
	"rotate_pitch_fwd",
	"rotate_pitch_back",
	"rotate_roll_left",
	"rotate_roll_right",
	"rotation_mode",
	"rotate_drag_pad",
	"rotate_reset",
	"rotate_snap",
	"rotate_drag",
	"hover_raise",
	"hover_lower",
	"lock_vertical",
	"camera_mode",
	"camera_orbit",
	"camera_look_left",
	"camera_look_right",
	"camera_look_up",
	"camera_look_down",
	"camera_pan_left",
	"camera_pan_right",
	"camera_pan_forward",
	"camera_pan_back",
	"camera_modifier",
	"camera_zoom_in",
	"camera_zoom_out",
	"camera_zoom_modifier",
	"camera_snap_home",
	"camera_snap_goal",
	"camera_reset",
	"pause_menu",
	"net_debug_toggle",
	"tuning_panel_toggle",
	"sandbox_next_slot",
	"show_scores",
	"sandbox_reset_field",
	"sandbox_toggle_timer",
	"sandbox_spawn_tower",
	"hud_toggle",
	"sandbox_force_special",
	"screenshot_capture",
	# menu accept/cancel need an explicit gamepad half too
	# (tools/bootstrap_project.gd's own "--- UI (menus) ---" block).
	"ui_accept",
	"ui_cancel",
]

## Actions whose mouse or gamepad half is deliberately absent, with the reason.
## Anything not listed here must be bound on both devices.
const DEVICE_EXCEPTIONS: Dictionary = {
	# B owns the gamepad yaw snap; shoulders no longer rotate.
	"rotate_yaw_ccw": "pad",
	"rotate_yaw_cw": "pad",
	# Godot cannot bind InputEventMouseMotion to an action; the mouse drives the
	# ghost through relative motion instead (see tools/bootstrap_project.gd).
	"ghost_move_left": "mouse",
	"ghost_move_right": "mouse",
	"ghost_move_forward": "mouse",
	"ghost_move_back": "mouse",
	"camera_look_left": "mouse",
	"camera_look_right": "mouse",
	"camera_look_up": "mouse",
	"camera_look_down": "mouse",
	# The gamepad's right stick orbits directly, so it needs no hold modifier
	# (renamed from camera_orbit_hold).
	"camera_mode": "pad",
	# RMB is the primary orbit hold now (camera_mode/C stays a
	# keyboard alias); the right stick orbits unconditionally on gamepad for
	# the same reason camera_mode needs no hold there.
	"camera_orbit": "pad",
	# fix (coordinator): MMB moved to rotate_drag's
	# continuous spin alone, so a single MMB press no longer also fires this
	# action's old tap (that was firing both from one press -- every drag
	# started with an unwanted 90 degree step). rotate_yaw_cw (KEY_S / RB)
	# already gives an identical single-tap 90 degree yaw on both devices, so
	# this action keeps only its gamepad RB binding rather than hunting for a
	# spare desktop key (tools/bootstrap_project.gd).
	"rotate_snap": "mouse",
	# DECISION: no gamepad equivalent -- rotate_yaw_cw (RB) already gives a 90
	# degree yaw tap, and the right stick is the gamepad's own always-on
	# orbit, so there is no spare gamepad gesture for a drag-rotate
	# (tools/bootstrap_project.gd).
	"rotate_drag": "pad",
	# The gamepad already keeps ghost movement (left stick) and height (RS
	# click/X) on separate physical inputs, so there is nothing to lock.
	"lock_vertical": "pad",
	# Controller update (re-confirmed): RT held + left stick now free-rotates the block
	# continuously (rotate_drag's own gesture, mirrored for gamepad); the
	# keyboard's R key stays rotation_mode's 90 degree snap grid unchanged, so
	# rotation_mode itself carries no gamepad binding any more.
	"rotation_mode": "pad",
	# The gamepad-only free-rotate gesture (RT + left stick) above -- rotate_drag
	# (MMB) is this gesture's mouse/keyboard half already; there is no separate
	# desktop binding for this action itself.
	"rotate_drag_pad": "mouse",
	# Triggers alone must NEVER zoom -- the trigger
	# axes came off camera_zoom_in/out entirely; Z/X are keyboard-only now.
	"camera_zoom_in": "pad",
	"camera_zoom_out": "pad",
	# The gamepad-only continuous zoom modifier (LT + left stick) above -- Z/X
	# are this gesture's keyboard half already; there is no separate desktop
	# binding for this action itself.
	"camera_zoom_modifier": "mouse",
}

const AUTOLOADS: PackedStringArray = [
	"StartupPump", "Events", "Settings", "Net", "Match", "SnapshotSync", "MatchNet", "Sfx", "Screenshots", "Rumble"
]


func test_snap_rotation_uses_b_without_shoulder_rotation() -> void:
	var snap_buttons: Array[int] = []
	for event: InputEvent in InputMap.action_get_events(&"rotate_snap"):
		if event is InputEventJoypadButton:
			snap_buttons.append(event.button_index)
	assert_eq(snap_buttons, [JOY_BUTTON_B])
	for action: StringName in [&"rotate_snap", &"rotate_yaw_ccw", &"rotate_yaw_cw"]:
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventJoypadButton:
				assert_false(event.button_index in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER])


func test_autoloads_are_registered() -> void:
	for singleton: String in AUTOLOADS:
		assert_true(
			ProjectSettings.has_setting("autoload/%s" % singleton),
			"Autoload %s is missing (spec 3.2)." % singleton
		)
		assert_not_null(
			get_tree().root.get_node_or_null(NodePath(singleton)),
			"Autoload %s did not load at runtime." % singleton
		)


func test_every_required_action_exists() -> void:
	for action: String in REQUIRED_ACTIONS:
		assert_true(InputMap.has_action(action), "Input action %s is missing (spec 2.5)." % action)


func test_every_action_is_bound_on_both_devices() -> void:
	for action: String in REQUIRED_ACTIONS:
		if not InputMap.has_action(action):
			continue  # Reported by test_every_required_action_exists.
		var exception: String = str(DEVICE_EXCEPTIONS.get(action, ""))
		var has_desktop: bool = false
		var has_pad: bool = false
		for event: InputEvent in InputMap.action_get_events(StringName(action)):
			if event is InputEventKey or event is InputEventMouseButton:
				has_desktop = true
			elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
				has_pad = true
		if exception != "mouse":
			assert_true(has_desktop, "Action %s has no keyboard or mouse binding." % action)
		if exception != "pad":
			assert_true(has_pad, "Action %s has no gamepad binding." % action)


func test_bindings_accept_any_gamepad() -> void:
	for action: String in REQUIRED_ACTIONS:
		if not InputMap.has_action(action):
			continue
		for event: InputEvent in InputMap.action_get_events(StringName(action)):
			assert_eq(
				event.device,
				-1,
				"Action %s is bound to one device slot; use -1 so any gamepad works." % action
			)
