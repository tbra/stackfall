extends GutTest
## Bontago-1pi.191: the in-match HUD scale is separate from the UI scale, and the minimap size is an
## option. Covers persistence + migration, HUD-only scaling, live minimap resize, and the round-timer /
## minimap / held-next layout at the extreme scales.

const SETTINGS_SCRIPT: GDScript = preload("res://autoload/Settings.gd")
const WINDOWS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1920, 1080)]
const SETTLE_FRAMES: int = 4
const EDGE_EPS: float = 1.5

var _cfg_path: String


func before_each() -> void:
	_cfg_path = OS.get_user_data_dir().path_join("test_hud_scale_tmp.cfg")
	if FileAccess.file_exists(_cfg_path):
		DirAccess.remove_absolute(_cfg_path)


func after_each() -> void:
	if FileAccess.file_exists(_cfg_path):
		DirAccess.remove_absolute(_cfg_path)
	Settings.reset_ui_scale()
	Settings.reset_hud_scale()
	Settings.reset_minimap_size()
	UiScaleTuning.current_scale = -1.0
	UiScaleTuning.current_hud_scale = -1.0
	UiScaleTuning.current_minimap_preset = -1


func _fresh() -> Node:
	var settings: Node = autofree(SETTINGS_SCRIPT.new())
	add_child_autofree(settings)
	settings.set_config_path_for_test(_cfg_path)
	return settings


func test_defaults_persist_and_sanitize() -> void:
	var tuning: UiScaleTuning = UiScaleTuning.shared()
	var settings: Node = _fresh()
	assert_eq(settings.hud_scale(), tuning.default_scale)
	assert_eq(settings.minimap_size_preset(), tuning.minimap_default_preset)
	settings.set_hud_scale(1.52)
	settings.set_minimap_size_preset(2)
	var reloaded: Node = _fresh()
	assert_almost_eq(reloaded.hud_scale(), 1.5, 0.0001)
	assert_eq(reloaded.minimap_size_preset(), 2)
	settings.set_hud_scale(99.0)
	assert_eq(settings.hud_scale(), tuning.max_scale)
	settings.set_minimap_size_preset(42)
	assert_eq(settings.minimap_size_preset(), tuning.minimap_size_presets_px.size() - 1)
	assert_eq(settings.ui_scale(), tuning.default_scale, "the UI scale is untouched by the HUD scale")


func test_old_save_without_hud_keys_migrates_hud_scale_from_ui_scale() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("graphics", "ui_scale", 1.5)
	cfg.save(_cfg_path)
	var settings: Node = _fresh()
	assert_almost_eq(settings.hud_scale(), 1.5, 0.0001, "the HUD keeps its old UI-scaled size")
	assert_eq(settings.minimap_size_preset(), UiScaleTuning.shared().minimap_default_preset)


func test_hud_relative_factor_makes_hud_independent_of_ui_scale() -> void:
	UiScaleTuning.current_scale = 1.5
	UiScaleTuning.current_hud_scale = 1.0
	assert_almost_eq(UiScaleTuning.hud_relative_factor(), 1.0 / 1.5, 0.0001)
	UiScaleTuning.current_hud_scale = 1.5
	assert_almost_eq(UiScaleTuning.hud_relative_factor(), 1.0, 0.0001)


func test_options_rows_exist_and_apply() -> void:
	var menu: Node = autofree((load("res://ui/OptionsMenu.tscn") as PackedScene).instantiate())
	add_child(menu)
	await get_tree().process_frame
	var meter: UiSegmentMeter = menu.get_node("%HudScaleSlider") as UiSegmentMeter
	var dropdown: UiDropdown = menu.get_node("%MinimapSizeOption") as UiDropdown
	assert_not_null(meter)
	assert_not_null(dropdown)
	assert_eq(dropdown.item_count, UiScaleTuning.shared().minimap_size_presets_px.size())
	dropdown.item_selected.emit(2)
	assert_eq(Settings.minimap_size_preset(), 2)
	meter.value_changed.emit(meter.step_count)
	assert_eq(Settings.hud_scale(), UiScaleTuning.shared().max_scale)


func _hud_in(vp: SubViewport) -> HUD:
	var hud: HUD = (load("res://ui/HUD.tscn") as PackedScene).instantiate() as HUD
	vp.add_child(hud)
	hud.set_local_slot(0)
	return hud


func _rect(control: Control) -> Rect2:
	return control.get_global_transform() * Rect2(Vector2.ZERO, control.size)


func test_hud_scale_changes_only_the_hud_and_keeps_alignments() -> void:
	var tuning: UiScaleTuning = UiScaleTuning.shared()
	for window: Vector2i in WINDOWS:
		for hud_scale: float in [tuning.min_scale, tuning.default_scale, tuning.max_scale]:
			for preset: int in [0, tuning.minimap_size_presets_px.size() - 1]:
				Settings.set_hud_scale(hud_scale)
				Settings.set_minimap_size_preset(preset)
				var vp: SubViewport = UiScale.make_viewport(window)
				vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
				add_child_autofree(vp)
				var hud: HUD = _hud_in(vp)
				for _i: int in SETTLE_FRAMES:
					await get_tree().process_frame
				var where: String = "%s hud %.2f minimap %d" % [window, hud_scale, preset]
				var screen: Rect2 = Rect2(Vector2.ZERO, Vector2(vp.get_visible_rect().size))
				var minimap: Rect2 = _rect(hud._minimap)
				var backplate: Rect2 = _rect(hud._top_left_backplate)
				var held: Rect2 = _rect(hud._held_next_panel)
				var expected_px: float = float(tuning.minimap_size_px_for(preset)) * hud._scale_root.scale.x
				assert_almost_eq(minimap.size.x, expected_px, EDGE_EPS, "minimap size %s" % where)
				assert_true(screen.grow(EDGE_EPS).encloses(minimap), "minimap on screen %s: %s" % [where, minimap])
				assert_true(screen.grow(EDGE_EPS).encloses(backplate), "stats on screen %s" % where)
				assert_true(screen.grow(EDGE_EPS).encloses(held), "held/next on screen %s" % where)
				assert_false(held.intersects(minimap), "held/next vs minimap %s" % where)
				var timer: Control = hud._round_timer
				var slot_rect: Rect2 = _rect(timer.get_parent() as Control)
				assert_almost_eq(slot_rect.position.x, minimap.end.x, EDGE_EPS, "timer slot right edge = minimap right edge %s" % where)
				assert_almost_eq(slot_rect.position.y, backplate.position.y, EDGE_EPS, "timer top = stats top %s" % where)
				var hud_factor: float = hud_scale / tuning.default_scale
				assert_almost_eq(hud._scale_root.scale.x * UiScale.user_factor(), tuning.base_scale * hud_factor, 0.001, "total HUD factor follows HUD scale only %s" % where)
				vp.queue_free()
	Settings.reset_hud_scale()


func test_countdown_and_eliminated_banners_centre_on_screen_at_extreme_scales() -> void:
	var tuning: UiScaleTuning = UiScaleTuning.shared()
	for window: Vector2i in WINDOWS:
		for hud_scale: float in [tuning.min_scale, tuning.max_scale]:
			Settings.set_hud_scale(hud_scale)
			var vp: SubViewport = UiScale.make_viewport(window)
			vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			add_child_autofree(vp)
			var hud: HUD = _hud_in(vp)
			for _i: int in SETTLE_FRAMES:
				await get_tree().process_frame
			var screen: Rect2 = Rect2(Vector2.ZERO, Vector2(vp.get_visible_rect().size))
			var where: String = "%s hud %.2f" % [window, hud_scale]
			for label_name: String in ["CountdownLabel", "EliminatedLabel"]:
				var label: Label = hud.find_child(label_name, true, false) as Label
				assert_not_null(label, "%s exists %s" % [label_name, where])
				var rect: Rect2 = _rect(label)
				assert_almost_eq(rect.get_center().x, screen.get_center().x, EDGE_EPS, "%s centre x %s" % [label_name, where])
				assert_almost_eq(rect.get_center().y, screen.get_center().y, EDGE_EPS, "%s centre y %s" % [label_name, where])
				assert_true(screen.grow(EDGE_EPS).encloses(rect), "%s on screen %s" % [label_name, where])
			vp.queue_free()
	Settings.reset_hud_scale()


func test_minimap_presets_sit_bottom_right_unclipped() -> void:
	var tuning: UiScaleTuning = UiScaleTuning.shared()
	for window: Vector2i in WINDOWS:
		for preset: int in tuning.minimap_size_presets_px.size():
			Settings.set_minimap_size_preset(preset)
			var vp: SubViewport = UiScale.make_viewport(window)
			vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			add_child_autofree(vp)
			var hud: HUD = _hud_in(vp)
			hud._minimap.set_map_def(MapDef.new())
			for _i: int in SETTLE_FRAMES:
				await get_tree().process_frame
			var where: String = "%s preset %d" % [window, preset]
			var screen: Rect2 = Rect2(Vector2.ZERO, Vector2(vp.get_visible_rect().size))
			var minimap: Rect2 = _rect(hud._minimap)
			assert_true(hud._minimap.visible, "minimap shown once a map is set %s" % where)
			assert_eq(hud._minimap.size_px(), tuning.minimap_size_px_for(preset), "size_px %s" % where)
			assert_true(screen.grow(EDGE_EPS).encloses(minimap), "unclipped %s: %s" % [where, minimap])
			var margin_right: float = screen.end.x - minimap.end.x
			var margin_bottom: float = screen.end.y - minimap.end.y
			assert_true(margin_right < screen.size.x * 0.1 and margin_bottom < screen.size.y * 0.15, "bottom-right %s: %s" % [where, minimap])
			vp.queue_free()


func test_timer_ring_bottom_scales_with_hud_scale() -> void:
	var tuning: UiScaleTuning = UiScaleTuning.shared()
	var vp: SubViewport = UiScale.make_viewport(WINDOWS[0])
	add_child_autofree(vp)
	var hud: HUD = _hud_in(vp)
	Settings.set_hud_scale(tuning.min_scale)
	await get_tree().process_frame
	await get_tree().process_frame
	var small: float = hud.timer_ring_bottom_px()
	Settings.set_hud_scale(tuning.max_scale)
	await get_tree().process_frame
	await get_tree().process_frame
	var large: float = hud.timer_ring_bottom_px()
	assert_gt(small, 0.0)
	assert_almost_eq(large / small, tuning.max_scale / tuning.min_scale, 0.01, "banner offset follows the HUD scale")
	Settings.reset_hud_scale()
