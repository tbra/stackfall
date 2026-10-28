class_name DebugOverlayLayout
extends RefCounted
## Where the four debug panels sit, so no two open ones overlap and none covers the HUD. Pure
## placement; the panels keep their own look. Every position derives from the HUD's own scale and
## minimap size (UiScaleTuning runtime values) and the arcade HUD inset, so it follows the HUD scale,
## the UI scale and the minimap preset; the gaps and the timer ring's size are DebugConfig tunables.
##
## Bottom-right stack, growing up from the minimap: F2 (pose) right above it, F3 (net) right above F2.
## Top band: F9 (bot cost) ends left of the HUD's timer ring and F1 (perf) starts right of it, so the
## centre of the screen stays free and neither reaches the stats backplate or the round clock. On a
## canvas too narrow for F9 beside the ring (a UI scale above 100%) it drops below the stats cluster.
##
## DECISION: the stack's heights live in a static array (a panel reports its own while shown, 0 while
## hidden) rather than the panels finding each other: they are created in different places and may not
## reach into siblings. A hidden panel leaves no gap.

## Slots of the bottom-right stack, nearest the minimap first.
enum Stack { POSE, NET }

static var _stack_heights: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])


## A stack panel's current height (0 when hidden); call it every frame from the panel.
static func report_stack_height(slot: Stack, height: float) -> void:
	_stack_heights[slot] = height


## Distance from the canvas bottom to the bottom edge of `slot`'s panel: above the minimap, then above
## every visible panel in the slots below.
static func stack_bottom_px(slot: Stack, config: DebugConfig) -> float:
	var gap: float = config.overlay_margin.y
	var minimap_px: float = float(UiScaleTuning.shared().minimap_size_px_for(UiScaleTuning.runtime_minimap_preset()))
	var bottom: float = (hud_inset_px() + minimap_px) * hud_factor() + gap
	for below: int in range(int(slot)):
		if _stack_heights[below] > 0.0:
			bottom += _stack_heights[below] + gap
	return bottom


## Inset from the canvas right edge: the minimap's own, so the stack is flush with it.
static func stack_right_px() -> float:
	return hud_inset_px() * hud_factor()


## Top edge of the F1 and F9 panels: level with the HUD's top row.
static func top_px() -> float:
	return hud_inset_px() * hud_factor()


## Distance from the canvas centre line to the nearest edge of the F1 and F9 panels: the timer ring's
## half width plus a gap.
static func centre_clearance_px(config: DebugConfig) -> float:
	return config.hud_timer_ring_half_width_px * hud_factor() + config.overlay_margin.x


## Anchors a stack panel bottom-right and grows it up and left from its slot.
static func place_stack(panel: Control, slot: Stack, config: DebugConfig) -> void:
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT, true)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_right = -stack_right_px()
	panel.offset_bottom = -stack_bottom_px(slot, config)
	panel.offset_left = panel.offset_right
	panel.offset_top = panel.offset_bottom


## Anchors a top-band panel to the canvas centre line, `left_of_centre` or right of it, growing away from
## the centre.
static func place_beside_centre(panel: Control, left_of_centre: bool, config: DebugConfig) -> void:
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP, true)
	panel.grow_vertical = Control.GROW_DIRECTION_END
	panel.offset_top = top_px()
	panel.offset_bottom = panel.offset_top
	var edge: float = -centre_clearance_px(config) if left_of_centre else centre_clearance_px(config)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN if left_of_centre else Control.GROW_DIRECTION_END
	panel.offset_left = edge
	panel.offset_right = edge


## F9's place: left of the timer ring when it fits between the stats cluster and the ring, else in the
## top-left column right under the stats cluster (clear of the ring, F1 and the bottom-left cards).
static func place_bot_cost(panel: Control, config: DebugConfig) -> void:
	var band_left: float = config.hud_top_left_right_px * hud_factor() + config.overlay_margin.x
	var room: float = panel.get_viewport_rect().size.x * 0.5 - centre_clearance_px(config) - band_left
	if room >= panel.get_combined_minimum_size().x:
		place_beside_centre(panel, true, config)
		return
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT, true)
	panel.grow_horizontal = Control.GROW_DIRECTION_END
	panel.grow_vertical = Control.GROW_DIRECTION_END
	panel.offset_left = stack_right_px()
	panel.offset_right = panel.offset_left
	panel.offset_top = config.hud_top_left_bottom_px * hud_factor() + config.overlay_margin.y
	panel.offset_bottom = panel.offset_top


## The HUD's inset from the screen edge in HUD pixels (the arcade token the HUD scenes use).
static func hud_inset_px() -> float:
	return float(MenuStyleFactory.arcade_tuning().space_5_px)


static func hud_factor() -> float:
	return UiScaleTuning.hud_relative_factor()
