extends GutTest
## ui/debug/DebugOverlayLayout.gd: the F2/F3 stack above the minimap and the F1/F9 pair around the timer ring.

var _config: DebugConfig = DebugConfig.new()


func after_each() -> void:
	DebugOverlayLayout.report_stack_height(DebugOverlayLayout.Stack.POSE, 0.0)
	DebugOverlayLayout.report_stack_height(DebugOverlayLayout.Stack.NET, 0.0)


func test_pose_sits_right_above_the_minimap() -> void:
	var minimap: float = float(UiScaleTuning.shared().minimap_size_px_for(UiScaleTuning.runtime_minimap_preset()))
	var expected: float = (DebugOverlayLayout.hud_inset_px() + minimap) * DebugOverlayLayout.hud_factor() + _config.overlay_margin.y
	assert_almost_eq(DebugOverlayLayout.stack_bottom_px(DebugOverlayLayout.Stack.POSE, _config), expected, 0.01)


func test_net_sits_above_an_open_pose_panel_and_closes_the_gap_when_it_is_hidden() -> void:
	var pose_bottom: float = DebugOverlayLayout.stack_bottom_px(DebugOverlayLayout.Stack.POSE, _config)
	assert_almost_eq(DebugOverlayLayout.stack_bottom_px(DebugOverlayLayout.Stack.NET, _config), pose_bottom, 0.01, "pose hidden: no gap")
	DebugOverlayLayout.report_stack_height(DebugOverlayLayout.Stack.POSE, 90.0)
	assert_almost_eq(
		DebugOverlayLayout.stack_bottom_px(DebugOverlayLayout.Stack.NET, _config),
		pose_bottom + 90.0 + _config.overlay_margin.y, 0.01, "pose open: net clears it plus a gap")


func test_place_stack_anchors_bottom_right_and_grows_up_and_left() -> void:
	var panel: PanelContainer = PanelContainer.new()
	add_child_autofree(panel)
	DebugOverlayLayout.place_stack(panel, DebugOverlayLayout.Stack.POSE, _config)
	assert_eq(panel.anchor_right, 1.0)
	assert_eq(panel.anchor_bottom, 1.0)
	assert_eq(panel.grow_horizontal, Control.GROW_DIRECTION_BEGIN)
	assert_eq(panel.grow_vertical, Control.GROW_DIRECTION_BEGIN)
	assert_almost_eq(panel.offset_right, -DebugOverlayLayout.stack_right_px(), 0.01)
	assert_almost_eq(panel.offset_bottom, -DebugOverlayLayout.stack_bottom_px(DebugOverlayLayout.Stack.POSE, _config), 0.01)


func test_the_top_band_panels_flank_the_centre_on_opposite_sides() -> void:
	var left: PanelContainer = PanelContainer.new()
	var right: PanelContainer = PanelContainer.new()
	add_child_autofree(left)
	add_child_autofree(right)
	DebugOverlayLayout.place_beside_centre(left, true, _config)
	DebugOverlayLayout.place_beside_centre(right, false, _config)
	var clearance: float = DebugOverlayLayout.centre_clearance_px(_config)
	assert_gt(clearance, _config.hud_timer_ring_half_width_px * DebugOverlayLayout.hud_factor(), "clear of the ring")
	assert_eq(left.anchor_left, 0.5)
	assert_eq(right.anchor_left, 0.5)
	assert_almost_eq(left.offset_right, -clearance, 0.01)
	assert_almost_eq(right.offset_left, clearance, 0.01)
	assert_eq(left.grow_horizontal, Control.GROW_DIRECTION_BEGIN)
	assert_eq(right.grow_horizontal, Control.GROW_DIRECTION_END)
	assert_almost_eq(left.offset_top, DebugOverlayLayout.top_px(), 0.01)


func test_the_layout_follows_the_hud_scale() -> void:
	var saved: float = UiScaleTuning.current_hud_scale
	UiScaleTuning.current_hud_scale = UiScaleTuning.runtime_scale()
	var base: float = DebugOverlayLayout.stack_bottom_px(DebugOverlayLayout.Stack.POSE, _config)
	UiScaleTuning.current_hud_scale = UiScaleTuning.runtime_scale() * 2.0
	var doubled: float = DebugOverlayLayout.stack_bottom_px(DebugOverlayLayout.Stack.POSE, _config)
	UiScaleTuning.current_hud_scale = saved
	assert_gt(doubled, base, "a larger HUD (and minimap) lifts the stack")


func test_bot_cost_sits_beside_the_ring_when_it_fits_and_drops_under_the_stats_cluster_when_it_does_not() -> void:
	var fits: PanelContainer = PanelContainer.new()
	add_child_autofree(fits)
	DebugOverlayLayout.place_bot_cost(fits, _config)
	assert_eq(fits.anchor_left, 0.5, "a narrow panel flanks the timer ring")
	var wide: PanelContainer = PanelContainer.new()
	wide.custom_minimum_size.x = get_viewport().get_visible_rect().size.x
	add_child_autofree(wide)
	DebugOverlayLayout.place_bot_cost(wide, _config)
	assert_eq(wide.anchor_left, 0.0, "a panel too wide for the band moves to the top-left column")
	assert_almost_eq(wide.offset_left, DebugOverlayLayout.stack_right_px(), 0.01)
	assert_almost_eq(wide.offset_top, _config.hud_top_left_bottom_px * DebugOverlayLayout.hud_factor() + _config.overlay_margin.y, 0.01)
