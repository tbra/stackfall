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
var _saved_skybox_default_set: String
var _saved_skybox_enabled: bool

## Bontago-xtq.36: saved/restored the same way every other live singleton
## field above is (this file's own header explains why) -- mutated by the
## new Sky-tab write-through test below.
var _saved_sky_fog_density: float


## Bontago-fca.38.1: the ~2900-node tab UI is built once per script, not once per
## test. Tests that only read the panel or write resources/controls run against
## _shared; after_each repairs it (rebuild) if anything left it dirty (a "•"
## modified marker, open/hidden state, swapped providers or wiring). Tests that
## open/close the panel, swap providers, wire a field/controller or alter a
## control's selection take their own throw-away panel via _own_panel().
var _shared: TuningPanel = null
var _shared_sky_theme: SkyThemeDef = null


func before_all() -> void:
	_shared = load("res://ui/TuningPanel.tscn").instantiate()
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
	var own: TuningPanel = autofree(load("res://ui/TuningPanel.tscn").instantiate())
	add_child_autofree(own)
	if prebuild:
		own.rebuild()
	_panel = own
	return own


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
		for prop_name: String in _shared.shown_fields_for(resource):
			if _shared.label_text_for(resource, prop_name).begins_with("•"):
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
	_saved_skybox_default_set = _panel.skybox_config.default_set
	_saved_skybox_enabled = _panel.skybox_config.enabled
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
	_shared.skybox_config.default_set = _saved_skybox_default_set
	_shared.skybox_config.enabled = _saved_skybox_enabled
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

## PhysicsTuning is 15 plain floats and nothing else (config/PhysicsTuning.gd,
## Bontago-xtq.17 added rebound_damping) -- no Color/Array/bool fields to
## complicate the count -- so it is the clean "one control per numeric field"
## fixture the design brief asks for.
func test_physics_tab_builds_one_control_per_exported_float_field() -> void:
	# Bontago-8or.10 (M8 P5): +2 for stable_freeze_delay_s and
	# stable_freeze_scan_interval_s (config/PhysicsTuning.gd's own new fields).
	# Bontago-8bc adds opt-in release tilt and minimum gap.
	# Bontago-1pi.11.24 adds stable_freeze_rest_epsilon_m.
	assert_eq(_panel.row_count_for(_panel.physics_tuning), 21)


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

func test_physics_tab_preset_dropdown_lists_one_item_per_shipped_preset() -> void:
	var physics_tab: Control = _panel._tab_container.get_node("Physics")
	var found: Array[Node] = physics_tab.find_children("*", "OptionButton", true, false)
	assert_eq(found.size(), 1)
	var dropdown: OptionButton = found[0] as OptionButton
	var preset_files: int = 0
	for file: String in DirAccess.get_files_at("res://config/physics_presets"):
		if file.ends_with(".tres"):
			preset_files += 1
	assert_eq(dropdown.item_count, preset_files, "one dropdown item per shipped preset file")
	var seen: Dictionary = {}
	for index: int in range(dropdown.item_count):
		var text: String = dropdown.get_item_text(index)
		assert_false(text.is_empty(), "item %d has a label" % index)
		assert_false(seen.has(text), "label %s is unique" % text)
		seen[text] = true


func test_original_feel_preset_live_values_and_current_clears_release_tilt() -> void:
	var block: Block = BlockFactory.build(load("res://config/blocks/cube.tres"), _panel.physics_tuning)
	add_child_autofree(block)
	_panel.apply_physics_preset("original_feel")
	assert_almost_eq(block.physics_material_override.bounce, 0.4, 0.0001)
	assert_almost_eq(block.angular_damp, 0.6, 0.0001)
	assert_almost_eq(block.tuning.release_tilt_degrees, 2.0, 0.0001)
	_panel.apply_physics_preset("current")
	assert_eq(block.tuning.release_tilt_degrees, 0.0)


func test_tokamak_preset_reaches_live_cube_and_disc_materials() -> void:
	_own_panel(false)
	var field: Field = Field.new()
	add_child_autofree(field)
	_panel.set_field(field)
	var block: Block = BlockFactory.build(load("res://config/blocks/cube.tres"), _panel.physics_tuning)
	add_child_autofree(block)
	_panel.apply_physics_preset("tokamak_defaults")
	assert_almost_eq(block.physics_material_override.friction, 0.5, 0.0001)
	assert_almost_eq(block.physics_material_override.bounce, 0.4, 0.0001)
	assert_almost_eq(field.physics_material_override.friction, 0.5, 0.0001)
	assert_almost_eq(block.linear_damp, 0.0, 0.0001)
	assert_almost_eq(block.angular_damp, 0.0, 0.0001)
	assert_almost_eq(_panel.physics_tuning.rebound_damping, 1.0, 0.0001)
	assert_almost_eq(_panel.physics_tuning.cube_mass, 1.0, 0.0001)
	assert_almost_eq(block.gravity_scale, 1.0, 0.0001)


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


func test_apply_physics_preset_overwrites_edited_values_with_the_preset_file() -> void:
	var preset: PhysicsTuning = load("res://config/physics_presets/heavy_bouncy.tres")
	_panel.physics_tuning.gravity_multiplier = preset.gravity_multiplier + 9.0
	_panel.physics_tuning.rebound_damping = preset.rebound_damping + 0.5

	_panel.apply_physics_preset("heavy_bouncy")

	assert_almost_eq(_panel.physics_tuning.gravity_multiplier, preset.gravity_multiplier, 0.0001)
	assert_almost_eq(_panel.physics_tuning.rebound_damping, preset.rebound_damping, 0.0001)


func test_apply_physics_preset_ignores_an_unknown_id() -> void:
	var before: float = _panel.physics_tuning.gravity_multiplier
	_panel.apply_physics_preset("not_a_real_preset")
	assert_almost_eq(_panel.physics_tuning.gravity_multiplier, before, 0.0001)


# --- Bontago-xtq.22: Skybox dropdown (Sky tab) --------------------------------
# (owner: disc reflectivity is "hard to judge with that texture -- add an
# option to F4 to change the skybox"). Every assertion below reads
# Skybox.list_available_sets() itself rather than a hardcoded set name, so
# this stays green on a checkout with the (gitignored, third-party) original
# textures installed AND on a bare CI checkout with none installed -- see
# tools/install_original_assets.ps1 and game/Skybox.gd's own class doc on why
# those assets never ship in this repo.
#
# Bontago-1pi.1 (owner playtest: "the skybox setting in territory should
# probably move over to sky settings"): this row moved from the Territory tab
# to the Sky tab -- every `_panel._tab_container.get_node("Territory")` below
# became `_panel._tab_container.get_node("Sky")`.

func _find_skybox_option(tab: Control) -> OptionButton:
	for node: Node in tab.find_children("*", "OptionButton", true, false):
		var option: OptionButton = node as OptionButton
		if option.item_count > 0 and option.get_item_text(0) == "Procedural / none":
			return option
	return null


func test_sky_tab_has_a_skybox_option_button_listing_procedural_and_every_discovered_set() -> void:
	var sky_tab: Control = _panel._tab_container.get_node("Sky")
	var option: OptionButton = _find_skybox_option(sky_tab)
	assert_not_null(option, "expected a Skybox OptionButton with 'Procedural / none' as its first item")

	var expected_sets: PackedStringArray = Skybox.list_available_sets()
	assert_eq(option.item_count, expected_sets.size() + 1)
	for i: int in range(expected_sets.size()):
		assert_eq(option.get_item_text(i + 1), expected_sets[i])


func test_skybox_row_preselects_the_current_config_value() -> void:
	_own_panel(false)
	var available: PackedStringArray = Skybox.list_available_sets()
	var target_id: String = available[0] if available.size() > 0 else Skybox.PROCEDURAL_SET_ID
	_panel.skybox_config.default_set = target_id
	_panel.skybox_config.enabled = target_id != Skybox.PROCEDURAL_SET_ID

	_panel.rebuild()

	var sky_tab: Control = _panel._tab_container.get_node("Sky")
	var option: OptionButton = _find_skybox_option(sky_tab)
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
	_own_panel(true)
	var skybox: Skybox = Skybox.new()
	skybox.config = _panel.skybox_config
	add_child_autofree(skybox)

	var sky_tab: Control = _panel._tab_container.get_node("Sky")
	var option: OptionButton = _find_skybox_option(sky_tab)
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
	_own_panel(false)
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
	_own_panel(false)
	var original: float = _panel.physics_tuning.gravity_multiplier
	_panel.physics_tuning.gravity_multiplier = original + 1.5

	_panel.reset_all()

	assert_almost_eq(_panel.physics_tuning.gravity_multiplier, original, 0.0001)


## Bontago-1pi.1 (owner playtest: "Sky settings in F4 doesn't reset"):
## reset_all() previously skipped sky_theme entirely (Bontago-xtq.36's own
## DECISION deferred it -- see reset_all()'s own comment). Wires a real
## Skybox (same fixture idiom test_sky_tab_fog_density_slider_writes_the_
## resource_and_reaches_a_live_skybox above uses) so this also pins "applies
## live", not just "the Resource field goes back to its file default".
func test_reset_reloads_sky_theme_from_disk_and_applies_live() -> void:
	_own_panel(false)
	var sky: Sky = Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	var environment: Environment = Environment.new()
	environment.sky = sky

	var skybox: Skybox = Skybox.new()
	skybox.config = _panel.skybox_config
	skybox.environment = environment
	add_child_autofree(skybox)  # _ready() joins Skybox.TUNING_GROUP for real.

	var original: float = _panel.sky_theme.fog_density
	_panel.sky_theme.fog_density = original + 0.5

	_panel.reset_all()

	assert_almost_eq(_panel.sky_theme.fog_density, original, 0.0001)
	assert_almost_eq(
		float(skybox.environment.fog_density), original, 0.0001,
		"reset must push apply_sky_theme_live() too, not just reload the Resource."
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
	# exactly what game/Main.gd's boot hook does before anything else runs.
	_panel.physics_tuning.gravity_multiplier = original_gravity
	_panel.camera_tuning.follow_distance = original_follow_distance

	TuningPanel.apply_saved_overrides()

	assert_almost_eq(_panel.physics_tuning.gravity_multiplier, original_gravity + 0.6, 0.0001)
	assert_almost_eq(_panel.camera_tuning.follow_distance, original_follow_distance + 3.0, 0.0001)


func test_apply_saved_overrides_ignores_a_stale_unknown_key() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("PhysicsTuning", "no_longer_a_real_field", 999.0)
	assert_eq(config.save(TuningPanel.save_path()), OK)

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


# --- Bontago-470.1: F4 Weather row ---------------------------------------------

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


func test_weather_row_lists_schedule_off_and_every_registered_type() -> void:
	_own_panel(false)
	_panel.net_provider = FakeNet.host()
	_panel.weather_provider = _fake_weather(true)
	_panel.rebuild()
	var option: OptionButton = _weather_option()
	assert_not_null(option)
	var texts: Array[String] = []
	for i: int in range(option.item_count):
		texts.append(option.get_item_text(i))
	assert_eq(texts, ["Schedule (lobby mode)", "Off", "Rain", "Snow", "Storm"])
	assert_false(option.disabled)


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


func test_weather_row_is_disabled_on_a_client_and_changes_nothing() -> void:
	_own_panel(false)
	_panel.net_provider = FakeNet.client(0)
	var weather: MatchWeather = _fake_weather(false)
	_panel.weather_provider = weather
	_panel.rebuild()
	assert_true(_weather_option().disabled)
	assert_false(_panel.apply_weather_override(&"rain"))
	assert_eq(weather.active_id(), &"")


# --- Availability: host/offline vs. client -----------------------------------

func test_offline_shows_every_tab() -> void:
	_own_panel(false)
	_panel.net_provider = FakeNet.offline()
	_panel.rebuild()
	for index: int in range(_panel._tab_container.get_tab_count()):
		assert_false(_panel._tab_container.is_tab_hidden(index))


func test_host_shows_every_tab() -> void:
	_own_panel(false)
	_panel.net_provider = FakeNet.host()
	_panel.rebuild()
	for index: int in range(_panel._tab_container.get_tab_count()):
		assert_false(_panel._tab_container.is_tab_hidden(index))


## Bontago-xtq.36: rewritten for the 10-tab layout the M7 tabs added --
## CLIENT_HIDDEN_TAB_FIRST moved from 2 to 7 (see that constant's own doc),
## so every visual tab (Camera, Controls, and the five new M7 tabs) must stay
## visible to a client, and only Physics/Territory/Feed (indices 7-9) hide.
func test_client_hides_physics_territory_and_feed_but_not_the_visual_tabs() -> void:
	_own_panel(false)
	_panel.net_provider = FakeNet.client(0)
	_panel.rebuild()
	var visible_names: PackedStringArray = [
		"Camera", "Controls", "Blocks FX", "Beacons", "Camera FX", "HUD", "Sky",
	]
	for index: int in range(visible_names.size()):
		assert_false(
			_panel._tab_container.is_tab_hidden(index),
			visible_names[index]
		)
	for index: int in range(_panel.CLIENT_HIDDEN_TAB_FIRST, _panel._tab_container.get_tab_count()):
		assert_true(_panel._tab_container.is_tab_hidden(index), "tab %d (Physics/Territory/Feed)" % index)


# --- Bontago-xtq.36: M7 art-direction tabs (Blocks FX/Beacons/Camera FX/HUD/Sky) ---

func test_tab_roster_has_one_unique_titled_page_per_tab() -> void:
	var tabs: TabContainer = _panel._tab_container
	assert_gt(tabs.get_tab_count(), 0, "fixture: the panel builds tabs")
	assert_eq(tabs.get_tab_count(), tabs.get_child_count(), "every tab is backed by exactly one page")
	var seen: Dictionary = {}
	for index: int in range(tabs.get_tab_count()):
		var title: String = tabs.get_tab_title(index)
		assert_false(title.is_empty(), "tab %d has a title" % index)
		assert_false(seen.has(title), "tab title %s is unique" % title)
		seen[title] = true
	for resource: Resource in [_panel.camera_tuning, _panel.ghost_tuning, _panel.physics_tuning, _panel.territory_tuning, _panel.block_feed_config]:
		assert_gt(_panel.row_count_for(resource), 0, "%s is shown on some tab" % resource)


## CameraShakeConfig (config/CameraShakeConfig.gd) is four plain floats and
## nothing else -- like PhysicsTuning's own "one control per numeric field"
## fixture above, no Color/bool/Vector field to complicate the count.
func test_camera_fx_tab_builds_one_control_per_exported_float_field() -> void:
	assert_eq(_panel.row_count_for(_panel.camera_shake_config), 4)


## SkyThemeDef.fog_density is a plain float (config/SkyThemeDef.gd) -- driving
## its slider must both write the live sky_theme Resource and reach a live
## Skybox via apply_sky_theme_live() (this file's header's "deterministic
## equivalent of a real drag" technique, same as
## test_apply_skybox_set_writes_the_config_and_reaches_a_live_skybox above).
func test_sky_tab_fog_density_slider_writes_the_resource_and_reaches_a_live_skybox() -> void:
	# Skybox.gd's own doc: environment is optional and every sky-material write
	# no-ops without it, so a bare Skybox.new() (as most fixtures above use)
	# would silently skip apply_theme()'s fog_density write. Wire a real
	# Environment/Sky first, matching test_skybox.gd's _make_wired_skybox().
	var sky: Sky = Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	var environment: Environment = Environment.new()
	environment.sky = sky

	var skybox: Skybox = Skybox.new()
	skybox.config = _panel.skybox_config
	skybox.environment = environment
	add_child_autofree(skybox)  # _ready() joins Skybox.TUNING_GROUP for real.

	var slider: HSlider = _panel.control_for(_panel.sky_theme, "fog_density") as HSlider
	assert_true(slider is HSlider)

	var new_value: float = _saved_sky_fog_density + 0.01
	slider.emit_signal("value_changed", new_value)

	assert_almost_eq(_panel.sky_theme.fog_density, new_value, 0.0001)
	assert_almost_eq(
		float(skybox.environment.fog_density), new_value, 0.0001,
		"changing the field must push apply_sky_theme_live() too, not just write the Resource."
	)


## Bontago-mp0.83 (owner playtest 2026-10-03): the Sky tab's cycle length row
## is a 60..1800 s slider whose edits reach a running CYCLE sky live and keep
## the time of day where it was.
func test_sky_tab_cycle_length_slider_is_live_and_keeps_the_time_of_day() -> void:
	var sunset: SkyThemeDef = Skybox.load_theme("sunset")
	var saved_sunset_length: float = sunset.cycle_length_seconds
	var saved_panel_length: float = _panel.sky_theme.cycle_length_seconds
	sunset.cycle_length_seconds = 300.0

	var sky: Sky = Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	var environment: Environment = Environment.new()
	environment.sky = sky
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.name = "Light"
	add_child_autofree(light)
	var skybox: Skybox = Skybox.new()
	skybox.config = _panel.skybox_config
	skybox.environment = environment
	skybox.theme = sunset
	add_child_autofree(skybox)  # _ready() joins Skybox.TUNING_GROUP for real.
	skybox.light_path = skybox.get_path_to(light)
	var match_config: MatchConfig = MatchConfig.new()
	match_config.sky_theme_mode = MatchConfig.SkyThemeMode.CYCLE
	skybox.configure_match_sky(match_config)

	var slider: HSlider = _panel.control_for(_panel.sky_theme, "cycle_length_seconds") as HSlider
	assert_true(slider is HSlider, "the Sky tab exposes the cycle length")
	assert_almost_eq(slider.min_value, 60.0, 0.001)
	assert_almost_eq(slider.max_value, 1800.0, 0.001)
	assert_false(_panel.hints.description_for("SkyThemeDef", "cycle_length_seconds").is_empty())

	var length_before: float = skybox.cycle_length_seconds()
	skybox.update_cycle_clock(60.0)
	var phase_before: float = skybox.cycle_phase_at(60.0)
	slider.emit_signal("value_changed", 600.0)

	assert_almost_eq(_panel.sky_theme.cycle_length_seconds, 600.0, 0.001, "the slider writes the Resource")
	assert_almost_eq(length_before, 300.0, 0.001, "fixture: shipped 5 min cycle")
	assert_almost_eq(skybox.cycle_length_seconds(), 600.0, 0.001, "and reaches the running cycle")
	assert_almost_eq(skybox.cycle_phase_at(60.0), phase_before, 0.0001, "time of day does not jump")
	skybox.update_cycle_clock(120.0)
	assert_almost_eq(skybox.cycle_phase_at(120.0), fposmod(phase_before + 60.0 / 600.0, 1.0), 0.0001)

	sunset.cycle_length_seconds = saved_sunset_length
	_panel.sky_theme.cycle_length_seconds = saved_panel_length


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
	_own_panel(false)
	var event: InputEventKey = _key_press(KEY_F4)
	assert_true(event.is_action_pressed(&"tuning_panel_toggle"), "F4 should map to tuning_panel_toggle")

	assert_false(_panel.visible)
	_panel._unhandled_input(event)
	assert_true(_panel.visible)
	_panel._unhandled_input(event)
	assert_false(_panel.visible)


func test_toggle_suppresses_and_restores_controller_input() -> void:
	_own_panel(false)
	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	_panel.set_controller(controller)
	assert_true(controller.input_enabled, "fixture: input starts enabled")

	_panel._unhandled_input(_key_press(KEY_F4))
	assert_false(controller.input_enabled, "opening the panel must suppress gameplay input")

	_panel._unhandled_input(_key_press(KEY_F4))
	assert_true(controller.input_enabled, "closing the panel must restore it")


func test_gamepad_x_alone_does_not_toggle() -> void:
	_own_panel(false)
	var event: InputEventJoypadButton = _pad_press(JOY_BUTTON_X)
	assert_true(event.is_action_pressed(&"tuning_panel_toggle"))

	_panel._unhandled_input(event)
	assert_false(_panel.visible, "X alone is hover_lower, not the tuning-panel chord.")


func test_gamepad_start_plus_x_toggles() -> void:
	_own_panel(false)
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
	_own_panel(false)
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
	_panel._tab_container.emit_signal("tab_clicked", target_tab)

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
	_own_panel(true)
	var target_tab: int = _panel._tab_container.get_tab_count() - 1
	_panel._tab_container.current_tab = target_tab
	_panel._tab_container.emit_signal("tab_changed", target_tab)
	_panel._tab_container.emit_signal("tab_clicked", target_tab)
	assert_eq(_panel._selected_tab_index, target_tab, "fixture: tab_changed must update the panel's own bookkeeping.")

	var fresh_panel: TuningPanel = autofree(load("res://ui/TuningPanel.tscn").instantiate())
	add_child_autofree(fresh_panel)
	fresh_panel.rebuild()

	assert_eq(
		fresh_panel._tab_container.current_tab, target_tab,
		"a brand-new panel instance must read the persisted tab straight from disk in its own _ready()."
	)


# --- Bontago-1pi.22: tab memory only writes on user interaction -------------

func test_programmatic_tab_selection_does_not_write() -> void:
	_own_panel(true)
	DirAccess.remove_absolute(_panel.save_path())
	assert_false(FileAccess.file_exists(_panel.save_path()), "fixture: file removed.")
	var target_tab: int = _panel._tab_container.get_tab_count() - 1
	_panel._tab_container.current_tab = target_tab
	_panel._tab_container.emit_signal("tab_changed", target_tab)
	_panel.rebuild()
	assert_false(FileAccess.file_exists(_panel.save_path()), "programmatic tab sets and rebuilds must not persist.")


func test_user_tab_selection_writes_to_per_pid_file() -> void:
	_own_panel(true)
	DirAccess.remove_absolute(_panel.save_path())
	assert_false(FileAccess.file_exists(_panel.save_path()), "fixture: file removed.")
	var target_tab: int = _panel._tab_container.get_tab_count() - 1
	_panel._tab_container.current_tab = target_tab
	_panel._tab_container.emit_signal("tab_clicked", target_tab)
	assert_true(FileAccess.file_exists(_panel.save_path()))
	assert_true(_panel.save_path().contains("_gut_"), "GUT writes go to the per-PID file.")
	assert_eq(_panel._load_selected_tab_index(), target_tab)


func test_persistence_disallowed_for_headless_non_gut_run() -> void:
	assert_false(UserPaths.persistence_allowed_for(false, "headless"))
	assert_true(UserPaths.persistence_allowed_for(false, "windows"))
	assert_true(UserPaths.persistence_allowed_for(true, "headless"))
	assert_true(UserPaths.persistence_allowed(), "GUT runs keep writing to the per-PID files.")


# --- Bontago-mv0.21: owner-tuned defaults --------------------------------------

func test_camera_and_ghost_tuning_defaults_are_physically_sensible() -> void:
	var camera: CameraTuning = CameraTuning.new()
	assert_gte(camera.follow_lag_seconds, 0.0, "smoothing time is never negative")
	assert_lt(camera.follow_pitch_deg, 0.0, "the follow camera looks down at the stack")
	assert_gt(camera.follow_pitch_deg, -90.0, "...but not straight down")
	var ghost: GhostTuning = GhostTuning.new()
	assert_gt(ghost.block_move_sensitivity, 0.0, "mouse motion moves the block forward, not backward or never")


# --- Bontago-mv0.21: self-describing rows (default + description) -------------

func test_every_row_label_shows_its_default_value() -> void:
	var resources: Array[Resource] = [
		_panel.camera_tuning, _panel.ghost_tuning, _panel.physics_tuning,
		_panel.territory_tuning, _panel.territory_visuals, _panel.block_feed_config,
	]
	var checked_any: bool = false
	var compared: int = 0
	for resource: Resource in resources:
		var shipped: Resource = null
		if not resource.resource_path.is_empty():
			shipped = ResourceLoader.load(resource.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		for prop_name: String in _panel.shown_fields_for(resource):
			checked_any = true
			var text: String = _panel.label_text_for(resource, prop_name)
			assert_true(text.contains(prop_name), "label %s names its field %s" % [text, prop_name])
			assert_true(text.contains("(default "), "%s.%s label %s must show its default" % [resource, prop_name, text])
			# Exact-format check for the types whose text is unambiguous: the label's
			# default is the value Reset restores (the shipped resource), read from disk.
			if shipped != null:
				var value: Variant = shipped.get(prop_name)
				if value is bool:
					compared += 1
					assert_true(text.contains("(default %s)" % ("true" if value else "false")), "%s default text" % prop_name)
				elif value is int:
					compared += 1
					assert_true(text.contains("(default %d)" % value), "%s default text" % prop_name)
	assert_true(checked_any, "fixture: at least one row must exist to check.")
	assert_gt(compared, 0, "fixture: at least one int/bool row compared against its shipped default")


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


# --- Bontago-sen.7: default label and highlight baseline == what Reset restores --

func test_reset_restores_shipped_tres_and_default_label_and_highlight_agree() -> void:
	var resources: Array[Resource] = [
		_panel.camera_tuning, _panel.ghost_tuning, _panel.physics_tuning,
		_panel.territory_tuning, _panel.territory_visuals, _panel.block_feed_config,
		_panel.skybox_config, _panel.sky_theme,
	]
	var differing: int = 0
	# Bontago-fca.38.1: every differing field is edited first, then one reset_all()
	# (a full ~2900-node rebuild) restores them all, then every field gets the same
	# per-field assertions as before (was one reset_all() per field).
	var edited: Array[Dictionary] = []
	for resource: Resource in resources:
		var shipped: Resource = ResourceLoader.load(resource.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		var gd_default: Resource = (resource.get_script() as Script).new() as Resource
		for prop_name: String in _panel.shown_fields_for(resource):
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
		assert_false(_panel.is_modified(resource, prop_name), "%s.%s must not be flagged modified after Reset." % [resource, prop_name])
		var label: String = _panel.label_text_for(resource, prop_name)
		assert_false(label.begins_with("•"), "%s must not carry the modified marker after Reset." % label)
		assert_true(label.contains(_panel._format_default(shipped_value, type)), "%s must show the shipped value as its default." % label)
	gut.p("fields whose .tres differs from .gd default: %d" % differing)


func test_no_row_is_modified_after_reset_all() -> void:
	_own_panel(false)
	_panel.reset_all()
	for resource: Resource in [_panel.camera_tuning, _panel.ghost_tuning, _panel.physics_tuning, _panel.territory_tuning, _panel.territory_visuals, _panel.block_feed_config]:
		for prop_name: String in _panel.shown_fields_for(resource):
			assert_false(_panel.is_modified(resource, prop_name), "%s.%s yellow after Reset." % [resource, prop_name])


# --- Bontago-xtq.34: M7 config resource hints completeness ----------------------

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
		# Bontago-adt.2: the disc-top surface sets (texture and procedural).
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


# --- Bontago-adt: Sky tab Theme dropdown ----------------------------------------

func _find_option_named(node: Node, option_name: String) -> OptionButton:
	if node is OptionButton and node.name == option_name:
		return node as OptionButton
	for child: Node in node.get_children():
		var found: OptionButton = _find_option_named(child, option_name)
		if found != null:
			return found
	return null


func test_sky_tab_theme_dropdown_lists_themes_and_switches_live() -> void:
	_own_panel(false)
	var saved_name: String = _panel.skybox_config.theme_name
	var skybox: Skybox = Skybox.new()
	skybox.config = _panel.skybox_config
	add_child_autofree(skybox)
	_panel.rebuild()
	var option: OptionButton = _find_option_named(_panel, "ThemeOption")
	assert_not_null(option, "expected a Theme OptionButton on the Sky tab")
	var ids: PackedStringArray = Skybox.list_available_themes()
	# Bontago-59o.18 (U1): the leading entry is the day/night cycle; every
	# static theme follows it in list_available_themes() order.
	assert_eq(option.item_count, ids.size() + 1)
	assert_eq(option.get_item_text(0), TuningPanel.CYCLE_THEME_ID, "cycle leads the list")
	assert_eq(option.focus_mode, Control.FOCUS_ALL, "gamepad/keyboard focusable")
	var night_index: int = ids.find("night") + 1
	option.select(night_index)
	option.item_selected.emit(night_index)
	assert_eq(_panel.skybox_config.theme_name, "night", "persists on SkyboxConfig like the Skybox row")
	assert_eq(_panel.sky_theme, Skybox.load_theme("night"), "sliders rebind to the active theme")
	assert_eq(skybox.theme, Skybox.load_theme("night"))
	assert_true(_panel.apply_sky_theme_id("sunset"))
	assert_eq(skybox.theme, Skybox.load_theme("sunset"))
	assert_false(_panel.apply_sky_theme_id("no_such_theme"))
	_panel.skybox_config.theme_name = saved_name
	_panel.sky_theme = Skybox.load_theme("sunset")


# --- Bontago-59o.18 (U1): cycle entry, Time-of-day row, live-edit routing --------

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


func test_theme_dropdown_cycle_entry_starts_the_cycle_and_persists_theme_name() -> void:
	_own_panel(false)
	var saved_name: String = _panel.skybox_config.theme_name
	var saved_theme: SkyThemeDef = _panel.sky_theme
	var spy: SpySkybox = _make_spy_skybox(false)
	_panel.rebuild()
	var option: OptionButton = _find_option_named(_panel, "ThemeOption")
	assert_eq(option.get_item_text(0), "cycle")
	option.select(0)
	option.item_selected.emit(0)
	assert_eq(spy.start_calls.size(), 1, "the cycle entry calls Skybox.start_cycle() on the live Skybox")
	assert_eq(spy.start_calls[0], Vector2(-1.0, -1.0), "defaults: running, from the start phase")
	assert_eq(spy.theme_id_calls.size(), 0, "not routed through the static set_theme_by_id")
	assert_eq(_panel.skybox_config.theme_name, "cycle", "persisted as theme_name per the plan")
	assert_eq(_panel.sky_theme, Skybox.load_theme("sunset"), "sliders edit the cycle's source theme")
	option = _find_option_named(_panel, "ThemeOption")
	assert_eq(option.selected, 0, "the rebuilt dropdown shows cycle")

	# Save override round trip: "cycle" survives a restart through the F4 file.
	assert_eq(_panel.save_overrides(), OK)
	assert_true(_panel.build_copy_text().contains("theme_name = \"cycle\""))
	_panel.skybox_config.theme_name = "sunset"
	TuningPanel.apply_saved_overrides()
	assert_eq(_panel.skybox_config.theme_name, "cycle", "theme_name = cycle round-trips through Save override")

	_panel.skybox_config.theme_name = saved_name
	_panel.sky_theme = saved_theme


func test_theme_dropdown_shows_cycle_while_a_live_skybox_runs_it() -> void:
	_own_panel(false)
	var spy: SpySkybox = _make_spy_skybox(true)
	assert_eq(_panel.skybox_config.theme_name, "sunset", "fixture: the persisted name is still the static default")
	assert_eq(_panel.theme_choice(), "cycle", "a match's running cycle is what F4 must show")
	_panel.rebuild()
	assert_eq(_find_option_named(_panel, "ThemeOption").selected, 0)
	spy.cycle_active = false
	assert_eq(_panel.theme_choice(), "sunset")


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
	assert_eq(_panel.time_of_day_choice(), "custom")
	option.select(0)
	option.item_selected.emit(0)
	assert_almost_eq(spy.lock_calls[-1], -1.0, 0.0001, "Running unlocks")
	assert_false(_panel.apply_time_of_day("midnight"), "an unknown choice is rejected")


func test_time_of_day_row_reflects_a_cycle_locked_by_the_lobby() -> void:
	_own_panel(false)
	var spy: SpySkybox = _make_spy_skybox(true)
	var source: SkyThemeDef = Skybox.load_theme("sunset")
	spy.locked = source.locked_phase_for("night")
	spy.phase_now = spy.locked
	_panel.rebuild()
	var option: OptionButton = _find_option_named(_panel, "TimeOfDayOption")
	assert_eq(option.selected, TuningPanel.TIME_OF_DAY_CHOICES.find("night"), "a lobby-locked night shows Night")
	spy.locked = 0.333
	spy.phase_now = 0.333
	_panel.rebuild()
	option = _find_option_named(_panel, "TimeOfDayOption")
	assert_eq(option.selected, TuningPanel.TIME_OF_DAY_CHOICES.find("custom"))
	assert_almost_eq((_find_control_named(_panel, "TimeOfDaySlider") as HSlider).value, 0.333, 0.006)


func test_time_of_day_row_is_disabled_while_a_static_theme_is_shown() -> void:
	_own_panel(false)
	var spy: SpySkybox = _make_spy_skybox(false)
	_panel.rebuild()
	assert_true(_find_option_named(_panel, "TimeOfDayOption").disabled)
	assert_false((_find_control_named(_panel, "TimeOfDaySlider") as HSlider).editable)
	_panel.apply_time_of_day("night")
	assert_eq(spy.lock_calls.size(), 0, "nothing to lock without a running cycle")


func test_live_sky_edit_refreshes_cycle_sources_instead_of_applying_the_static_theme() -> void:
	_own_panel(false)
	var spy: SpySkybox = _make_spy_skybox(true)
	_panel.rebuild()
	var slider: HSlider = _panel.control_for(_panel.sky_theme, "fog_density") as HSlider
	slider.emit_signal("value_changed", _saved_sky_fog_density + 0.01)
	assert_eq(spy.refresh_calls, 1, "a cycle Skybox re-copies the source themes")
	assert_eq(spy.applied_themes.size(), 0, "apply_theme would swap the live cycle for the static material")
	spy.cycle_active = false
	slider.emit_signal("value_changed", _saved_sky_fog_density + 0.02)
	assert_eq(spy.refresh_calls, 1)
	assert_eq(spy.applied_themes.size(), 1, "a static Skybox still gets apply_theme")
	assert_eq(spy.applied_themes[0], _panel.sky_theme)


func test_editing_a_locked_phase_export_moves_the_selected_preset() -> void:
	_own_panel(false)
	var spy: SpySkybox = _make_spy_skybox(true)
	_panel.rebuild()
	var source: SkyThemeDef = Skybox.load_theme("sunset")
	var saved_phase: float = source.cycle_locked_phase_sunset
	_panel.apply_time_of_day("sunset")
	var slider: HSlider = _panel.control_for(_panel.sky_theme, "cycle_locked_phase_sunset") as HSlider
	assert_not_null(slider, "the locked phase is tunable on the Sky tab")
	slider.emit_signal("value_changed", 0.5)
	assert_almost_eq(spy.lock_calls[-1], 0.5, 0.0001, "the new phase is applied to the locked sky now")
	source.cycle_locked_phase_sunset = saved_phase


func test_reset_keeps_a_running_cycle_instead_of_switching_to_the_static_theme() -> void:
	_own_panel(false)
	var spy: SpySkybox = _make_spy_skybox(true)
	_panel.reset_all()
	assert_true(spy.cycle_active, "reset must not replace the cycle with a static theme")
	assert_eq(spy.theme_id_calls.size(), 0)
	assert_gt(spy.refresh_calls, 0, "the reset values are re-copied into the cycle")


func test_ui_is_lazy_and_freed_on_close() -> void:
	var fresh: TuningPanel = autofree(load("res://ui/TuningPanel.tscn").instantiate())
	add_child_autofree(fresh)
	assert_eq(fresh.get_children().map(func(n: Node) -> String: return str(n.name) + n.get_class()), [], "No UI nodes are built while the panel has never been opened.")
	fresh._toggle_panel()
	assert_gt(fresh.row_count_for(fresh.physics_tuning), 0, "Opening builds the rows.")
	fresh._toggle_panel()
	assert_eq(fresh.get_child_count(), 0, "Closing frees the UI.")
	assert_eq(fresh.row_count_for(fresh.physics_tuning), 0, "Closing drops the row references.")


## Bontago-1pi.21: a GUT run must never touch the owner's real overrides file.
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
