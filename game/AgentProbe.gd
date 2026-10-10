class_name AgentProbe
extends RefCounted
## Agent probe mode: agent-launched Godot runs (tools/*.tscn scenes, or any run
## passing `-- --agent-probe`) must never disturb the owner: tiny window, no
## focus, muted, and the mouse is never captured (Bontago-fca.1). Pure static
## helpers; Settings._ready() calls apply() once at startup.
##   godot --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy \
##     --path . res://tools/x.tscn -- --agent-probe [--render-size=1920x1080]

const FLAG: String = "--agent-probe"
const RENDER_SIZE_PREFIX: String = "--render-size="
const TOOLS_SCENE_PREFIX: String = "res://tools/"
## Benchmarks under tests/bench are agent runs too (session debrief 2026-10-01).
const BENCH_SCENE_PREFIX: String = "res://tests/bench/"
const QUIT_ON_MENU_FLAG: String = "--quit-on-menu"
const STARTUP_LINE_FORMAT: String = "AGENT_PROBE startup first_frame_ms=%d menu_ready_ms=%d"
const MENU_MISSING_MS: int = -1
const MENU_TIMEOUT_EXIT_CODE: int = 1
## DECISION: the "menu never appeared" timeout reuses the loading screen's
## ready timeout instead of a new tunable.
## Loaded lazily (load(), only under --quit-on-menu) and matched by script path
## so this autoload-reachable file never pulls the menu or tuning graph in.
const LOADING_TUNING_PATH: String = "res://config/loading_screen_tuning.tres"
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

static var _forced: int = -1  # test seam: -1 = detect, 0 = off, 1 = on
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
					or arg.begins_with(BENCH_SCENE_PREFIX) or arg.begins_with("tests/bench/")):
			return true
	return false


static func is_active() -> bool:
	if _forced >= 0:
		return _forced == 1
	if _cached < 0:
		_cached = 1 if detect(OS.get_cmdline_args(), OS.get_cmdline_user_args()) else 0
	return _cached == 1


static func set_forced_for_test(state: int) -> void:
	_forced = state


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
	(Engine.get_main_loop() as SceneTree).quit(exit_code)


## Mouse-capture gate: sets the mode unless probe mode forbids capture.
static func set_mouse_mode(mode: Input.MouseMode) -> void:
	if is_active() and mode != Input.MOUSE_MODE_VISIBLE:
		mode = Input.MOUSE_MODE_VISIBLE
	Input.mouse_mode = mode


## A SubViewport of the --render-size (or fallback) attached to `parent`, so a
## bench/screenshot renders at full resolution while the OS window stays tiny.
static func make_render_viewport(parent: Node, fallback: Vector2i) -> SubViewport:
	var size: Vector2i = parse_render_size(OS.get_cmdline_user_args())
	if size == Vector2i.ZERO:
		size = fallback
	# One scaling rule (ui/UiScale.gd): same stretch maths as a real window.
	var vp: SubViewport = UiScale.make_viewport(size)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Share the root world: a bare SubViewport has no World3D, which breaks
	# get_viewport().world_3d users (raycasts, DiscMirror).
	vp.world_3d = parent.get_viewport().world_3d
	parent.add_child(vp)
	return vp


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
