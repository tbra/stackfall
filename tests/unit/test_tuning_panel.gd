extends GutTest
## Bontago-mv0.18: ui/TuningPanel.gd's reflection-built tabs (one control per
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
## (game/Main.gd now calls TuningPanel.apply_saved_overrides() first thing).

var _panel: TuningPanel = null

var _saved_gravity: float
var _saved_friction: float
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
var _saved_skybox_default_set: String
var _saved_skybox_enabled: bool


func before_each() -> void:
	_panel = autofree(load("res://ui/TuningPanel.tscn").instantiate())
	add_child_autofree(_panel)

	_saved_gravity = _panel.physics_tuning.gravity_multiplier
	_saved_friction = _panel.physics_tuning.block_friction
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
	_saved_skybox_default_set = _panel.skybox_config.default_set
	_saved_skybox_enabled = _panel.skybox_config.enabled


func after_each() -> void:
	_panel.physics_tuning.gravity_multiplier = _saved_gravity
	_panel.physics_tuning.block_friction = _saved_friction
	_panel.physics_tuning.block_bounce = _saved_bounce
	_panel.physics_tuning.block_linear_damp = _saved_linear_damp
	_panel.physics_tuning.block_angular_damp = _saved_angular_damp
	_panel.physics_tuning.cube_mass = _saved_cube_mass
	_panel.physics_tuning.rebound_damping = _saved_rebound_damping
	_panel.camera_tuning.follow_block = _saved_follow_block
	_panel.camera_tuning.follow_distance = _saved_follow_distance
	_panel.territory_tuning.max_cell_toggles_per_frame = _saved_max_cell_toggles
	_panel.ghost_tuning.tint_color = _saved_tint_color
	_panel.territory_visuals.disk_metallic = _saved_disk_metallic
	_panel.skybox_config.default_set = _saved_skybox_default_set
	_panel.skybox_config.enabled = _saved_skybox_enabled

	Input.action_release(&"pause_menu")

	var dir: DirAccess = DirAccess.open("user://")
	if dir != null and dir.file_exists("tuning_overrides.cfg"):
		dir.remove("tuning_overrides.cfg")


# --- Reflection: one control per exported field ------------------------------

## PhysicsTuning is 15 plain floats and nothing else (config/PhysicsTuning.gd,
## Bontago-xtq.17 added rebound_damping) -- no Color/Array/bool fields to
## complicate the count -- so it is the clean "one control per numeric field"
## fixture the design brief asks for.
func test_physics_tab_builds_one_control_per_exported_float_field() -> void:
	assert_eq(_panel.row_count_for(_panel.physics_tuning), 15)


func test_float_field_gets_an_hslider() -> void:
	var control: Control = _panel.control_for(_panel.physics_tuning, "gravity_multiplier")
	assert_true(control is HSlider)
	assert_almost_eq((control as HSlider).value, _saved_gravity, 0.0001)


func test_int_field_gets_a_spinbox() -> void:
	var control: Control = _panel.control_for(_panel.territory_tuning, "max_cell_toggles_per_frame")
	assert_true(control is SpinBox)
	assert_almost_eq((control as SpinBox).value, float(_saved_max_cell_toggles), 0.0001)


func test_bool_field_gets_a_checkbutton() -> void:
	var control: Control = _panel.control_for(_panel.camera_tuning, "follow_block")
	assert_true(control is CheckButton)
	assert_eq((control as CheckButton).button_pressed, _saved_follow_block)


func test_color_field_gets_a_colorpickerbutton() -> void:
	var control: Control = _panel.control_for(_panel.ghost_tuning, "tint_color")
	assert_true(control is ColorPickerButton)
	assert_true((control as ColorPickerButton).color.is_equal_approx(_saved_tint_color))


func test_array_and_packed_array_fields_get_no_control() -> void:
	assert_null(_panel.control_for(_panel.block_feed_config, "shapes"))
	assert_null(_panel.control_for(_panel.block_feed_config, "weight_overrides"))
	assert_null(_panel.control_for(_panel.block_feed_config, "stabilizer_ids"))


# --- Controls write the live resource -----------------------------------------
#
# Range/SpinBox's own C++ setter does not emit value_changed synchronously
# from a plain property assignment (verified against this engine build: only
# a real mouse drag or an explicit emit_signal() does) -- emit_signal() is
# exactly how Godot itself would eventually deliver that signal to this
# panel's connected Callable, so driving it directly here is the deterministic
# equivalent of a user dragging the control, the same idea as this project's
# other GUT UI tests (e.g. tests/unit/test_net_debug_overlay.gd emits
# Events.net_stats_updated directly rather than waiting on a real network
# tick).

func test_slider_change_writes_the_resource() -> void:
	var slider: HSlider = _panel.control_for(_panel.physics_tuning, "gravity_multiplier") as HSlider
	slider.emit_signal("value_changed", 2.4)
	assert_almost_eq(_panel.physics_tuning.gravity_multiplier, 2.4, 0.0001)


func test_spinbox_change_writes_the_resource() -> void:
	var spin: SpinBox = _panel.control_for(_panel.territory_tuning, "max_cell_toggles_per_frame") as SpinBox
	spin.emit_signal("value_changed", 10.0)
	assert_eq(_panel.territory_tuning.max_cell_toggles_per_frame, 10)


func test_checkbutton_change_writes_the_resource() -> void:
	var check: CheckButton = _panel.control_for(_panel.camera_tuning, "follow_block") as CheckButton
	check.emit_signal("toggled", not _saved_follow_block)
	assert_eq(_panel.camera_tuning.follow_block, not _saved_follow_block)


func test_colorpicker_change_writes_the_resource() -> void:
	var picker: ColorPickerButton = _panel.control_for(_panel.ghost_tuning, "tint_color") as ColorPickerButton
	var new_color: Color = Color(0.1, 0.2, 0.3, 0.4)
	picker.emit_signal("color_changed", new_color)
	assert_true(_panel.ghost_tuning.tint_color.is_equal_approx(new_color))


# --- Physics live-apply: an existing Block, not just new spawns --------------

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


# --- Bontago-xtq.17: Physics preset dropdown ---------------------------------

func test_physics_tab_has_a_preset_option_button_with_three_presets() -> void:
	var physics_tab: Control = _panel._tab_container.get_node("Physics")
	var found: Array[Node] = physics_tab.find_children("*", "OptionButton", true, false)
	assert_eq(found.size(), 1)
	assert_eq((found[0] as OptionButton).item_count, 3)


func test_apply_physics_preset_copies_values_and_reapplies_live() -> void:
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = BlockFactory.build(shape, _panel.physics_tuning)
	add_child_autofree(block)  # _ready() joins Block.TUNING_GROUP for real.

	_panel.apply_physics_preset("heavy_bouncy")

	var preset: PhysicsTuning = load("res://config/physics_presets/heavy_bouncy.tres")
	assert_almost_eq(_panel.physics_tuning.cube_mass, preset.cube_mass, 0.0001)
	assert_almost_eq(_panel.physics_tuning.gravity_multiplier, preset.gravity_multiplier, 0.0001)
	assert_almost_eq(_panel.physics_tuning.rebound_damping, preset.rebound_damping, 0.0001)
	assert_almost_eq(
		block.gravity_scale, preset.gravity_multiplier, 0.0001,
		"a preset pick must reach an already-standing block via apply_physics_live(), not just write the Resource."
	)


func test_apply_physics_preset_current_matches_the_shipped_defaults() -> void:
	_panel.physics_tuning.gravity_multiplier = 99.0
	_panel.physics_tuning.rebound_damping = 0.1

	_panel.apply_physics_preset("current")

	assert_almost_eq(_panel.physics_tuning.gravity_multiplier, _saved_gravity, 0.0001)
	assert_almost_eq(_panel.physics_tuning.rebound_damping, 1.0, 0.0001)


func test_apply_physics_preset_ignores_an_unknown_id() -> void:
	var before: float = _panel.physics_tuning.gravity_multiplier
	_panel.apply_physics_preset("not_a_real_preset")
	assert_almost_eq(_panel.physics_tuning.gravity_multiplier, before, 0.0001)


# --- Bontago-xtq.22: Skybox dropdown (Territory tab) -------------------------
# (owner: disc reflectivity is "hard to judge with that texture -- add an
# option to F4 to change the skybox"). Every assertion below reads
# Skybox.list_available_sets() itself rather than a hardcoded set name, so
# this stays green on a checkout with the (gitignored, third-party) original
# textures installed AND on a bare CI checkout with none installed -- see
# tools/install_original_assets.ps1 and game/Skybox.gd's own class doc on why
# those assets never ship in this repo.

func _find_skybox_option(tab: Control) -> OptionButton:
	for node: Node in tab.find_children("*", "OptionButton", true, false):
		var option: OptionButton = node as OptionButton
		if option.item_count > 0 and option.get_item_text(0) == "Procedural / none":
			return option
	return null


func test_territory_tab_has_a_skybox_option_button_listing_procedural_and_every_discovered_set() -> void:
	var territory_tab: Control = _panel._tab_container.get_node("Territory")
	var option: OptionButton = _find_skybox_option(territory_tab)
	assert_not_null(option, "expected a Skybox OptionButton with 'Procedural / none' as its first item")

	var expected_sets: PackedStringArray = Skybox.list_available_sets()
	assert_eq(option.item_count, expected_sets.size() + 1)
	for i: int in range(expected_sets.size()):
		assert_eq(option.get_item_text(i + 1), expected_sets[i])


func test_skybox_row_preselects_the_current_config_value() -> void:
	var available: PackedStringArray = Skybox.list_available_sets()
	var target_id: String = available[0] if available.size() > 0 else Skybox.PROCEDURAL_SET_ID
	_panel.skybox_config.default_set = target_id
	_panel.skybox_config.enabled = target_id != Skybox.PROCEDURAL_SET_ID

	_panel.rebuild()

	var territory_tab: Control = _panel._tab_container.get_node("Territory")
	var option: OptionButton = _find_skybox_option(territory_tab)
	var expected_text: String = "Procedural / none" if target_id == Skybox.PROCEDURAL_SET_ID else target_id
	assert_eq(option.get_item_text(option.selected), expected_text)


func test_apply_skybox_set_writes_the_config_and_reaches_a_live_skybox() -> void:
	var skybox: Skybox = Skybox.new()
	skybox.config = _panel.skybox_config
	add_child_autofree(skybox)  # _ready() joins Skybox.TUNING_GROUP for real.

	_panel.apply_skybox_set("bontago-xtq22-no-such-set")

	assert_eq(_panel.skybox_config.default_set, "bontago-xtq22-no-such-set")
	assert_true(_panel.skybox_config.enabled)
	assert_true(
		skybox.fallback_active,
		"an unknown set falls back cleanly, but fallback_active only flips via Skybox.apply_set() actually " +
		"running on this live node -- proves the panel pushed the pick, not just wrote the Resource."
	)


func test_apply_skybox_set_procedural_disables_the_live_skybox() -> void:
	var skybox: Skybox = Skybox.new()
	skybox.config = _panel.skybox_config
	add_child_autofree(skybox)

	_panel.apply_skybox_set(Skybox.PROCEDURAL_SET_ID)

	assert_false(_panel.skybox_config.enabled)
	assert_true(skybox.fallback_active)


func test_apply_skybox_set_is_safe_with_no_live_skybox_in_the_tree() -> void:
	# No Skybox ever joined Skybox.TUNING_GROUP here -- must not error, and must
	# still write the shared config so Save override/Copy see the pick.
	_panel.apply_skybox_set("some-set")
	assert_eq(_panel.skybox_config.default_set, "some-set")
	assert_true(_panel.skybox_config.enabled)


## Same deterministic-equivalent-of-a-real-click technique this file's own
## header documents for HSlider/SpinBox/CheckButton/ColorPickerButton: driving
## the control's own signal directly is what a real mouse click eventually
## delivers too.
func test_selecting_the_skybox_dropdown_item_applies_it() -> void:
	var skybox: Skybox = Skybox.new()
	skybox.config = _panel.skybox_config
	add_child_autofree(skybox)

	var territory_tab: Control = _panel._tab_container.get_node("Territory")
	var option: OptionButton = _find_skybox_option(territory_tab)
	# Last item is always the highest-sorted discovered set, or index 0
	# (Procedural, the only item) if none are installed -- either way a real,
	# in-range index distinct from whatever _find_skybox_option()'s own probe
	# (index 0) selected by default.
	var target_index: int = option.item_count - 1
	option.selected = target_index
	option.emit_signal("item_selected", target_index)

	var item_text: String = option.get_item_text(target_index)
	if item_text == "Procedural / none":
		assert_false(_panel.skybox_config.enabled)
	else:
		assert_eq(_panel.skybox_config.default_set, item_text)
		assert_true(_panel.skybox_config.enabled)


func test_a_slider_drag_reaches_an_already_placed_block_end_to_end() -> void:
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = BlockFactory.build(shape, _panel.physics_tuning)
	add_child_autofree(block)

	var slider: HSlider = _panel.control_for(_panel.physics_tuning, "block_linear_damp") as HSlider
	slider.emit_signal("value_changed", 0.9)

	assert_almost_eq(block.linear_damp, 0.9, 0.0001, "changing the field must push the live-apply hook too, not just write the Resource.")


# --- Territory visuals live-apply --------------------------------------------

func test_territory_visuals_change_refreshes_a_wired_overlays_shader_uniform() -> void:
	var field: Field = autofree(Field.new())
	add_child_autofree(field)  # Field._ready() builds a real, configured overlay.
	_panel.set_field(field)

	var saved_metallic: float = _panel.territory_visuals.disk_metallic
	_panel.territory_visuals.disk_metallic = saved_metallic + 0.3

	_panel.refresh_territory_visuals_live()

	var material: ShaderMaterial = field.overlay().material()
	assert_almost_eq(float(material.get_shader_parameter(&"base_metallic")), saved_metallic + 0.3, 0.0001)


func test_refresh_territory_visuals_live_is_a_no_op_with_no_field_wired() -> void:
	# _panel here never had set_field() called -- must not error.
	_panel.refresh_territory_visuals_live()
	assert_true(true, "no field wired must not error.")


# --- Camera live-apply (Bontago-mv0.20b) -------------------------------------


func test_camera_tuning_slider_change_reaches_a_camera_rig_in_the_tree() -> void:
	var rig: CameraRig = autofree(load("res://game/CameraRig.tscn").instantiate())
	add_child_autofree(rig)  # rig._ready() joins CameraRig.TUNING_GROUP for real.
	rig.tuning = _panel.camera_tuning  # the same live singleton this panel edits.
	assert_true(rig.tuning.follow_block, "fixture: follow_block defaults to true.")

	var slider: HSlider = _panel.control_for(_panel.camera_tuning, "follow_distance") as HSlider
	slider.emit_signal("value_changed", rig.tuning.zoom_max + 999.0)

	assert_almost_eq(
		rig.get_distance(), rig.tuning.zoom_max, 0.0001,
		"changing the field must push apply_follow_tuning() too, not just write the Resource."
	)


func test_apply_camera_tuning_live_is_a_noop_with_no_rig_in_the_tree() -> void:
	# No CameraRig ever joined CameraRig.TUNING_GROUP here -- must not error.
	_panel.apply_camera_tuning_live()
	assert_true(true, "no rig in the tree must not error.")


# --- Reset / Save / Copy ------------------------------------------------------

func test_reset_reloads_physics_tuning_from_disk() -> void:
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
	# exactly what game/Main.gd's boot hook does before anything else runs.
	_panel.physics_tuning.gravity_multiplier = original_gravity
	_panel.camera_tuning.follow_distance = original_follow_distance

	TuningPanel.apply_saved_overrides()

	assert_almost_eq(_panel.physics_tuning.gravity_multiplier, original_gravity + 0.6, 0.0001)
	assert_almost_eq(_panel.camera_tuning.follow_distance, original_follow_distance + 3.0, 0.0001)


func test_apply_saved_overrides_ignores_a_stale_unknown_key() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("PhysicsTuning", "no_longer_a_real_field", 999.0)
	assert_eq(config.save("user://tuning_overrides.cfg"), OK)

	# Must not error (Object.set() on an unknown property is otherwise silently
	# ignored by Godot itself, but the explicit valid-key filter is what this
	# test pins).
	TuningPanel.apply_saved_overrides()
	assert_true(true, "a stale key must not raise an error.")


func test_copy_text_includes_every_resource_section_and_current_values() -> void:
	_panel.physics_tuning.gravity_multiplier = 1.75

	var text: String = _panel.build_copy_text()

	assert_true(text.contains("# CameraTuning"))
	assert_true(text.contains("# GhostTuning"))
	assert_true(text.contains("# PhysicsTuning"))
	assert_true(text.contains("# TerritoryTuning"))
	assert_true(text.contains("# TerritoryVisuals"))
	assert_true(text.contains("# BlockFeedConfig"))
	assert_true(text.contains("gravity_multiplier = 1.75"))


# --- Availability: host/offline vs. client -----------------------------------

func test_offline_shows_every_tab() -> void:
	_panel.net_provider = FakeNet.offline()
	_panel.rebuild()
	for index: int in range(_panel._tab_container.get_tab_count()):
		assert_false(_panel._tab_container.is_tab_hidden(index))


func test_host_shows_every_tab() -> void:
	_panel.net_provider = FakeNet.host()
	_panel.rebuild()
	for index: int in range(_panel._tab_container.get_tab_count()):
		assert_false(_panel._tab_container.is_tab_hidden(index))


func test_client_hides_physics_territory_and_feed_but_not_camera_or_controls() -> void:
	_panel.net_provider = FakeNet.client(0)
	_panel.rebuild()
	assert_false(_panel._tab_container.is_tab_hidden(0), "Camera")
	assert_false(_panel._tab_container.is_tab_hidden(1), "Controls")
	for index: int in range(2, _panel._tab_container.get_tab_count()):
		assert_true(_panel._tab_container.is_tab_hidden(index), "tab %d (Physics/Territory/Feed)" % index)


# --- Toggle: F4 / gamepad Start+X --------------------------------------------

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
	var event: InputEventKey = _key_press(KEY_F4)
	assert_true(event.is_action_pressed(&"tuning_panel_toggle"), "F4 should map to tuning_panel_toggle")

	assert_false(_panel.visible)
	_panel._unhandled_input(event)
	assert_true(_panel.visible)
	_panel._unhandled_input(event)
	assert_false(_panel.visible)


func test_toggle_suppresses_and_restores_controller_input() -> void:
	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	_panel.set_controller(controller)
	assert_true(controller.input_enabled, "fixture: input starts enabled")

	_panel._unhandled_input(_key_press(KEY_F4))
	assert_false(controller.input_enabled, "opening the panel must suppress gameplay input")

	_panel._unhandled_input(_key_press(KEY_F4))
	assert_true(controller.input_enabled, "closing the panel must restore it")


func test_gamepad_x_alone_does_not_toggle() -> void:
	var event: InputEventJoypadButton = _pad_press(JOY_BUTTON_X)
	assert_true(event.is_action_pressed(&"tuning_panel_toggle"))

	_panel._unhandled_input(event)
	assert_false(_panel.visible, "X alone is hover_lower, not the tuning-panel chord.")


func test_gamepad_start_plus_x_toggles() -> void:
	Input.action_press(&"pause_menu")
	var event: InputEventJoypadButton = _pad_press(JOY_BUTTON_X)

	_panel._unhandled_input(event)

	assert_true(_panel.visible, "Start held + X pressed should toggle the panel.")


# --- Bontago-xtq.13 (owner playtest 2026-09-23, "F4 should remember which
# tab was active when reopened") ---------------------------------------------

## Must fail against the pre-xtq.13 code (rebuild() on every reopen replaced
## every tab page with no restore step, so TabContainer.current_tab silently
## landed back on 0) and pass once the panel remembers the tab across a
## close/reopen in the same session.
func test_f4_remembers_selected_tab_across_close_and_reopen() -> void:
	_panel._unhandled_input(_key_press(KEY_F4))
	assert_true(_panel.visible, "fixture: opened.")

	# Same deterministic-equivalent-of-a-real-click technique this file's own
	# header already documents for HSlider/SpinBox/CheckButton/
	# ColorPickerButton: TabContainer.current_tab's own C++ setter does not
	# emit tab_changed synchronously from a plain property assignment on this
	# engine build either, only a real click (or an explicit emit) does.
	var target_tab: int = _panel._tab_container.get_tab_count() - 1
	_panel._tab_container.current_tab = target_tab
	_panel._tab_container.emit_signal("tab_changed", target_tab)

	_panel._unhandled_input(_key_press(KEY_F4))  # close
	assert_false(_panel.visible)

	_panel._unhandled_input(_key_press(KEY_F4))  # reopen -> rebuild()
	assert_true(_panel.visible)
	assert_eq(
		_panel._tab_container.current_tab, target_tab,
		"F4 must remember the tab that was open when it closed, not reset to tab 0."
	)


## The same memory, but via a real save/load round trip through SAVE_PATH
## (test_save_and_apply_saved_overrides_round_trip_via_user_dir's own idea,
## applied to _selected_tab_index instead of a tuning field) -- proves the tab
## choice survives a fresh TuningPanel instance (a stand-in for a full app
## restart), not just the same live panel object.
func test_selected_tab_index_persists_across_a_fresh_panel_instance() -> void:
	var target_tab: int = _panel._tab_container.get_tab_count() - 1
	_panel._tab_container.current_tab = target_tab
	_panel._tab_container.emit_signal("tab_changed", target_tab)
	assert_eq(_panel._selected_tab_index, target_tab, "fixture: tab_changed must update the panel's own bookkeeping.")

	var fresh_panel: TuningPanel = autofree(load("res://ui/TuningPanel.tscn").instantiate())
	add_child_autofree(fresh_panel)

	assert_eq(
		fresh_panel._tab_container.current_tab, target_tab,
		"a brand-new panel instance must read the persisted tab straight from disk in its own _ready()."
	)


# --- Bontago-mv0.21: owner-tuned defaults --------------------------------------

func test_camera_tuning_default_values() -> void:
	var fresh: CameraTuning = CameraTuning.new()
	assert_almost_eq(fresh.follow_lag_seconds, 0.0, 0.0001)
	assert_almost_eq(fresh.follow_pitch_deg, -35.0, 0.0001)


func test_ghost_tuning_default_value() -> void:
	var fresh: GhostTuning = GhostTuning.new()
	assert_almost_eq(fresh.block_move_sensitivity, 0.015, 0.0001)


# --- Bontago-mv0.21: self-describing rows (default + description) -------------

func test_every_row_label_shows_its_default_value() -> void:
	var resources: Array[Resource] = [
		_panel.camera_tuning, _panel.ghost_tuning, _panel.physics_tuning,
		_panel.territory_tuning, _panel.territory_visuals, _panel.block_feed_config,
	]
	var checked_any: bool = false
	for resource: Resource in resources:
		for prop_name: String in _panel.shown_fields_for(resource):
			checked_any = true
			var text: String = _panel.label_text_for(resource, prop_name)
			assert_true(text.contains("(default"), "%s.%s label %s must show its default" % [resource, prop_name, text])
	assert_true(checked_any, "fixture: at least one row must exist to check.")


func test_every_shown_field_has_a_non_empty_description() -> void:
	var resources: Array[Resource] = [
		_panel.camera_tuning, _panel.ghost_tuning, _panel.physics_tuning,
		_panel.territory_tuning, _panel.territory_visuals, _panel.block_feed_config,
	]
	var checked_any: bool = false
	for resource: Resource in resources:
		var class_label: String = String((resource.get_script() as Script).get_global_name())
		for prop_name: String in _panel.shown_fields_for(resource):
			checked_any = true
			var description: String = _panel.hints.description_for(class_label, prop_name)
			assert_false(description.is_empty(), "%s.%s has no description in TuningPanelHints" % [class_label, prop_name])
	assert_true(checked_any, "fixture: at least one row must exist to check.")


# --- Bontago-mv0.21: modified marker -------------------------------------------

func test_modified_marker_toggles_on_change_and_clears_on_reset() -> void:
	assert_false(_panel.is_modified(_panel.physics_tuning, "gravity_multiplier"), "fixture: starts at its default.")

	var slider: HSlider = _panel.control_for(_panel.physics_tuning, "gravity_multiplier") as HSlider
	slider.emit_signal("value_changed", _saved_gravity + 0.5)

	assert_true(_panel.is_modified(_panel.physics_tuning, "gravity_multiplier"), "changing the value must mark the row modified.")
	assert_true(_panel.label_text_for(_panel.physics_tuning, "gravity_multiplier").begins_with("•"), "the label must carry the modified marker.")

	_panel.reset_all()

	assert_false(_panel.is_modified(_panel.physics_tuning, "gravity_multiplier"), "reset_all() must clear the modified marker.")
