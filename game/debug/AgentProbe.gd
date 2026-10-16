class_name AgentProbe
extends RefCounted
## Agent probe mode: agent-launched Godot runs (tools/*.tscn scenes, or any run
## passing `-- --agent-probe`) must never disturb the owner: tiny window, no
## focus, muted, and the mouse is never captured. Pure static
## helpers; Settings._ready() calls apply() once at startup.
##   godot --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy \
##     --path . res://tools/shot.tscn -- --agent-probe [--render-size=1920x1080]

const FLAG: String = "--agent-probe"
const RENDER_SIZE_PREFIX: String = "--render-size="
const TOOLS_SCENE_PREFIX: String = "res://tools/"
## Benchmark and ENet scenes anywhere under tests/ are agent runs too (session).
const TEST_SCENE_PREFIX: String = "res://tests/"
const QUIT_ON_MENU_FLAG: String = "--quit-on-menu"
const STARTUP_LINE_FORMAT: String = "AGENT_PROBE startup first_frame_ms=%d menu_ready_ms=%d"
const MENU_MISSING_MS: int = -1
const MENU_TIMEOUT_EXIT_CODE: int = 1
## DECISION: the "menu never appeared" timeout reuses the loading screen's
## ready timeout instead of a new tunable.
## Loaded lazily (load(), only under --quit-on-menu) and matched by script path
## so this autoload-reachable file never pulls the menu or tuning graph in.
const LOADING_TUNING_PATH: String = "res://config/ui/loading_screen_tuning.tres"
const MAIN_MENU_SCRIPT_FILE: String = "MainMenu.gd"
const PORT_ARG_PREFIX: String = "--port="
## DECISION: random free UDP port range for agent-run hosts, kept clear of the
## default game port so benches never block tools/run_m3a_local.ps1.
const FREE_PORT_MIN: int = 48000
const FREE_PORT_SPAN: int = 10000
const FREE_PORT_TRIES: int = 50
## DECISION: probe window size; tools needing a real render resolution use
## make_render_viewport() instead of a big window.
const WINDOW_SIZE: Vector2i = Vector2i(320, 180)

static var _cached: int = -1
static var _first_frame_ms: int = MENU_MISSING_MS
static var _startup_done: bool = false


## Pure detection: user args containing the flag, or any arg naming a scene
## under res://tools/ (a game scene run from the editor is unaffected).
static func detect(cmdline_args: PackedStringArray, user_args: PackedStringArray) -> bool:
	if user_args.has(FLAG) or cmdline_args.has(FLAG):
		return true
	for arg: String in cmdline_args:
		if (arg.ends_with(".tscn") or arg.ends_with(".scn")) \
				and (arg.begins_with(TOOLS_SCENE_PREFIX) or arg.begins_with("tools/")
					or arg.begins_with(TEST_SCENE_PREFIX) or arg.begins_with("tests/")):
			return true
	return false


static func is_active() -> bool:
	if _cached < 0:
		_cached = 1 if detect(OS.get_cmdline_args(), OS.get_cmdline_user_args()) else 0
	return _cached == 1


## Parses `--render-size=WxH` from the user args; (0, 0) when absent/invalid.
static func parse_render_size(user_args: PackedStringArray) -> Vector2i:
	for arg: String in user_args:
		if arg.begins_with(RENDER_SIZE_PREFIX):
			var parts: PackedStringArray = arg.trim_prefix(RENDER_SIZE_PREFIX).to_lower().split("x")
			if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
				return Vector2i(int(parts[0]), int(parts[1]))
	return Vector2i.ZERO


## Startup side effects: no focus, small window, master bus muted.
static func apply() -> void:
	if not is_active():
		return
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(WINDOW_SIZE)
	var master: int = AudioServer.get_bus_index(&"Master")
	if master >= 0:
		AudioServer.set_bus_mute(master, true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if wants_quit_on_menu(OS.get_cmdline_user_args()):
		_install_startup_watch()


## True when the user args ask for the boot check (`--quit-on-menu`).
static func wants_quit_on_menu(user_args: PackedStringArray) -> bool:
	return user_args.has(QUIT_ON_MENU_FLAG)


## The one-line report for the boot check; menu_ms < 0 means it never appeared.
static func format_startup_line(first_frame_ms: int, menu_ms: int) -> String:
	return STARTUP_LINE_FORMAT % [first_frame_ms, menu_ms]


static func _install_startup_watch() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	tree.process_frame.connect(_on_first_frame, CONNECT_ONE_SHOT)
	tree.node_added.connect(_on_node_added)
	var tuning: Resource = load(LOADING_TUNING_PATH)
	var timeout_s: float = float(tuning.get(&"ready_timeout_s"))
	tree.create_timer(timeout_s, true, false, true).timeout.connect(_on_menu_timeout)


static func _on_first_frame() -> void:
	_first_frame_ms = Time.get_ticks_msec()


static func _on_node_added(node: Node) -> void:
	if _startup_done or not _is_main_menu(node):
		return
	# Ready once the menu is in the tree and has processed a frame.
	node.get_tree().process_frame.connect(_on_menu_frame, CONNECT_ONE_SHOT)


static func _is_main_menu(node: Node) -> bool:
	var script: Script = node.get_script() as Script
	return script != null and script.resource_path.get_file() == MAIN_MENU_SCRIPT_FILE


static func _on_menu_frame() -> void:
	if _startup_done:
		return
	_finish_startup(Time.get_ticks_msec(), 0)


static func _on_menu_timeout() -> void:
	if not _startup_done:
		_finish_startup(MENU_MISSING_MS, MENU_TIMEOUT_EXIT_CODE)


static func _finish_startup(menu_ms: int, exit_code: int) -> void:
	_startup_done = true
	print(format_startup_line(_first_frame_ms, menu_ms))
	var sfx: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Sfx")
	if sfx != null:
		sfx.call(&"quit_tree", exit_code)  # drains audio first
	else:
		QuitFlag.mark()
		(Engine.get_main_loop() as SceneTree).quit(exit_code)


## Mouse-capture gate: sets the mode unless probe mode forbids capture.
static func set_mouse_mode(mode: Input.MouseMode) -> void:
	Input.mouse_mode = mouse_mode_for(mode, is_active())


## Pure gate behind set_mouse_mode(): probe mode never captures or confines the mouse.
static func mouse_mode_for(mode: Input.MouseMode, probe_active: bool) -> Input.MouseMode:
	if probe_active and mode != Input.MOUSE_MODE_VISIBLE:
		return Input.MOUSE_MODE_VISIBLE
	return mode


## A SubViewport of the --render-size (or fallback) attached to `parent`, so a
## bench/screenshot renders at full resolution while the OS window stays tiny.
static func make_render_viewport(parent: Node, fallback: Vector2i) -> SubViewport:
	var size: Vector2i = parse_render_size(OS.get_cmdline_user_args())
	if size == Vector2i.ZERO:
		size = fallback
	return make_viewport(parent, size)


## A SubViewport of exactly `size` attached to `parent` (tools/shot.gd renders one per --render-size entry).
static func make_viewport(parent: Node, size: Vector2i) -> SubViewport:
	# One scaling rule (ui/theme/UiScale.gd): same stretch maths as a real window.
	var vp: SubViewport = UiScale.make_viewport(size)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Share the root world: a bare SubViewport has no World3D, which breaks
	# get_viewport().world_3d users (raycasts, DiscMirror).
	vp.world_3d = parent.get_viewport().world_3d
	parent.add_child(vp)
	return vp


# --- Capture setup hooks (tools/shot.gd) ---------------------------------------------------------
# Called only by the capture tool, which always runs in probe mode; each hook reaches the game
# through Object.get/set so this autoload-reachable file never pulls the camera, sky or menu graph in.

const CAM_YAW_INDEX: int = 0
const CAM_PITCH_INDEX: int = 1
const CAM_DISTANCE_INDEX: int = 2
const CAM_TARGET_X_INDEX: int = 3
const CAM_POSE_PARTS: int = 3
const CAM_POSE_TARGET_PARTS: int = 6

## Presses and releases an Input Map action inside `viewport` (the overlays listen for
## InputEventAction.is_action_pressed in _unhandled_input).
static func press_action(viewport: Viewport, action: StringName) -> bool:
	if not InputMap.has_action(action):
		return false
	for pressed: bool in [true, false]:
		var event: InputEventAction = InputEventAction.new()
		event.action = action
		event.pressed = pressed
		viewport.push_input(event)
	return true


## Puts Main's camera rig on a pose: yaw, pitch (degrees), orbit distance (m) and an optional target
## x,y,z (6 values). Re-call it every frame while settling; the rig eases back otherwise.
static func apply_camera_pose(main: Node, pose: PackedFloat32Array) -> bool:
	if pose.size() != CAM_POSE_PARTS and pose.size() != CAM_POSE_TARGET_PARTS:
		return false
	var rig: Object = main.get("_camera_rig") as Object
	if rig == null:
		return false
	rig.set("_yaw", deg_to_rad(pose[CAM_YAW_INDEX]))
	rig.set("_pitch", deg_to_rad(pose[CAM_PITCH_INDEX]))
	rig.set("_distance", pose[CAM_DISTANCE_INDEX])
	if pose.size() == CAM_POSE_TARGET_PARTS:
		rig.set("_target", Vector3(pose[CAM_TARGET_X_INDEX], pose[CAM_TARGET_X_INDEX + 1], pose[CAM_TARGET_X_INDEX + 2]))
	return true


## Main's skybox: an optional theme id ("" keeps the current one) and an optional cycle phase in
## [0, 1) (negative keeps the running clock). False when the sky is missing or the theme unknown.
static func apply_sky(main: Node, theme_id: String, phase: float) -> bool:
	var skybox: Object = main.get("_skybox") as Object
	if skybox == null:
		return false
	if not theme_id.is_empty() and not bool(skybox.call(&"set_theme_by_id", theme_id)):
		return false
	if phase >= 0.0:
		skybox.call(&"set_cycle_phase", phase)
	return true


## True when the command line names an explicit --port=<n>.
static func has_cli_port(user_args: PackedStringArray) -> bool:
	for arg: String in user_args:
		if arg.begins_with(PORT_ARG_PREFIX):
			return true
	return false


## A currently bindable UDP port in [FREE_PORT_MIN, FREE_PORT_MIN + SPAN), or 0.
## Net.host_game() uses it in probe mode so agent-run hosts (benches, tool
## scenes) never collide with each other or with the ENet acceptance harness.
static func free_udp_port() -> int:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	for _try: int in FREE_PORT_TRIES:
		var port: int = FREE_PORT_MIN + rng.randi() % FREE_PORT_SPAN
		var probe: PacketPeerUDP = PacketPeerUDP.new()
		var err: Error = probe.bind(port)
		probe.close()
		if err == OK:
			return port
	return 0
