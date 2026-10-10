class_name UiToggle
extends Button
## The design system's Toggle (docs/ui_reskin/components.md "Toggle"): a knob block sliding in a
## sunken disc-900 well, mint when on, with the ON / OFF word beside it (the word is required;
## owner 2026-10-10: one toggle look everywhere). A UiRowItem (TOGGLE): one row height, sized to
## its content, never expands. Keyboard / pad: ui_accept toggles, ui_left switches off and
## ui_right switches on (SliderNav-style). The well and knob are drawn here from
## ArcadeVisualTuning + ComponentMetrics; the word is the Button's own text. Disabled keeps showing
## its state, dimmed by `disabled_alpha`.
## DECISION (1pi.159.5): the knob jumps between its two ends (no slide tween); the design's motion
## tokens are not wired into any component yet.

const WORD_ON: String = "ON"
const WORD_OFF: String = "OFF"
## Inset gaps across the well: left of the knob, between the two knob positions, right of them.
const KNOB_GAPS: float = 3.0

## Accessible name; used as the tooltip when no tooltip is set.
@export var caption: String = "":
	set(value):
		caption = value
		_refresh()
## Draws the ON / OFF word right of the well.
@export var show_word: bool = true:
	set(value):
		show_word = value
		_refresh()
## Gallery preview of the hover look (a pointer cannot be held over a captured control).
var preview_hover: bool = false:
	set(value):
		preview_hover = value
		_refresh()


func _init() -> void:
	toggle_mode = true
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	UiRowItem.apply(self, UiRowItem.Kind.TOGGLE)
	toggled.connect(_on_toggled)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	_refresh()


func set_on(on: bool) -> void:
	button_pressed = on


## Sets the state without emitting `toggled` (remote sync, read-only clients).
func set_on_silent(on: bool) -> void:
	set_pressed_no_signal(on)
	_refresh()


func is_on() -> bool:
	return button_pressed


## The ON / OFF word shown for [param on].
static func state_word_for(on: bool) -> String:
	return WORD_ON if on else WORD_OFF


## The knob's face: mint when on, a disc face when off (tokens).
static func knob_face_for(on: bool, arcade: ArcadeVisualTuning = null) -> Color:
	var tokens: ArcadeVisualTuning = arcade if arcade != null else MenuStyleFactory.arcade_tuning()
	return tokens.mint_color if on else tokens.disc_500_color


## The knob's left edge inside a well [param well_width] wide for [param on] (off = left end).
static func knob_x_for(on: bool, well_width: float, knob_width: float, inset: float) -> float:
	return well_width - inset - knob_width if on else inset


func _gui_input(event: InputEvent) -> void:
	if disabled:
		return
	if event.is_action_pressed(&"ui_left"):
		accept_event()
		set_on(false)
	elif event.is_action_pressed(&"ui_right"):
		accept_event()
		set_on(true)


func _on_toggled(_on: bool) -> void:
	_refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		_refresh()


func _knob_width(m: ComponentMetrics) -> float:
	return (float(m.toggle_well_width_px) - KNOB_GAPS * float(m.toggle_knob_inset_px)) / 2.0


func _refresh() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var m: ComponentMetrics = UiRowItem.metrics()
	text = state_word_for(button_pressed) if show_word else ""
	if tooltip_text.is_empty() and not caption.is_empty():
		tooltip_text = caption
	# The word sits right of the well: one empty box per state carries the left margin.
	var left: float = float(m.toggle_well_width_px)
	if show_word:
		left += float(arcade.space_2_px)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var box: StyleBoxEmpty = StyleBoxEmpty.new()
		box.content_margin_left = left
		box.content_margin_right = float(arcade.space_1_px) if show_word else 0.0
		add_theme_stylebox_override(state, box)
	var on_ink: Color = arcade.mint_color
	var off_ink: Color = arcade.dust_color
	var off_hover: Color = arcade.sand_color
	for item: String in ["font_color", "font_focus_color"]:
		add_theme_color_override(item, off_hover if preview_hover else off_ink)
	add_theme_color_override("font_hover_color", off_hover)
	for item: String in ["font_pressed_color", "font_hover_pressed_color"]:
		add_theme_color_override(item, on_ink)
	var dimmed: Color = on_ink if button_pressed else off_ink
	dimmed.a *= arcade.disabled_alpha
	add_theme_color_override("font_disabled_color", dimmed)
	add_theme_font_size_override("font_size", arcade.font_size_label_px)
	# A stable width: the wider of ON / OFF, so the row does not jitter when it flips.
	var font: Font = get_theme_font("font")
	var widest: float = 0.0
	if show_word and font != null:
		widest = maxf(font.get_string_size(WORD_ON, HORIZONTAL_ALIGNMENT_LEFT, -1, arcade.font_size_label_px).x, font.get_string_size(WORD_OFF, HORIZONTAL_ALIGNMENT_LEFT, -1, arcade.font_size_label_px).x)
	var min_x: float = maxf(UiRowItem.min_width_for(UiRowItem.Kind.TOGGLE, m), left + widest + float(arcade.space_1_px))
	custom_minimum_size.x = min_x
	queue_redraw()


func _hovered() -> bool:
	return (is_hovered() or preview_hover) and not disabled


func _draw() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var m: ComponentMetrics = UiRowItem.metrics()
	var alpha: float = arcade.disabled_alpha if disabled else 1.0
	var well_size: Vector2 = Vector2(float(m.toggle_well_width_px), float(m.toggle_well_height_px))
	var well_rect: Rect2 = Rect2(Vector2(0.0, (size.y - well_size.y) / 2.0), well_size)
	var well: StyleBoxFlat = StyleBoxFlat.new()
	well.bg_color = Color(arcade.disc_900_color, alpha)
	well.set_corner_radius_all(arcade.radius_block_px)
	well.set_border_width_all(arcade.well_border_px)
	var edge: Color = arcade.cream_color if _hovered() else arcade.disc_400_color
	if button_pressed and not _hovered():
		edge = arcade.mint_lip_color
	well.border_color = Color(edge, edge.a * alpha)
	well.set_content_margin_all(0.0)
	well.draw(get_canvas_item(), well_rect)
	var inset: float = float(m.toggle_knob_inset_px)
	var knob_w: float = _knob_width(m)
	var knob_h: float = well_size.y - 2.0 * inset
	var knob_rect: Rect2 = Rect2(
		Vector2(knob_x_for(button_pressed, well_size.x, knob_w, inset), well_rect.position.y + inset),
		Vector2(knob_w, knob_h))
	var face: Color = knob_face_for(button_pressed, arcade)
	var state: int = BlockStyleBox.STATE_HOVER if _hovered() else BlockStyleBox.STATE_NORMAL
	if disabled:
		state = BlockStyleBox.STATE_DISABLED
	var knob: BlockStyleBox = BlockStyleBox.make(face, arcade, true, state, MenuStyleFactory.lip_for(face), MenuStyleFactory.top_for(face))
	knob.draw(get_canvas_item(), knob_rect)
