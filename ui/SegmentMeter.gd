class_name SegmentMeter
extends Control
## Stackfall Arcade SegmentMeter (docs/ui_reskin/components.md, Bontago-hfa.4): a slider drawn as voxel
## cells in a well. It is an overlay on a real HSlider, so the slider keeps every behaviour it has
## (mouse drag and click, ui_left/ui_right through ui/SliderNav.gd, focus outline, editable); this
## node only paints the track. Filled cells are flare blocks, the current cell has a cream outline,
## and a muted or disabled meter shows dust cells instead.

const OPTIONS_TUNING: OptionsVisualTuning = preload("res://config/options_visual_tuning.tres")

var _slider: HSlider = null
var _dimmed: bool = false


## Turns [param slider] into a SegmentMeter: the slider's own track/grabber art is blanked and the
## returned overlay draws the well and the cells.
static func attach(slider: HSlider) -> SegmentMeter:
	var empty: StyleBoxEmpty = StyleBoxEmpty.new()
	slider.add_theme_stylebox_override("slider", empty)
	slider.add_theme_stylebox_override("grabber_area", empty)
	slider.add_theme_stylebox_override("grabber_area_highlight", empty)
	var blank: ImageTexture = ImageTexture.create_from_image(Image.create_empty(1, 1, false, Image.FORMAT_RGBA8))
	slider.add_theme_icon_override("grabber", blank)
	slider.add_theme_icon_override("grabber_highlight", blank)
	slider.add_theme_icon_override("grabber_disabled", blank)
	slider.set_meta(SliderNav.META_SEGMENT_COUNT, OPTIONS_TUNING.segment_count)
	slider.custom_minimum_size.y = float(OPTIONS_TUNING.meter_height_px)
	var meter: SegmentMeter = SegmentMeter.new()
	meter.name = "SegmentMeter"
	meter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meter._slider = slider
	slider.add_child(meter)
	slider.value_changed.connect(meter._on_slider_changed)
	slider.focus_entered.connect(meter.queue_redraw)
	slider.focus_exited.connect(meter.queue_redraw)
	return meter


func _on_slider_changed(_value: float) -> void:
	queue_redraw()


## Muted/disabled meters draw dust cells (the fill is no longer the live value).
func set_dimmed(dimmed: bool) -> void:
	if _dimmed != dimmed:
		_dimmed = dimmed
		queue_redraw()


## How many of [param count] cells are filled for [param slider]'s current value.
static func filled_cells(slider: HSlider, count: int) -> int:
	var span: float = slider.max_value - slider.min_value
	if span <= 0.0:
		return 0
	return clampi(roundi((slider.value - slider.min_value) / span * float(count)), 0, count)


func _draw() -> void:
	if _slider == null:
		return
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var well: StyleBoxFlat = StyleBoxFlat.new()
	well.bg_color = arcade.disc_900_color
	well.border_color = arcade.disc_400_color
	well.set_border_width_all(arcade.well_border_px)
	well.set_corner_radius_all(arcade.radius_block_px)
	draw_style_box(well, Rect2(Vector2.ZERO, size))
	var count: int = maxi(OPTIONS_TUNING.segment_count, 1)
	var inset: float = float(arcade.well_border_px + arcade.space_1_px)
	var area: Rect2 = Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0)
	if area.size.x <= 0.0 or area.size.y <= 0.0:
		return
	var gap: float = float(arcade.space_1_px)
	var cell_w: float = (area.size.x - gap * float(count - 1)) / float(count)
	var filled: int = filled_cells(_slider, count)
	var live: bool = _slider.editable and not _dimmed
	for i: int in range(count):
		var rect: Rect2 = Rect2(area.position + Vector2(float(i) * (cell_w + gap), 0.0), Vector2(cell_w, area.size.y))
		var on: bool = i < filled
		var face: Color = arcade.disc_700_color
		var lip: Color = arcade.disc_600_color
		if on:
			face = arcade.flare_color if live else arcade.dust_color
			lip = arcade.flare_lip_color if live else arcade.disc_400_color
		draw_style_box(_cell_box(face, lip, arcade), rect)
	var current: int = clampi(filled - 1, 0, count - 1)
	var outline: Rect2 = Rect2(area.position + Vector2(float(current) * (cell_w + gap), 0.0), Vector2(cell_w, area.size.y))
	var outline_box: StyleBoxFlat = StyleBoxFlat.new()
	outline_box.draw_center = false
	outline_box.border_color = arcade.cream_color
	outline_box.set_border_width_all(arcade.well_border_px)
	outline_box.set_corner_radius_all(arcade.radius_cell_px)
	if filled > 0 and live:
		draw_style_box(outline_box, outline)


func _cell_box(face: Color, lip: Color, arcade: ArcadeVisualTuning) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = face
	box.border_color = lip
	box.border_width_bottom = arcade.pressed_lip_px
	box.set_corner_radius_all(arcade.radius_cell_px)
	return box
