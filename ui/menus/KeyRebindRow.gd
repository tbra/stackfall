class_name KeyRebindRow
extends Button
## One row of the Options key-rebinding list, built by ui/menus/OptionsMenu.gd (one per
## OptionsMenu.REBINDABLE_ACTIONS entry). Shows the action's current binding(s) as InputGlyph
## icons (InputMap.action_get_events(), which already reflects Settings key overrides) and
## captures the next InputEventKey/InputEventMouseButton/InputEventJoypadButton while "listening".
##
## The row itself is the Button, so a click or Space/Enter anywhere on it starts listening and the
## shared theme focus ring highlights the whole row. %Content (an HBoxContainer inside this Button,
## mouse_filter = IGNORE on every nested container so clicks fall through to the Button) holds the
## row visuals.

signal rebind_captured(action: StringName, event: InputEvent)

## At most two glyphs per row; extra bindings collapse into a "+N" glyph.
const MAX_GLYPHS: int = 2

const INPUT_GLYPH_SCENE: PackedScene = preload("res://ui/hud/InputGlyph.tscn")

## The listening prompt, shown in rim in place of the glyphs. The gamepad page asks for a button.
const LISTENING_TEXT_KEYBOARD: String = "PRESS A KEY\u2026"
const LISTENING_TEXT_GAMEPAD: String = "PRESS A BUTTON\u2026"
const LISTENING_LABEL_NAME: String = "ListeningLabel"
const OPTIONS_TUNING: OptionsVisualTuning = preload("res://config/ui/options_visual_tuning.tres")

## Player-facing action names. Only covers OptionsMenu.REBINDABLE_ACTIONS; anything missing here
## falls back to _display_name()'s auto-titlecase so a new rebindable action is never unlabeled.
const DISPLAY_NAMES: Dictionary[StringName, String] = {
	&"ghost_place": "Place block",
	&"use_gift_slot": "Activate gift",
	&"rotate_yaw_ccw": "Rotate left",
	&"rotate_yaw_cw": "Rotate right",
	&"rotate_pitch_fwd": "Tilt forward",
	&"rotate_pitch_back": "Tilt back",
	&"rotate_roll_left": "Roll left",
	&"rotate_roll_right": "Roll right",
	&"rotation_mode": "Free rotation mode (hold)",
	&"rotate_reset": "Reset rotation",
	&"rotate_drag": "Free rotate (drag)",
	&"rotate_snap": "Rotate 90 deg",
	&"rotate_drag_pad": "Free rotate (hold)",
	&"hover_raise": "Raise block",
	&"hover_lower": "Lower block",
	&"lock_vertical": "Lock height",
	&"camera_mode": "Camera mode",
	&"camera_orbit": "Orbit camera",
	&"camera_pan_left": "Pan left",
	&"camera_pan_right": "Pan right",
	&"camera_pan_forward": "Pan forward",
	&"camera_pan_back": "Pan back",
	&"camera_modifier": "Camera modifier",
	&"camera_zoom_in": "Zoom in",
	&"camera_zoom_out": "Zoom out",
	&"camera_snap_home": "Snap to home",
	&"camera_snap_goal": "Snap to goal",
	&"camera_reset": "Reset camera",
	&"pause_menu": "Pause",
	&"show_scores": "Show scores (hold)",
	&"chat_open": "Chat",
}

## The gamepad page lists only the pad's real controls. The pad rotates with B (rotate_snap, a
## 90 degree tap) and with RT held + left stick (rotate_drag_pad, free rotation), so those two have
## their own rows and the keyboard stand-in rows (Rotate left/right, Free rotation mode, Free
## rotate (drag)) are hidden on the pad page (PAD_NOT_APPLICABLE). An action's glyphs are always
## its own pad events.

## Pad-only actions: they have no mouse/keyboard binding (tools/bootstrap_project.gd), so
## their rows exist on the gamepad page only.
const PAD_ONLY_ACTIONS: Array[StringName] = [&"rotate_snap", &"rotate_drag_pad"]

## DECISION: actions with no gamepad function at all are hidden
## from the gamepad page instead of showing a blank row. lock_vertical: spec
## 2.5 "Lock to vertical" gamepad cell is "(stick and height are already
## separate)" -- left stick moves X/Z, LB/RB move height, so there is nothing to
## lock. They stay listed (and rebindable) on the keyboard/mouse page.
##
## DECISION (most camera controls make no
## sense to remap on a pad): the gamepad page also hides the camera rows that
## are fixed gestures rather than choices -- camera mode, the four pans (only
## live in the unused free camera, left stick + modifier), the pan modifier,
## and zoom in/out (the pad zooms with LT + left stick). "Orbit camera" (right
## stick) stays as the one camera row a pad player may want to read.
##
## Also hidden on the pad page: Orbit camera (the right stick always orbits and is not
## rebindable). It stays on the mouse/keyboard page (right mouse button).
const PAD_NOT_APPLICABLE: Array[StringName] = [
	&"lock_vertical",
	&"rotate_yaw_ccw", &"rotate_yaw_cw", &"rotation_mode", &"rotate_drag",
	&"camera_orbit",
	&"camera_mode", &"camera_modifier",
	&"camera_pan_left", &"camera_pan_right", &"camera_pan_forward", &"camera_pan_back",
	&"camera_zoom_in", &"camera_zoom_out",
	# chat is keyboard only, no pad function.
	&"chat_open",
]

## Rows hidden on both pages while CameraTuning.snap_enabled is false.
const SNAP_ACTIONS: Array[StringName] = [&"camera_snap_home", &"camera_snap_goal"]

## Read for snap_enabled only (a const Resource would be a private copy in GDScript).
@export var camera_tuning: CameraTuning = preload("res://config/player/camera_tuning.tres")

## Reused only for the row's own subtle hover/pressed highlight; the shared Theme's default
## "focus" stylebox is left untouched so focus reads like every other Control.
@export var tuning: MenuVisualTuning = preload("res://config/ui/menu_visual_tuning.tres")

@onready var _action_label: Label = %ActionLabel
@onready var _glyph_row: HBoxContainer = %GlyphRow

var _action: StringName = &""
var _listening: bool = false
var _banded: bool = false
var _idle_s: float = 0.0
## Axes (joypad axis index -> true) already past the bind threshold when listening started.
var _blocked_axes: Dictionary[int, bool] = {}


## Live-refreshes this row's glyphs whenever the player's last-used device changes, so
## OptionsMenu need not rebuild the whole list.
func _ready() -> void:
	%Content.minimum_size_changed.connect(_sync_content_minimum_size)
	_sync_content_minimum_size()
	_apply_row_style()
	pressed.connect(_on_pressed)
	Events.input_device_changed.connect(_on_input_device_changed)


func _sync_content_minimum_size() -> void:
	var needed: Vector2 = %Content.get_combined_minimum_size() + Vector2(28.0, 16.0)
	custom_minimum_size = Vector2(needed.x, maxf(float(OPTIONS_TUNING.binding_row_min_height_px), needed.y))


## BindingRow look. Alternate rows are lightly banded (disc-700), the hovered row is
## disc-700, the focused row is disc-600 inside the theme's 3 px cream outline, and a listening row
## swaps all of that for a rim edge.
func _apply_row_style() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var normal: StyleBox = StyleBoxEmpty.new()
	if _banded:
		var band: Color = arcade.disc_700_color
		band.a = OPTIONS_TUNING.binding_band_alpha
		normal = _row_box(band, arcade)
	var hover: StyleBoxFlat = _row_box(arcade.disc_700_color, arcade)
	if _listening:
		var listening: StyleBoxFlat = _row_box(arcade.disc_700_color, arcade)
		listening.border_color = arcade.rim_color
		listening.set_border_width_all(arcade.well_border_px)
		normal = listening
		hover = listening
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("disabled", normal)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", hover)
	add_theme_stylebox_override("hover_pressed", hover)
	var focus_box: StyleBoxFlat = _row_box(arcade.disc_600_color, arcade)
	focus_box.border_color = arcade.cream_color
	focus_box.set_border_width_all(arcade.focus_px)
	add_theme_stylebox_override("focus", focus_box)


func _row_box(face: Color, arcade: ArcadeVisualTuning) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = face
	box.set_corner_radius_all(arcade.radius_block_px)
	return box


## Whether this row is an alternate (banded) row; set by ui/menus/OptionsMenu.gd.
func set_banded(banded: bool) -> void:
	_banded = banded
	_apply_row_style()


func _on_input_device_changed(_device: StringName) -> void:
	if not _listening:
		_refresh_glyphs()


## Called once by OptionsMenu right after instancing this row, the same
## "setup() before use" convention ui/debug/TuningPanel.gd's own per-row builders
## follow (there: a resource + property name; here: one action name).
func setup(action: StringName) -> void:
	_action = action
	_action_label.text = _display_name(action)
	_refresh_glyphs()


## Test seam: whether this row is currently armed to capture the next input.
func is_listening() -> bool:
	return _listening


## Test seam: the Control a synthetic `pressed.emit()` (or a real click) targets to start
## listening. The row itself is the Button, so this is the row.
func rebind_button() -> Button:
	return self


## Public refresh seam: OptionsMenu's Reset-to-defaults changes the InputMap under every built
## row, so it calls this on each instead of rebuilding the list.
func refresh() -> void:
	_refresh_glyphs()


## Drops keyboard focus from this row: while focused, Godot's GUI layer treats Space/Enter as
## this Button's accelerator and arrows/Tab as focus navigation, a second path (besides _input()
## below) by which those keys could be swallowed before the row sees them.
func _on_pressed() -> void:
	_listening = true
	_idle_s = 0.0
	_collect_blocked_axes()
	release_focus()
	_apply_row_style()
	_show_listening_glyph()


func _collect_blocked_axes() -> void:
	_blocked_axes.clear()
	for device: int in Input.get_connected_joypads():
		for axis: int in range(JOY_AXIS_MAX):
			if absf(Input.get_joy_axis(device, axis as JoyAxis)) >= OPTIONS_TUNING.rebind_axis_threshold:
				_blocked_axes[axis] = true


## Replaces the glyph row with one placeholder InputGlyph, so the listening state lives in the
## same visual slot the real bindings occupy.
func _show_listening_glyph() -> void:
	_clear_glyphs()
	var prompt: Label = Label.new()
	prompt.name = LISTENING_LABEL_NAME
	prompt.text = LISTENING_TEXT_GAMEPAD if Settings.active_input_device() == Settings.DEVICE_GAMEPAD else LISTENING_TEXT_KEYBOARD
	prompt.theme_type_variation = &"FieldLabel"
	prompt.add_theme_font_size_override("font_size", MenuStyleFactory.arcade_tuning().font_size_button_sm_px)
	prompt.add_theme_color_override("font_color", MenuStyleFactory.arcade_tuning().rim_color)
	prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glyph_row.add_child(prompt)


## Captures the very next real input while listening: InputEventKey, InputEventMouseButton,
## InputEventJoypadButton, or an InputEventJoypadMotion past
## OptionsVisualTuning.rebind_axis_threshold (triggers and stick directions, stored as axis +
## sign; _handle_motion). Pad B binds instead of cancelling.
##
## Captured in Node._input(), which runs before Control GUI dispatch and Node._unhandled_input().
## Afterwards the GUI layer would have consumed a click on the panel's mouse_filter=STOP background and
## Space/Enter/arrows/Tab on the still-focused row (see _on_pressed()'s release_focus()), so a
## listening row would never see them.
##
## ui_cancel cancels the capture instead of binding Escape/gamepad B onto the action. It is caught
## here because _input() reaches every node before OptionsMenu's _unhandled_input() back-out
## handler, so a listening row always sees ui_cancel first.
func _input(event: InputEvent) -> void:
	if not _listening:
		return
	# The idle timer is NOT reset here: stick drift or mouse motion must not postpone the cancel;
	# every event that matters ends listening by capturing or cancelling.
	if event is InputEventJoypadButton:
		# B (ui_cancel's pad button) is a valid binding while listening;
		# the pad player cancels with the idle timeout, Esc or a mouse click.
		if event.is_pressed():
			_capture(event)
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_cancel"):
		_cancel_listening()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadMotion:
		_handle_motion(event as InputEventJoypadMotion)
		return
	if event is InputEventKey or event is InputEventMouseButton:
		if not event.is_pressed() or event.is_echo():
			return
		if event is InputEventMouseButton and Settings.active_input_device() == Settings.DEVICE_GAMEPAD:
			# DECISION: a pad page has nothing to bind a mouse click to,
			# so a click cancels instead of leaving the row armed.
			_cancel_listening()
			get_viewport().set_input_as_handled()
			return
		_capture(event)
		get_viewport().set_input_as_handled()


## Idle timeout for a listening row, so a pad player who armed a row by accident is not stuck
## (B binds rather than cancels).
func _process(delta: float) -> void:
	if not _listening:
		return
	_idle_s += delta
	if _idle_s >= OPTIONS_TUNING.rebind_idle_timeout_s:
		_cancel_listening()


## Binds a trigger or stick direction (axis + sign) once it passes the config threshold. An
## axis that was already past it when listening began (a stick still held from menu
## navigation) is ignored until it has returned below the threshold.
func _handle_motion(motion: InputEventJoypadMotion) -> void:
	var magnitude: float = absf(motion.axis_value)
	var threshold: float = OPTIONS_TUNING.rebind_axis_threshold
	if magnitude < threshold:
		_blocked_axes.erase(motion.axis)
		return
	if _blocked_axes.has(motion.axis):
		return
	var bound: InputEventJoypadMotion = InputEventJoypadMotion.new()
	bound.axis = motion.axis
	bound.axis_value = signf(motion.axis_value)
	_capture(bound)
	get_viewport().set_input_as_handled()


func _capture(event: InputEvent) -> void:
	_listening = false
	_apply_row_style()
	Settings.set_key_override(_action, event)
	_refresh_glyphs()
	_restore_focus()
	rebind_captured.emit(_action, event)


func _cancel_listening() -> void:
	_listening = false
	_apply_row_style()
	_refresh_glyphs()
	_restore_focus()


## _on_pressed() drops focus for the duration of a capture; once the capture ends the row takes it
## back, so keyboard/gamepad navigation continues from the remapped row. Only when nothing else
## has taken focus in the meantime.
func _restore_focus() -> void:
	if is_visible_in_tree() and get_viewport().gui_get_focus_owner() == null:
		grab_focus()


func _clear_glyphs() -> void:
	for child: Node in _glyph_row.get_children():
		_glyph_row.remove_child(child)
		child.queue_free()


## Rebuilds %GlyphRow from only the events of the active device family (Settings
## active_input_device()). On the gamepad page an action without its own pad event shows no glyph,
## a PAD_NOT_APPLICABLE action hides the row, and a PAD_ONLY_ACTIONS action is hidden on the
## mouse/keyboard page. Any other row with no binding for the active family stays visible with an
## empty glyph row, still rebindable. A third glyph shows "+N" instead of a real icon.
func _refresh_glyphs() -> void:
	_clear_glyphs()
	visible = is_available_on_active_device()

	var events: Array[InputEvent] = _events_for_active_device()
	var shown_count: int = mini(events.size(), MAX_GLYPHS)
	InputGlyph.build_for_events(_glyph_row, events, shown_count)

	if events.size() > MAX_GLYPHS:
		var overflow: InputGlyph = INPUT_GLYPH_SCENE.instantiate() as InputGlyph
		_glyph_row.add_child(overflow)
		overflow.set_overflow_count(events.size() - MAX_GLYPHS)


## Whether this row belongs on the page of the player's active device family:
## false for a PAD_NOT_APPLICABLE action while the gamepad page shows, for a
## PAD_ONLY_ACTIONS action while the keyboard/mouse page shows, and for
## the snap rows while snapping is disabled in CameraTuning.
## Computed from Settings (not from `visible`) so ui/menus/OptionsMenu.gd can ask it
## when rebuilding the focus chain without depending on signal order.
func is_available_on_active_device() -> bool:
	if SNAP_ACTIONS.has(_action) and not camera_tuning.snap_enabled:
		return false
	if Settings.active_input_device() != Settings.DEVICE_GAMEPAD:
		return not PAD_ONLY_ACTIONS.has(_action)
	return not PAD_NOT_APPLICABLE.has(_action)


func _events_for_active_device() -> Array[InputEvent]:
	if Settings.active_input_device() == Settings.DEVICE_GAMEPAD:
		return gamepad_events_for(_action)
	return events_of_family(_action, false)


## The gamepad controls the Options page shows for `action`: its own pad events
## (empty when it has none). Public static so tests can assert the resolution
## without building a row.
static func gamepad_events_for(action: StringName) -> Array[InputEvent]:
	return events_of_family(action, true)


static func events_of_family(action: StringName, gamepad: bool) -> Array[InputEvent]:
	return InputGlyph.events_of_family(action, gamepad)


## Friendly label for `action`; falls back to auto-titlecase ("ghost_move_left" -> "Ghost Move
## Left") for anything DISPLAY_NAMES does not cover.
func _display_name(action: StringName) -> String:
	if DISPLAY_NAMES.has(action):
		return DISPLAY_NAMES[action]
	var words: PackedStringArray = String(action).split("_")
	var parts: PackedStringArray = PackedStringArray()
	for word: String in words:
		if word.is_empty():
			continue
		parts.append(word[0].to_upper() + word.substr(1))
	return " ".join(parts)
