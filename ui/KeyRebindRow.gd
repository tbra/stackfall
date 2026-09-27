class_name KeyRebindRow
extends Button
## docs/M6_PLAN.md package C2: one row per rebindable Input Map action, built
## dynamically by ui/OptionsMenu.gd's _build_rebind_rows() (one instance of
## this scene per OptionsMenu.REBINDABLE_ACTIONS entry). Shows the action's
## current binding(s) as InputGlyph icons (InputMap.action_get_events(),
## which already reflects any Settings key override -- Settings.
## _apply_key_overrides() writes straight onto the InputMap, see
## autoload/Settings.gd's own doc) and captures the next InputEventKey/
## InputEventMouseButton/InputEventJoypadButton while "listening".
##
## Bontago-1pi.10 polish pass (owner: "Remove the per-row 'Rebind' buttons.
## The whole row is the focusable/clickable target"): this scene's own root
## is now the Button (extends Button, not HBoxContainer) -- a click or
## Space/Enter anywhere on the row starts listening, exactly like the old
## dedicated RebindButton did, and the shared stackfall_theme.tres focus ring
## still highlights the whole row on gamepad/keyboard focus for free (Button
## already owns that). %Content (an HBoxContainer laid out full-rect inside
## this Button, mouse_filter = IGNORE on every nested container so a click
## anywhere in it falls through to this Button) holds the actual row visuals.

signal rebind_captured(action: StringName, event: InputEvent)

## Owner: "max two glyphs per row, extra bindings hidden behind '+1'".
const MAX_GLYPHS: int = 2

const INPUT_GLYPH_SCENE: PackedScene = preload("res://ui/InputGlyph.tscn")

## Friendly, player-facing action names (owner: "Friendly action names and
## grouping ... human labels"). Deliberately only covers
## OptionsMenu.REBINDABLE_ACTIONS -- anything missing here falls back to
## _display_name()'s old auto-titlecase, so a future rebindable action never
## goes unlabeled just because nobody updated this dictionary yet.
const DISPLAY_NAMES: Dictionary[StringName, String] = {
	&"ghost_place": "Place block",
	&"rotate_yaw_ccw": "Rotate left",
	&"rotate_yaw_cw": "Rotate right",
	&"rotate_pitch_fwd": "Tilt forward",
	&"rotate_pitch_back": "Tilt back",
	&"rotate_roll_left": "Roll left",
	&"rotate_roll_right": "Roll right",
	&"rotation_mode": "Free rotation mode",
	&"rotate_reset": "Reset rotation",
	&"rotate_drag": "Rotate (drag)",
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
	&"pause_menu": "Pause",
}

## Reused only for the row's own subtle hover/pressed highlight -- a calm
## list row, not another coral pill button (ui/theme/MenuStyleFactory.gd's
## own pill/chip styles are for actual buttons; this row keeps the shared
## Theme's default "focus" stylebox untouched so gamepad/keyboard focus still
## reads exactly like every other focusable Control in the project).
@export var tuning: MenuVisualTuning = preload("res://config/menu_visual_tuning.tres")

@onready var _action_label: Label = %ActionLabel
@onready var _glyph_row: HBoxContainer = %GlyphRow

var _action: StringName = &""
var _listening: bool = false


## Bontago-1pi.10 (owner: "default to only showing mouse/keyboard, switch to
## showing only gamepad options on gamepad input"): live-refreshes this row's
## glyphs whenever the player's last-used device changes, without the
## OptionsMenu that built this row needing to rebuild the whole list.
func _ready() -> void:
	%Content.minimum_size_changed.connect(_sync_content_minimum_size)
	_sync_content_minimum_size()
	_apply_row_style()
	pressed.connect(_on_pressed)
	Events.input_device_changed.connect(_on_input_device_changed)


func _sync_content_minimum_size() -> void:
	var needed: Vector2 = %Content.get_combined_minimum_size() + Vector2(28.0, 16.0)
	custom_minimum_size = Vector2(needed.x, maxf(52.0, needed.y))


func _apply_row_style() -> void:
	var empty: StyleBoxEmpty = StyleBoxEmpty.new()
	add_theme_stylebox_override("normal", empty)
	add_theme_stylebox_override("disabled", empty)

	var hover: StyleBoxFlat = StyleBoxFlat.new()
	hover.bg_color = tuning.pill_cream_hover_color
	hover.bg_color.a = 0.35
	hover.set_corner_radius_all(int(tuning.well_corner_radius_px))
	add_theme_stylebox_override("hover", hover)

	var pressed_box: StyleBoxFlat = StyleBoxFlat.new()
	pressed_box.bg_color = tuning.pill_coral_color
	pressed_box.bg_color.a = 0.30
	pressed_box.set_corner_radius_all(int(tuning.well_corner_radius_px))
	add_theme_stylebox_override("pressed", pressed_box)
	add_theme_stylebox_override("hover_pressed", pressed_box)


func _on_input_device_changed(_device: StringName) -> void:
	if not _listening:
		_refresh_glyphs()


## Called once by OptionsMenu right after instancing this row, the same
## "setup() before use" convention ui/TuningPanel.gd's own per-row builders
## follow (there: a resource + property name; here: one action name).
func setup(action: StringName) -> void:
	_action = action
	_action_label.text = _display_name(action)
	_refresh_glyphs()


func action_name() -> StringName:
	return _action


## Test seam (tests/unit/test_options_menu.gd): whether this row is currently
## armed to capture the next input.
func is_listening() -> bool:
	return _listening


## Test seam: the Control a synthetic `pressed.emit()` (or a real click)
## should target to start listening. The row itself IS the Button now (no
## separate child RebindButton) -- kept under its old name so
## tests/unit/test_key_rebind_row.gd's own real-Viewport click tests keep
## working unchanged; it still targets exactly the clickable/focusable
## Control this row is built from.
func rebind_button() -> Button:
	return self


## Public refresh seam: ui/OptionsMenu.gd's own Reset-to-defaults action
## changes the InputMap out from under every already-built row at once, so
## it calls this on each one afterward rather than rebuilding the whole list.
func refresh() -> void:
	_refresh_glyphs()


## Drops keyboard focus from this row (Bontago-8or.19, owner playtest
## feedback/playtest.md: "no option to actually remap the ones that are
## mapped") -- while this row stays focused, Godot's own GUI layer treats
## Space/Enter as *this Button's* activate accelerator and arrows/Tab as
## focus navigation, so a still-focused row is a second, independent path
## (besides _input() below) by which those keys could be swallowed before
## this row ever sees them.
func _on_pressed() -> void:
	_listening = true
	release_focus()
	_show_listening_glyph()


## Owner: "activating it enters 'press a key/button…' state shown in the
## glyph slot" -- replaces the glyph row with one placeholder InputGlyph
## rather than a separate text label, so the listening state lives in
## exactly the same visual slot the real bindings occupy.
func _show_listening_glyph() -> void:
	_clear_glyphs()
	var glyph: InputGlyph = INPUT_GLYPH_SCENE.instantiate() as InputGlyph
	_glyph_row.add_child(glyph)
	glyph.set_listening()


## Captures the very next real input while listening -- InputEventKey,
## InputEventMouseButton or InputEventJoypadButton (docs/M6_PLAN.md package
## C2's own list; joypad *motion*/axis is left out on purpose -- a rebind is a
## discrete press, not an analog drift, the same digital-vs-analog split
## tools/bootstrap_project.gd's own action bindings already follow).
##
## Captured in Node._input() rather than Node._unhandled_input() (Bontago-
## 8or.19, owner playtest feedback/playtest.md: "no option to actually remap
## the ones that are mapped"). Godot's own input pipeline runs, in order,
## Node._input() -> Control GUI dispatch (focus navigation, button
## accelerators, mouse_filter consumption) -> Node._unhandled_input(); as
## _unhandled_input(), this method only ever saw whatever the GUI layer left
## over, which for a full-screen options panel is close to nothing: a mouse
## click anywhere on the panel's own mouse_filter=STOP background was
## consumed by the GUI layer before it could reach here, and Space/Enter/
## arrows/Tab were consumed by the still-focused row's own GUI
## accelerator/focus-navigation handling instead (see _on_pressed()'s
## release_focus() call above, which closes that second path). Moving the
## capture to _input() runs it *before* any of that GUI processing, so a
## listening row now sees the raw event first regardless of what sits under
## the pointer or which control has focus.
##
## ui_cancel cancels the capture instead of binding Escape/gamepad B onto the
## action -- caught here, before OptionsMenu's own _unhandled_input() back-out
## handler, because _input() is delivered to every node in the tree (deepest
## first) before Godot even starts the GUI/_unhandled_input phases that
## OptionsMenu's own handler relies on, so a listening row always sees
## ui_cancel first.
func _input(event: InputEvent) -> void:
	if not _listening:
		return
	if event.is_action_pressed(&"ui_cancel"):
		_cancel_listening()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		if not event.is_pressed() or event.is_echo():
			return
		_capture(event)
		get_viewport().set_input_as_handled()


func _capture(event: InputEvent) -> void:
	_listening = false
	Settings.set_key_override(_action, event)
	_refresh_glyphs()
	rebind_captured.emit(_action, event)


func _cancel_listening() -> void:
	_listening = false
	_refresh_glyphs()


func _clear_glyphs() -> void:
	for child: Node in _glyph_row.get_children():
		_glyph_row.remove_child(child)
		child.queue_free()


## Bontago-1pi.10: rebuilds %GlyphRow from only the events of the active
## device family (autoload/Settings.gd's own active_input_device()) -- the
## "only showing mouse/keyboard, switch to showing only gamepad" behavior the
## owner asked for. A row with no binding at all for the active family (the
## K+M-only rows tools/bootstrap_project.gd never gave a gamepad binding,
## e.g. rotate_drag/lock_vertical/camera_mode/camera_orbit -- see
## ui/OptionsMenu.gd's own REBINDABLE_ACTIONS doc) is left visible with an
## empty glyph row -- still a real, rebindable row for that device.
## Owner: "max two glyphs per row, extra bindings hidden behind '+1'" -- a
## third InputGlyph shows "+N" instead of a third real icon.
func _refresh_glyphs() -> void:
	_clear_glyphs()

	var events: Array[InputEvent] = _events_for_active_device()
	var shown_count: int = mini(events.size(), MAX_GLYPHS)
	for i: int in range(shown_count):
		var glyph: InputGlyph = INPUT_GLYPH_SCENE.instantiate() as InputGlyph
		_glyph_row.add_child(glyph)
		glyph.set_event(events[i])

	if events.size() > MAX_GLYPHS:
		var overflow: InputGlyph = INPUT_GLYPH_SCENE.instantiate() as InputGlyph
		_glyph_row.add_child(overflow)
		overflow.set_overflow_count(events.size() - MAX_GLYPHS)


func _events_for_active_device() -> Array[InputEvent]:
	var want_gamepad: bool = Settings.active_input_device() == Settings.DEVICE_GAMEPAD
	var matched: Array[InputEvent] = []
	if not InputMap.has_action(_action):
		return matched
	for event: InputEvent in InputMap.action_get_events(_action):
		var is_gamepad: bool = event is InputEventJoypadButton or event is InputEventJoypadMotion
		if is_gamepad == want_gamepad:
			matched.append(event)
	return matched


## Friendly label for `action` (owner: "Friendly action names ... human
## labels") -- falls back to the old cosmetic auto-titlecase
## ("ghost_move_left" -> "Ghost Move Left") for anything DISPLAY_NAMES
## doesn't cover, so a fresh action added to REBINDABLE_ACTIONS never shows
## up blank just because nobody updated DISPLAY_NAMES yet.
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
