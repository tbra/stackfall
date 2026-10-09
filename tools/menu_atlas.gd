extends Node
## Menu atlas (Bontago-fca.71): one screenshot of every menu/page at each
## requested render size, a paginated labelled contact sheet per size and an
## index.md (including every skipped item with its reason).
##
##   godot --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy \
##     --path <checkout> res://tools/menu_atlas.tscn -- --agent-probe --out=<dir> \
##     [--sizes=1280x720,1920x1080,3440x1440] [--only=<name filter>]
##
## --out    absolute output directory (required).
## --sizes  comma list of WxH render sizes (default 1280x720,1920x1080). Each size renders
##          into its own AgentProbe SubViewport; the OS window is never resized.
## --only   keep only shots whose "menu__page" name contains this substring.
##
## Pages are enumerated from the scenes themselves (MainMenu PAGE_* constants, the
## OptionsMenu tab buttons, Lobby sections, Tutorial steps, TuningPanel tabs); the
## explicit entries (results variants, loading, pause, overlays) each carry a comment.
## Prints `MENU_ATLAS done shots=N skipped=M out=<dir>` and exits 0 (1 on failure).

const OUT_ARG: String = "--out="
const SIZES_ARG: String = "--sizes="
const ONLY_ARG: String = "--only="
const DEFAULT_SIZES: String = "1280x720,1920x1080"
const FAIL_EXIT_CODE: int = 1
const BOOT_FRAMES: int = 3
const STARTUP_WAIT_S: float = 1.5
const SETTLE_FRAMES: int = 6
const LONG_SETTLE_FRAMES: int = 30
const STATE_WAIT_TIMEOUT_S: float = 30.0
const PLAYING_WAIT_FRAMES: int = 90
const PLAYER_NAME: String = "Atlas"
const SPLIT: String = "__"
const INDEX_FILE: String = "index.md"
## Contact sheet layout (hard cap per page is ContactSheet.MAX_SHEET_PX_W/H).
const SHEET_COLUMNS: int = 3
const SHEET_GAP: int = 6
const LABEL_HEIGHT: int = 24
const LABEL_FONT_SIZE: int = 15
const LABEL_BG: Color = Color(0.1, 0.1, 0.1, 1.0)
const LABEL_FG: Color = Color(0.92, 0.92, 0.92, 1.0)
const LABEL_FRAMES: int = 2
const MAIN_SCENE: String = "res://game/Main.tscn"
const TAB_BUTTON_GLOB: String = "*TabButton"

var _out: String = ""
var _only: String = ""
var _sizes: Array[Vector2i] = []
var _vp: SubViewport = null
var _main: Node = null
var _size: Vector2i = Vector2i.ZERO
## One dict per saved shot: {menu, page, size, file}.
var _shots: Array[Dictionary] = []
## One dict per skipped item: {menu, page, reason}.
var _skipped: Array[Dictionary] = []


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_out = _arg(args, OUT_ARG)
	if _out.is_empty():
		_fail("missing --out=<dir>")
		return
	_only = _arg(args, ONLY_ARG)
	var sizes_text: String = _arg(args, SIZES_ARG)
	if sizes_text.is_empty():
		sizes_text = DEFAULT_SIZES
	for part: String in sizes_text.split(","):
		var wh: PackedStringArray = part.to_lower().split("x")
		if wh.size() != 2 or not wh[0].is_valid_int() or not wh[1].is_valid_int():
			_fail("bad --sizes entry '%s'" % part)
			return
		_sizes.append(Vector2i(int(wh[0]), int(wh[1])))
	DirAccess.make_dir_recursive_absolute(_out)
	# DECISION: the F3/F4 debug overlays are gated on DebugMode (editor-only by default);
	# the atlas must show them, so force it on through the documented test seam.
	DebugMode.set_override_for_test(true)
	for size: Vector2i in _sizes:
		_size = size
		await _run_size()
	await _build_sheets()
	_write_index()
	print("MENU_ATLAS done shots=%d skipped=%d out=%s" % [_shots.size(), _skipped_unique(), _out])
	get_tree().quit()


# --- one render size ------------------------------------------------------------

func _run_size() -> void:
	# --render-size is deliberately not passed: make_render_viewport uses the fallback.
	_vp = AgentProbe.make_render_viewport(self, _size)
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_vp.add_child(_main)
	for _i: int in range(BOOT_FRAMES):
		await get_tree().process_frame
	await get_tree().create_timer(STARTUP_WAIT_S).timeout
	await _section_main_menu()
	await _section_bots_match()
	await _section_tutorial()
	await _section_sandbox()
	await _to_menu()
	_main.queue_free()
	_vp.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


## Returns the live Main to its main menu (leaves any session / tears the world down).
func _to_menu() -> void:
	var tutorial: Tutorial = _main.get("_tutorial") as Tutorial
	if tutorial != null:
		tutorial.call("_end_tutorial")
	if Net.mode() != Net.Mode.OFFLINE:
		Net.leave()
	if Match.state() != Match.State.LOBBY:
		Match.abort_match()
	await _settle(LONG_SETTLE_FRAMES)


# --- main menu, options, host dialog ----------------------------------------------

func _section_main_menu() -> void:
	var menu: MainMenu = _main.get("_main_menu") as MainMenu
	if menu == null:
		_skip("main_menu", "*", "Main did not create a MainMenu")
		return
	# Pages enumerated from MainMenu's own PAGE_* constants (new pages are picked up).
	var pages: Dictionary = {}
	var constants: Dictionary = (MainMenu as GDScript).get_script_constant_map()
	for key: Variant in constants:
		if String(key).begins_with("PAGE_") and constants[key] is int:
			pages[int(constants[key])] = String(key).trim_prefix("PAGE_").to_lower()
	var values: Array = pages.keys()
	values.sort()
	menu.set_debug_entry_enabled(true)  # PAGE_DEBUG is only reachable with the debug entry on
	for value: int in values:
		var page: String = String(pages[value])
		menu.call("_set_page", value)
		if value == MainMenu.PAGE_JOIN:
			menu.set("_join_steam_tab", false)
			menu.call("_set_page", value)
			page = "join_lan"
		await _shot("main_menu", page)
		if value == MainMenu.PAGE_JOIN:
			if bool(menu.call("_steam_available")):
				menu.call("_on_join_steam_tab_pressed")
				await _shot("main_menu", "join_steam")
			else:
				_skip("main_menu", "join_steam", "Steam is not available in an agent run (no GodotSteam init)")
	menu.call("_set_page", MainMenu.PAGE_HOME)
	# Host dialog: opened exactly like the Host button; closed again without confirming.
	menu.call("_on_host_pressed")
	await _settle(LONG_SETTLE_FRAMES)
	var dialog: ConfirmationDialog = menu.get("_host_dialog") as ConfirmationDialog
	# The popup never renders into the SubViewport capture (verified: the shot shows the bare menu).
	_skip("main_menu", "host_dialog", "ConfirmationDialog popup is not rendered into the SubViewport capture")
	dialog.hide()
	await _section_options(menu)
	if is_instance_valid(menu):
		menu.call("_set_page", MainMenu.PAGE_HOME)


func _section_options(menu: MainMenu) -> void:
	menu.call("_on_options_pressed")
	await _settle(SETTLE_FRAMES)
	var options: OptionsMenu = menu.get("_options_menu") as OptionsMenu
	if options == null:
		_skip("options", "*", "OptionsMenu did not open from the main menu")
		return
	await _options_tabs(options, "options")
	options.emit_signal("closed")
	await _settle(SETTLE_FRAMES)


## Every tab button of an OptionsMenu (found by the *TabButton naming), keyboard/mouse
## then gamepad device view, scrolled top then bottom; plus the rebind-listening view.
func _options_tabs(options: OptionsMenu, menu_name: String) -> void:
	var buttons: Array[Node] = options.find_children(TAB_BUTTON_GLOB, "Button", true, false)
	for node: Node in buttons:
		var button: Button = node as Button
		var tab: String = button.name.trim_suffix("TabButton").to_lower()
		button.button_pressed = true
		await _settle(SETTLE_FRAMES)
		if tab == "controls":
			await _options_controls(options, menu_name)
			continue
		await _shot(menu_name, tab)
		var scroll: ScrollContainer = _first_scroll(options)
		if scroll != null and scroll.get_v_scroll_bar().max_value > scroll.size.y:
			scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
			await _settle(SETTLE_FRAMES)
			await _shot(menu_name, tab + "_scrolled_bottom")
			scroll.scroll_vertical = 0
	if buttons.is_empty():
		await _shot(menu_name, "default")


func _options_controls(options: OptionsMenu, menu_name: String) -> void:
	await _shot(menu_name, "controls_keyboard")
	var rows: Array[KeyRebindRow] = options.rebind_rows()
	if not rows.is_empty():
		# Key rebind view: the first row armed to capture the next input.
		rows[0].rebind_button().pressed.emit()
		await _settle(SETTLE_FRAMES)
		await _shot(menu_name, "controls_rebind_listening")
		rows[0].call("_cancel_listening")
	Settings.set_active_input_device_for_test(Settings.DEVICE_GAMEPAD)
	await _settle(SETTLE_FRAMES)
	await _shot(menu_name, "controls_gamepad")
	Settings.set_active_input_device_for_test(Settings.DEVICE_KEYBOARD_MOUSE)
	await _settle(SETTLE_FRAMES)


func _first_scroll(root: Node) -> ScrollContainer:
	var found: Array[Node] = root.find_children("*", "ScrollContainer", true, false)
	for node: Node in found:
		if (node as ScrollContainer).is_visible_in_tree():
			return node as ScrollContainer
	return null


# --- lobby, loading, match overlays ------------------------------------------------

func _section_bots_match() -> void:
	var menu: MainMenu = _main.get("_main_menu") as MainMenu
	if menu == null:
		_skip("lobby", "*", "no main menu to start a bots game from")
		return
	# Play local -> Vs bots: the real path (host 1 human + 1 bot, lobby editable).
	menu.bots_requested.emit(PLAYER_NAME)
	await _wait_for(func() -> bool: return _main.get("_lobby") != null)
	await _settle(LONG_SETTLE_FRAMES)
	var lobby: Lobby = _main.get("_lobby") as Lobby
	if lobby == null:
		_skip("lobby", "*", "lobby did not appear after bots_requested")
		return
	await _shot("lobby", "default")
	# Sections are enumerated from the Lobby; only their Advanced block collapses.
	var sections: Array = lobby.call("_sections")
	for section: LobbySection in sections:
		section.set_advanced_open(true)
	await _settle(SETTLE_FRAMES)
	await _shot("lobby", "advanced_open")
	var scroll: ScrollContainer = lobby.get("_settings_scroll") as ScrollContainer
	if scroll != null and scroll.get_v_scroll_bar().max_value > scroll.size.y:
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
		await _settle(SETTLE_FRAMES)
		await _shot("lobby", "advanced_open_scrolled_bottom")
	for section: LobbySection in sections:
		section.set_advanced_open(false)
	if scroll != null:
		scroll.scroll_vertical = 0
	# Start: ready up the host, press Start (real path through Main: pending overlay first).
	(lobby.get("_ready_check") as CheckButton).button_pressed = true
	await _settle(SETTLE_FRAMES)
	lobby.call("_on_start_pressed")
	var loading: LoadingScreen = _main.get("_loading_screen") as LoadingScreen
	await _wait_for(func() -> bool: return loading.visible)
	await _settle(SETTLE_FRAMES)
	await _shot("loading_screen", "loading")
	if loading.ready_gate_armed():
		await _wait_for(func() -> bool: return loading.accepts_ready_input())
		await _settle(SETTLE_FRAMES)
		await _shot("loading_screen", "ready_prompt")
		loading.press_ready()
	else:
		_skip("loading_screen", "ready_prompt", "ready gate not armed in this run")
	await _wait_for(func() -> bool: return not loading.visible)
	await _wait_for(func() -> bool: return Match.state() == Match.State.PLAYING)
	await _settle(PLAYING_WAIT_FRAMES)
	await _shot("hud", "match_playing")
	await _overlays_in_match()
	await _to_menu()


func _overlays_in_match() -> void:
	# ScoreboardOverlay: hold show_scores (action state + the input event it listens for).
	Input.action_press(&"show_scores")
	var press: InputEventAction = InputEventAction.new()
	press.action = &"show_scores"
	press.pressed = true
	_vp.push_input(press)
	await _settle(SETTLE_FRAMES)
	await _shot("scoreboard", "held")
	Input.action_release(&"show_scores")
	var release: InputEventAction = InputEventAction.new()
	release.action = &"show_scores"
	release.pressed = false
	_vp.push_input(release)
	await _settle(SETTLE_FRAMES)
	# NetDebugOverlay (F3), shown for the live host session.
	var overlay: NetDebugOverlay = _main.get("_debug_overlay") as NetDebugOverlay
	if overlay != null:
		overlay.visible = true
		await _settle(SETTLE_FRAMES)
		await _shot("net_debug_overlay", "host_session")
		overlay.visible = false
	else:
		_skip("net_debug_overlay", "host_session", "Main built no NetDebugOverlay for this match")
	# PauseMenu, then its Options overlay (every tab, via the shared helper).
	var pause: PauseMenu = _main.get("_pause_menu") as PauseMenu
	if pause != null:
		pause.suppressed = false
		pause.call("_open")
		await _settle(SETTLE_FRAMES)
		await _shot("pause_menu", "home")
		pause.call("_on_options_pressed")
		await _settle(SETTLE_FRAMES)
		var options: OptionsMenu = pause.get("_options_menu") as OptionsMenu
		if options != null:
			await _options_tabs(options, "pause_options")
		else:
			_skip("pause_options", "*", "PauseMenu did not open an OptionsMenu")
		pause.call("force_close")
		await _settle(SETTLE_FRAMES)
	else:
		_skip("pause_menu", "*", "Main has no PauseMenu")
	await _results_variants()


## ResultsScreen: explicit variants driven through show_results() with the live payload
## (win for the local human, loss to the bot, draw), since the real end needs a won match.
func _results_variants() -> void:
	var results: ResultsScreen = _main.get("_results_screen") as ResultsScreen
	if results == null:
		_skip("results_screen", "*", "Main has no ResultsScreen")
		return
	var base: Dictionary = Match.stats().build_live_payload()
	var variants: Array[Dictionary] = [
		{"name": "win_local", "winner": Net.local_slot()},
		{"name": "lose_to_bot", "winner": 1},
		{"name": "draw", "winner": -1},
	]
	for variant: Dictionary in variants:
		var payload: Dictionary = base.duplicate(true)
		payload[ResultsPayload.KEY_LIVE] = false
		var winner: int = int(variant["winner"])
		payload[ResultsPayload.KEY_WINNER_ID] = winner
		var slot_item: PlayerSlot = Match.slot(winner) if winner >= 0 else null
		payload[ResultsPayload.KEY_WINNER_NAME] = slot_item.display_name if slot_item != null else ""
		results.show_results(payload)
		await _settle(SETTLE_FRAMES)
		await _shot("results_screen", String(variant["name"]))
		results.clear_results()
	results.visible = false


# --- tutorial, sandbox -------------------------------------------------------------

func _section_tutorial() -> void:
	_main.call("start_tutorial_from_menu")
	await _wait_for(func() -> bool: return _main.get("_tutorial") != null)
	# The loading overlay fades out over the first frames; wait it out.
	var loading: LoadingScreen = _main.get("_loading_screen") as LoadingScreen
	await _wait_for(func() -> bool: return not loading.visible)
	await _settle(LONG_SETTLE_FRAMES)
	var tutorial: Tutorial = _main.get("_tutorial") as Tutorial
	if tutorial == null:
		_skip("tutorial", "*", "Tutorial did not start")
		return
	# Steps enumerated from the TutorialConfig resource the scene uses.
	var steps: Array = tutorial.tutorial_config.steps
	for i: int in steps.size():
		tutorial.call("_begin_step", i)
		await _settle(SETTLE_FRAMES)
		await _shot("tutorial", "step%d_%s" % [i + 1, String((steps[i] as TutorialStep).id)])
	await _to_menu()


func _section_sandbox() -> void:
	_main.call("start_sandbox_from_menu")
	await _wait_for(func() -> bool: return _main.get("_sandbox") != null)
	await _settle(PLAYING_WAIT_FRAMES)
	var sandbox: Sandbox = _main.get("_sandbox") as Sandbox
	if sandbox == null:
		_skip("sandbox_panel", "*", "Sandbox did not start")
		return
	await _shot("sandbox_panel", "default")
	var tuning: TuningPanel = sandbox.get("_tuning_panel") as TuningPanel
	if tuning == null:
		_skip("tuning_panel", "*", "Sandbox has no TuningPanel")
	else:
		tuning.call("_toggle_panel")  # F4
		await _settle(LONG_SETTLE_FRAMES)
		var tabs: TabContainer = tuning.get("_tab_container") as TabContainer
		if tabs == null:
			_skip("tuning_panel", "*", "TuningPanel built no TabContainer")
		else:
			# Top-level sections are the TabContainer tabs.
			for i: int in tabs.get_tab_count():
				tabs.current_tab = i
				await _settle(SETTLE_FRAMES)
				await _shot("tuning_panel", "tab%02d_%s" % [i, tabs.get_tab_title(i).to_lower().replace(" ", "_")])
		if tuning.visible:
			tuning.call("_toggle_panel")
	var overlay: NetDebugOverlay = _main.get("_debug_overlay") as NetDebugOverlay
	if overlay != null:
		overlay.visible = true
		await _settle(SETTLE_FRAMES)
		await _shot("net_debug_overlay", "sandbox_offline")
		overlay.visible = false
	await _to_menu()


# --- capture -------------------------------------------------------------------------

func _shot(menu_name: String, page: String) -> void:
	var key: String = menu_name + SPLIT + page
	if not _only.is_empty() and not key.contains(_only):
		return
	await _settle(1)
	await RenderingServer.frame_post_draw
	var image: Image = _vp.get_texture().get_image()
	var file: String = "%s%s%dx%d.png" % [key, SPLIT, _size.x, _size.y]
	if image == null or image.is_empty() or image.save_png(_out.path_join(file)) != OK:
		_skip(menu_name, page, "capture failed at %s" % _size)
		return
	_shots.append({"menu": menu_name, "page": page, "size": _size, "file": file})
	print("MENU_ATLAS shot ", file)


func _skip(menu_name: String, page: String, reason: String) -> void:
	_skipped.append({"menu": menu_name, "page": page, "reason": reason})


func _skipped_unique() -> int:
	var seen: Dictionary = {}
	for item: Dictionary in _skipped:
		seen["%s/%s/%s" % [item["menu"], item["page"], item["reason"]]] = true
	return seen.size()


func _settle(frames: int) -> void:
	for _i: int in range(frames):
		await get_tree().process_frame


func _wait_for(condition: Callable) -> void:
	var deadline: int = Time.get_ticks_msec() + int(STATE_WAIT_TIMEOUT_S * 1000.0)
	while not bool(condition.call()) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


# --- contact sheets and index ------------------------------------------------------------

func _build_sheets() -> void:
	var label_vp: SubViewport = SubViewport.new()
	var bg: ColorRect = ColorRect.new()
	bg.color = LABEL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var label: Label = Label.new()
	label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	label.add_theme_color_override("font_color", LABEL_FG)
	label.position = Vector2(4.0, 2.0)
	bg.add_child(label)
	label_vp.add_child(bg)
	label_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(label_vp)
	for size: Vector2i in _sizes:
		var items: Array[Dictionary] = []
		for shot: Dictionary in _shots:
			if shot["size"] == size:
				items.append(shot)
		if items.is_empty():
			continue
		await _sheet_for_size(size, items, label_vp, label)
	label_vp.queue_free()


func _sheet_for_size(size: Vector2i, items: Array[Dictionary], label_vp: SubViewport, label: Label) -> void:
	var cell_w: int = int((ContactSheet.MAX_SHEET_PX_W - SHEET_GAP * (SHEET_COLUMNS + 1)) / float(SHEET_COLUMNS))
	var thumb_h: int = int(round(float(size.y) * float(cell_w) / float(size.x)))
	var row_h: int = thumb_h + LABEL_HEIGHT
	var rows_per_page: int = maxi(1, int((ContactSheet.MAX_SHEET_PX_H - SHEET_GAP) / float(row_h + SHEET_GAP)))
	var per_page: int = rows_per_page * SHEET_COLUMNS
	var pages: int = ceili(float(items.size()) / float(per_page))
	label_vp.size = Vector2i(cell_w, LABEL_HEIGHT)
	for page: int in pages:
		var chunk: Array = items.slice(page * per_page, (page + 1) * per_page)
		var rows: int = ceili(float(chunk.size()) / float(SHEET_COLUMNS))
		var cols: int = mini(SHEET_COLUMNS, chunk.size())
		var sheet: Image = Image.create_empty(
				cols * cell_w + SHEET_GAP * (cols + 1), rows * row_h + SHEET_GAP * (rows + 1), false, Image.FORMAT_RGBA8)
		sheet.fill(ContactSheet.BACKGROUND)
		for i: int in chunk.size():
			var shot: Dictionary = chunk[i]
			var thumb: Image = Image.load_from_file(_out.path_join(String(shot["file"])))
			thumb.convert(Image.FORMAT_RGBA8)
			thumb.resize(cell_w, thumb_h, Image.INTERPOLATE_LANCZOS)
			label.text = "%s / %s" % [shot["menu"], shot["page"]]
			await _settle(LABEL_FRAMES)
			await RenderingServer.frame_post_draw
			var bar: Image = label_vp.get_texture().get_image()
			bar.convert(Image.FORMAT_RGBA8)
			var origin: Vector2i = Vector2i(
					SHEET_GAP + (i % SHEET_COLUMNS) * (cell_w + SHEET_GAP),
					SHEET_GAP + (i / SHEET_COLUMNS) * (row_h + SHEET_GAP))
			sheet.blit_rect(bar, Rect2i(Vector2i.ZERO, bar.get_size()), origin)
			sheet.blit_rect(thumb, Rect2i(Vector2i.ZERO, thumb.get_size()), origin + Vector2i(0, LABEL_HEIGHT))
		var name: String = "contact_sheet_%dx%d_p%d.png" % [size.x, size.y, page + 1]
		if sheet.save_png(_out.path_join(name)) != OK:
			_fail("could not save " + name)
			return
		print("MENU_ATLAS sheet ", _out.path_join(name), " ", sheet.get_size())


func _write_index() -> void:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("# Menu atlas")
	lines.append("")
	lines.append("| menu | page | size | file |")
	lines.append("|---|---|---|---|")
	for shot: Dictionary in _shots:
		var size: Vector2i = shot["size"]
		lines.append("| %s | %s | %dx%d | %s |" % [shot["menu"], shot["page"], size.x, size.y, shot["file"]])
	lines.append("")
	lines.append("## Skipped")
	lines.append("")
	if _skipped.is_empty():
		lines.append("(none)")
	else:
		lines.append("| menu | page | reason |")
		lines.append("|---|---|---|")
		var seen: Dictionary = {}
		for item: Dictionary in _skipped:
			var key: String = "%s/%s/%s" % [item["menu"], item["page"], item["reason"]]
			if seen.has(key):
				continue
			seen[key] = true
			lines.append("| %s | %s | %s |" % [item["menu"], item["page"], item["reason"]])
	var file: FileAccess = FileAccess.open(_out.path_join(INDEX_FILE), FileAccess.WRITE)
	if file == null:
		_fail("cannot write index.md")
		return
	file.store_string("\n".join(lines) + "\n")
	file.close()


func _arg(args: PackedStringArray, prefix: String) -> String:
	for a: String in args:
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return ""


func _fail(message: String) -> void:
	printerr("MENU_ATLAS failed: ", message)
	get_tree().quit(FAIL_EXIT_CODE)
