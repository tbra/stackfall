extends GutTest
## M0 acceptance, checked by machine rather than by eye.
##
## The project settings and the Input Map are the whole deliverable of M0, so
## they get a test: if someone changes the physics engine, drops physics
## interpolation, or adds a control with no gamepad binding, this fails.

## Spec 2.5, plus the pause action the shell needs. Every one of these must have
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
	"rotate_free_hold",
	"rotate_reset",
	"hover_raise",
	"hover_lower",
	"throw_aim",
	"camera_orbit_hold",
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
	"camera_snap_home",
	"camera_snap_goal",
	"pause_menu",
	"net_debug_toggle",
]

## Actions whose mouse or gamepad half is deliberately absent, with the reason.
## Anything not listed here must be bound on both devices.
const DEVICE_EXCEPTIONS: Dictionary = {
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
	# The gamepad's right stick orbits directly, so it needs no hold modifier.
	"camera_orbit_hold": "pad",
}

const AUTOLOADS: PackedStringArray = ["Events", "Settings", "Net", "Match"]


func test_physics_engine_is_jolt() -> void:
	assert_eq(
		str(ProjectSettings.get_setting("physics/3d/physics_engine", "")),
		"Jolt Physics",
		"Spec 3.1 requires Jolt for 3D physics."
	)


func test_physics_runs_at_60_hz() -> void:
	assert_eq(Engine.physics_ticks_per_second, 60, "Spec 3.5 fixes the tick rate at 60 Hz.")


func test_physics_interpolation_is_on() -> void:
	assert_true(
		bool(ProjectSettings.get_setting("physics/common/physics_interpolation", false)),
		"Spec 3.5 needs interpolation so rendering stays smooth above 60 fps."
	)


func test_renderer_is_forward_plus() -> void:
	assert_eq(
		str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")),
		"forward_plus",
		"Spec 3.1 requires the Forward+ renderer."
	)


func test_jolt_solver_iterations_match_spec() -> void:
	# Spec 3.5: "Start at 10 and 4, and tune using a benchmark scene with a
	# 40-block tower." Position stayed at 4 (raising it to 80 changed the
	# benchmark by nothing). Velocity had to go to 192, because Jolt's
	# Gauss-Seidel velocity solver propagates a contact impulse across roughly
	# one contact per iteration, so an N-cube column needs about 4-5N
	# iterations before the support force is distributed through the whole
	# chain. Under that, every block keeps a residual velocity, the stack
	# never sleeps, and above ~15 blocks it leans until it topples. See the
	# long comment in tools/bootstrap_project.gd for the measurements.
	assert_eq(
		int(ProjectSettings.get_setting("physics/jolt_physics_3d/simulation/velocity_steps", 0)),
		192,
		"A 40-cube column needs ~4-5x its height in velocity iterations (see tools/bootstrap_project.gd)."
	)
	assert_eq(
		int(ProjectSettings.get_setting("physics/jolt_physics_3d/simulation/position_steps", 0)),
		4,
		"Spec 3.5's starting position iteration count; the tower benchmark gave no reason to raise it."
	)


func test_blocks_are_not_damped_into_stability() -> void:
	# Guard rail for spec 1.6's "real sense of weight and balance": towers are
	# held up by solver convergence, not by damping. Linear damping caps a
	# falling block at g / damp, so anything much above 0.3 makes blocks float
	# down. See config/PhysicsTuning.gd's DECISION comment.
	var tuning: PhysicsTuning = load("res://config/physics_tuning.tres")
	assert_lt(
		tuning.block_linear_damp, 0.31,
		"Linear damping of %.2f caps terminal fall speed at %.1f m/s; blocks would float." % [
			tuning.block_linear_damp,
			ProjectSettings.get_setting("physics/3d/default_gravity", 9.8) / maxf(tuning.block_linear_damp, 0.001),
		]
	)


func test_untyped_declarations_are_errors() -> void:
	assert_eq(
		int(ProjectSettings.get_setting("debug/gdscript/warnings/untyped_declaration", 0)),
		2,
		"CLAUDE.md treats untyped declarations as errors, not warnings."
	)


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
