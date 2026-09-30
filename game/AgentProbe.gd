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
## DECISION: probe window size; tools needing a real render resolution use
## make_render_viewport() instead of a big window.
const WINDOW_SIZE: Vector2i = Vector2i(320, 180)

static var _forced: int = -1  # test seam: -1 = detect, 0 = off, 1 = on
static var _cached: int = -1


## Pure detection: user args containing the flag, or any arg naming a scene
## under res://tools/ (a game scene run from the editor is unaffected).
static func detect(cmdline_args: PackedStringArray, user_args: PackedStringArray) -> bool:
	if user_args.has(FLAG) or cmdline_args.has(FLAG):
		return true
	for arg: String in cmdline_args:
		if (arg.ends_with(".tscn") or arg.ends_with(".scn")) \
				and (arg.begins_with(TOOLS_SCENE_PREFIX) or arg.begins_with("tools/")):
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
	var vp: SubViewport = SubViewport.new()
	vp.size = size
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Share the root world: a bare SubViewport has no World3D, which breaks
	# get_viewport().world_3d users (raycasts, DiscMirror).
	vp.world_3d = parent.get_viewport().world_3d
	parent.add_child(vp)
	return vp
