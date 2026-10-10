class_name ReadyPill
extends PanelContainer
## The icon-only Ready / Not ready pill (Bontago-1pi.94 S3): a mint pill with a tick when ready, a
## dark pill with an hourglass otherwise, the words kept as the accessible tooltip. Shared by the
## lobby's seat rows (ui/lobby/LobbySeatRow.gd) and the loading screen's player rows
## (Bontago-1pi.158) so both draw the exact same component.

const TICK: int = 0x2713
const HOURGLASS: int = 0x231A

var is_ready: bool = false
var label: Label = null
var _tuning: MenuVisualTuning = null
## < 0 keeps the badge style's own vertical content margin; >= 0 overrides it (compact rows).
var _margin_y_px: float = -1.0


## The accessible text of a Ready / Not ready pill (the pill itself shows only its icon).
static func tooltip_for(ready: bool) -> String:
	return "Ready" if ready else "Not ready"


static func create(ready: bool, min_size: Vector2, tuning: MenuVisualTuning, margin_y_px: float = -1.0) -> ReadyPill:
	var pill: ReadyPill = ReadyPill.new()
	pill._tuning = tuning
	pill._margin_y_px = margin_y_px
	pill.custom_minimum_size = min_size
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pill.label = Label.new()
	pill.label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pill.label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pill.add_child(pill.label)
	pill.set_ready(ready)
	return pill


## Restyles the pill for the new state (cheap; callers may call it every refresh).
func set_ready(ready: bool) -> void:
	is_ready = ready
	var color: Color = _tuning.pill_mint_color if ready else MenuStyleFactory.arcade_tuning().disc_600_color
	var box: StyleBoxFlat = MenuStyleFactory.make_badge(color, _tuning)
	if _margin_y_px >= 0.0:
		box.content_margin_top = _margin_y_px
		box.content_margin_bottom = _margin_y_px
	add_theme_stylebox_override("panel", box)
	label.text = char(TICK) if ready else char(HOURGLASS)
	tooltip_text = tooltip_for(ready)
	# Bontago-hfa.5: the glyph takes the better-contrasting of ink / cream for its face.
	label.add_theme_color_override("font_color", MenuStyleFactory.ink_for_face(color))
