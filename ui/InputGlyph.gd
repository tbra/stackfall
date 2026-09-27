class_name InputGlyph
extends Control
## Real, in-repo-drawn icon glyphs for a single InputEvent (Bontago-1pi.10
## polish pass, owner: "real icon glyphs, drawn in-repo (no downloads)").
## Everything renders via _draw() with plain Control primitives
## (draw_style_box/draw_circle/draw_rect/draw_polygon/draw_string) -- no
## textures, no third-party assets, nothing binary added to the repo.
## ui/KeyRebindRow.gd builds one of these per bound event of the active
## device family (autoload/Settings.gd's own active_input_device()).
##
## Keyboard keys still read as a "key cap" (a rounded rect with the key's own
## short label); mouse and gamepad events get a real pictogram instead of
## text: a mouse silhouette with the pressed button/wheel direction
## highlighted, colored circles for the four Xbox-style face buttons,
## rounded "tabs" for shoulders/triggers, a cross with the pressed arm filled
## for the D-pad, and a plain circle for a stick click.

@export var tuning: MenuVisualTuning = preload("res://config/menu_visual_tuning.tres")

## Owner: "Glyph height consistent (~32 px at 1080p)".
const GLYPH_HEIGHT_PX: float = 32.0
const SHAPE_WIDTH_PX: float = 32.0
const MOUSE_WIDTH_PX: float = 22.0
const SHOULDER_WIDTH_PX: float = 40.0
const KEY_MIN_WIDTH_PX: float = 30.0
const KEY_PADDING_PX: float = 10.0

enum Kind { KEY, MOUSE, FACE, SHOULDER, TRIGGER, DPAD, STICK, GENERIC }

const FACE_COLORS: Dictionary[int, Color] = {
	JOY_BUTTON_A: Color(0.36, 0.72, 0.38, 1.0),
	JOY_BUTTON_B: Color(0.82, 0.30, 0.28, 1.0),
	JOY_BUTTON_X: Color(0.30, 0.53, 0.83, 1.0),
	JOY_BUTTON_Y: Color(0.87, 0.74, 0.24, 1.0),
}

const DPAD_DIRECTIONS: Dictionary[int, StringName] = {
	JOY_BUTTON_DPAD_UP: &"up",
	JOY_BUTTON_DPAD_DOWN: &"down",
	JOY_BUTTON_DPAD_LEFT: &"left",
	JOY_BUTTON_DPAD_RIGHT: &"right",
}

const SHOULDER_BUTTONS: Dictionary[int, String] = {
	JOY_BUTTON_LEFT_SHOULDER: "LB",
	JOY_BUTTON_RIGHT_SHOULDER: "RB",
}

const TRIGGER_AXES: Dictionary[int, String] = {
	JOY_AXIS_TRIGGER_LEFT: "LT",
	JOY_AXIS_TRIGGER_RIGHT: "RT",
}

const STICK_BUTTONS: Dictionary[int, String] = {
	JOY_BUTTON_LEFT_STICK: "L3",
	JOY_BUTTON_RIGHT_STICK: "R3",
}

## tools/bootstrap_project.gd's own bootstrap bindings set physical_keycode
## (layout-independent) rather than keycode -- as_text_physical_keycode()
## already gives a readable name for every one of those, but a few read long
## ("Bracket Left", "Page Up", "Escape"); this maps the ones this project
## actually binds (tools/bootstrap_project.gd's own KEY_* list) to a short
## glyph label. Keyed by the raw Key enum value, not by parsing display text,
## so it never depends on Godot's own wording for a given locale/version.
const SHORT_KEY_LABELS: Dictionary[Key, String] = {
	KEY_BRACKETLEFT: "[",
	KEY_BRACKETRIGHT: "]",
	KEY_PAGEUP: "PgUp",
	KEY_PAGEDOWN: "PgDn",
	KEY_ESCAPE: "Esc",
	KEY_HOME: "Home",
	KEY_END: "End",
	KEY_DELETE: "Del",
	KEY_BACKSPACE: "Bksp",
	KEY_ENTER: "Enter",
	KEY_TAB: "Tab",
	KEY_SPACE: "Space",
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

var _kind: Kind = Kind.GENERIC
var _text: String = "?"
var _mouse_button: int = -1
var _dpad_dir: StringName = &""
var _face_color: Color = Color.WHITE


func _ready() -> void:
	custom_minimum_size = Vector2(SHAPE_WIDTH_PX, GLYPH_HEIGHT_PX)


## Configures this badge for `event`. Safe to call repeatedly (KeyRebindRow
## rebuilds its glyph row every time the binding or the active device
## changes) -- each call fully replaces this glyph's state and redraws
## rather than layering onto a previous call's state.
func set_event(event: InputEvent) -> void:
	if event is InputEventKey:
		_configure_key(event as InputEventKey)
	elif event is InputEventMouseButton:
		_configure_mouse(event as InputEventMouseButton)
	elif event is InputEventJoypadButton:
		_configure_joypad_button(event as InputEventJoypadButton)
	elif event is InputEventJoypadMotion:
		_configure_joypad_motion(event as InputEventJoypadMotion)
	else:
		_kind = Kind.GENERIC
		_text = event.as_text()
		custom_minimum_size = Vector2(SHAPE_WIDTH_PX, GLYPH_HEIGHT_PX)
	queue_redraw()


## Renders a plain "+N" overflow badge instead of a real event -- Owner: "max
## two glyphs per row, extra bindings hidden behind '+1'".
func set_overflow_count(count: int) -> void:
	_kind = Kind.GENERIC
	_text = "+%d" % count
	custom_minimum_size = Vector2(SHAPE_WIDTH_PX, GLYPH_HEIGHT_PX)
	queue_redraw()


## Renders the row's own "listening" placeholder (owner: "activating it
## enters 'press a key/button…' state shown in the glyph slot").
func set_listening() -> void:
	_kind = Kind.GENERIC
	_text = "…"
	custom_minimum_size = Vector2(SHAPE_WIDTH_PX * 2.0, GLYPH_HEIGHT_PX)
	queue_redraw()


## Test seam: the short descriptive text this event maps to (not necessarily
## painted on screen -- a mouse/D-pad/stick glyph is a pictogram with no
## drawn label, this is still its accessible/test-facing summary).
func label_text() -> String:
	return _text


func _configure_key(key_event: InputEventKey) -> void:
	_kind = Kind.KEY
	var code: Key = key_event.keycode if key_event.keycode != KEY_NONE else key_event.physical_keycode
	if SHORT_KEY_LABELS.has(code):
		_text = SHORT_KEY_LABELS[code]
	else:
		_text = key_event.as_text_keycode() if key_event.keycode != KEY_NONE else key_event.as_text_physical_keycode()
		if _text.is_empty():
			_text = "Key"
	custom_minimum_size = Vector2(maxf(KEY_MIN_WIDTH_PX, _text.length() * 11.0 + KEY_PADDING_PX), GLYPH_HEIGHT_PX)


func _configure_mouse(mouse_event: InputEventMouseButton) -> void:
	_kind = Kind.MOUSE
	_mouse_button = mouse_event.button_index
	_text = MOUSE_BUTTON_LABELS.get(_mouse_button, "MB%d" % _mouse_button)
	custom_minimum_size = Vector2(MOUSE_WIDTH_PX, GLYPH_HEIGHT_PX)


func _configure_joypad_button(joy_event: InputEventJoypadButton) -> void:
	var index: int = joy_event.button_index
	_text = JOYPAD_BUTTON_LABELS.get(index, "Btn%d" % index)
	if FACE_COLORS.has(index):
		_kind = Kind.FACE
		_face_color = FACE_COLORS[index]
		custom_minimum_size = Vector2(SHAPE_WIDTH_PX, GLYPH_HEIGHT_PX)
	elif SHOULDER_BUTTONS.has(index):
		_kind = Kind.SHOULDER
		custom_minimum_size = Vector2(SHOULDER_WIDTH_PX, GLYPH_HEIGHT_PX)
	elif DPAD_DIRECTIONS.has(index):
		_kind = Kind.DPAD
		_dpad_dir = DPAD_DIRECTIONS[index]
		custom_minimum_size = Vector2(SHAPE_WIDTH_PX, GLYPH_HEIGHT_PX)
	elif STICK_BUTTONS.has(index):
		_kind = Kind.STICK
		custom_minimum_size = Vector2(SHAPE_WIDTH_PX, GLYPH_HEIGHT_PX)
	else:
		_kind = Kind.GENERIC
		custom_minimum_size = Vector2(SHAPE_WIDTH_PX, GLYPH_HEIGHT_PX)


func _configure_joypad_motion(motion_event: InputEventJoypadMotion) -> void:
	var axis: int = motion_event.axis
	_text = JOYPAD_AXIS_LABELS.get(axis, "Axis%d" % axis)
	if TRIGGER_AXES.has(axis):
		_kind = Kind.TRIGGER
		custom_minimum_size = Vector2(SHOULDER_WIDTH_PX, GLYPH_HEIGHT_PX)
	else:
		_kind = Kind.STICK
		custom_minimum_size = Vector2(SHAPE_WIDTH_PX, GLYPH_HEIGHT_PX)


func _draw() -> void:
	match _kind:
		Kind.KEY:
			_draw_key_cap()
		Kind.MOUSE:
			_draw_mouse()
		Kind.FACE:
			_draw_face_button()
		Kind.SHOULDER, Kind.TRIGGER:
			_draw_tab()
		Kind.DPAD:
			_draw_dpad()
		Kind.STICK:
			_draw_stick()
		_:
			_draw_generic()


func _key_box(color: Color) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = color.lightened(0.35)
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	return box


func _draw_key_cap() -> void:
	draw_style_box(_key_box(tuning.pill_dark_slate_color), Rect2(Vector2.ZERO, size))
	_draw_centered_text(_text, tuning.label_ink_light_color, 13)


func _draw_generic() -> void:
	draw_style_box(_key_box(tuning.pill_dark_slate_color), Rect2(Vector2.ZERO, size))
	_draw_centered_text(_text, tuning.label_ink_light_color, 13)


## A mouse silhouette (rounded body + a button-split line + a small wheel
## slot) with the pressed button or wheel direction highlighted -- owner:
## "mouse glyph = mouse outline with the relevant button/wheel highlighted".
func _draw_mouse() -> void:
	var body: Rect2 = Rect2(Vector2(1.0, 1.0), size - Vector2(2.0, 2.0))
	var outline: StyleBoxFlat = StyleBoxFlat.new()
	outline.bg_color = tuning.pill_dark_slate_color
	outline.border_color = tuning.pill_dark_slate_hover_color
	outline.set_border_width_all(1)
	outline.corner_radius_top_left = int(body.size.x * 0.5)
	outline.corner_radius_top_right = int(body.size.x * 0.5)
	outline.corner_radius_bottom_left = int(body.size.x * 0.35)
	outline.corner_radius_bottom_right = int(body.size.x * 0.35)
	draw_style_box(outline, body)

	var top_h: float = body.size.y * 0.42
	var third: float = body.size.x / 3.0
	var highlight: Color = tuning.pill_coral_color

	# Divider lines between the two top buttons and the top/bottom halves.
	draw_line(body.position + Vector2(third, 0.0), body.position + Vector2(third, top_h), tuning.pill_dark_slate_hover_color, 1.0)
	draw_line(body.position + Vector2(third * 2.0, 0.0), body.position + Vector2(third * 2.0, top_h), tuning.pill_dark_slate_hover_color, 1.0)
	draw_line(body.position + Vector2(0.0, top_h), body.position + Vector2(body.size.x, top_h), tuning.pill_dark_slate_hover_color, 1.0)

	match _mouse_button:
		MOUSE_BUTTON_LEFT:
			draw_rect(Rect2(body.position, Vector2(third, top_h)), highlight)
		MOUSE_BUTTON_RIGHT:
			draw_rect(Rect2(body.position + Vector2(third * 2.0, 0.0), Vector2(third, top_h)), highlight)
		MOUSE_BUTTON_MIDDLE:
			draw_rect(Rect2(body.position + Vector2(third, 0.0), Vector2(third, top_h)), highlight)
		MOUSE_BUTTON_WHEEL_UP:
			draw_rect(Rect2(body.position + Vector2(third, 0.0), Vector2(third, top_h * 0.5)), highlight)
		MOUSE_BUTTON_WHEEL_DOWN:
			draw_rect(Rect2(body.position + Vector2(third, top_h * 0.5), Vector2(third, top_h * 0.5)), highlight)
		_:
			draw_rect(Rect2(body.position + Vector2(third, 0.0), Vector2(third, top_h)), highlight)


func _draw_face_button() -> void:
	var center: Vector2 = size * 0.5
	var radius: float = minf(size.x, size.y) * 0.5 - 1.0
	draw_circle(center, radius, _face_color)
	_draw_centered_text(_text, Color(0.06, 0.06, 0.08, 1.0), 15)


func _draw_tab() -> void:
	var box: StyleBoxFlat = _key_box(tuning.pill_dark_slate_color)
	box.set_corner_radius_all(int(size.y * 0.5))
	draw_style_box(box, Rect2(Vector2.ZERO, size))
	_draw_centered_text(_text, tuning.label_ink_light_color, 12)


func _draw_dpad() -> void:
	var center: Vector2 = size * 0.5
	var arm: float = minf(size.x, size.y) * 0.25
	var thickness: float = arm * 0.9
	var dim: Color = tuning.pill_dark_slate_color
	var lit: Color = tuning.pill_coral_color

	var up_rect: Rect2 = Rect2(center + Vector2(-thickness * 0.5, -arm * 2.0), Vector2(thickness, arm))
	var down_rect: Rect2 = Rect2(center + Vector2(-thickness * 0.5, arm), Vector2(thickness, arm))
	var left_rect: Rect2 = Rect2(center + Vector2(-arm * 2.0, -thickness * 0.5), Vector2(arm, thickness))
	var right_rect: Rect2 = Rect2(center + Vector2(arm, -thickness * 0.5), Vector2(arm, thickness))
	var center_rect: Rect2 = Rect2(center - Vector2(thickness, thickness) * 0.5, Vector2(thickness, thickness))

	draw_rect(up_rect, lit if _dpad_dir == &"up" else dim)
	draw_rect(down_rect, lit if _dpad_dir == &"down" else dim)
	draw_rect(left_rect, lit if _dpad_dir == &"left" else dim)
	draw_rect(right_rect, lit if _dpad_dir == &"right" else dim)
	draw_rect(center_rect, dim)


func _draw_stick() -> void:
	var center: Vector2 = size * 0.5
	var radius: float = minf(size.x, size.y) * 0.5 - 1.0
	draw_circle(center, radius, tuning.pill_dark_slate_color)
	draw_arc(center, radius, 0.0, TAU, 24, tuning.pill_dark_slate_hover_color, 1.5)
	var stick_label: String = "L" if _text.begins_with("L") else "R"
	_draw_centered_text(stick_label, tuning.label_ink_light_color, 11)


func _draw_centered_text(text: String, color: Color, font_size: int) -> void:
	var font: Font = get_theme_default_font()
	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, font_size)
	var pos: Vector2 = (size - text_size) * 0.5
	pos.y += font.get_ascent(font_size)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
