class_name UiChipToggle
extends Button
## The design system's ChipToggle (docs/ui_reskin/components.md "ChipToggle"): a compact block for
## the gift / special pool and the lobby's experiment flags. On = a `mint` block with an ink
## check box holding a tick; off = a `disc-700` block with an empty box, so the state never relies
## on colour alone. A UiRowItem (BUTTON_SM height). Pad / keyboard: ui_accept toggles. A chip that
## is switched off for the match (set_available(false), e.g. the Cat gift) is shown disabled; its
## reason is read back with unavailable_reason() for inline help. The label is the Button's text, the optional pictogram its icon.

@export var label: String = "":
	set(value):
		label = value
		text = value
@export var chip_icon: Texture2D = null:
	set(value):
		chip_icon = value
		icon = value

var _available: bool = true
var _unavailable_reason: String = ""
## The shared look this chip last applied, and which face its "disabled" block currently shows.
var _applied_generation: int = -1
var _shown_pressed: bool = false

const BASE_STATES: PackedStringArray = ["normal", "hover", "pressed", "hover_pressed"]
const OFF_INK_ITEMS: PackedStringArray = ["font_color", "font_focus_color", "font_hover_color", "icon_normal_color", "icon_focus_color", "icon_hover_color"]
const ON_INK_ITEMS: PackedStringArray = ["font_pressed_color", "font_hover_pressed_color", "icon_pressed_color", "icon_hover_pressed_color"]

static var _look: Dictionary = {}
static var _look_tuning: ArcadeVisualTuning = null
static var _look_metrics: ComponentMetrics = null
static var _look_generation: int = 0


func _init() -> void:
	toggle_mode = true
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggled.connect(_on_toggled)
	_restyle()
	UiRowItem.apply(self, UiRowItem.Kind.BUTTON_SM)


func set_on(on: bool) -> void:
	button_pressed = on


## Sets the state without emitting `toggled` (remote sync).
func set_on_silent(on: bool) -> void:
	set_pressed_no_signal(on)
	_restyle()


func is_on() -> bool:
	return button_pressed


## Shows the chip disabled (e.g. a gift that is switched off); [param why] is its inline reason.
func set_available(available: bool, why: String = "") -> void:
	_available = available
	_unavailable_reason = why if not available else ""
	disabled = not available
	_restyle()


## The reason a chip is switched off ("" when available); shown as inline help, never as a tooltip.
func unavailable_reason() -> String:
	return _unavailable_reason


func is_available() -> bool:
	return _available


## The face of a chip: mint when on, disc-700 when off (tokens).
static func face_for(on: bool, arcade: ArcadeVisualTuning = null) -> Color:
	var tokens: ArcadeVisualTuning = arcade if arcade != null else MenuStyleFactory.arcade_tuning()
	return tokens.mint_color if on else tokens.disc_700_color


func _on_toggled(_on: bool) -> void:
	_restyle()


## Applies the shared per-theme look. The five blocks and the ink colours are identical for every
## chip, so they are built once per token set ([method _shared_look]) and shared by every instance;
## per chip only the "disabled" block (it shows the chip's own on/off face) is swapped when the
## state flips. The shared boxes are never touched after they are built.
func _restyle() -> void:
	var look: Dictionary = _shared_look()
	if _applied_generation != _look_generation:
		_applied_generation = _look_generation
		var boxes: Dictionary = look["boxes"] as Dictionary
		for state: String in BASE_STATES:
			add_theme_stylebox_override(state, boxes[state] as StyleBox)
		var off_ink: Color = look["off_ink"] as Color
		var on_ink: Color = look["on_ink"] as Color
		for item: String in OFF_INK_ITEMS:
			add_theme_color_override(item, off_ink)
		for item: String in ON_INK_ITEMS:
			add_theme_color_override(item, on_ink)
		add_theme_font_size_override("font_size", look["font_size"] as int)
		add_theme_constant_override("icon_max_width", look["icon_max_width"] as int)
		_shown_pressed = not button_pressed  # force the disabled block below
	if _shown_pressed != button_pressed:
		_shown_pressed = button_pressed
		var boxes_now: Dictionary = look["boxes"] as Dictionary
		add_theme_stylebox_override("disabled", boxes_now["disabled_on" if button_pressed else "disabled_off"] as StyleBox)
	queue_redraw()


## Drops the shared blocks so the next chip (re)styles from the current tokens (tests, tooling).
static func invalidate_style_cache() -> void:
	_look = {}
	_look_tuning = null
	_look_metrics = null


## The shared look of the current token set, rebuilt only when the tokens or metrics resource
## instance changes or [method invalidate_style_cache] ran (a Resource's `changed` also drops it).
static func _shared_look() -> Dictionary:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var m: ComponentMetrics = UiRowItem.metrics()
	if not _look.is_empty() and _look_tuning == arcade and _look_metrics == m:
		return _look
	var off_face: Color = face_for(false, arcade)
	var on_face: Color = face_for(true, arcade)
	var off_hover: Color = off_face.lerp(Color.WHITE, arcade.block_hover_light_mix)
	var on_hover: Color = on_face.lerp(Color.WHITE, arcade.block_hover_light_mix)
	var lip_off: Color = MenuStyleFactory.lip_for(off_face)
	var lip_on: Color = MenuStyleFactory.lip_for(on_face)
	var top_off: Color = MenuStyleFactory.top_for(off_face)
	var top_on: Color = MenuStyleFactory.top_for(on_face)
	var normal: int = BlockStyleBox.STATE_NORMAL
	var disabled_state: int = BlockStyleBox.STATE_DISABLED
	# Godot's "pressed" is the toggled-on look; the block itself stays unpressed (lit, ledged).
	var boxes: Dictionary = {
		"normal": BlockStyleBox.make(off_face, arcade, true, normal, lip_off, top_off),
		"hover": BlockStyleBox.make(off_hover, arcade, true, normal, lip_off, top_off),
		"pressed": BlockStyleBox.make(on_face, arcade, true, normal, lip_on, top_on),
		"hover_pressed": BlockStyleBox.make(on_hover, arcade, true, normal, lip_on, top_on),
		"disabled_off": BlockStyleBox.make(off_face, arcade, true, disabled_state, MenuStyleFactory.lip_for(off_face), MenuStyleFactory.top_for(off_face)),
		"disabled_on": BlockStyleBox.make(on_face, arcade, true, disabled_state, MenuStyleFactory.lip_for(on_face), MenuStyleFactory.top_for(on_face)),
	}
	var lead: float = float(arcade.space_3_px + m.chip_box_px + arcade.space_2_px)
	var pad: float = float(arcade.button_sm_pad_y_px)
	for key: String in boxes:
		var box: BlockStyleBox = boxes[key] as BlockStyleBox
		box.content_margin_left = lead
		# The row-item vertical fit (UiBlockButton.fit_row_height) applied once, to the shared box.
		box.content_margin_top = maxf(box.content_margin_top - pad, 0.0)
		box.content_margin_bottom = maxf(box.content_margin_bottom - pad, 0.0)
	_look = {
		"boxes": boxes,
		"off_ink": MenuStyleFactory.ink_for_face(off_face),
		"on_ink": MenuStyleFactory.ink_for_face(on_face),
		"font_size": arcade.font_size_button_sm_px,
		"icon_max_width": arcade.icon_max_width_px,
	}
	_look_generation += 1
	_look_tuning = arcade
	_look_metrics = m
	if not arcade.changed.is_connected(invalidate_style_cache):
		arcade.changed.connect(invalidate_style_cache)
	return _look


func _draw() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var m: ComponentMetrics = UiRowItem.metrics()
	var box: StyleBox = get_theme_stylebox("normal")
	var centre_y: float = (box.content_margin_top + size.y - box.content_margin_bottom) / 2.0
	var edge: float = float(m.chip_box_px)
	var rect: Rect2 = Rect2(Vector2(float(arcade.space_3_px), centre_y - edge / 2.0), Vector2(edge, edge))
	var alpha: float = arcade.disabled_alpha if disabled else 1.0
	var frame: StyleBoxFlat = StyleBoxFlat.new()
	frame.set_corner_radius_all(arcade.radius_cell_px)
	if button_pressed:
		frame.bg_color = Color(arcade.ink_color, alpha)
	else:
		frame.bg_color = Color(arcade.disc_900_color, alpha)
		frame.set_border_width_all(arcade.well_border_px)
		frame.border_color = Color(arcade.disc_400_color, alpha)
	frame.draw(get_canvas_item(), rect)
	if button_pressed:
		var tick: Color = Color(arcade.mint_color, alpha)
		var points: PackedVector2Array = PackedVector2Array([
			rect.position + rect.size * Vector2(TICK_START.x, TICK_START.y),
			rect.position + rect.size * Vector2(TICK_MID.x, TICK_MID.y),
			rect.position + rect.size * Vector2(TICK_END.x, TICK_END.y),
		])
		draw_polyline(points, tick, float(m.chip_check_stroke_px), true)


## The tick's three points as fractions of the check box (a fixed glyph shape, not a tunable).
const TICK_START: Vector2 = Vector2(0.22, 0.52)
const TICK_MID: Vector2 = Vector2(0.42, 0.72)
const TICK_END: Vector2 = Vector2(0.78, 0.28)
