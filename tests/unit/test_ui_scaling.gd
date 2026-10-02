extends GutTest
## Bontago-1pi.26: nothing in the UI scales independently. The project stretch
## (ui/UiScale.gd) is the one rule; each screen is laid out in a SubViewport
## that emulates a real window of every supported size, and key elements must
## keep their logical size (so physical size / stretch factor is constant),
## their corner insets, stay fully on screen and not overlap where they must not.

const SIZES: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440),
	Vector2i(3440, 1440), Vector2i(900, 1200),
]
const SETTLE_FRAMES: int = 4
const EDGE_EPS: float = 1.0
const SIZE_TOLERANCE: float = 0.015
const INSET_TOLERANCE_PX: float = 1.5
const FRACTION_TOLERANCE: float = 0.03
const WIDE_ASPECT: float = 16.0 / 9.0 - 0.001
const LOGICAL_KEY: String = "_logical"


class FakeMatchNet:
	extends RefCounted

	func request_replay() -> void:
		pass

	func request_return_to_lobby() -> void:
		pass


func after_each() -> void:
	Match.abort_match()
	Settings.set_active_input_device_for_test(Settings.DEFAULT_ACTIVE_DEVICE)


# --- harness ----------------------------------------------------------------

func _host(window: Vector2i) -> SubViewport:
	var vp: SubViewport = UiScale.make_viewport(window)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child_autofree(vp)
	return vp


func _settle() -> void:
	for _i: int in SETTLE_FRAMES:
		await get_tree().process_frame


func _rect_of(node: Node, path: String) -> Rect2:
	var control: Control = node.get_node_or_null(path) as Control
	assert_not_null(control, "missing node %s" % path)
	if control == null:
		return Rect2()
	return control.get_global_rect()


## screen builder -> per-size {element name: Rect2 in logical px}.
func _measure(builder: Callable, names: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for window: Vector2i in SIZES:
		var vp: SubViewport = _host(window)
		var root: Node = builder.call(vp)
		await _settle()
		var rects: Dictionary = {}
		for element: String in names:
			rects[element] = _rect_of(root, element)
		rects[LOGICAL_KEY] = Rect2(Vector2.ZERO, Vector2(vp.get_visible_rect().size))
		out[window] = rects
		vp.queue_free()
		await get_tree().process_frame
	return out


func _check_on_screen(measured: Dictionary, names: PackedStringArray, label: String) -> void:
	for window: Vector2i in measured:
		var rects: Dictionary = measured[window]
		var screen: Rect2 = (rects[LOGICAL_KEY] as Rect2).grow(EDGE_EPS)
		for element: String in names:
			var rect: Rect2 = rects[element]
			assert_true(rect.size.x > 0.0 and rect.size.y > 0.0, "%s %s has no size at %s" % [label, element, window])
			assert_true(screen.encloses(rect), "%s %s %s leaves the %s screen" % [label, element, rect, window])


## Fixed-size elements: the logical size is identical at every window size, so
## physical size = logical size * stretch factor with no extra scaling.
func _check_fixed_size(measured: Dictionary, names: PackedStringArray, label: String) -> void:
	var reference: Dictionary = measured[SIZES[0]]
	for window: Vector2i in measured:
		var rects: Dictionary = measured[window]
		for element: String in names:
			var size_now: Vector2 = (rects[element] as Rect2).size
			var want: Vector2 = (reference[element] as Rect2).size
			assert_almost_eq(size_now.x, want.x, maxf(1.0, want.x * SIZE_TOLERANCE), "%s %s width at %s" % [label, element, window])
			assert_almost_eq(size_now.y, want.y, maxf(1.0, want.y * SIZE_TOLERANCE), "%s %s height at %s" % [label, element, window])


## Flexible elements: on windows at least 16:9, height as a fraction of the window is constant.
func _check_height_fraction(measured: Dictionary, names: PackedStringArray, label: String) -> void:
	var reference: Dictionary = measured[SIZES[0]]
	for window: Vector2i in measured:
		if float(window.x) / float(window.y) < WIDE_ASPECT:
			continue
		var rects: Dictionary = measured[window]
		var logical_h: float = (rects[LOGICAL_KEY] as Rect2).size.y
		var ref_h: float = (reference[LOGICAL_KEY] as Rect2).size.y
		for element: String in names:
			var fraction: float = (rects[element] as Rect2).size.y / logical_h
			var want: float = (reference[element] as Rect2).size.y / ref_h
			assert_almost_eq(fraction, want, FRACTION_TOLERANCE, "%s %s height fraction at %s" % [label, element, window])


## Distance from the element to its anchor corner stays constant. corner: tl, tr, bl, br.
func _check_corner_inset(measured: Dictionary, element: String, corner: String, label: String) -> void:
	var reference: Vector2 = _inset(measured[SIZES[0]], element, corner)
	for window: Vector2i in measured:
		var inset: Vector2 = _inset(measured[window], element, corner)
		assert_almost_eq(inset.x, reference.x, INSET_TOLERANCE_PX, "%s %s x-inset at %s" % [label, element, window])
		assert_almost_eq(inset.y, reference.y, INSET_TOLERANCE_PX, "%s %s y-inset at %s" % [label, element, window])


func _inset(rects: Dictionary, element: String, corner: String) -> Vector2:
	var rect: Rect2 = rects[element]
	var screen: Rect2 = rects[LOGICAL_KEY]
	var x: float = rect.position.x if corner.ends_with("l") else screen.end.x - rect.end.x
	var y: float = rect.position.y if corner.begins_with("t") else screen.end.y - rect.end.y
	return Vector2(x, y)


func _check_no_overlap(measured: Dictionary, pairs: Array, label: String) -> void:
	for window: Vector2i in measured:
		var rects: Dictionary = measured[window]
		for pair: Array in pairs:
			var a: Rect2 = rects[pair[0]]
			var b: Rect2 = rects[pair[1]]
			assert_false(a.intersects(b), "%s %s %s overlaps %s %s at %s" % [label, pair[0], a, pair[1], b, window])


# --- builders ---------------------------------------------------------------

func _build_menu(vp: SubViewport) -> Node:
	var menu: MainMenu = load("res://ui/MainMenu.tscn").instantiate() as MainMenu
	vp.add_child(menu)
	menu.net_provider = FakeNet.new()
	return menu


func _build_lobby(vp: SubViewport) -> Node:
	var lobby: Lobby = load("res://ui/Lobby.tscn").instantiate() as Lobby
	vp.add_child(lobby)
	var fake: FakeNet = FakeNet.new()
	fake.is_host_value = true
	fake.is_offline_value = true
	lobby.net_provider = fake
	lobby._update_host_only_state()
	return lobby


func _build_options(vp: SubViewport) -> Node:
	var menu: OptionsMenu = load("res://ui/OptionsMenu.tscn").instantiate() as OptionsMenu
	vp.add_child(menu)
	return menu


func _build_hud(vp: SubViewport) -> Node:
	var hud: HUD = load("res://ui/HUD.tscn").instantiate() as HUD
	vp.add_child(hud)
	hud.set_territory_shares(PackedFloat32Array([0.4, 0.3, 0.2, 0.1]))
	hud.set_local_slot(0)
	return hud


func _build_results(vp: SubViewport) -> Node:
	var screen: ResultsScreen = load("res://ui/ResultsScreen.tscn").instantiate() as ResultsScreen
	vp.add_child(screen)
	screen.net_provider = FakeNet.host()
	screen.match_net_provider = FakeMatchNet.new()
	var fake_match: FakeMatch = FakeMatch.new()
	fake_match.config = MatchConfig.new()
	screen.match_provider = fake_match
	var rows: Array[Dictionary] = []
	for i: int in 8:
		rows.append({
			"slot_id": i, "name": "Player %d" % (i + 1), "team_id": i, "is_bot": i > 0,
			"blocks_placed": 20 + i, "blocks_lost": i, "gifts_claimed": 1, "specials_used": 1,
			"territory_share": 0.12, "eliminated_at": MatchStats.NOT_ELIMINATED,
		})
	screen.show_results({
		"winner_kind": MatchStats.WINNER_KIND_SLOT, "winner_id": 0, "winner_name": "Player 1",
		"match_duration": 120.0, "rows": rows,
		"mode": {"mode_id": MatchConfig.GameMode.CAPTURE_THE_FLAG, "scores": [499.7, 0.0, 0.0, 0.0]},
	})
	return screen


func _build_loading(vp: SubViewport) -> Node:
	var screen: LoadingScreen = load("res://ui/LoadingScreen.tscn").instantiate() as LoadingScreen
	vp.add_child(screen)
	var slots: Array[PlayerSlot] = []
	for i: int in 4:
		slots.append(PlayerSlot.new(i, i, "Player %d" % (i + 1), Color.WHITE))
	screen.show_for_match(MatchConfig.new(), slots)
	return screen


# --- tests ------------------------------------------------------------------

func test_ui_scale_rule_matches_project_stretch() -> void:
	assert_eq(ProjectSettings.get_setting("display/window/stretch/mode"), "canvas_items")
	assert_eq(ProjectSettings.get_setting("display/window/stretch/aspect"), "expand")
	assert_almost_eq(UiScale.factor(Vector2(3440, 1440)), 2.0, 0.001)
	assert_eq(UiScale.logical_size(Vector2(3440, 1440)), Vector2i(1720, 720))
	assert_almost_eq(UiScale.factor(Vector2(900, 1200)), 900.0 / 1280.0, 0.001)
	assert_eq(UiScale.logical_size(Vector2(1280, 720)), Vector2i(1280, 720))


func test_no_ui_script_applies_its_own_scale() -> void:
	# The static audit behind the rule: no UI script multiplies the canvas itself.
	var dir: DirAccess = DirAccess.open("res://ui")
	for file: String in dir.get_files():
		if not file.ends_with(".gd") or file == "SplashScreen.gd":
			continue
		var text: String = FileAccess.get_file_as_string("res://ui/" + file)
		for needle: String in ["content_scale_factor", "content_scale_size", "window_get_size", "screen_get_size", "get_window().size", "control.scale ="]:
			assert_false(text.contains(needle), "%s uses %s" % [file, needle])


func test_main_menu_scales_uniformly() -> void:
	var names: PackedStringArray = ["%Panel", "%HostButton", "%JoinButton", "%GamepadHintPill"]
	var measured: Dictionary = await _measure(_build_menu, names)
	_check_on_screen(measured, names, "menu")
	_check_fixed_size(measured, PackedStringArray(["%HostButton", "%JoinButton"]), "menu")
	_check_height_fraction(measured, PackedStringArray(["%Panel"]), "menu")
	_check_no_overlap(measured, [["%Panel", "%GamepadHintPill"], ["%HostButton", "%JoinButton"]], "menu")


func test_lobby_scales_uniformly() -> void:
	var names: PackedStringArray = ["%SettingsCard", "%PlayersCard", "%StartButton", "%BackButton", "%WaitingStatusPill", "%HeaderTitle"]
	var measured: Dictionary = await _measure(_build_lobby, names)
	_check_on_screen(measured, names, "lobby")
	_check_fixed_size(measured, PackedStringArray(["%StartButton", "%BackButton"]), "lobby")
	_check_height_fraction(measured, PackedStringArray(["%SettingsCard", "%PlayersCard"]), "lobby")
	_check_corner_inset(measured, "%BackButton", "tr", "lobby")
	_check_corner_inset(measured, "%StartButton", "br", "lobby")
	_check_no_overlap(measured, [
		["%SettingsCard", "%PlayersCard"], ["%SettingsCard", "%StartButton"], ["%PlayersCard", "%StartButton"],
		["%HeaderTitle", "%BackButton"], ["%WaitingStatusPill", "%StartButton"], ["%WaitingStatusPill", "%SettingsCard"],
	], "lobby")


func test_options_scales_uniformly() -> void:
	var names: PackedStringArray = ["Frame/Panel", "%SettingsTabButton", "%ControlsTabButton"]
	var measured: Dictionary = await _measure(_build_options, names)
	_check_on_screen(measured, names, "options")
	_check_fixed_size(measured, PackedStringArray(["%SettingsTabButton", "%ControlsTabButton"]), "options")
	_check_height_fraction(measured, PackedStringArray(["Frame/Panel"]), "options")
	_check_no_overlap(measured, [["%SettingsTabButton", "%ControlsTabButton"]], "options")


func test_hud_scales_uniformly_and_never_overlaps() -> void:
	var names: PackedStringArray = ["TopLeftBackplate", "HeldNextPanel", "TimerRing", "Minimap"]
	var measured: Dictionary = await _measure(_build_hud, names)
	_check_on_screen(measured, names, "hud")
	_check_fixed_size(measured, names, "hud")
	_check_corner_inset(measured, "TopLeftBackplate", "tl", "hud")
	_check_corner_inset(measured, "HeldNextPanel", "bl", "hud")
	_check_corner_inset(measured, "Minimap", "br", "hud")
	_check_no_overlap(measured, [
		["TopLeftBackplate", "HeldNextPanel"], ["TopLeftBackplate", "TimerRing"],
		["TopLeftBackplate", "Minimap"], ["HeldNextPanel", "Minimap"], ["HeldNextPanel", "TimerRing"],
		["TimerRing", "Minimap"],
	], "hud")


func test_hud_with_gift_card_keeps_clear_of_other_widgets() -> void:
	for window: Vector2i in SIZES:
		var vp: SubViewport = _host(window)
		var hud: HUD = _build_hud(vp) as HUD
		hud._gift_slot_column.visible = true
		hud._held_next_panel.offset_right = hud._gift_slot_panel_base_right + hud._gift_slot_extra_width
		await _settle()
		var panel: Rect2 = hud._held_next_panel.get_global_rect()
		assert_false(panel.intersects(hud._minimap.get_global_rect()), "gift card panel hits minimap at %s" % window)
		assert_false(panel.intersects(hud._timer_ring.get_global_rect()), "gift card panel hits timer at %s" % window)
		assert_false(panel.intersects(hud._top_left_backplate.get_global_rect()), "gift card panel hits stats at %s" % window)
		assert_true(Rect2(Vector2.ZERO, Vector2(vp.get_visible_rect().size)).encloses(panel), "gift panel off screen at %s" % window)
		vp.queue_free()


func test_hud_steps_aside_while_results_are_shown() -> void:
	var vp: SubViewport = _host(SIZES[0])
	var hud: HUD = _build_hud(vp) as HUD
	await _settle()
	assert_true(hud.visible)
	Events.match_results_ready.emit({"winner_kind": MatchStats.WINNER_KIND_SLOT, "winner_id": 0, "winner_name": "A", "rows": []})
	assert_false(hud.visible, "HUD must hide under the results screen")
	Events.match_state_changed.emit(Match.State.END, Match.State.LOADING)
	assert_true(hud.visible, "HUD returns for the next match")


func test_results_scales_uniformly() -> void:
	var names: PackedStringArray = ["%Card", "%ReplayButton", "%LobbyButton", "%SettingsButton"]
	var measured: Dictionary = await _measure(_build_results, names)
	_check_on_screen(measured, names, "results")
	_check_fixed_size(measured, PackedStringArray(["%ReplayButton", "%LobbyButton", "%SettingsButton"]), "results")
	_check_height_fraction(measured, PackedStringArray(["%Card"]), "results")
	_check_no_overlap(measured, [
		["%ReplayButton", "%LobbyButton"], ["%LobbyButton", "%SettingsButton"],
	], "results")


func test_loading_scales_uniformly() -> void:
	var names: PackedStringArray = ["%Card", "%ProgressBar"]
	var measured: Dictionary = await _measure(_build_loading, names)
	_check_on_screen(measured, names, "loading")
	_check_fixed_size(measured, PackedStringArray(["%Card"]), "loading")
