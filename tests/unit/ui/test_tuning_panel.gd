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
## new Sky-tab write-through test below.
var _saved_sky_fog_density: float


## the ~2900-node tab UI is built once per script, not once per
## test. Tests that only read the panel or write resources/controls run against
## _shared; after_each repairs it (rebuild) if anything left it dirty (a "•"
## modified marker, open/hidden state, swapped providers or wiring). Tests that
## open/close the panel, swap providers, wire a field/controller or alter a
## control's selection take their own throw-away panel via _own_panel().
var _shared: TuningPanel = null
var _shared_sky_theme: SkyThemeDef = null


func before_all() -> void:
	_shared = load("res://ui/debug/TuningPanel.tscn").instantiate()
	add_child(_shared)
	_shared.rebuild()
	_shared_sky_theme = _shared.sky_theme


func after_all() -> void:
	if _shared != null:
		_shared.free()
		_shared = null


## A fresh panel for a test that mutates panel-level state. prebuild = false
## leaves the UI unbuilt for a test that rebuilds/opens it itself (half the cost).
func _own_panel(prebuild: bool) -> TuningPanel:
	var own: TuningPanel = autofree(load("res://ui/debug/TuningPanel.tscn").instantiate())
	add_child_autofree(own)
	if prebuild:
		own.rebuild()
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
	if _shared.sky_theme != _shared_sky_theme or _shared.net_provider != Net:
		return true
	var resources: Array[Resource] = [
		_shared.camera_tuning, _shared.ghost_tuning, _shared.physics_tuning,
		_shared.territory_tuning, _shared.territory_visuals, _shared.block_feed_config,
		_shared.sky_theme,
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
	_saved_sky_fog_density = _panel.sky_theme.fog_density


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
	_shared.sky_theme.fog_density = _saved_sky_fog_density

	Input.action_release(&"pause_menu")

	if FileAccess.file_exists(TuningPanel.save_path()):
		DirAccess.remove_absolute(TuningPanel.save_path())
	_panel = _shared
	if _shared_is_dirty():
		_shared.visible = false
		_shared.net_provider = Net
		_shared.sky_theme = _shared_sky_theme
		_shared.rebuild()


# --- Reflection: one control per exported field ------------------------------

func test_slider_change_writes_the_resource() -> void:
	var slider: HSlider = _control_for(_panel, _panel.physics_tuning, "gravity_multiplier") as HSlider
	slider.emit_signal("value_changed", 2.4)
	assert_almost_eq(_panel.physics_tuning.gravity_multiplier, 2.4, 0.0001)


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


func test_a_slider_drag_reaches_an_already_placed_block_end_to_end() -> void:
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = BlockFactory.build(shape, _panel.physics_tuning)
	add_child_autofree(block)

	var slider: HSlider = _control_for(_panel, _panel.physics_tuning, "block_linear_damp") as HSlider
	slider.emit_signal("value_changed", 0.9)

	assert_almost_eq(block.linear_damp, 0.9, 0.0001, "changing the field must push the live-apply hook too, not just write the Resource.")


# --- Territory visuals live-apply --------------------------------------------

func test_reset_reloads_physics_tuning_from_disk() -> void:
	_own_panel(false)
	var original: float = _panel.physics_tuning.gravity_multiplier
	_panel.physics_tuning.gravity_multiplier = original + 1.5

	_panel.reset_all()

	assert_almost_eq(_panel.physics_tuning.gravity_multiplier, original, 0.0001)


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
	w.set_host_override(host)
	return w


func test_weather_row_selection_forces_swaps_and_releases_on_the_host() -> void:
	_own_panel(false)
	_panel.net_provider = FakeNet.host()
	var weather: MatchWeather = _fake_weather(true)
	_panel.weather_provider = weather
	_panel.rebuild()
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


func test_gamepad_start_plus_x_toggles() -> void:
	_own_panel(false)
	Input.action_press(&"pause_menu")
	var event: InputEventJoypadButton = _pad_press(JOY_BUTTON_X)

	_panel._unhandled_input(event)

	assert_true(_panel.visible, "Start held + X pressed should toggle the panel.")


# --- ("F4 should remember which
# tab was active when reopened") ---------------------------------------------

func test_persistence_disallowed_for_headless_non_gut_run() -> void:
	assert_false(UserPaths.persistence_allowed_for(false, "headless"))
	assert_true(UserPaths.persistence_allowed_for(false, "windows"))
	assert_true(UserPaths.persistence_allowed_for(true, "headless"))
	assert_true(UserPaths.persistence_allowed(), "GUT runs keep writing to the per-PID files.")


# --- tuned defaults --------------------------------------

func test_reset_restores_shipped_tres_and_default_label_and_highlight_agree() -> void:
	var resources: Array[Resource] = [
		_panel.camera_tuning, _panel.ghost_tuning, _panel.physics_tuning,
		_panel.territory_tuning, _panel.territory_visuals, _panel.block_feed_config,
		_panel.skybox_config, _panel.sky_theme,
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
	gut.p("fields whose .tres differs from .gd default: %d" % differing)


## Test that every exported numeric/bool/Color property in the M7 config resources
## (BeaconVisualTuning, CameraShakeConfig, BlockEffectsConfig, HUDVisualTuning,
## SkyThemeDef) has both a range hint (for numeric fields) and a description hint
## in tuning_panel_hints.tres. These resources are not exposed in the TuningPanel
## UI yet, but hints are provided for future panel extension.
func test_m7_config_resources_have_complete_hints() -> void:
	var resources: Array[Resource] = [
		BeaconVisualTuning.new(),
		CameraShakeConfig.new(),
		BlockEffectsConfig.new(),
		HUDVisualTuning.new(),
		SkyThemeDef.new(),
		# the disc-top procedural surface.
		DiscSurfaceDef.new(),
		AmbientLifeConfig.new(),
		QualityGovernorConfig.new(),
	]

	var hints: TuningPanelHints = _panel.hints
	var checked_any: bool = false

	for resource: Resource in resources:
		var class_label: String = String((resource.get_script() as Script).get_global_name())

		for prop: Dictionary in resource.get_property_list():
			if not _panel._is_exported_field(prop):
				continue

			var prop_name: String = str(prop.get("name", ""))
			var type: int = int(prop.get("type", TYPE_NIL))
			checked_any = true

			# Every exported property must have a description.
			var description: String = hints.description_for(class_label, prop_name)
			assert_false(
				description.is_empty(),
				"%s.%s has no description in TuningPanelHints" % [class_label, prop_name]
			)

			# Numeric fields (float, int) must have a range.
			if type == TYPE_FLOAT or type == TYPE_INT:
				var range: Vector2 = hints.range_for(class_label, prop_name)
				var has_range: bool = not (is_nan(range.x) and is_nan(range.y))
				assert_true(
					has_range,
					"%s.%s (type %d) has no range in TuningPanelHints" % [class_label, prop_name, type]
				)

	assert_true(checked_any, "fixture: at least one M7 config field must exist to check.")


# --- Sky tab Theme dropdown ----------------------------------------

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
	var applied_themes: Array[SkyThemeDef] = []
	var theme_id_calls: Array[String] = []

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

	func refresh_cycle_sources() -> void:
		refresh_calls += 1

	func apply_theme(applied_theme: SkyThemeDef) -> void:
		applied_themes.append(applied_theme)

	func set_theme_by_id(theme_id: String) -> bool:
		theme_id_calls.append(theme_id)
		cycle_active = false
		return true

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


func test_time_of_day_row_routes_every_choice_through_set_locked_phase() -> void:
	_own_panel(false)
	var spy: SpySkybox = _make_spy_skybox(true)
	_panel.rebuild()
	var option: OptionButton = _find_option_named(_panel, "TimeOfDayOption")
	var slider: HSlider = _find_control_named(_panel, "TimeOfDaySlider") as HSlider
	assert_not_null(option, "expected a Time of day OptionButton on the Sky tab")
	assert_not_null(slider, "expected a Time of day slider on the Sky tab")
	var labels: Array[String] = []
	for index: int in range(option.item_count):
		labels.append(option.get_item_text(index))
	assert_eq(labels, ["Running", "Sunset", "Dawn", "Night", "Custom"])
	assert_eq(option.focus_mode, Control.FOCUS_ALL, "gamepad/keyboard focusable")
	assert_eq(slider.focus_mode, Control.FOCUS_ALL, "gamepad/keyboard focusable")
	assert_eq(option.selected, 0, "a running cycle shows Running")
	assert_false(option.disabled)
	assert_false(slider.editable, "the slider is for Custom only")

	var source: SkyThemeDef = Skybox.load_theme("sunset")
	var expected: Array[float] = [
		-1.0, source.locked_phase_for("sunset"), source.locked_phase_for("dawn"), source.locked_phase_for("night"),
	]
	for index: int in range(1, 4):
		assert_gt(expected[index], -0.5, "fixture: SkyThemeDef locks a phase for %s" % labels[index])
	for index: int in [1, 2, 3, 0]:
		option.select(index)
		option.item_selected.emit(index)
		assert_almost_eq(spy.lock_calls[-1], expected[index], 0.0001, "%s locks the cycle at its phase" % labels[index])
		assert_false(slider.editable)

	option.select(4)
	option.item_selected.emit(4)
	assert_almost_eq(spy.lock_calls[-1], spy.phase_now, 0.0001, "Custom locks where the cycle is now (no jump)")
	assert_true(slider.editable)
	assert_almost_eq(slider.value, spy.phase_now, 0.0001)
	slider.value_changed.emit(0.6)
	assert_almost_eq(spy.lock_calls[-1], 0.6, 0.0001, "the slider moves the lock")
	assert_eq(option.selected, TuningPanel.TIME_OF_DAY_CHOICES.find(TuningPanel.TIME_CUSTOM), "the dropdown still shows Custom after a slider move")
	assert_true(slider.editable, "the slider stays editable on Custom")
	option.select(0)
	option.item_selected.emit(0)
	assert_almost_eq(spy.lock_calls[-1], -1.0, 0.0001, "Running unlocks")
	assert_false(_panel.apply_time_of_day("midnight"), "an unknown choice is rejected")


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


# --- no unused rows, grouped and sorted ------------------------

## Fields read only through an accessor method on their own config class: the
## accessor name must still appear in live game code outside config/ and the panel.
const READ_VIA_ACCESSOR: Dictionary = {
	"GhostTuning.home_spawn_beacon_margin": "home_spawn_clear_hover",
	"GhostTuning.home_spawn_back_offset": "home_spawn_back_position",
	"QolExperiments.pause_max_s": "effective_pause_max_s",
	"QolExperiments.backlog_max": "effective_backlog_max",
	"QolExperiments.goal_radius_multiplier": "effective_goal_radius",
	"QolExperiments.gift_slot_min_window_s": "effective_gift_min_window_s",
	"QolExperiments.gift_queue_after_next": "gift_after_next_in_force",
	"SkyThemeDef.aurora_start_night_mix": "aurora_night_strength",
	"SkyThemeDef.aurora_full_night_mix": "aurora_night_strength",
	"SkyThemeDef.cycle_locked_phase_sunset": "locked_phase_for",
	"SkyThemeDef.cycle_locked_phase_dawn": "locked_phase_for",
	"SkyThemeDef.cycle_locked_phase_night": "locked_phase_for",
}
const LIVE_CODE_DIRS: PackedStringArray = ["game", "autoload", "core", "net", "ui", "shaders"]


func _collect_code(dir_path: String, out: PackedStringArray) -> void:
	for sub: String in DirAccess.get_directories_at(dir_path):
		_collect_code("%s/%s" % [dir_path, sub], out)
	for file_name: String in DirAccess.get_files_at(dir_path):
		if not (file_name.ends_with(".gd") or file_name.ends_with(".gdshader")):
			continue
		if file_name == "TuningPanel.gd":
			continue
		var text: String = FileAccess.get_file_as_string("%s/%s" % [dir_path, file_name])
		var kept: PackedStringArray = PackedStringArray()
		for line: String in text.split("
"):
			if not line.strip_edges().begins_with("#"):
				kept.append(line)
		out.append("
".join(kept))
