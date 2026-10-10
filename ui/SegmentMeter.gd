class_name SegmentMeter
extends Control
## Stackfall Arcade SegmentMeter (docs/ui_reskin/components.md, Bontago-hfa.4): a slider drawn as voxel
## cells in a well. It is an overlay on a real HSlider, so the slider keeps every behaviour it has
## (mouse drag and click, ui_left/ui_right through ui/SliderNav.gd, focus outline, editable); this
## node only paints the track. Filled cells are flare blocks, the current cell has a cream outline,
## and a muted or disabled meter shows dust cells instead.
## Bontago-1pi.159.7: now a thin compatibility layer. The painting lives in UiSegmentMeter.draw_cells
## (the design-system component); this overlay stays until the Lobby / Options migrations
## (1pi.159.2 / 1pi.159.3) replace each HSlider + overlay with a UiSegmentMeter.

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
	var count: int = maxi(OPTIONS_TUNING.segment_count, 1)
	var live: bool = _slider.editable and not _dimmed
	UiSegmentMeter.draw_cells(self, Rect2(Vector2.ZERO, size), filled_cells(_slider, count), count, live)
