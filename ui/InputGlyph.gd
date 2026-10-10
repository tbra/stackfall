class_name InputGlyph
extends Control
## Icon glyph for a single InputEvent (Bontago-1pi.10 polish pass; Bontago-1pi.35
## adopts the new art in assets/ui/input_glyphs/). ui/KeyRebindRow.gd builds one
## of these per bound event of the active device family (autoload/Settings.gd's
## own active_input_device()); set_event() is the single seam every consumer uses.
##
## Texture path (preferred): keyboard keys resolve through
## assets/ui/input_glyphs/key_atlas/catalog.json (Godot keycode -> keycap PNG);
## mouse buttons/wheel resolve to mouse_*.svg; gamepad buttons and trigger/stick
## axes resolve to the base gamepad_*.svg files. A key the catalog does not
## cover (or one bound with modifiers) draws the label-free blank keycap with
## the real key name as a runtime text label; an unnamed gamepad button does the
## same on gamepad_button_blank.svg. The source art is paper-and-ink coloured
## (not meant for theme tinting), so it stays readable on light and dark buttons.
##
## Fallback path (kept): when the texture for an event cannot be loaded, the
## original in-repo _draw() primitives render it exactly as before -- Control
## primitives only (draw_style_box/draw_circle/draw_rect/draw_polygon/
## draw_string): a "key cap" rounded rect with the key's short label, a mouse
## silhouette with the pressed button/wheel highlighted, colored circles for the
## four Xbox-style face buttons, rounded "tabs" for shoulders/triggers, a cross
## with the pressed arm filled for the D-pad, and a plain circle for a stick
## click.

@export var tuning: MenuVisualTuning = preload("res://config/menu_visual_tuning.tres")
## Stick direction / click / chord art (Bontago-mp0.124), keyed in config.
@export var glyph_table: InputGlyphTable = preload("res://config/input_glyph_table.tres")

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

## Stick side per click button / axis, and the direction an axis value points
## to (Godot: X negative = left, Y negative = up) -- keys of InputGlyphTable.
const STICK_CLICK_SIDES: Dictionary[int, StringName] = {
	JOY_BUTTON_LEFT_STICK: &"left",
	JOY_BUTTON_RIGHT_STICK: &"right",
}
const STICK_AXIS_SIDES: Dictionary[int, StringName] = {
	JOY_AXIS_LEFT_X: &"left",
	JOY_AXIS_LEFT_Y: &"left",
	JOY_AXIS_RIGHT_X: &"right",
	JOY_AXIS_RIGHT_Y: &"right",
}
const STICK_HORIZONTAL_AXES: Array[int] = [JOY_AXIS_LEFT_X, JOY_AXIS_RIGHT_X]
## Combo art is authored 160x64 against the 64x64 single glyphs.
const COMBO_ASPECT: float = 2.5

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

# --- Texture art (Bontago-1pi.35) ------------------------------------------------
# DECISION: the glyph art locations are pure asset paths, kept as consts here
# (they are binary art references, not tunable values); the layout numbers
# below are measurements of that art's own SVG geometry, documented per const.
const GLYPH_SCENE_PATH: String = "res://ui/InputGlyph.tscn"
const GLYPH_ASSET_ROOT: String = "res://assets/ui/input_glyphs/"
const KEY_ATLAS_SUBDIR: String = "key_atlas/"
const KEY_CATALOG_FILE: String = "key_atlas/catalog.json"
const BLANK_KEYCAP_FILE: String = "key_atlas/keycap_blank.svg"
const BLANK_GAMEPAD_BUTTON_FILE: String = "gamepad_button_blank.svg"

## DECISION: the base gamepad_*.svg / mouse_*.svg files are used; the
## *_VARIANTS.md alternatives are not wired in. Mouse buttons beyond these
## (extra side buttons) keep the _draw() silhouette.
const MOUSE_GLYPH_FILES: Dictionary[int, String] = {
	MOUSE_BUTTON_LEFT: "mouse_left.svg",
	MOUSE_BUTTON_RIGHT: "mouse_right.svg",
	MOUSE_BUTTON_MIDDLE: "mouse_middle.svg",
	MOUSE_BUTTON_WHEEL_UP: "mouse_wheel_up.svg",
	MOUSE_BUTTON_WHEEL_DOWN: "mouse_wheel_down.svg",
	MOUSE_BUTTON_WHEEL_LEFT: "mouse_wheel_left.svg",
	MOUSE_BUTTON_WHEEL_RIGHT: "mouse_wheel_right.svg",
	MOUSE_BUTTON_XBUTTON1: "mouse_button_4.svg",
	MOUSE_BUTTON_XBUTTON2: "mouse_button_5.svg",
}

const JOYPAD_BUTTON_GLYPH_FILES: Dictionary[int, String] = {
	JOY_BUTTON_A: "gamepad_a.svg",
	JOY_BUTTON_B: "gamepad_b.svg",
	JOY_BUTTON_X: "gamepad_x.svg",
	JOY_BUTTON_Y: "gamepad_y.svg",
	JOY_BUTTON_LEFT_SHOULDER: "gamepad_lb.svg",
	JOY_BUTTON_RIGHT_SHOULDER: "gamepad_rb.svg",
	JOY_BUTTON_LEFT_STICK: "gamepad_stick_left.svg",
	JOY_BUTTON_RIGHT_STICK: "gamepad_stick_right.svg",
	JOY_BUTTON_START: "gamepad_start.svg",
	JOY_BUTTON_BACK: "gamepad_back.svg",
	JOY_BUTTON_GUIDE: "gamepad_guide.svg",
	JOY_BUTTON_MISC1: "gamepad_misc.svg",
	JOY_BUTTON_DPAD_UP: "gamepad_dpad_up.svg",
	JOY_BUTTON_DPAD_DOWN: "gamepad_dpad_down.svg",
	JOY_BUTTON_DPAD_LEFT: "gamepad_dpad_left.svg",
	JOY_BUTTON_DPAD_RIGHT: "gamepad_dpad_right.svg",
}

const JOYPAD_AXIS_GLYPH_FILES: Dictionary[int, String] = {
	JOY_AXIS_TRIGGER_LEFT: "gamepad_lt.svg",
	JOY_AXIS_TRIGGER_RIGHT: "gamepad_rt.svg",
	JOY_AXIS_LEFT_X: "gamepad_stick_left.svg",
	JOY_AXIS_LEFT_Y: "gamepad_stick_left.svg",
	JOY_AXIS_RIGHT_X: "gamepad_stick_right.svg",
	JOY_AXIS_RIGHT_Y: "gamepad_stick_right.svg",
}

## A modifier key's own event carries its own modifier bit; only an *extra*
## modifier (Ctrl+E) makes the atlas keycap for the base key misleading.
const KEY_OWN_MODIFIER_MASKS: Dictionary[int, int] = {
	KEY_SHIFT: KEY_MASK_SHIFT,
	KEY_CTRL: KEY_MASK_CTRL,
	KEY_ALT: KEY_MASK_ALT,
	KEY_META: KEY_MASK_META,
}

## keycap_blank.svg is 128 source px square; its rounded corner plus stroke
## occupy the outer 40 px (0.3125) on each side, so a wider keycap stretches
## only the centre slice and keeps both caps undistorted.
const KEYCAP_CAP_FRACTION: float = 0.3125
## The keycap face spans y 9..100 of 128 (above the lower lip); the label sits
## on the middle of that band.
const KEYCAP_FACE_CENTER_Y_FRACTION: float = 0.43
const KEYCAP_LABEL_FONT_SIZE: int = 13
## gamepad_button_blank.svg's face spans y 15..42 of 64 and x 6..58 (the pill).
const PAD_BUTTON_FACE_CENTER_Y_FRACTION: float = 0.445
const PAD_BUTTON_FACE_WIDTH_FRACTION: float = 0.7
const PAD_BUTTON_LABEL_FONT_SIZE: int = 12
const LABEL_MIN_FONT_SIZE: int = 7

enum Shell { NONE, KEYCAP, PAD_BUTTON }

## Kinds drawn as Stackfall Arcade caps; mouse, D-pad and stick keep their pictograms.
const ARCADE_CAP_KINDS: Array[Kind] = [Kind.KEY, Kind.FACE, Kind.SHOULDER, Kind.TRIGGER, Kind.GENERIC]
## Legend size on a cap (design system label/caption floor is 13 px).
const ARCADE_LEGEND_FONT_SIZE: int = 14

## Test seam: where the glyph art is read from. Pointing it at a missing
## folder proves the _draw() fallback path.
var asset_root: String = GLYPH_ASSET_ROOT

# Parsed key_atlas/catalog.json per asset root: Dictionary[int, String] of
# Godot keycode -> PNG file name. Loaded once, shared by every glyph.
static var _key_atlas_cache: Dictionary[String, Dictionary] = {}
# Imported textures by path; a missing asset is cached as null so a bad path
# is probed once, not on every set_event().
static var _texture_cache: Dictionary[String, Texture2D] = {}

var _kind: Kind = Kind.GENERIC
var _text: String = "?"
var _mouse_button: int = -1
var _dpad_dir: StringName = &""
var _face_color: Color = Color.WHITE
var _texture: Texture2D = null
var _shell: Shell = Shell.NONE
## Stackfall Arcade (UI reskin P6): keys, pad face buttons, shoulders/triggers and plain text badges
## are drawn as ink-on-block caps instead of the paper-and-ink art. False for table art (stick
## directions, combos) and for kinds that keep their pictogram (mouse, D-pad, stick).
var _arcade_cap: bool = false
## True while the texture is authored table art (stick direction/click, combo) that stays as drawn.
var _table_art: bool = false
var _listening: bool = false
var _face_button_index: int = -1
var _arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()


func _ready() -> void:
	# The atlas art is rasterised at 4x its on-screen size with mipmaps (see the
	# asset README); sample them so the downscale stays crisp.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(SHAPE_WIDTH_PX, GLYPH_HEIGHT_PX)


## Configures this badge for `event`. Safe to call repeatedly (KeyRebindRow
## rebuilds its glyph row every time the binding or the active device
## changes) -- each call fully replaces this glyph's state and redraws
## rather than layering onto a previous call's state.
func set_event(event: InputEvent) -> void:
	_clear_texture()
	_listening = false
	_face_button_index = -1
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
	_refresh_arcade_cap()
	queue_redraw()


## Chord prompt: `events` (all gamepad) held together. Uses the authored combo
## art when the component set has one (LB+RB, RT+right stick), else the first
## event's own glyph; the label is always the joined component labels.
func set_chord(events: Array[InputEvent]) -> void:
	if events.is_empty():
		return
	set_event(events[0])
	if events.size() == 1:
		return
	var ids: PackedStringArray = PackedStringArray()
	var labels: PackedStringArray = PackedStringArray()
	for event: InputEvent in events:
		var id: String = pad_component_id(event)
		if id.is_empty():
			ids.clear()
			break
		ids.append(id)
	for event: InputEvent in events:
		var part: InputGlyph = InputGlyph.new()
		part.set_event(event)
		labels.append(part.label_text())
		part.free()
	_text = "+".join(labels)
	if not ids.is_empty() and _apply_table_texture(glyph_table.combo(ids)):
			custom_minimum_size = Vector2(GLYPH_HEIGHT_PX * COMBO_ASPECT, GLYPH_HEIGHT_PX)
	_refresh_arcade_cap()
	queue_redraw()


## Events bound to `action` on one device family (gamepad when `gamepad`, else
## keyboard/mouse). Empty for an unknown action. The only place UI code reads
## the Input Map for prompts (single-source concept G).
static func events_of_family(action: StringName, gamepad: bool) -> Array[InputEvent]:
	var matched: Array[InputEvent] = []
	if not InputMap.has_action(action):
		return matched
	for event: InputEvent in InputMap.action_get_events(action):
		var is_gamepad: bool = event is InputEventJoypadButton or event is InputEventJoypadMotion
		if is_gamepad == gamepad:
			matched.append(event)
	return matched


## Events of `action` for `device` (a Settings.DEVICE_* family; empty = the
## player's active device).
static func events_for_action(action: StringName, device: StringName = &"") -> Array[InputEvent]:
	var family: StringName = device if device != &"" else Settings.active_input_device()
	return events_of_family(action, family == Settings.DEVICE_GAMEPAD)


## Instantiates one glyph per event (at most `max_count` when > 0) under
## `parent` and returns them.
static func build_for_events(parent: Control, events: Array[InputEvent], max_count: int = 0) -> Array[InputGlyph]:
	var built: Array[InputGlyph] = []
	var scene: PackedScene = load(GLYPH_SCENE_PATH) as PackedScene
	for event: InputEvent in events:
		if max_count > 0 and built.size() >= max_count:
			break
		var glyph: InputGlyph = scene.instantiate() as InputGlyph
		parent.add_child(glyph)
		glyph.set_event(event)
		built.append(glyph)
	return built


## Glyphs for the first `max_count` (0 = all) bindings of `action` on the
## active device, parented under `parent`.
static func build_for_action(parent: Control, action: StringName, max_count: int = 0) -> Array[InputGlyph]:
	return build_for_events(parent, events_for_action(action), max_count)


## Stable text signature of the active-device bindings of `action` (cache key).
static func signature_for_action(action: StringName) -> String:
	var parts: PackedStringArray = PackedStringArray([String(Settings.active_input_device())])
	for event: InputEvent in events_for_action(action):
		parts.append(event.as_text())
	return "|".join(parts)


## Stable id of a gamepad event for combo lookup ("lb", "rt", "stick_right",
## ...), or "" for anything that is not a named pad button/axis.
static func pad_component_id(event: InputEvent) -> String:
	var file: String = ""
	if event is InputEventJoypadButton:
		file = JOYPAD_BUTTON_GLYPH_FILES.get((event as InputEventJoypadButton).button_index, "")
	elif event is InputEventJoypadMotion:
		file = JOYPAD_AXIS_GLYPH_FILES.get((event as InputEventJoypadMotion).axis, "")
	return file.trim_prefix("gamepad_").trim_suffix(".svg")


## Renders a plain "+N" overflow badge instead of a real event -- Owner: "max
## two glyphs per row, extra bindings hidden behind '+1'".
func set_overflow_count(count: int) -> void:
	_clear_texture()
	_kind = Kind.GENERIC
	_listening = false
	_text = "+%d" % count
	custom_minimum_size = Vector2(SHAPE_WIDTH_PX, GLYPH_HEIGHT_PX)
	_refresh_arcade_cap()
	queue_redraw()


## Renders the row's own "listening" placeholder (owner: "activating it
## enters 'press a key/button…' state shown in the glyph slot").
func set_listening() -> void:
	_clear_texture()
	_kind = Kind.GENERIC
	_text = "…"
	_listening = true
	custom_minimum_size = Vector2(SHAPE_WIDTH_PX * 2.0, GLYPH_HEIGHT_PX)
	_refresh_arcade_cap()
	queue_redraw()


## Test seam: the short descriptive text this event maps to (not necessarily
## painted on screen -- a mouse/D-pad/stick glyph is a pictogram with no
## drawn label, this is still its accessible/test-facing summary).
func label_text() -> String:
	return _text


## Test seam: the art this glyph draws, or null while it renders through the
## _draw() fallback primitives (missing asset, "+N" badge, listening dots).
func glyph_texture() -> Texture2D:
	return _texture


## Test seam: true when the texture is a label-free blank shell and the real
## name is drawn on top as runtime text (unmapped/modified key, unnamed button).
func uses_blank_shell() -> bool:
	return _shell != Shell.NONE


## Test seam: true when this glyph paints a Stackfall Arcade cap (keys, face buttons, chips).
func is_arcade_cap() -> bool:
	return _arcade_cap


## Test seam: the face colour of the arcade cap this glyph paints.
func arcade_face_color() -> Color:
	return _arcade_cap_face()


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
	_apply_key_texture(key_event, code)


func _configure_mouse(mouse_event: InputEventMouseButton) -> void:
	_kind = Kind.MOUSE
	_mouse_button = mouse_event.button_index
	_text = MOUSE_BUTTON_LABELS.get(_mouse_button, "MB%d" % _mouse_button)
	custom_minimum_size = Vector2(MOUSE_WIDTH_PX, GLYPH_HEIGHT_PX)
	if MOUSE_GLYPH_FILES.has(_mouse_button):
		_apply_square_texture(asset_root + MOUSE_GLYPH_FILES[_mouse_button])


func _configure_joypad_button(joy_event: InputEventJoypadButton) -> void:
	var index: int = joy_event.button_index
	_text = JOYPAD_BUTTON_LABELS.get(index, "Btn%d" % index)
	if FACE_COLORS.has(index):
		_kind = Kind.FACE
		_face_color = FACE_COLORS[index]
		_face_button_index = index
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
	if STICK_CLICK_SIDES.has(index) and _apply_table_texture(glyph_table.stick_click(STICK_CLICK_SIDES[index])):
		return
	_apply_pad_texture(JOYPAD_BUTTON_GLYPH_FILES.get(index, ""))


func _configure_joypad_motion(motion_event: InputEventJoypadMotion) -> void:
	var axis: int = motion_event.axis
	_text = JOYPAD_AXIS_LABELS.get(axis, "Axis%d" % axis)
	if TRIGGER_AXES.has(axis):
		_kind = Kind.TRIGGER
		custom_minimum_size = Vector2(SHOULDER_WIDTH_PX, GLYPH_HEIGHT_PX)
	else:
		_kind = Kind.STICK
		custom_minimum_size = Vector2(SHAPE_WIDTH_PX, GLYPH_HEIGHT_PX)
		# A stick axis bound with a sign (axis_value) is a directed prompt.
		if STICK_AXIS_SIDES.has(axis) and not is_zero_approx(motion_event.axis_value):
			var direction: StringName = _axis_direction(axis, motion_event.axis_value)
			if _apply_table_texture(glyph_table.stick_direction(STICK_AXIS_SIDES[axis], direction)):
				_text = "%s %s" % [_text, direction]
				return
	_apply_pad_texture(JOYPAD_AXIS_GLYPH_FILES.get(axis, ""))


# --- Texture resolution ----------------------------------------------------------


func _clear_texture() -> void:
	_table_art = false
	_texture = null
	_shell = Shell.NONE


## Keyboard: the catalog's keycap for this keycode; a key the catalog does not
## list (international/future remaps), or one bound with an extra modifier,
## gets the blank keycap with the key name as a runtime label instead.
func _apply_key_texture(key_event: InputEventKey, code: Key) -> void:
	if not _has_extra_modifier(key_event, code):
		var atlas_file: String = _key_atlas_file(code)
		if not atlas_file.is_empty():
			if _apply_square_texture(asset_root + KEY_ATLAS_SUBDIR + atlas_file):
				return
	var shell: Texture2D = _load_texture(asset_root + BLANK_KEYCAP_FILE)
	if shell == null:
		return
	_texture = shell
	_shell = Shell.KEYCAP
	var label_width: float = _label_width(_text, KEYCAP_LABEL_FONT_SIZE)
	custom_minimum_size = Vector2(maxf(GLYPH_HEIGHT_PX, label_width + KEY_PADDING_PX), GLYPH_HEIGHT_PX)


## Gamepad: the named SVG, else the blank button shell with the runtime label
## (an unnamed button such as a paddle keeps its "BtnN" text).
func _apply_pad_texture(file: String) -> void:
	if not file.is_empty() and _apply_square_texture(asset_root + file):
		return
	var shell: Texture2D = _load_texture(asset_root + BLANK_GAMEPAD_BUTTON_FILE)
	if shell == null:
		return
	_texture = shell
	_shell = Shell.PAD_BUTTON
	custom_minimum_size = Vector2(GLYPH_HEIGHT_PX, GLYPH_HEIGHT_PX)


## Square art drawn at the ~32 px glyph height; false when the asset is missing
## so the caller keeps the _draw() fallback.
func _apply_square_texture(path: String) -> bool:
	var texture: Texture2D = _load_texture(path)
	if texture == null:
		return false
	_texture = texture
	_shell = Shell.NONE
	custom_minimum_size = Vector2(GLYPH_HEIGHT_PX, GLYPH_HEIGHT_PX)
	return true


## Table art (stick direction/click, combos): only with the shipped asset root
## so the missing-folder fallback seam still reaches _draw().
func _apply_table_texture(texture: Texture2D) -> bool:
	if texture == null or asset_root != GLYPH_ASSET_ROOT:
		return false
	_texture = texture
	_shell = Shell.NONE
	custom_minimum_size = Vector2(GLYPH_HEIGHT_PX, GLYPH_HEIGHT_PX)
	_table_art = true
	return true


static func _axis_direction(axis: int, value: float) -> StringName:
	if STICK_HORIZONTAL_AXES.has(axis):
		return &"left" if value < 0.0 else &"right"
	return &"up" if value < 0.0 else &"down"


func _has_extra_modifier(key_event: InputEventKey, code: Key) -> bool:
	var mask: int = key_event.get_modifiers_mask()
	mask &= ~int(KEY_OWN_MODIFIER_MASKS.get(code, 0))
	return mask != 0


func _key_atlas_file(code: Key) -> String:
	var files: Dictionary = _key_atlas_files(asset_root)
	return str(files.get(int(code), ""))


func _label_width(text: String, font_size: int) -> float:
	return get_theme_default_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x


## Parses key_atlas/catalog.json once per asset root (keys[].code/file).
static func _key_atlas_files(root: String) -> Dictionary:
	if _key_atlas_cache.has(root):
		return _key_atlas_cache[root]
	var files: Dictionary[int, String] = {}
	var catalog_path: String = root + KEY_CATALOG_FILE
	if ResourceLoader.exists(catalog_path):
		var catalog: JSON = ResourceLoader.load(catalog_path) as JSON
		if catalog != null and catalog.data is Dictionary:
			var entries: Variant = (catalog.data as Dictionary).get("keys", [])
			if entries is Array:
				for entry: Variant in entries as Array:
					if entry is Dictionary:
						var record: Dictionary = entry as Dictionary
						if record.has("code") and record.has("file"):
							files[int(record["code"])] = str(record["file"])
	_key_atlas_cache[root] = files
	return files


static func _load_texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path]
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		texture = ResourceLoader.load(path) as Texture2D
	_texture_cache[path] = texture
	return texture


func _draw() -> void:
	if _arcade_cap:
		_draw_arcade_cap()
		return
	if _texture != null:
		_draw_texture_glyph()
		return
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


# --- Stackfall Arcade caps (UI reskin P6) -----------------------------------------


## Decides whether this glyph is an arcade cap and, if so, sizes it to its legend. The loaded
## texture stays resolved (glyph_texture() seam, missing-asset fallback) but is not painted.
func _refresh_arcade_cap() -> void:
	_arcade_cap = not _table_art and ARCADE_CAP_KINDS.has(_kind)
	if not _arcade_cap:
		return
	var width: float = GLYPH_HEIGHT_PX
	if not _is_round_cap():
		width = maxf(GLYPH_HEIGHT_PX, _label_width(_text, ARCADE_LEGEND_FONT_SIZE) + float(_arcade.space_2_px) * 2.0)
	custom_minimum_size = Vector2(width, GLYPH_HEIGHT_PX)


## A single pad face button is a round cap; a chord containing one is a chip.
func _is_round_cap() -> bool:
	return _kind == Kind.FACE and _face_button_index >= 0 and not _text.contains("+")


func _draw_arcade_cap() -> void:
	var face: Color = _arcade_cap_face()
	if _is_round_cap():
		_draw_round_cap(face, InputGlyphTable.face_button_lip_color(_face_button_index, _arcade))
		return
	var lip: Color = _arcade.rim_lip_color if _listening else Color.TRANSPARENT
	draw_style_box(BlockStyleBox.make(face, _arcade, true, BlockStyleBox.STATE_NORMAL, lip), Rect2(Vector2.ZERO, size))
	var face_top: float = float(_arcade.top_px)
	var face_bottom: float = size.y - float(_arcade.drop_sm_px) - float(_arcade.lip_sm_px)
	_draw_text_at(_text, MenuStyleFactory.ink_for_face(face), ARCADE_LEGEND_FONT_SIZE,
		Vector2(size.x * 0.5, (face_top + face_bottom) * 0.5))


## Face colour per kind: keys cream, pad chips and chords sand, plain badges disc-600, the
## listening placeholder rim gold, a lone face button its own token.
func _arcade_cap_face() -> Color:
	if _listening:
		return _arcade.rim_color
	match _kind:
		Kind.KEY:
			return _arcade.cream_color
		Kind.FACE:
			if _is_round_cap():
				return InputGlyphTable.face_button_color(_face_button_index, _arcade)
			return _arcade.sand_color
		Kind.SHOULDER, Kind.TRIGGER:
			return _arcade.sand_color
	return _arcade.disc_600_color


## Round pad cap: ledge circle, lip circle, lit top circle, face circle (the same four layers as
## a block, stacked so the lit top and dark lip read as crescents).
func _draw_round_cap(face: Color, lip: Color) -> void:
	var drop: float = float(_arcade.drop_sm_px)
	var lip_h: float = float(_arcade.lip_sm_px)
	var top_h: float = float(_arcade.top_px)
	var radius: float = (size.y - drop) * 0.5
	var center: Vector2 = Vector2(size.x * 0.5, radius)
	var lip_color: Color = lip if lip.a > 0.0 else face.lerp(Color.BLACK, _arcade.block_lip_dark_mix)
	var top_color: Color = face.lerp(Color.WHITE, _arcade.block_top_light_mix)
	draw_circle(center + Vector2(0.0, drop), radius, _arcade.disc_950_color)
	draw_circle(center, radius, lip_color)
	var upper_radius: float = radius - lip_h * 0.5
	var upper_center: Vector2 = center - Vector2(0.0, lip_h * 0.5)
	draw_circle(upper_center, upper_radius, top_color)
	draw_circle(upper_center + Vector2(0.0, top_h), upper_radius - top_h * 0.5, face)
	_draw_text_at(_text, _arcade.ink_color, ARCADE_LEGEND_FONT_SIZE, upper_center + Vector2(0.0, top_h * 0.5))


func _draw_texture_glyph() -> void:
	match _shell:
		Shell.KEYCAP:
			_draw_keycap_shell()
		Shell.PAD_BUTTON:
			var rect: Rect2 = _fitted_rect()
			draw_texture_rect(_texture, rect, false)
			var face_center: Vector2 = rect.position + Vector2(
				rect.size.x * 0.5, rect.size.y * PAD_BUTTON_FACE_CENTER_Y_FRACTION)
			var face_width: float = rect.size.x * PAD_BUTTON_FACE_WIDTH_FRACTION
			var font_size: int = _fit_font_size(_text, PAD_BUTTON_LABEL_FONT_SIZE, face_width)
			_draw_text_at(_text, tuning.ink_color, font_size, face_center)
		_:
			draw_texture_rect(_texture, _fitted_rect(), false)


## The blank keycap, widened to the label: both rounded caps keep their shape
## and only the centre slice stretches; narrower than two caps it is drawn whole.
func _draw_keycap_shell() -> void:
	var source: Vector2 = _texture.get_size()
	var cap_scale: float = size.y / source.y
	var cap_source_width: float = source.x * KEYCAP_CAP_FRACTION
	var cap_width: float = cap_source_width * cap_scale
	if size.x <= cap_width * 2.0:
		draw_texture_rect(_texture, Rect2(Vector2.ZERO, size), false)
	else:
		draw_texture_rect_region(_texture, Rect2(0.0, 0.0, cap_width, size.y),
			Rect2(0.0, 0.0, cap_source_width, source.y))
		draw_texture_rect_region(_texture, Rect2(cap_width, 0.0, size.x - cap_width * 2.0, size.y),
			Rect2(cap_source_width, 0.0, source.x - cap_source_width * 2.0, source.y))
		draw_texture_rect_region(_texture, Rect2(size.x - cap_width, 0.0, cap_width, size.y),
			Rect2(source.x - cap_source_width, 0.0, cap_source_width, source.y))
	var face_center: Vector2 = Vector2(size.x * 0.5, size.y * KEYCAP_FACE_CENTER_Y_FRACTION)
	var font_size: int = _fit_font_size(_text, KEYCAP_LABEL_FONT_SIZE, size.x - KEY_PADDING_PX)
	_draw_text_at(_text, tuning.ink_color, font_size, face_center)


## Aspect-preserving, centred fit of the texture inside this control.
func _fitted_rect() -> Rect2:
	var source: Vector2 = _texture.get_size()
	var fit: float = minf(size.x / source.x, size.y / source.y)
	var fitted: Vector2 = source * fit
	return Rect2((size - fitted) * 0.5, fitted)


## Largest font size <= `base` whose `text` fits `max_width`, never below
## LABEL_MIN_FONT_SIZE.
func _fit_font_size(text: String, base: int, max_width: float) -> int:
	var font_size: int = base
	while font_size > LABEL_MIN_FONT_SIZE and _label_width(text, font_size) > max_width:
		font_size -= 1
	return font_size


func _draw_text_at(text: String, color: Color, font_size: int, center: Vector2) -> void:
	var font: Font = get_theme_default_font()
	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, font_size)
	var pos: Vector2 = center - text_size * 0.5
	pos.y += font.get_ascent(font_size)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


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
