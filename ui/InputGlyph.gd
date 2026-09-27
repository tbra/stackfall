class_name InputGlyph
extends PanelContainer
## One small glyph badge for a single InputEvent -- a rounded "key cap"
## background with a short label. ui/KeyRebindRow.gd builds one of these per
## bound event of the active device family (autoload/Settings.gd's own
## active_input_device()), so the Controls page reads as compact icons
## instead of comma-joined Godot event text (owner feedback: "using glyphs to
## show what different actions are mapped to").
##
## DECISION (Bontago-1pi.10, time-budgeted worker package): every glyph shape
## here is a StyleBoxFlat + Label -- no custom _draw()/SVG art. A rounded
## rect covers keyboard keys and mouse buttons/wheel; a fully round pill
## marks a gamepad face button (A/B/X/Y) to hint "this one is round on the
## real pad". CLAUDE.md's "don't add third-party assets" is satisfied
## trivially (nothing downloaded, nothing binary added); a later art pass can
## swap in real per-button SVG icons without touching any call site, since
## every caller only ever calls set_event().

## Preloaded so a fresh InputGlyph always has *some* tuning even when built
## from GDScript (ui/KeyRebindRow.gd's _refresh_glyphs()) with no scene-level
## @export wired up -- the same default-resource idiom game/CameraRig.gd's
## own `tuning` export and ui/MainMenu.gd's own `tuning` export both use.
@export var tuning: MenuVisualTuning = preload("res://config/menu_visual_tuning.tres")

## Xbox-style face buttons (spec controls table): round on the real pad, so
## their glyph is drawn as a full pill rather than the default rounded rect.
const FACE_BUTTONS: Array[int] = [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y]

const JOYPAD_BUTTON_LABELS: Dictionary[int, String] = {
	JOY_BUTTON_A: "A",
	JOY_BUTTON_B: "B",
	JOY_BUTTON_X: "X",
	JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB",
	JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_LEFT_STICK: "L3",
	JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_START: "Start",
	JOY_BUTTON_BACK: "Back",
	JOY_BUTTON_DPAD_UP: "D-Up",
	JOY_BUTTON_DPAD_DOWN: "D-Down",
	JOY_BUTTON_DPAD_LEFT: "D-Left",
	JOY_BUTTON_DPAD_RIGHT: "D-Right",
	JOY_BUTTON_GUIDE: "Guide",
	JOY_BUTTON_MISC1: "Misc",
}

const JOYPAD_AXIS_LABELS: Dictionary[int, String] = {
	JOY_AXIS_TRIGGER_LEFT: "LT",
	JOY_AXIS_TRIGGER_RIGHT: "RT",
	JOY_AXIS_LEFT_X: "L Stick",
	JOY_AXIS_LEFT_Y: "L Stick",
	JOY_AXIS_RIGHT_X: "R Stick",
	JOY_AXIS_RIGHT_Y: "R Stick",
}

const MOUSE_BUTTON_LABELS: Dictionary[int, String] = {
	MOUSE_BUTTON_LEFT: "LMB",
	MOUSE_BUTTON_RIGHT: "RMB",
	MOUSE_BUTTON_MIDDLE: "MMB",
	MOUSE_BUTTON_WHEEL_UP: "Wheel Up",
	MOUSE_BUTTON_WHEEL_DOWN: "Wheel Down",
	MOUSE_BUTTON_WHEEL_LEFT: "Wheel Left",
	MOUSE_BUTTON_WHEEL_RIGHT: "Wheel Right",
	MOUSE_BUTTON_XBUTTON1: "MB4",
	MOUSE_BUTTON_XBUTTON2: "MB5",
}

@onready var _label: Label = %GlyphLabel


## Configures this badge for `event`. Safe to call repeatedly (KeyRebindRow
## rebuilds its glyph row every time the binding or the active device
## changes) -- each call fully replaces the label text and stylebox rather
## than layering onto a previous call's state.
func set_event(event: InputEvent) -> void:
	_label.text = _label_for(event)
	_apply_style(_is_face_button(event))


## Test seam: the text this badge is currently showing.
func label_text() -> String:
	return _label.text


func _label_for(event: InputEvent) -> String:
	if event is InputEventKey:
		# tools/bootstrap_project.gd's own bootstrap bindings set
		# physical_keycode (layout-independent), leaving keycode at KEY_NONE
		# (0) -- as_text_keycode() on that reads back "(Unset)", not the real
		# key, so this falls back to as_text_physical_keycode() whenever
		# keycode itself carries nothing.
		var key_event: InputEventKey = event as InputEventKey
		var text: String = key_event.as_text_keycode() if key_event.keycode != KEY_NONE else key_event.as_text_physical_keycode()
		return text if not text.is_empty() else "Key"
	if event is InputEventMouseButton:
		var mouse_index: int = (event as InputEventMouseButton).button_index
		return MOUSE_BUTTON_LABELS.get(mouse_index, "MB%d" % mouse_index)
	if event is InputEventJoypadButton:
		var joy_index: int = (event as InputEventJoypadButton).button_index
		return JOYPAD_BUTTON_LABELS.get(joy_index, "Btn%d" % joy_index)
	if event is InputEventJoypadMotion:
		var axis: int = (event as InputEventJoypadMotion).axis
		return JOYPAD_AXIS_LABELS.get(axis, "Axis%d" % axis)
	return event.as_text()


func _is_face_button(event: InputEvent) -> bool:
	return event is InputEventJoypadButton and FACE_BUTTONS.has((event as InputEventJoypadButton).button_index)


func _apply_style(round_pill: bool) -> void:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = tuning.pill_dark_slate_color
	box.border_color = tuning.pill_dark_slate_hover_color
	box.set_border_width_all(1)
	box.set_corner_radius_all(999 if round_pill else 6)
	box.content_margin_left = 8.0
	box.content_margin_right = 8.0
	box.content_margin_top = 3.0
	box.content_margin_bottom = 3.0
	add_theme_stylebox_override("panel", box)
	_label.add_theme_color_override("font_color", tuning.label_ink_light_color)
