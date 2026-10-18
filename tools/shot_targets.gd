class_name ShotTargets
extends RefCounted
## The shot list of tools/shot.gd: argument and JSON parsing (pure, unit-tested) and the per-target
## setup coroutines that put a live Main (or any scene) into the state a capture needs.
##
## Targets (the `target` key / --target=):
##   main_menu              the main menu home page.
##   menu     page=<name>   a main-menu page by PAGE_* name (home, join, debug ...) or `host_dialog`.
##   options  tab=<name>    the Options menu from the main menu; tab = a *TabButton name (audio, video ...).
##   lobby    kind=bots|hosted, seats=N, bots=B, style=classic|tiles|table|board, advanced=1
##   sandbox  preset=default|gift_demo|tower_topple|tutorial
##   match    mode=<name>, bots=B, seats=N, watch=1 (all-bot spectator match), follow=<bot index>,
##            difficulty=easy|normal|hard|mixed
##   scene    path=res://...tscn   any scene, instanced alone.
## Setup keys valid for every target: overlays=[f1,f2,f3,f4], f4_tab=<index|title>, hud=0|1,
## sky=<theme id>, time=<cycle phase 0..1>, cam=yaw,pitch,dist[,x,y,z], frames=<physics frames to wait>,
## speed=<Engine.time_scale while waiting>, name=<file stem>.

const TARGET_MAIN_MENU: String = "main_menu"
const TARGET_MENU: String = "menu"
const TARGET_OPTIONS: String = "options"
const TARGET_LOBBY: String = "lobby"
const TARGET_SANDBOX: String = "sandbox"
const TARGET_MATCH: String = "match"
const TARGET_SCENE: String = "scene"
const TARGETS: PackedStringArray = [
	TARGET_MAIN_MENU, TARGET_MENU, TARGET_OPTIONS, TARGET_LOBBY, TARGET_SANDBOX, TARGET_MATCH, TARGET_SCENE,
]
const LOBBY_BOTS: String = "bots"
const LOBBY_HOSTED: String = "hosted"
const PRESETS: PackedStringArray = ["default", "gift_demo", "tower_topple", "tutorial"]
const STYLES: PackedStringArray = ["classic", "tiles", "table", "board"]
## Overlay key -> Input Map action that toggles it.
const OVERLAY_ACTIONS: Dictionary = {
	"f1": &"perf_overlay_toggle",
	"f2": &"bot_cost_overlay_toggle",
	"f3": &"net_debug_toggle",
	"f4": &"tuning_panel_toggle",
}
const HUD_ACTION: StringName = &"hud_toggle"

const OUT_ARG: String = "--out="
const SIZES_ARG: String = "--render-size="
const SIZES_ALT_ARG: String = "--sizes="
const SHOTS_ARG: String = "--shots="
const SHEET_ARG: String = "--sheet"
const DEFAULT_SIZE: Vector2i = Vector2i(1920, 1080)
const DEFAULT_FRAMES: int = 90
const DEFAULT_SEATS: int = 2
const DEFAULT_WATCH_BOTS: int = 4
const DEFAULT_SPEED: float = 1.0
const MAX_FRAMES: int = 36000
const MAX_SPEED: float = 8.0
const CAM_MIN_PARTS: int = 3
const CAM_TARGET_PARTS: int = 6
const NO_VALUE: int = -1

const BOOT_FRAMES: int = 3
const STARTUP_WAIT_S: float = 1.5
const SETTLE_FRAMES: int = 6
const LONG_SETTLE_FRAMES: int = 30
const STATE_WAIT_TIMEOUT_S: float = 60.0
const PLAYER_NAME: String = "Shot"
const TAB_BUTTON_GLOB: String = "*TabButton"
const MAIN_SCENE: String = "res://game/main/Main.tscn"
const SHEET_COLUMNS: int = 3
const SHEET_GAP: int = 6
const SHEET_LABEL_HEIGHT: int = 24
const SHEET_MAX_W: int = 2600
const SHEET_MAX_H: int = 3000

## Keys a shot may carry; anything else is a typo and rejected.
const SHOT_KEYS: PackedStringArray = [
	"name", "target", "page", "tab", "kind", "seats", "bots", "style", "advanced", "preset", "mode", "watch",
	"follow", "difficulty", "path", "overlays", "f4_tab", "hud", "sky", "time", "cam", "frames", "speed",
]


# --- Argument parsing (pure) -------------------------------------------------------------------------

## Parses the user args into {error, out, sizes, sheet, shots}. `error` is empty on success. Single-shot
## flags (--target=lobby --seats=8 ...) are the defaults every --shots=<json file or inline json> entry
## overrides; with no --shots the flags describe the one shot.
static func parse_args(args: PackedStringArray, file_reader: Callable = Callable()) -> Dictionary:
	var result: Dictionary = {"error": "", "out": "", "sizes": [DEFAULT_SIZE], "sheet": false, "shots": []}
	result["out"] = _arg(args, OUT_ARG)
	if str(result["out"]).is_empty():
		return _failed(result, "missing --out=<dir>")
	var sizes_text: String = _arg(args, SIZES_ARG)
	if sizes_text.is_empty():
		sizes_text = _arg(args, SIZES_ALT_ARG)
	if not sizes_text.is_empty():
		var sizes: Array = parse_sizes(sizes_text)
		if sizes.is_empty():
			return _failed(result, "bad --render-size '%s', want WxH[,WxH...]" % sizes_text)
		result["sizes"] = sizes
	result["sheet"] = args.has(SHEET_ARG) or _arg(args, SHEET_ARG + "=") == "1"
	var defaults: Dictionary = {}
	for key: String in SHOT_KEYS:
		var text: String = _arg(args, "--" + key.replace("_", "-") + "=")
		if not text.is_empty():
			defaults[key] = text
	if args.has("--watch"):
		defaults["watch"] = "1"
	var raw_shots: Array = []
	var shots_text: String = _arg(args, SHOTS_ARG)
	if shots_text.is_empty():
		raw_shots.append({})
	else:
		var parsed: Dictionary = parse_shots_json(_read_shots_text(shots_text, file_reader))
		if not str(parsed["error"]).is_empty():
			return _failed(result, str(parsed["error"]))
		raw_shots = parsed["shots"]
	var shots: Array[Dictionary] = []
	for raw: Variant in raw_shots:
		var merged: Dictionary = defaults.duplicate()
		merged.merge(raw as Dictionary, true)
		var shot: Dictionary = normalize_shot(merged)
		if not str(shot["error"]).is_empty():
			return _failed(result, "shot %d: %s" % [shots.size() + 1, str(shot["error"])])
		shots.append(shot)
	_uniquify_names(shots)
	result["shots"] = shots
	return result


## "1280x720,1920x1080" -> [Vector2i, ...]; empty on any bad entry.
static func parse_sizes(text: String) -> Array:
	var sizes: Array = []
	for part: String in text.split(",", false):
		var wh: PackedStringArray = part.strip_edges().to_lower().split("x")
		if wh.size() != 2 or not wh[0].is_valid_int() or not wh[1].is_valid_int() or int(wh[0]) <= 0 or int(wh[1]) <= 0:
			return []
		var size: Vector2i = Vector2i(int(wh[0]), int(wh[1]))
		if not sizes.has(size):
			sizes.append(size)
	return sizes


## A JSON array of shot objects, or {"shots": [...]}. -> {error, shots}.
static func parse_shots_json(text: String) -> Dictionary:
	var result: Dictionary = {"error": "", "shots": []}
	if text.is_empty():
		return _failed(result, "--shots is empty or unreadable")
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _failed(result, "--shots json line %d: %s" % [json.get_error_line(), json.get_error_message()])
	var data: Variant = json.data
	if data is Dictionary and (data as Dictionary).has("shots"):
		data = (data as Dictionary)["shots"]
	if not data is Array or (data as Array).is_empty():
		return _failed(result, "--shots must be a non-empty array of shot objects")
	for entry: Variant in data as Array:
		if not entry is Dictionary:
			return _failed(result, "--shots entries must be objects")
		result["shots"].append(entry)
	return result


## One raw shot (string or JSON-typed values) -> a normalised, validated shot Dictionary with typed fields
## and `error` set when invalid. Pure: touches no scene.
static func normalize_shot(raw: Dictionary) -> Dictionary:
	var shot: Dictionary = {
		"error": "", "name": "", "target": "", "page": "", "tab": "", "kind": LOBBY_BOTS,
		"seats": NO_VALUE, "bots": NO_VALUE, "style": 0, "advanced": false, "preset": "default", "mode": "",
		"watch": false, "follow": NO_VALUE, "difficulty": "", "path": "", "overlays": PackedStringArray(),
		"f4_tab": "", "hud": NO_VALUE, "sky": "", "time": -1.0, "cam": PackedFloat32Array(),
		"frames": DEFAULT_FRAMES, "speed": DEFAULT_SPEED,
	}
	for key: Variant in raw:
		if not SHOT_KEYS.has(str(key)):
			return _failed(shot, "unknown key '%s'" % key)
	var target: String = str(raw.get("target", "")).to_lower()
	if not TARGETS.has(target):
		return _failed(shot, "target must be one of %s (got '%s')" % [", ".join(TARGETS), target])
	shot["target"] = target
	for key: String in ["name", "page", "tab", "preset", "mode", "difficulty", "path", "sky", "f4_tab"]:
		if raw.has(key):
			shot[key] = str(raw[key]).strip_edges()
	for key: String in ["seats", "bots", "follow", "frames"]:
		if raw.has(key):
			var number: Variant = _as_int(raw[key])
			if number == null:
				return _failed(shot, "%s must be an integer" % key)
			shot[key] = int(number)
	if int(shot["frames"]) < 0 or int(shot["frames"]) > MAX_FRAMES:
		return _failed(shot, "frames must be 0..%d" % MAX_FRAMES)
	for key: String in ["advanced", "watch"]:
		if raw.has(key):
			shot[key] = _as_bool(raw[key])
	if raw.has("hud"):
		shot["hud"] = 1 if _as_bool(raw["hud"]) else 0
	if raw.has("time"):
		var phase: String = str(raw["time"])
		if not phase.is_valid_float():
			return _failed(shot, "time must be a cycle phase 0..1")
		shot["time"] = float(phase)
	if raw.has("speed"):
		var speed: String = str(raw["speed"])
		if not speed.is_valid_float() or float(speed) <= 0.0 or float(speed) > MAX_SPEED:
			return _failed(shot, "speed must be 0..%s" % MAX_SPEED)
		shot["speed"] = float(speed)
	if raw.has("kind"):
		shot["kind"] = str(raw["kind"]).to_lower()
		if shot["kind"] != LOBBY_BOTS and shot["kind"] != LOBBY_HOSTED:
			return _failed(shot, "kind must be bots or hosted")
	if raw.has("style"):
		var style: int = STYLES.find(str(raw["style"]).to_lower())
		if style < 0 and str(raw["style"]).is_valid_int():
			style = int(str(raw["style"]))
		if style < 0 or style >= STYLES.size():
			return _failed(shot, "style must be one of %s" % ", ".join(STYLES))
		shot["style"] = style
	if not PRESETS.has(str(shot["preset"])):
		return _failed(shot, "preset must be one of %s" % ", ".join(PRESETS))
	if raw.has("overlays"):
		var overlays: Variant = _as_string_list(raw["overlays"])
		for overlay: String in overlays as PackedStringArray:
			if not OVERLAY_ACTIONS.has(overlay):
				return _failed(shot, "overlay '%s' must be one of f1,f2,f3,f4" % overlay)
		shot["overlays"] = overlays
	if not str(shot["f4_tab"]).is_empty():
		var with_f4: PackedStringArray = shot["overlays"]
		if not with_f4.has("f4"):
			with_f4.append("f4")
		shot["overlays"] = with_f4
	if raw.has("cam"):
		var cam: PackedFloat32Array = parse_cam(raw["cam"])
		if cam.is_empty():
			return _failed(shot, "cam must be yaw,pitch,distance[,x,y,z]")
		shot["cam"] = cam
	if target == TARGET_SCENE and not str(shot["path"]).begins_with("res://"):
		return _failed(shot, "scene target needs path=res://...tscn")
	if str(shot["mode"]) != "" and WatchBotsOptions.mode_from_text(str(shot["mode"]).to_lower()) < 0:
		return _failed(shot, "unknown mode '%s'" % shot["mode"])
	if str(shot["difficulty"]) != "" and WatchBotsOptions.difficulty_from_text(str(shot["difficulty"]).to_lower()) < 0:
		return _failed(shot, "unknown difficulty '%s'" % shot["difficulty"])
	if int(shot["follow"]) != NO_VALUE and not bool(shot["watch"]):
		return _failed(shot, "follow needs watch=1 (the spectator camera)")
	if target == TARGET_MATCH and bool(shot["watch"]) and int(shot["bots"]) == NO_VALUE:
		shot["bots"] = DEFAULT_WATCH_BOTS
	shot["seats"] = _resolved_seats(shot)
	if str(shot["name"]).is_empty():
		shot["name"] = default_name(shot)
	shot["name"] = sanitize_name(str(shot["name"]))
	return shot


## "yaw,pitch,distance[,tx,ty,tz]" (string or JSON array) -> floats; empty when malformed.
static func parse_cam(value: Variant) -> PackedFloat32Array:
	var parts: PackedStringArray = PackedStringArray()
	if value is Array:
		for item: Variant in value as Array:
			parts.append(str(item))
	else:
		parts = str(value).split(",")
	var out: PackedFloat32Array = PackedFloat32Array()
	if parts.size() != CAM_MIN_PARTS and parts.size() != CAM_TARGET_PARTS:
		return out
	for part: String in parts:
		if not part.strip_edges().is_valid_float():
			return PackedFloat32Array()
		out.append(float(part.strip_edges()))
	return out


static func default_name(shot: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray([str(shot["target"])])
	for key: String in ["page", "tab", "preset", "mode"]:
		var text: String = str(shot[key])
		if not text.is_empty() and not (key == "preset" and text == "default"):
			parts.append(text)
	if str(shot["target"]) == TARGET_LOBBY:
		parts.append(str(shot["kind"]))
		parts.append("%dseats" % int(shot["seats"]))
		parts.append(str(STYLES[int(shot["style"])]))
	if str(shot["target"]) == TARGET_SCENE:
		parts.append(str(shot["path"]).get_file().get_basename())
	if bool(shot["watch"]):
		parts.append("watch%d" % int(shot["bots"]))
	return "_".join(parts)


static func sanitize_name(text: String) -> String:
	var out: String = ""
	for i: int in text.length():
		var c: String = text[i]
		out += c if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "_" or c == "-" else "_"
	return out


## The PNG file name of one shot at one render size.
static func file_name(shot: Dictionary, size: Vector2i) -> String:
	return "%s_%dx%d.png" % [str(shot["name"]), size.x, size.y]


## Sheet grid for `count` equally sized shots: columns, cell size, rows per page, pages. Every page is
## at most SHEET_MAX_W x SHEET_MAX_H.
static func sheet_layout(count: int, shot_size: Vector2i) -> Dictionary:
	var columns: int = clampi(count, 1, SHEET_COLUMNS)
	var cell_w: int = mini(int((SHEET_MAX_W - SHEET_GAP * (columns + 1)) / float(columns)), maxi(shot_size.x, 1))
	var thumb_h: int = maxi(1, int(round(float(shot_size.y) * float(cell_w) / float(maxi(shot_size.x, 1)))))
	var row_h: int = thumb_h + SHEET_LABEL_HEIGHT
	var rows_per_page: int = maxi(1, int((SHEET_MAX_H - SHEET_GAP) / float(row_h + SHEET_GAP)))
	var per_page: int = rows_per_page * columns
	return {
		"columns": columns, "cell_w": cell_w, "thumb_h": thumb_h, "row_h": row_h,
		"per_page": per_page, "pages": ceili(float(maxi(count, 1)) / float(per_page)),
	}


# --- Per-target setup (live scene) -----------------------------------------------------------------------

## Brings `main` (a fresh or reset Main under `vp`) to the shot's state, then settles `frames` physics
## frames while re-applying the camera / sky. Returns "" on success or the reason it failed.
static func setup(host: Node, vp: SubViewport, main: Node, shot: Dictionary) -> String:
	var error: String = ""
	match str(shot["target"]):
		TARGET_MAIN_MENU:
			error = await _menu_page(host, main, "home")
		TARGET_MENU:
			error = await _menu_page(host, main, str(shot["page"]) if not str(shot["page"]).is_empty() else "home")
		TARGET_OPTIONS:
			error = await _options(host, main, str(shot["tab"]))
		TARGET_LOBBY:
			error = await _lobby(host, main, shot)
		TARGET_SANDBOX:
			error = await _sandbox(host, main, str(shot["preset"]))
		TARGET_MATCH:
			error = await _match(host, main, shot)
	if not error.is_empty():
		return error
	return await finish_setup(host, vp, main, shot)


## The setup shared by every target: overlays, HUD, f4 tab, sky/time, camera, wait frames.
static func finish_setup(host: Node, vp: SubViewport, main: Node, shot: Dictionary) -> String:
	var overlays: PackedStringArray = shot["overlays"]
	for overlay: String in overlays:
		AgentProbe.press_action(vp, OVERLAY_ACTIONS[overlay])
		await settle(host, SETTLE_FRAMES)
	if int(shot["hud"]) == 0:
		AgentProbe.press_action(vp, HUD_ACTION)
		await settle(host, 1)
	if not str(shot["f4_tab"]).is_empty():
		var error: String = await _select_f4_tab(host, main, str(shot["f4_tab"]))
		if not error.is_empty():
			return error
	if not str(shot["sky"]).is_empty() and not AgentProbe.apply_sky(main, str(shot["sky"]), -1.0):
		return "unknown sky '%s' (or no skybox in this scene)" % shot["sky"]
	var cam: PackedFloat32Array = shot["cam"]
	var phase: float = float(shot["time"])
	var follow: int = int(shot["follow"])
	if follow >= 0:
		var spectator: Object = main.get("_spectator") as Object
		if spectator == null:
			return "follow needs a watch match (no spectator)"
		for _i: int in range(follow + 1):
			spectator.call(&"follow_next")
	var speed: float = float(shot["speed"])
	Engine.time_scale = speed
	for _i: int in range(int(shot["frames"])):
		_reapply(main, cam, phase)
		await host.get_tree().physics_frame
	Engine.time_scale = DEFAULT_SPEED
	_reapply(main, cam, phase)
	await settle(host, 1)
	return ""


static func _reapply(main: Node, cam: PackedFloat32Array, phase: float) -> void:
	if not cam.is_empty():
		AgentProbe.apply_camera_pose(main, cam)
	if phase >= 0.0:
		AgentProbe.apply_sky(main, "", phase)


static func _select_f4_tab(host: Node, main: Node, tab: String) -> String:
	var panels: Array[Node] = main.find_children("*", "TuningPanel", true, false)
	if panels.is_empty():
		return "f4_tab: no TuningPanel in this scene"
	var tabs: TabContainer = (panels[0] as Object).get("_tab_container") as TabContainer
	if tabs == null:
		return "f4_tab: the panel has no tabs (is it open?)"
	var index: int = int(tab) if tab.is_valid_int() else NO_VALUE
	if index == NO_VALUE:
		for i: int in tabs.get_tab_count():
			if tabs.get_tab_title(i).to_lower().contains(tab.to_lower()):
				index = i
				break
	if index < 0 or index >= tabs.get_tab_count():
		return "f4_tab '%s' not found (%d tabs)" % [tab, tabs.get_tab_count()]
	tabs.current_tab = index
	await settle(host, SETTLE_FRAMES)
	return ""


static func _menu_page(host: Node, main: Node, page: String) -> String:
	var menu: MainMenu = main.get("_main_menu") as MainMenu
	if menu == null:
		return "Main has no main menu"
	menu.set_debug_entry_enabled(true)  # PAGE_DEBUG is only reachable with the debug entry on
	if page == "host_dialog":
		menu.call("_on_host_pressed")
		await settle(host, LONG_SETTLE_FRAMES)
		return ""
	var constants: Dictionary = (MainMenu as GDScript).get_script_constant_map()
	var key: String = "PAGE_" + page.to_upper()
	if not constants.has(key) or not constants[key] is int:
		var known: PackedStringArray = PackedStringArray()
		for name: Variant in constants:
			if str(name).begins_with("PAGE_"):
				known.append(str(name).trim_prefix("PAGE_").to_lower())
		return "unknown menu page '%s' (known: %s)" % [page, ", ".join(known)]
	menu.call("_set_page", int(constants[key]))
	await settle(host, LONG_SETTLE_FRAMES)
	return ""


static func _options(host: Node, main: Node, tab: String) -> String:
	var menu: MainMenu = main.get("_main_menu") as MainMenu
	if menu == null:
		return "Main has no main menu"
	menu.call("_on_options_pressed")
	await settle(host, SETTLE_FRAMES)
	var options: OptionsMenu = menu.get("_options_menu") as OptionsMenu
	if options == null:
		return "the Options menu did not open"
	if tab.is_empty():
		return ""
	for node: Node in options.find_children(TAB_BUTTON_GLOB, "Button", true, false):
		if node.name.to_lower().trim_suffix("tabbutton") == tab.to_lower():
			(node as Button).button_pressed = true
			await settle(host, SETTLE_FRAMES)
			return ""
	return "options tab '%s' not found" % tab


static func _lobby(host: Node, main: Node, shot: Dictionary) -> String:
	var error: String = await _host_lobby(host, main, shot)
	if not error.is_empty():
		return error
	var lobby: Lobby = main.get("_lobby") as Lobby
	if lobby == null:
		return "the lobby did not appear"
	if bool(shot["advanced"]):
		for section: UiSection in lobby.call("_sections"):
			section.set_advanced_open(true)
	await settle(host, LONG_SETTLE_FRAMES)
	return ""


## Opens a lobby the way the game does: the vs-bots menu entry, or a direct host, then publishes the
## shot's seat count and bot count as the lobby settings.
static func _host_lobby(host: Node, main: Node, shot: Dictionary) -> String:
	LobbySeatVariants.chosen = int(shot["style"])
	var config: MatchConfig = (main.get("match_config") as MatchConfig).duplicate(true) as MatchConfig
	config.player_count = int(shot["seats"])
	config.ai_count = clampi(maxi(int(shot["bots"]), 0), 0, config.player_count - 1)
	if not str(shot["mode"]).is_empty():
		config.game_mode = MatchConfig.resolve_game_mode(WatchBotsOptions.mode_from_text(str(shot["mode"]).to_lower()))
	if str(shot["kind"]) == LOBBY_BOTS:
		var menu: MainMenu = main.get("_main_menu") as MainMenu
		if menu == null:
			return "Main has no main menu to start vs-bots from"
		menu.bots_requested.emit(PLAYER_NAME)
	else:
		var err: Error = Net.host_game(0, PLAYER_NAME, false)
		if err != OK:
			return "Net.host_game failed: %s" % error_string(err)
	if not await wait_for(host, func() -> bool: return main.get("_lobby") != null):
		return "the lobby did not appear within %ds" % int(STATE_WAIT_TIMEOUT_S)
	await settle(host, SETTLE_FRAMES)
	Net.set_lobby_data(config.to_dict())
	return ""


static func _sandbox(host: Node, main: Node, preset: String) -> String:
	var method: StringName = &"start_sandbox_from_menu"
	var property: String = "_sandbox"
	match preset:
		"gift_demo":
			method = &"start_gift_demo_from_menu"
		"tower_topple":
			method = &"start_tower_topple_from_menu"
		"tutorial":
			method = &"start_tutorial_from_menu"
			property = "_tutorial"
	main.call(method)
	if not await wait_for(host, func() -> bool: return main.get(property) != null):
		return "%s did not start" % preset
	var loading: LoadingScreen = main.get("_loading_screen") as LoadingScreen
	if loading != null:
		await wait_for(host, func() -> bool: return not loading.visible)
	await settle(host, LONG_SETTLE_FRAMES)
	return ""


static func _match(host: Node, main: Node, shot: Dictionary) -> String:
	if bool(shot["watch"]):
		DebugMode.set_override_for_test(true)
		var args: PackedStringArray = PackedStringArray(["--watch-bots=%d" % int(shot["bots"])])
		if not str(shot["mode"]).is_empty():
			args.append("--mode=" + str(shot["mode"]))
		if not str(shot["difficulty"]).is_empty():
			args.append("--difficulty=" + str(shot["difficulty"]))
		var options: WatchBotsOptions = WatchBotsOptions.from_args(args, WatchBotsOptions.defaults())
		main.call(&"start_watch_bots", options)
	else:
		var error: String = await _host_lobby(host, main, shot)
		if not error.is_empty():
			return error
		var lobby: Lobby = main.get("_lobby") as Lobby
		(lobby.get("_ready_check") as CheckButton).button_pressed = true
		await settle(host, SETTLE_FRAMES)
		lobby.call("_on_start_pressed")
	var loading: LoadingScreen = main.get("_loading_screen") as LoadingScreen
	if loading != null and loading.ready_gate_armed():
		await wait_for(host, func() -> bool: return loading.accepts_ready_input())
		loading.press_ready()
	if bool(shot["watch"]) and not await wait_for(host, func() -> bool: return main.get("_spectator") != null):
		return "the watch match built no spectator (is debug mode on?)"
	if not await wait_for(host, func() -> bool: return Match.state() == Match.State.PLAYING):
		return "the match did not reach PLAYING within %ds" % int(STATE_WAIT_TIMEOUT_S)
	if loading != null:
		await wait_for(host, func() -> bool: return not loading.visible)
	await settle(host, LONG_SETTLE_FRAMES)
	return ""


## Returns a live Main to its main menu through the pause menu's Leave handler, which frees an offline
## sandbox, leaves any hosted session and aborts the match (the same path a player takes).
static func return_to_menu(host: Node, main: Node) -> void:
	Engine.time_scale = DEFAULT_SPEED
	var tutorial: Object = main.get("_tutorial") as Object
	if tutorial != null:
		tutorial.call("_end_tutorial")
	main.call("_on_pause_leave_requested")
	await settle(host, LONG_SETTLE_FRAMES)


static func settle(host: Node, frames: int) -> void:
	for _i: int in range(frames):
		await host.get_tree().process_frame


## True when `condition` became true before STATE_WAIT_TIMEOUT_S.
static func wait_for(host: Node, condition: Callable) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(STATE_WAIT_TIMEOUT_S * 1000.0)
	while not bool(condition.call()) and Time.get_ticks_msec() < deadline:
		await host.get_tree().process_frame
	return bool(condition.call())


# --- helpers ----------------------------------------------------------------------------------------------

static func _resolved_seats(shot: Dictionary) -> int:
	var seats: int = int(shot["seats"])
	if seats == NO_VALUE:
		seats = maxi(DEFAULT_SEATS, int(shot["bots"]) + 1)
	return clampi(seats, MatchConfig.PLAYER_COUNT_MIN, MatchConfig.PLAYER_COUNT_MAX)


static func _uniquify_names(shots: Array[Dictionary]) -> void:
	var seen: Dictionary = {}
	for shot: Dictionary in shots:
		var base: String = str(shot["name"])
		var count: int = int(seen.get(base, 0)) + 1
		seen[base] = count
		if count > 1:
			shot["name"] = "%s_%d" % [base, count]


static func _read_shots_text(value: String, file_reader: Callable) -> String:
	var trimmed: String = value.strip_edges()
	if trimmed.begins_with("[") or trimmed.begins_with("{"):
		return trimmed
	if file_reader.is_valid():
		return str(file_reader.call(value))
	return FileAccess.get_file_as_string(value)


static func _as_int(value: Variant) -> Variant:
	if value is int:
		return value
	if value is float and is_equal_approx(float(value), roundf(float(value))):
		return int(value)
	if value is String and (value as String).is_valid_int():
		return int(value)
	return null


static func _as_bool(value: Variant) -> bool:
	if value is bool:
		return value
	var text: String = str(value).to_lower()
	return text == "1" or text == "true" or text == "yes" or text == "on"


static func _as_string_list(value: Variant) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var items: Array = (value as Array) if value is Array else str(value).split(",", false)
	for item: Variant in items:
		var text: String = str(item).strip_edges().to_lower()
		if not text.is_empty():
			out.append(text)
	return out


static func _arg(args: PackedStringArray, prefix: String) -> String:
	for a: String in args:
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return ""


static func _failed(result: Dictionary, message: String) -> Dictionary:
	result["error"] = message
	return result
