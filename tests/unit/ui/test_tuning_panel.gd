extends GutTest
## ui/debug/TuningPanel.gd's reflection-built tabs (one control per
## exported numeric/bool/Color field of the live tuning resources), the F4 /
## gamepad Start+X toggle (tools/bootstrap_project.gd's chord DECISION), the
## physics/territory-visuals live-apply hooks, and the Reset/Save/Copy
## buttons' underlying logic.
##
## camera_tuning/physics_tuning/territory_tuning/ghost_tuning are the same
## process-wide singletons every other script's `@export var tuning: ... =
## preload(...)` field resolves to (test_playercontroller_mouse.gd's own
## CameraTuning comment documents why: mutating one of these leaks into every
## other test that reads it), so every test that edits one restores it in
## after_each() -- and any test that writes user://tuning_overrides.cfg
## removes it too, so a leftover file can't silently change
## config/*.tres-backed defaults for a later test file's Main.tscn boot
## (game/main/Main.gd calls TuningOverrides.apply_saved() first thing).

var _panel: TuningPanel = null

var _saved_gravity: float
var _saved_friction: float
var _saved_disk_friction: float
var _saved_bounce: float
var _saved_linear_damp: float
var _saved_angular_damp: float
var _saved_cube_mass: float
var _saved_rebound_damping: float
var _saved_follow_block: bool
var _saved_follow_distance: float
var _saved_max_cell_toggles: int
var _saved_tint_color: Color
var _saved_disk_metallic: float

## saved/restored the same way every other live singleton
## field above is (this file's own header explains why) -- mutated by the
## new Sky-tab write-through test below (the first day keyframe's fog density).
var _saved_sky_fog_density: float


## the ~2900-node tab UI is built once per script, not once per
## test. Tests that only read the panel or write resources/controls run against
## _shared; after_each repairs it (rebuild) if anything left it dirty (a "•"
## modified marker, open/hidden state, swapped providers or wiring). Tests that
## open/close the panel, swap providers, wire a field/controller or alter a
## control's selection take their own throw-away panel via _own_panel().
var _shared: TuningPanel = null
var _shared_sky_cycle: SkyCycleDef = null


func before_all() -> void:
	_shared = load("res://ui/debug/TuningPanel.tscn").instantiate()
	add_child(_shared)
	_rebuild_all(_shared)
	_shared_sky_cycle = _shared.sky_cycle


func after_all() -> void:
	if _shared != null:
		_shared.free()
		_shared = null


## Tabs build their rows when first shown, so a test that reads any row shows every tab once.
func _show_all_tabs(panel: TuningPanel) -> void:
	for index: int in panel._tab_container.get_tab_count():
		panel._tab_container.current_tab = index


func _show_tab(panel: TuningPanel, tab_name: String) -> void:
	var tabs: TabContainer = panel._tab_container
	tabs.current_tab = tabs.get_tab_idx_from_control(tabs.get_node(tab_name))


func _rebuild_all(panel: TuningPanel) -> void:
	panel.rebuild()
	_show_all_tabs(panel)


## A fresh panel for a test that mutates panel-level state. prebuild = false
## leaves the UI unbuilt for a test that rebuilds/opens it itself (half the cost).
func _own_panel(prebuild: bool) -> TuningPanel:
	var own: TuningPanel = autofree(load("res://ui/debug/TuningPanel.tscn").instantiate())
	add_child_autofree(own)
	if prebuild:
		_rebuild_all(own)
	_panel = own
	return own


## The panel's row for one field ({} if none): the node tree holds the same controls and labels.
func _row(panel: TuningPanel, resource: Resource, prop_name: String) -> Dictionary:
	for row: Dictionary in panel._rows:
		if row.get("resource") == resource and row.get("property") == prop_name:
			return row
	return {}


func _control_for(panel: TuningPanel, resource: Resource, prop_name: String) -> Control:
	return _row(panel, resource, prop_name).get("control") as Control


func _shown_fields_for(panel: TuningPanel, resource: Resource) -> Array[String]:
	var names: Array[String] = []
	for row: Dictionary in panel._rows:
		if row.get("resource") == resource:
			names.append(String(row.get("property")))
	return names


## The row as text: the modified marker, the human label and the "(default ...)" annotation.
func _label_text_for(panel: TuningPanel, resource: Resource, prop_name: String) -> String:
	var row: Dictionary = _row(panel, resource, prop_name)
	if row.is_empty():
		return ""
	return "%s (%s)" % [(row["name_label"] as Label).text, (row["default_label"] as Label).text]


func _shared_is_dirty() -> bool:
	if _shared._tab_container == null or _shared.visible:
		return true
	if _shared.sky_cycle != _shared_sky_cycle or _shared.net_provider != Net:
		return true
	var resources: Array[Resource] = [
		_shared.camera_tuning, _shared.ghost_tuning, _shared.physics_tuning,
		_shared.territory_tuning, _shared.territory_visuals, _shared.block_feed_config,
		_shared.sky_cycle, _shared.sky_cycle.day_keyframes[0], _shared.sky_cycle.night, _shared.storm_overlay,
	]
	for resource: Resource in resources:
		for prop_name: String in _shown_fields_for(_shared, resource):
			if _label_text_for(_shared, resource, prop_name).begins_with("•"):
				return true
	return false


func before_each() -> void:
	_panel = _shared

	_saved_gravity = _panel.physics_tuning.gravity_multiplier
	_saved_friction = _panel.physics_tuning.block_friction
	_saved_disk_friction = _panel.physics_tuning.disk_friction
	_saved_bounce = _panel.physics_tuning.block_bounce
	_saved_linear_damp = _panel.physics_tuning.block_linear_damp
	_saved_angular_damp = _panel.physics_tuning.block_angular_damp
	_saved_cube_mass = _panel.physics_tuning.cube_mass
	_saved_rebound_damping = _panel.physics_tuning.rebound_damping
	_saved_follow_block = _panel.camera_tuning.follow_block
	_saved_follow_distance = _panel.camera_tuning.follow_distance
	_saved_max_cell_toggles = _panel.territory_tuning.max_cell_toggles_per_frame
	_saved_tint_color = _panel.ghost_tuning.tint_color
	_saved_disk_metallic = _panel.territory_visuals.disk_metallic
	_saved_sky_fog_density = _panel.sky_cycle.day_keyframes[0].fog_density


func after_each() -> void:
	_shared.physics_tuning.gravity_multiplier = _saved_gravity
	_shared.physics_tuning.block_friction = _saved_friction
	_shared.physics_tuning.disk_friction = _saved_disk_friction
	_shared.physics_tuning.block_bounce = _saved_bounce
	_shared.physics_tuning.block_linear_damp = _saved_linear_damp
	_shared.physics_tuning.block_angular_damp = _saved_angular_damp
	_shared.physics_tuning.cube_mass = _saved_cube_mass
	_shared.physics_tuning.rebound_damping = _saved_rebound_damping
	_shared.camera_tuning.follow_block = _saved_follow_block
	_shared.camera_tuning.follow_distance = _saved_follow_distance
	_shared.territory_tuning.max_cell_toggles_per_frame = _saved_max_cell_toggles
	_shared.ghost_tuning.tint_color = _saved_tint_color
	_shared.territory_visuals.disk_metallic = _saved_disk_metallic
	_shared.sky_cycle.day_keyframes[0].fog_density = _saved_sky_fog_density

	Input.action_release(&"pause_menu")

	if FileAccess.file_exists(TuningPanel.save_path()):
		DirAccess.remove_absolute(TuningPanel.save_path())
	_panel = _shared
	if _shared_is_dirty():
		_shared.visible = false
		_shared.net_provider = Net
		_shared.sky_cycle = _shared_sky_cycle
		_rebuild_all(_shared)


# --- Reflection: one control per exported field ------------------------------

func test_slider_change_writes_the_resource() -> void:
	var slider: HSlider = _control_for(_panel, _panel.physics_tuning, "gravity_multiplier") as HSlider
	var original: float = _panel.physics_tuning.gravity_multiplier
	slider.emit_signal("value_changed", 2.4)
	assert_almost_eq(_panel.physics_tuning.gravity_multiplier, 2.4, 0.0001)
	# Dragging back clears the modified marker, so the shared panel is clean for the next test.
	slider.emit_signal("value_changed", original)


func test_apply_physics_live_updates_an_existing_blocks_damping_material_and_gravity() -> void:
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = BlockFactory.build(shape, _panel.physics_tuning)
	add_child_autofree(block)  # _ready() joins Block.TUNING_GROUP for real.

	_panel.physics_tuning.block_linear_damp = 0.77
	_panel.physics_tuning.block_angular_damp = 0.66
	_panel.physics_tuning.block_friction = 0.11
	_panel.physics_tuning.block_bounce = 0.22
	_panel.physics_tuning.gravity_multiplier = 1.9

	_panel.apply_physics_live()

	assert_almost_eq(block.linear_damp, 0.77, 0.0001)
	assert_almost_eq(block.angular_damp, 0.66, 0.0001)
	assert_almost_eq(block.physics_material_override.friction, 0.11, 0.0001)
	assert_almost_eq(block.physics_material_override.bounce, 0.22, 0.0001)
	assert_almost_eq(block.gravity_scale, 1.9, 0.0001)


# --- Physics preset dropdown ---------------------------------

func test_apply_physics_preset_copies_values_and_reapplies_live() -> void:
	_own_panel(false)
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = BlockFactory.build(shape, _panel.physics_tuning)
	add_child_autofree(block)  # _ready() joins Block.TUNING_GROUP for real.

	_panel.apply_physics_preset("heavy_bouncy")

	var preset: PhysicsTuning = load("res://config/physics/presets/heavy_bouncy.tres")
	assert_almost_eq(_panel.physics_tuning.cube_mass, preset.cube_mass, 0.0001)
	assert_almost_eq(_panel.physics_tuning.gravity_multiplier, preset.gravity_multiplier, 0.0001)
	assert_almost_eq(_panel.physics_tuning.rebound_damping, preset.rebound_damping, 0.0001)
	assert_almost_eq(
		block.gravity_scale, preset.gravity_multiplier, 0.0001,
		"a preset pick must reach an already-standing block via apply_physics_live(), not just write the Resource."
	)


func test_save_and_apply_saved_overrides_round_trip_via_user_dir() -> void:
	var original_gravity: float = _panel.physics_tuning.gravity_multiplier
	var original_follow_distance: float = _panel.camera_tuning.follow_distance
	_panel.physics_tuning.gravity_multiplier = original_gravity + 0.6
	_panel.camera_tuning.follow_distance = original_follow_distance + 3.0

	var err: Error = _panel.save_overrides()
	assert_eq(err, OK)

	# Simulate a fresh boot: put the shared singletons back to their file
	# defaults, then let the saved override reapply the edited values --
	# exactly what game/main/Main.gd's boot hook does before anything else runs.
	_panel.physics_tuning.gravity_multiplier = original_gravity
	_panel.camera_tuning.follow_distance = original_follow_distance

	TuningOverrides.apply_saved()

	assert_almost_eq(_panel.physics_tuning.gravity_multiplier, original_gravity + 0.6, 0.0001)
	assert_almost_eq(_panel.camera_tuning.follow_distance, original_follow_distance + 3.0, 0.0001)


func _weather_option() -> OptionButton:
	return _panel._tab_container.find_child("WeatherOption", true, false) as OptionButton


func _fake_weather(host: bool) -> MatchWeather:
	var w: MatchWeather = MatchWeather.new()
	var defs: Array[WeatherTuning] = []
	for id: StringName in [&"rain", &"snow", &"storm"]:
		var def: WeatherTuning = WeatherTuning.new()
		def.id = id
		def.display_name = String(id).capitalize()
		defs.append(def)
	w.set_defs(defs)
	WeatherTestHost.bind_host(self, w, host)
	return w


func test_weather_row_selection_forces_swaps_and_releases_on_the_host() -> void:
	_own_panel(false)
	_panel.net_provider = FakeNet.host()
	var weather: MatchWeather = _fake_weather(true)
	_panel.weather_provider = weather
	_panel.rebuild()
	_show_tab(_panel, "Sky")
	var option: OptionButton = _weather_option()
	option.select(2)
	option.item_selected.emit(2)
	assert_eq(weather.active_id(), &"rain")
	option = _weather_option()
	option.select(4)
	option.item_selected.emit(4)
	assert_eq(weather.active_id(), &"storm", "switching replaces the previous weather")
	option.select(1)
	option.item_selected.emit(1)
	assert_eq(weather.active_id(), &"")
	option.select(0)
	option.item_selected.emit(0)
	assert_eq(weather.debug_override(), &"")


## the 10-task-tab layout -- CLIENT_HIDDEN_TAB_FIRST is 7 (added SFX), so
## every look/feel tab (Camera ... SFX) stays visible to a client and only the
## host-only simulation tabs (Physics, Territory rules, Block bag, QoL) hide.
func test_client_hides_the_simulation_tabs_but_not_the_visual_tabs() -> void:
	_own_panel(false)
	_panel.net_provider = FakeNet.client(0)
	_panel.rebuild()
	var visible_names: PackedStringArray = [
		"Camera", "Controls", "Ghost & Blocks", "Territory look", "HUD", "Sky", "SFX",
	]
	for index: int in range(visible_names.size()):
		assert_false(
			_panel._tab_container.is_tab_hidden(index),
			visible_names[index]
		)
	for index: int in range(_panel.CLIENT_HIDDEN_TAB_FIRST, _panel._tab_container.get_tab_count()):
		assert_true(_panel._tab_container.is_tab_hidden(index), "tab %d (host-only simulation tab)" % index)


# --- M7 art-direction tabs (Blocks FX/Beacons/Camera FX/HUD/Sky) ---

func _key_press(keycode: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.device = -1
	event.physical_keycode = keycode
	event.pressed = true
	return event


func _pad_press(button: JoyButton) -> InputEventJoypadButton:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = -1
	event.button_index = button
	event.pressed = true
	return event


func test_f4_toggles_visibility_both_ways() -> void:
	_own_panel(false)
	var event: InputEventKey = _key_press(KEY_F4)
	assert_true(event.is_action_pressed(&"tuning_panel_toggle"), "F4 should map to tuning_panel_toggle")

	assert_false(_panel.visible)
	_panel._unhandled_input(event)
	assert_true(_panel.visible)
	_panel._unhandled_input(event)
	assert_false(_panel.visible)


## Number of tab pages that hold built rows.
func _built_tab_count(panel: TuningPanel) -> int:
	var built: int = 0
	for page: Node in panel._tab_container.get_children():
		if page.get_child_count() > 0:
			built += 1
	return built


func test_only_the_shown_tab_builds_its_rows_and_keeps_them() -> void:
	_own_panel(false)
	_panel.rebuild()
	assert_eq(_built_tab_count(_panel), 1, "only the shown tab is built")
	var tabs: TabContainer = _panel._tab_container
	var other: int = (tabs.current_tab + 1) % tabs.get_tab_count()
	assert_eq(tabs.get_tab_control(other).get_child_count(), 0, "a hidden tab has no rows yet")
	tabs.current_tab = other
	assert_eq(_built_tab_count(_panel), 2, "showing a tab builds it")
	var page_rows: Node = tabs.get_tab_control(other).get_child(0)
	tabs.current_tab = (other + 1) % tabs.get_tab_count()
	tabs.current_tab = other
	assert_same(tabs.get_tab_control(other).get_child(0), page_rows, "a built tab is kept, not rebuilt")


func test_gamepad_dpad_tab_switch_builds_the_new_tab_with_focusable_rows() -> void:
	_own_panel(false)
	_panel.rebuild()
	var tabs: TabContainer = _panel._tab_container
	_panel.visible = true
	tabs.current_tab = 0
	var bar: TabBar = tabs.get_tab_bar()
	var event: InputEventJoypadButton = _pad_press(JOY_BUTTON_DPAD_RIGHT)
	assert_true(event.is_action_pressed(&"ui_right"), "fixture: d-pad right is ui_right")
	bar.grab_focus()
	Input.parse_input_event(event)
	await wait_physics_frames(2)
	assert_eq(tabs.current_tab, 1, "d-pad right moves to the next tab")
	var page: Node = tabs.get_tab_control(1)
	assert_gt(page.get_child_count(), 0, "the new tab is built when shown")
	var focusable: Array[Node] = page.find_children("*", "Control", true, false).filter(
		func(node: Node) -> bool: return (node as Control).focus_mode == Control.FOCUS_ALL
	)
	assert_gt(focusable.size(), 0, "the new tab's rows can take focus")


func test_gamepad_start_plus_x_toggles() -> void:
	_own_panel(false)
	Input.action_press(&"pause_menu")
	var event: InputEventJoypadButton = _pad_press(JOY_BUTTON_X)

	_panel._unhandled_input(event)

	assert_true(_panel.visible, "Start held + X pressed should toggle the panel.")


func test_reset_restores_shipped_tres_and_default_label_and_highlight_agree() -> void:
	var resources: Array[Resource] = [
		_panel.camera_tuning, _panel.ghost_tuning, _panel.physics_tuning,
		_panel.territory_tuning, _panel.territory_visuals, _panel.block_feed_config,
		_panel.skybox_config, _panel.sky_cycle,
	]
	var differing: int = 0
	# every differing field is edited first, then one reset_all()
	# (a full ~2900-node rebuild) restores them all, then every field gets the same
	# per-field assertions as before (was one reset_all() per field).
	var edited: Array[Dictionary] = []
	for resource: Resource in resources:
		var shipped: Resource = ResourceLoader.load(resource.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		var gd_default: Resource = (resource.get_script() as Script).new() as Resource
		for prop_name: String in _shown_fields_for(_panel, resource):
			var type: int = typeof(resource.get(prop_name))
			if type != TYPE_FLOAT and type != TYPE_INT:
				continue
			if is_equal_approx(float(shipped.get(prop_name)), float(gd_default.get(prop_name))):
				continue
			# A field whose .tres value differs from its .gd default.
			differing += 1
			resource.set(prop_name, float(shipped.get(prop_name)) + 1.0 if type == TYPE_FLOAT else int(shipped.get(prop_name)) + 1)
			edited.append({"resource": resource, "prop": prop_name, "type": type, "shipped": shipped.get(prop_name)})
	_panel.reset_all()
	_show_all_tabs(_panel)
	for entry: Dictionary in edited:
		var resource: Resource = entry["resource"] as Resource
		var prop_name: String = entry["prop"] as String
		var type: int = entry["type"] as int
		var shipped_value: Variant = entry["shipped"]
		assert_true(is_equal_approx(float(resource.get(prop_name)), float(shipped_value)), "%s.%s must return to the shipped .tres value." % [resource, prop_name])
		var label: String = _label_text_for(_panel, resource, prop_name)
		assert_false(label.begins_with("•"), "%s must not carry the modified marker after Reset." % label)
		var row: Dictionary = _row(_panel, resource, prop_name)
		assert_true(label.contains((row["default_label"] as Label).text), "%s must carry its default column text." % label)
		assert_true(is_equal_approx(float(row["default"]), float(shipped_value)), "%s default must be the shipped value." % prop_name)
	assert_gt(differing, 0, "fixture: at least one shipped value differs from its script default")
	gut.p("fields whose .tres differs from .gd default: %d" % differing)


# --- Sky tab ----------------------------------------

func _find_option_named(node: Node, option_name: String) -> OptionButton:
	if node is OptionButton and node.name == option_name:
		return node as OptionButton
	for child: Node in node.get_children():
		var found: OptionButton = _find_option_named(child, option_name)
		if found != null:
			return found
	return null


## Records every Skybox API call the Sky tab makes, without the real Skybox's
## scene build (its _ready() only joins the tuning group). Behaviour lands with
## package C1a; U1 only has to route through the API.
class SpySkybox extends Skybox:
	var cycle_active: bool = false
	var locked: float = -1.0
	var phase_now: float = 0.4
	var start_calls: Array[Vector2] = []
	var lock_calls: Array[float] = []
	var refresh_calls: int = 0

	func _ready() -> void:
		add_to_group(Skybox.TUNING_GROUP)

	func start_cycle(lock_at: float = -1.0, open_at: float = -1.0) -> void:
		start_calls.append(Vector2(lock_at, open_at))
		cycle_active = true
		locked = lock_at

	func set_locked_phase(phase: float) -> void:
		lock_calls.append(phase)
		locked = phase

	func locked_phase() -> float:
		return locked

	func is_cycle_active() -> bool:
		return cycle_active

	func current_cycle_phase() -> float:
		return phase_now if cycle_active else -1.0

	func refresh_sky_def() -> void:
		refresh_calls += 1

	# Reset also re-applies the six-face set and the reflection probe; the spy has
	# built no faces or probe, so those two are inert.
	func apply_set(_set_name: String, _root_override: String = "") -> bool:
		return true

	func refresh_from_visuals() -> void:
		pass


func _make_spy_skybox(cycle_active: bool) -> SpySkybox:
	var spy: SpySkybox = SpySkybox.new()
	spy.cycle_active = cycle_active
	add_child_autofree(spy)
	return spy


func _find_control_named(node: Node, control_name: String) -> Control:
	if node is Control and node.name == control_name:
		return node as Control
	for child: Node in node.get_children():
		var found: Control = _find_control_named(child, control_name)
		if found != null:
			return found
	return null


func _sky_page(panel: TuningPanel) -> Control:
	var tabs: TabContainer = panel._tab_container
	return tabs.get_node("Sky") as Control


func test_time_of_day_controls_lock_the_live_cycle() -> void:
	_own_panel(false)
	var spy: SpySkybox = _make_spy_skybox(true)
	_panel.rebuild()
	_show_tab(_panel, "Sky")
	var option: OptionButton = _find_option_named(_panel, "TimeOfDayOption")
	var slider: HSlider = _find_control_named(_panel, "TimeOfDaySlider") as HSlider
	assert_not_null(option, "expected a Time of day control on the Sky tab")
	assert_not_null(slider, "expected a Time of day slider on the Sky tab")
	var sunset: float = _panel.sky_cycle.locked_phase_for("sunset")
	assert_gt(sunset, -0.5, "fixture: the cycle locks a phase for sunset")
	var sunset_index: int = -1
	var custom_index: int = -1
	for index: int in range(option.item_count):
		var text: String = option.get_item_text(index).to_lower()
		if text == "sunset":
			sunset_index = index
		elif text == "custom":
			custom_index = index
	option.select(sunset_index)
	option.item_selected.emit(sunset_index)
	assert_almost_eq(spy.lock_calls[-1], sunset, 0.0001, "choosing Sunset locks the cycle at its phase")
	assert_false(slider.editable, "the slider is for Custom only")
	option.select(custom_index)
	option.item_selected.emit(custom_index)
	assert_true(slider.editable)
	slider.value_changed.emit(0.6)
	assert_almost_eq(spy.lock_calls[-1], 0.6, 0.0001, "the slider moves the lock")
	assert_eq(option.selected, custom_index, "the choice still shows Custom after a slider move")
	option.select(0)
	option.item_selected.emit(0)
	assert_almost_eq(spy.lock_calls[-1], -1.0, 0.0001, "the first choice, Running, unlocks")


## Editing a Sky-tab slider reaches a live resource and refreshes the Skybox.
func test_editing_a_sky_field_reaches_the_resource_and_refreshes_the_skybox() -> void:
	_own_panel(false)
	var spy: SpySkybox = _make_spy_skybox(true)
	spy.sky_def = _panel.sky_cycle.duplicate() as SkyCycleDef
	_panel.rebuild()
	_show_tab(_panel, "Sky")
	var before: Dictionary = _sky_values(_panel)
	var refreshed: bool = false
	for node: Node in _sky_page(_panel).find_children("*", "HSlider", true, false):
		var slider: HSlider = node as HSlider
		if slider.name == "TimeOfDaySlider" or not slider.editable:
			continue
		slider.value = slider.min_value if not is_equal_approx(slider.value, slider.min_value) else slider.max_value
		if spy.refresh_calls > 0:
			refreshed = true
			break
	assert_true(refreshed, "a sky slider edit refreshes the live Skybox")
	assert_ne(_sky_values(_panel), before, "the edit reached a sky resource")


func _sky_values(panel: TuningPanel) -> Dictionary:
	var values: Dictionary = {}
	var resources: Array[Resource] = [panel.sky_cycle, panel.sky_cycle.night, panel.storm_overlay]
	resources.append_array(panel.sky_cycle.day_keyframes)
	for resource: Resource in resources:
		for prop: Dictionary in resource.get_property_list():
			if int(prop.get("usage", 0)) & PROPERTY_USAGE_EDITOR != 0 and typeof(resource.get(prop["name"])) == TYPE_FLOAT:
				values["%d:%s" % [resource.get_instance_id(), prop["name"]]] = resource.get(prop["name"])
	return values


func test_the_sky_tab_fields_can_take_focus() -> void:
	_own_panel(false)
	_panel.rebuild()
	_panel.show()
	_show_tab(_panel, "Sky")
	assert_gt(FocusWalk.live_focusable(_sky_page(_panel)).size(), 0, "the Sky tab's rows can take focus")



func test_persistence_disallowed_for_headless_non_gut_run() -> void:
	assert_false(UserPaths.persistence_allowed_for(false, "headless"))
	assert_true(UserPaths.persistence_allowed_for(false, "windows"))
	assert_true(UserPaths.persistence_allowed_for(true, "headless"))
	assert_true(UserPaths.persistence_allowed(), "GUT runs keep writing to the per-PID files.")


## a GUT run must never touch the owner's real overrides file.
func test_gut_run_save_overrides_never_touches_real_file() -> void:
	var real: String = TuningPanel.SAVE_PATH
	var existed: bool = FileAccess.file_exists(real)
	var mtime: int = FileAccess.get_modified_time(real) if existed else 0
	assert_ne(TuningPanel.save_path(), real, "GUT run maps to a per-PID file")
	assert_eq(_panel.save_overrides(), OK)
	assert_true(FileAccess.file_exists(TuningPanel.save_path()), "wrote the GUT file")
	assert_eq(FileAccess.file_exists(real), existed, "real file existence unchanged")
	if existed:
		assert_eq(FileAccess.get_modified_time(real), mtime, "real file mtime unchanged")
