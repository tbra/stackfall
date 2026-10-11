class_name InputGlyph
extends Control
## Icon glyph for a single InputEvent (Bontago-1pi.10 polish pass; Bontago-1pi.35
## adopts the new art in assets/ui/input_glyphs/). ui/KeyRebindRow.gd builds one
## of these per bound event of the active device family (autoload/Settings.gd's
## own active_input_device()); set_event() is the single seam every consumer uses.
##
## Every glyph is code-drawn in the Stackfall Arcade design system (docs/ui_reskin/components.md
## KeyPrompt; Bontago-1pi.159.17), so it shares the block recipe (lit top, lip, ledge) and the tokens
## of ArcadeVisualTuning and recolours with them: keys are cream caps with an ink legend, shoulders,
## triggers and chords sand chips, pad face buttons round caps (A mint, B flare, X player-2, Y rim;
## the PlayStation set draws cross/circle/square/triangle on the same caps), the stick is a sand
## round cap with an L/R legend (a rim arrow when it is a direction, L3/R3 for the click), and the
## mouse and D-pad are block pictograms with the bound button lit in rim gold.
##
## The paper-and-ink art in assets/ui/input_glyphs/ is still resolved (glyph_texture(),
## uses_blank_shell() test seams, missing-folder probe) but no longer painted.

## Stick direction / click / chord art (Bontago-mp0.124), keyed in config.
@export var glyph_table: InputGlyphTable = preload("res://config/input_glyph_table.tres")
## Pad family for legends and face symbols (AUTO follows the connected pad, Xbox when none).
@export var pad_style: PadStyle = PadStyle.AUTO

## Owner: "Glyph height consistent (~32 px at 1080p)".
const GLYPH_HEIGHT_PX: float = 32.0
const SHAPE_WIDTH_PX: float = 32.0
const MOUSE_WIDTH_PX: float = 22.0
const SHOULDER_WIDTH_PX: float = 40.0

enum Kind { KEY, MOUSE, FACE, SHOULDER, TRIGGER, DPAD, STICK, GENERIC }

## Pad face buttons (round caps); their colours live in InputGlyphTable.face_button_color().
const FACE_BUTTONS: Array[int] = [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y]

## Which pad family the legends and face symbols follow. AUTO reads the first connected pad's name.
enum PadStyle { AUTO, XBOX, PLAYSTATION }

## Substrings (lower case) of Input.get_joy_name() that identify a PlayStation-family pad.
const PLAYSTATION_JOY_NAME_MARKERS: Array[String] = ["playstation", "ps3", "ps4", "ps5", "dualshock", "dualsense", "sony"]

## PlayStation legends for the buttons that differ from the Xbox set (JOYPAD_BUTTON_LABELS).
const PLAYSTATION_BUTTON_LABELS: Dictionary[int, String] = {
	JOY_BUTTON_A: "Cross",
	JOY_BUTTON_B: "Circle",
	JOY_BUTTON_X: "Square",
	JOY_BUTTON_Y: "Triangle",
	JOY_BUTTON_LEFT_SHOULDER: "L1",
	JOY_BUTTON_RIGHT_SHOULDER: "R1",
	JOY_BUTTON_START: "Options",
	JOY_BUTTON_BACK: "Share",
	JOY_BUTTON_GUIDE: "PS",
}
const PLAYSTATION_AXIS_LABELS: Dictionary[int, String] = {
	JOY_AXIS_TRIGGER_LEFT: "L2",
	JOY_AXIS_TRIGGER_RIGHT: "R2",
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

enum Shell { NONE, KEYCAP, PAD_BUTTON }

## Kinds drawn as Stackfall Arcade caps; mouse, D-pad and stick are block pictograms.
const ARCADE_CAP_KINDS: Array[Kind] = [Kind.KEY, Kind.FACE, Kind.SHOULDER, Kind.TRIGGER, Kind.GENERIC]
## Legend size on a cap (design system label/caption floor is 13 px).
const ARCADE_LEGEND_FONT_SIZE: int = 14
## Mouse pictogram geometry (22x32 block): inset of the button rules from the face edge, the share
## of the face the button row takes, rule width, wheel chevron half-size, side-button digit size.
const MOUSE_OUTLINE_PX: float = 2.0
const MOUSE_WHEEL_HEIGHT_FRACTION: float = 0.7
const MOUSE_SIDE_MARK_PX: Vector2 = Vector2(4.0, 8.0)
const MOUSE_BUTTON_ROW_FRACTION: float = 0.46
const MOUSE_LINE_PX: float = 1.0
const MOUSE_CHEVRON_PX: float = 3.0
const MOUSE_WHEEL_WIDTH_PX: float = 6.0
const MOUSE_SIDE_FONT_SIZE: int = 13
## PlayStation symbol geometry on the 32 px round cap, D-pad arm width (share of the cross) and
## chevron, stick direction arrow (size, and how far toward the cap edge it sits).
const PS_SYMBOL_HALF_PX: float = 6.0
const PS_SYMBOL_LINE_PX: float = 2.5
const PS_CIRCLE_SEGMENTS: int = 24
const PS_TRIANGLE_BASE: float = 0.8
const DPAD_ARM_FRACTION: float = 0.36
const DPAD_CHEVRON_PX: float = 3.0
const STICK_ARROW_PX: float = 3.0
const STICK_ARROW_REACH_FRACTION: float = 0.68

## Test seam: where the glyph art is read from. Pointing it at a missing
## folder proves the _draw() fallback path.
var asset_root: String = GLYPH_ASSET_ROOT

# Parsed key_atlas/catalog.json per asset root: Dictionary[int, String] of
# Godot keycode -> PNG file name. Loaded once, shared by every glyph.
static var _key_atlas_cache: Dictionary[String, Dictionary] = {}
# Imported textures by path; a missing asset is cached as null so a bad path
# is probed once, not on every set_event().
static var _texture_cache: Dictionary[String, Texture2D] = {}


## Bontago-xtq.44: drops the static texture/material cache on exit (freed before the renderer shuts down).
static func release_statics() -> void:
	_key_atlas_cache.clear()
	_texture_cache.clear()

var _kind: Kind = Kind.GENERIC
var _text: String = "?"
var _mouse_button: int = -1
var _dpad_dir: StringName = &""
var _pad_style: PadStyle = PadStyle.XBOX
var _stick_side: StringName = &""
var _stick_direction: StringName = &""
var _stick_click: bool = false
## True for a chord prompt (several events held together): drawn as one sand chip.
var _chord: bool = false
var _texture: Texture2D = null
var _shell: Shell = Shell.NONE
## Keys, pad face buttons, shoulders/triggers, chords and plain text badges are ink-on-block caps;
## false for the mouse, D-pad and stick pictograms.
var _arcade_cap: bool = false
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
	_chord = false
	_stick_side = &""
	_stick_direction = &""
	_stick_click = false
	_pad_style = _resolve_pad_style()
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
	_chord = true
	if not ids.is_empty():
		_apply_table_texture(glyph_table.combo(ids))
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
	_chord = false
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
	_chord = false
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
	_apply_key_texture(key_event, code)


func _configure_mouse(mouse_event: InputEventMouseButton) -> void:
	_kind = Kind.MOUSE
	_mouse_button = mouse_event.button_index
	_text = MOUSE_BUTTON_LABELS.get(_mouse_button, "MB%d" % _mouse_button)
	if MOUSE_GLYPH_FILES.has(_mouse_button):
		_apply_square_texture(asset_root + MOUSE_GLYPH_FILES[_mouse_button])


func _configure_joypad_button(joy_event: InputEventJoypadButton) -> void:
	var index: int = joy_event.button_index
	_text = _pad_button_label(index)
	if FACE_BUTTONS.has(index):
		_kind = Kind.FACE
		_face_button_index = index
	elif SHOULDER_BUTTONS.has(index):
		_kind = Kind.SHOULDER
	elif DPAD_DIRECTIONS.has(index):
		_kind = Kind.DPAD
		_dpad_dir = DPAD_DIRECTIONS[index]
	elif STICK_BUTTONS.has(index):
		_kind = Kind.STICK
		_stick_side = STICK_CLICK_SIDES[index]
		_stick_click = true
	else:
		_kind = Kind.GENERIC
	if STICK_CLICK_SIDES.has(index) and _apply_table_texture(glyph_table.stick_click(STICK_CLICK_SIDES[index])):
		return
	_apply_pad_texture(JOYPAD_BUTTON_GLYPH_FILES.get(index, ""))


func _configure_joypad_motion(motion_event: InputEventJoypadMotion) -> void:
	var axis: int = motion_event.axis
	_text = _pad_axis_label(axis)
	if TRIGGER_AXES.has(axis):
		_kind = Kind.TRIGGER
	else:
		_kind = Kind.STICK
		_stick_side = STICK_AXIS_SIDES.get(axis, &"left")
		# A stick axis bound with a sign (axis_value) is a directed prompt.
		if STICK_AXIS_SIDES.has(axis) and not is_zero_approx(motion_event.axis_value):
			_stick_direction = _axis_direction(axis, motion_event.axis_value)
			if _apply_table_texture(glyph_table.stick_direction(_stick_side, _stick_direction)):
				_text = "%s %s" % [_text, _stick_direction]
				return
	_apply_pad_texture(JOYPAD_AXIS_GLYPH_FILES.get(axis, ""))


## The pad family this glyph follows: the forced `pad_style`, else the first connected pad's name.
func _resolve_pad_style() -> PadStyle:
	if pad_style != PadStyle.AUTO:
		return pad_style
	var pads: Array[int] = Input.get_connected_joypads()
	if pads.is_empty():
		return PadStyle.XBOX
	return style_for_joy_name(Input.get_joy_name(pads[0]))


## PlayStation for a Sony-family joypad name, else Xbox (also the Steam Input / generic default).
static func style_for_joy_name(joy_name: String) -> PadStyle:
	var lowered: String = joy_name.to_lower()
	for marker: String in PLAYSTATION_JOY_NAME_MARKERS:
		if lowered.contains(marker):
			return PadStyle.PLAYSTATION
	return PadStyle.XBOX


func _pad_button_label(index: int) -> String:
	if _pad_style == PadStyle.PLAYSTATION and PLAYSTATION_BUTTON_LABELS.has(index):
		return PLAYSTATION_BUTTON_LABELS[index]
	return JOYPAD_BUTTON_LABELS.get(index, "Btn%d" % index)


func _pad_axis_label(axis: int) -> String:
	if _pad_style == PadStyle.PLAYSTATION and PLAYSTATION_AXIS_LABELS.has(axis):
		return PLAYSTATION_AXIS_LABELS[axis]
	return JOYPAD_AXIS_LABELS.get(axis, "Axis%d" % axis)


## Test seam: the pad family this glyph resolved for its current event.
func resolved_pad_style() -> PadStyle:
	return _pad_style


# --- Texture resolution ----------------------------------------------------------


func _clear_texture() -> void:
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


## Square art drawn at the ~32 px glyph height; false when the asset is missing
## so the caller keeps the _draw() fallback.
func _apply_square_texture(path: String) -> bool:
	var texture: Texture2D = _load_texture(path)
	if texture == null:
		return false
	_texture = texture
	_shell = Shell.NONE
	return true


## Table art (stick direction/click, combos), resolved as a seam only with the shipped asset root.
func _apply_table_texture(texture: Texture2D) -> bool:
	if texture == null or asset_root != GLYPH_ASSET_ROOT:
		return false
	_texture = texture
	_shell = Shell.NONE
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
	match _kind:
		Kind.MOUSE:
			_draw_mouse()
		Kind.DPAD:
			_draw_dpad()
		Kind.STICK:
			_draw_stick()


# --- Stackfall Arcade caps and pictograms ------------------------------------------


## Decides whether this glyph is a cap or a pictogram and sizes it: caps to their legend, round
## caps and pictograms to the square glyph box.
func _refresh_arcade_cap() -> void:
	_arcade_cap = _chord or ARCADE_CAP_KINDS.has(_kind)
	var width: float = GLYPH_HEIGHT_PX
	if _arcade_cap and not _is_round_cap():
		var legend: float = _label_width(_text.to_upper(), ARCADE_LEGEND_FONT_SIZE)
		var minimum: float = SHOULDER_WIDTH_PX if _kind == Kind.SHOULDER or _kind == Kind.TRIGGER else GLYPH_HEIGHT_PX
		width = maxf(minimum, legend + float(_arcade.space_2_px) * 2.0)
	custom_minimum_size = Vector2(width, GLYPH_HEIGHT_PX)


## A single pad face button is a round cap; a chord containing one is a chip.
func _is_round_cap() -> bool:
	return not _chord and _kind == Kind.FACE and _face_button_index >= 0


func _draw_arcade_cap() -> void:
	var face: Color = _arcade_cap_face()
	if _is_round_cap():
		var center: Vector2 = _draw_round_base(face, InputGlyphTable.face_button_lip_color(_face_button_index, _arcade))
		if _pad_style == PadStyle.PLAYSTATION:
			_draw_playstation_symbol(center, _face_button_index)
		else:
			_draw_text_at(_text.to_upper(), _arcade.ink_color, ARCADE_LEGEND_FONT_SIZE, center)
		return
	var lip: Color = _arcade.rim_lip_color if _listening else Color.TRANSPARENT
	draw_style_box(BlockStyleBox.make(face, _arcade, true, BlockStyleBox.STATE_NORMAL, lip), Rect2(Vector2.ZERO, size))
	var face_rect: Rect2 = _cap_face_rect(Rect2(Vector2.ZERO, size))
	# Bontago-1pi.149: the legend is uppercase per the mock; label_text() keeps the as_text() form.
	_draw_text_at(_text.to_upper(), MenuStyleFactory.ink_for_face(face), ARCADE_LEGEND_FONT_SIZE, face_rect.get_center())


## Face colour per kind: keys cream, pad chips and chords sand, plain badges disc-600, the
## listening placeholder rim gold, a lone face button its own token.
func _arcade_cap_face() -> Color:
	if _listening:
		return _arcade.rim_color
	if _chord:
		return _arcade.sand_color
	match _kind:
		Kind.KEY:
			return _arcade.cream_color
		Kind.FACE:
			return InputGlyphTable.face_button_color(_face_button_index, _arcade)
		Kind.SHOULDER, Kind.TRIGGER:
			return _arcade.sand_color
	return _arcade.disc_600_color


## Round cap: ledge circle, lip circle, lit top circle, face circle (the same four layers as a
## block, stacked so the lit top and dark lip read as crescents). Returns the legend centre.
func _draw_round_base(face: Color, lip: Color) -> Vector2:
	var drop: float = float(_arcade.drop_sm_px)
	var lip_h: float = float(_arcade.lip_sm_px)
	var top_h: float = float(_arcade.top_px)
	var radius: float = (minf(size.x, size.y) - drop) * 0.5
	var center: Vector2 = Vector2(size.x * 0.5, radius)
	var lip_color: Color = lip if lip.a > 0.0 else face.lerp(Color.BLACK, _arcade.block_lip_dark_mix)
	var top_color: Color = face.lerp(Color.WHITE, _arcade.block_top_light_mix)
	draw_circle(center + Vector2(0.0, drop), radius, _arcade.disc_950_color)
	draw_circle(center, radius, lip_color)
	var upper_radius: float = radius - lip_h * 0.5
	var upper_center: Vector2 = center - Vector2(0.0, lip_h * 0.5)
	draw_circle(upper_center, upper_radius, top_color)
	draw_circle(upper_center + Vector2(0.0, top_h), upper_radius - top_h * 0.5, face)
	return upper_center + Vector2(0.0, top_h * 0.5)


## PlayStation face symbol in ink on the cap: cross, circle, square, triangle.
func _draw_playstation_symbol(center: Vector2, button: int) -> void:
	var half: float = PS_SYMBOL_HALF_PX
	var ink: Color = _arcade.ink_color
	match button:
		JOY_BUTTON_A:
			draw_line(center + Vector2(-half, -half), center + Vector2(half, half), ink, PS_SYMBOL_LINE_PX, true)
			draw_line(center + Vector2(-half, half), center + Vector2(half, -half), ink, PS_SYMBOL_LINE_PX, true)
		JOY_BUTTON_B:
			draw_arc(center, half, 0.0, TAU, PS_CIRCLE_SEGMENTS, ink, PS_SYMBOL_LINE_PX, true)
		JOY_BUTTON_X:
			draw_rect(Rect2(center - Vector2(half, half), Vector2(half, half) * 2.0), ink, false, PS_SYMBOL_LINE_PX)
		JOY_BUTTON_Y:
			var apex: Vector2 = center + Vector2(0.0, -half)
			var left: Vector2 = center + Vector2(-half, half * PS_TRIANGLE_BASE)
			var right: Vector2 = center + Vector2(half, half * PS_TRIANGLE_BASE)
			draw_polyline(PackedVector2Array([apex, right, left, apex]), ink, PS_SYMBOL_LINE_PX, true)


func _draw_text_at(text: String, color: Color, font_size: int, center: Vector2) -> void:
	var font: Font = get_theme_default_font()
	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, font_size)
	var pos: Vector2 = center - text_size * 0.5
	pos.y += font.get_ascent(font_size)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


## Mouse pictogram (docs/ui_reskin/components.md KeyPrompt): a cream mouse body (rounded top and
## bottom, ink outline, disc-950 ledge like the caps), the button row split down the middle with a
## wheel pill in the split; the bound button fills rim gold, wheel directions light the pill and
## show an ink arrow below, the side buttons show a rim mark on the left edge and their number.
func _draw_mouse() -> void:
	var drop: float = float(_arcade.drop_sm_px)
	var outline: float = MOUSE_OUTLINE_PX
	var body_width: float = minf(MOUSE_WIDTH_PX, size.x)
	var body: Rect2 = Rect2(Vector2((size.x - body_width) * 0.5, 0.0), Vector2(body_width, size.y - drop))
	var top_radius: int = int(body_width * 0.5)
	var bottom_radius: int = _arcade.radius_block_px
	var ledge: StyleBoxFlat = _mouse_body_box(_arcade.disc_950_color, top_radius, bottom_radius, false)
	draw_style_box(ledge, Rect2(body.position + Vector2(0.0, drop), body.size))
	draw_style_box(_mouse_body_box(_arcade.cream_color, top_radius, bottom_radius, true), body)
	var inner: Rect2 = body.grow(-outline)
	var row_h: float = inner.size.y * MOUSE_BUTTON_ROW_FRACTION
	var half: float = inner.size.x * 0.5
	var corner: int = maxi(top_radius - int(outline), 0)
	var left_zone: Rect2 = Rect2(inner.position, Vector2(half, row_h))
	var right_zone: Rect2 = Rect2(inner.position + Vector2(half, 0.0), Vector2(half, row_h))
	var lower: Rect2 = Rect2(inner.position + Vector2(0.0, row_h), Vector2(inner.size.x, inner.size.y - row_h))
	var ink: Color = _arcade.ink_color
	var wheel_lit: bool = false
	match _mouse_button:
		MOUSE_BUTTON_LEFT:
			draw_style_box(_mouse_fill_box(_arcade.rim_color, corner, true), left_zone)
		MOUSE_BUTTON_RIGHT:
			draw_style_box(_mouse_fill_box(_arcade.rim_color, corner, false), right_zone)
		MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2:
			var mark: Rect2 = Rect2(Vector2(body.position.x - MOUSE_SIDE_MARK_PX.x * 0.5, lower.position.y + 1.0), MOUSE_SIDE_MARK_PX)
			draw_style_box(_ink_cell_box(), mark.grow(MOUSE_LINE_PX * 0.5))
			draw_style_box(_rim_cell_box(), mark)
		_:
			wheel_lit = true
	var center_x: float = inner.position.x + half
	draw_line(Vector2(center_x, inner.position.y), Vector2(center_x, inner.position.y + row_h), ink, MOUSE_LINE_PX)
	draw_line(Vector2(inner.position.x, inner.position.y + row_h), Vector2(inner.end.x, inner.position.y + row_h), ink, MOUSE_LINE_PX)
	var wheel: Rect2 = Rect2(Vector2(center_x - MOUSE_WHEEL_WIDTH_PX * 0.5, inner.position.y + MOUSE_LINE_PX),
		Vector2(MOUSE_WHEEL_WIDTH_PX, row_h * MOUSE_WHEEL_HEIGHT_FRACTION))
	draw_style_box(_cell_box(_arcade.dust_color), wheel)
	draw_rect(wheel, ink, false, MOUSE_LINE_PX)
	if wheel_lit:
		draw_style_box(_rim_cell_box(), wheel.grow(-MOUSE_LINE_PX))
	var arrow_at: Vector2 = lower.get_center()
	match _mouse_button:
		MOUSE_BUTTON_WHEEL_UP:
			_draw_chevron(arrow_at, Vector2.UP, MOUSE_CHEVRON_PX, ink)
		MOUSE_BUTTON_WHEEL_DOWN:
			_draw_chevron(arrow_at, Vector2.DOWN, MOUSE_CHEVRON_PX, ink)
		MOUSE_BUTTON_WHEEL_LEFT:
			_draw_chevron(arrow_at, Vector2.LEFT, MOUSE_CHEVRON_PX, ink)
		MOUSE_BUTTON_WHEEL_RIGHT:
			_draw_chevron(arrow_at, Vector2.RIGHT, MOUSE_CHEVRON_PX, ink)
		MOUSE_BUTTON_XBUTTON1:
			_draw_text_at("4", ink, MOUSE_SIDE_FONT_SIZE, arrow_at)
		MOUSE_BUTTON_XBUTTON2:
			_draw_text_at("5", ink, MOUSE_SIDE_FONT_SIZE, arrow_at)


## The mouse body: a rounded top (half the width) and bottom, with an ink outline when `outlined`.
func _mouse_body_box(color: Color, top_radius: int, bottom_radius: int, outlined: bool) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = color
	box.corner_radius_top_left = top_radius
	box.corner_radius_top_right = top_radius
	box.corner_radius_bottom_left = bottom_radius
	box.corner_radius_bottom_right = bottom_radius
	if outlined:
		box.border_color = _arcade.ink_color
		box.set_border_width_all(int(MOUSE_OUTLINE_PX))
	return box


## A lit button fill that follows the body's rounded top corner on its outer side only.
func _mouse_fill_box(color: Color, corner: int, left: bool) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = color
	if left:
		box.corner_radius_top_left = corner
	else:
		box.corner_radius_top_right = corner
	return box


func _ink_cell_box() -> StyleBoxFlat:
	return _cell_box(_arcade.ink_color)


## The rim-gold lit cell of a pictogram (small radius so it follows the block corners).
func _rim_cell_box() -> StyleBoxFlat:
	return _cell_box(_arcade.rim_color)


## The face area of a block-style cap: below the lit top edge, above the lip and the ledge.
func _cap_face_rect(cap: Rect2) -> Rect2:
	var top: float = float(_arcade.top_px)
	var bottom: float = cap.size.y - float(_arcade.drop_sm_px) - float(_arcade.lip_sm_px)
	return Rect2(cap.position + Vector2(0.0, top), Vector2(cap.size.x, bottom - top))


## A filled triangle of half-size `half` centred on `center` whose tip points along `direction`.
func _draw_chevron(center: Vector2, direction: Vector2, half: float, color: Color) -> void:
	var side: Vector2 = Vector2(-direction.y, direction.x)
	var points: PackedVector2Array = PackedVector2Array([
		center + direction * half,
		center - direction * half + side * half,
		center - direction * half - side * half,
	])
	draw_colored_polygon(points, color)


## D-pad pictogram: a sand cross on a disc-950 ledge with the bound arm lit in rim gold and an
## ink chevron pointing the way.
func _draw_dpad() -> void:
	var drop: float = float(_arcade.drop_sm_px)
	var side: float = minf(size.x, size.y - drop)
	var arm: float = side * DPAD_ARM_FRACTION
	var origin: Vector2 = Vector2((size.x - side) * 0.5, 0.0)
	var mid: Vector2 = origin + Vector2(side, side) * 0.5
	var horizontal: Rect2 = Rect2(Vector2(origin.x, mid.y - arm * 0.5), Vector2(side, arm))
	var vertical: Rect2 = Rect2(Vector2(mid.x - arm * 0.5, origin.y), Vector2(arm, side))
	var ledge: StyleBoxFlat = _cell_box(_arcade.disc_950_color)
	draw_style_box(ledge, Rect2(horizontal.position + Vector2(0.0, drop), horizontal.size))
	draw_style_box(ledge, Rect2(vertical.position + Vector2(0.0, drop), vertical.size))
	var cross: StyleBoxFlat = _cell_box(_arcade.sand_color)
	draw_style_box(cross, horizontal)
	draw_style_box(cross, vertical)
	var reach: float = (side - arm) * 0.5
	var direction: Vector2 = Vector2.ZERO
	var lit: Rect2 = Rect2()
	match _dpad_dir:
		&"up":
			direction = Vector2.UP
			lit = Rect2(vertical.position, Vector2(arm, reach + arm * 0.5))
		&"down":
			direction = Vector2.DOWN
			lit = Rect2(Vector2(vertical.position.x, mid.y - arm * 0.5), Vector2(arm, reach + arm * 0.5))
		&"left":
			direction = Vector2.LEFT
			lit = Rect2(horizontal.position, Vector2(reach + arm * 0.5, arm))
		&"right":
			direction = Vector2.RIGHT
			lit = Rect2(Vector2(mid.x - arm * 0.5, horizontal.position.y), Vector2(reach + arm * 0.5, arm))
	if direction == Vector2.ZERO:
		return
	draw_style_box(_rim_cell_box(), lit)
	_draw_chevron(mid + direction * (arm * 0.5 + reach * 0.5), direction, DPAD_CHEVRON_PX, _arcade.ink_color)


## Stick pictogram: a sand round cap with the side letter, L3/R3 for the click, and a flare arrow
## on the cap edge for a stick direction.
func _draw_stick() -> void:
	var center: Vector2 = _draw_round_base(_arcade.sand_color, Color.TRANSPARENT)
	var ink: Color = _arcade.ink_color
	var side_letter: String = "L" if _stick_side == &"left" else "R"
	if _stick_click:
		_draw_text_at("%s3" % side_letter, ink, ARCADE_LEGEND_FONT_SIZE, center)
		return
	_draw_text_at(side_letter, ink, ARCADE_LEGEND_FONT_SIZE, center)
	var radius: float = (minf(size.x, size.y) - float(_arcade.drop_sm_px)) * 0.5
	var direction: Vector2 = Vector2.ZERO
	match _stick_direction:
		&"up":
			direction = Vector2.UP
		&"down":
			direction = Vector2.DOWN
		&"left":
			direction = Vector2.LEFT
		&"right":
			direction = Vector2.RIGHT
	if direction != Vector2.ZERO:
		_draw_chevron(center + direction * radius * STICK_ARROW_REACH_FRACTION, direction, STICK_ARROW_PX, _arcade.flare_color)


func _cell_box(color: Color) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(_arcade.radius_cell_px)
	return box
