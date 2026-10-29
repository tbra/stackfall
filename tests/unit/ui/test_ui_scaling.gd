extends GutTest
## nothing in the UI scales independently. The project stretch
## (ui/theme/UiScale.gd) is the one rule; each screen is laid out in a SubViewport
## that emulates a real window of every supported size, and key elements must
## stay fully on screen.

const SIZES: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440),
	Vector2i(3440, 1440), Vector2i(900, 1200),
]
const SETTLE_FRAMES: int = 4
const EDGE_EPS: float = 1.0
const LOGICAL_KEY: String = "_logical"


class FakeMatchNet:
	extends RefCounted

	func request_replay() -> void:
		pass

	func request_return_to_lobby() -> void:
		pass


func after_each() -> void:
	Match.abort_match()
	Settings._input(InputEventKey.new())


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
	if control == null and node is HUD:
		# HUD controls live under the HudScaleRoot.
		control = node.find_child(path, true, false) as Control
	assert_not_null(control, "missing node %s" % path)
	if control == null:
		return Rect2()
	return control.get_global_transform() * Rect2(Vector2.ZERO, control.size)


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


# --- builders ---------------------------------------------------------------

func _build_lobby(vp: SubViewport) -> Node:
	var lobby: Lobby = load("res://ui/lobby/Lobby.tscn").instantiate() as Lobby
	vp.add_child(lobby)
	var fake: FakeNet = FakeNet.new()
	fake.is_host_value = true
	fake.is_offline_value = true
	lobby.net_provider = fake
	lobby._update_host_only_state()
	return lobby


func _build_hud(vp: SubViewport) -> Node:
	var hud: HUD = load("res://ui/hud/HUD.tscn").instantiate() as HUD
	vp.add_child(hud)
	hud.set_territory_shares(PackedFloat32Array([0.4, 0.3, 0.2, 0.1]))
	hud.set_local_slot(0)
	return hud


func test_ui_scale_rule_matches_project_stretch() -> void:
	assert_eq(ProjectSettings.get_setting("display/window/stretch/mode"), "canvas_items")
	assert_eq(ProjectSettings.get_setting("display/window/stretch/aspect"), "expand")
	assert_almost_eq(UiScale.stretch_factor(Vector2(3440, 1440)), 2.0, 0.001)
	assert_almost_eq(UiScale.stretch_factor(Vector2(900, 1200)), 900.0 / 1280.0, 0.001)
	# the 100% default is half the old mockup scale (1920x1080 logical at 1280x720).
	var base: float = UiScaleTuning.shared().base_scale
	assert_almost_eq(UiScale.factor(Vector2(3440, 1440)), 2.0 * base, 0.001)
	assert_eq(UiScale.logical_size(Vector2(1280, 720)), Vector2i(1920, 1080))
	assert_eq(UiScale.logical_size(Vector2(1920, 1080)), Vector2i(1920, 1080))


func test_user_scale_changes_the_logical_canvas() -> void:
	var tuning: UiScaleTuning = UiScaleTuning.shared()
	var saved: float = UiScaleTuning.current_scale
	UiScaleTuning.current_scale = tuning.min_scale
	assert_eq(UiScale.logical_size(Vector2(1280, 720)), Vector2i(2560, 1440), "min scale = factor 0.5")
	UiScaleTuning.current_scale = tuning.max_scale
	var max_logical: Vector2i = UiScale.logical_size(Vector2(1280, 720))
	assert_eq(max_logical, Vector2i(960, 540), "max = 200%: logical canvas 960x540 at 1280x720")
	UiScaleTuning.current_scale = saved


func _collect_ui_scripts(dir_path: String, out: PackedStringArray) -> void:
	for sub: String in DirAccess.get_directories_at(dir_path):
		_collect_ui_scripts("%s/%s" % [dir_path, sub], out)
	for file: String in DirAccess.get_files_at(dir_path):
		if file.ends_with(".gd"):
			out.append("%s/%s" % [dir_path, file])


func test_hud_elements_stay_on_screen_at_every_window_size() -> void:
	var names: PackedStringArray = ["TopLeftBackplate", "HeldNextPanel", "TimerRing", "Minimap"]
	var measured: Dictionary = await _measure(_build_hud, names)
	_check_on_screen(measured, names, "hud")


func _focusable_settings_controls(scroll: ScrollContainer) -> Array[Control]:
	var out: Array[Control] = []
	for node: Node in scroll.find_children("*", "Control", true, false):
		var control: Control = node as Control
		if control.focus_mode == Control.FOCUS_ALL and control.is_visible_in_tree():
			out.append(control)
	return out


func test_lobby_settings_all_visible_or_reachable_at_every_size() -> void:
	for window: Vector2i in SIZES:
		var vp: SubViewport = _host(window)
		var lobby: Lobby = _build_lobby(vp) as Lobby
		await _settle()
		# Lobby rework: advanced options live in collapsible blocks;
		# open every section and Advanced block so they are checked for reachability too.
		for section: UiSection in lobby._sections():
			if section.has_advanced():
				section.set_advanced_open(true)
		await _settle()
		var scroll: ScrollContainer = lobby.get_node("%SettingsScroll") as ScrollContainer
		assert_true(scroll.follow_focus, "settings scroll follows focus at %s" % window)
		var controls: Array[Control] = _focusable_settings_controls(scroll)
		assert_gt(controls.size(), 8, "settings controls found at %s" % window)
		for name: String in ["%GravityMeter", "%SpecialFreqMeter", "%GiftsCheck"]:
			assert_true(controls.has(lobby.get_node(name)), "%s focusable at %s" % [name, window])
		for control: Control in controls:
			# The column rebalance keeps content within the visible rect where it fits;
			# anything that does not fit must be reached by focus-follow scrolling.
			control.grab_focus()
			await get_tree().process_frame
			await get_tree().process_frame
			var view: Rect2 = scroll.get_global_rect().grow(EDGE_EPS)
			assert_true(view.encloses(control.get_global_rect()),
				"%s %s not visible after focus at %s (view %s)" % [control.name, control.get_global_rect(), window, view])
		# The goal-flag stepper takes focus itself; scroll to it explicitly too.
		var goal_spin: Control = lobby.get_node("%GoalFlagStepper") as Control
		scroll.ensure_control_visible(goal_spin)
		await get_tree().process_frame
		if goal_spin.is_visible_in_tree():
			assert_true(scroll.get_global_rect().grow(EDGE_EPS).encloses(goal_spin.get_global_rect()), "GoalFlagSpin unreachable at %s" % window)
		if scroll.get_v_scroll_bar().max_value <= scroll.get_v_scroll_bar().page + EDGE_EPS:
			scroll.scroll_vertical = 0
			var fully_visible: bool = true
			for control: Control in controls:
				fully_visible = fully_visible and scroll.get_global_rect().grow(EDGE_EPS).encloses(control.get_global_rect())
			assert_true(fully_visible, "no scrolling needed yet a control is clipped at %s" % window)
		vp.queue_free()
		await get_tree().process_frame
