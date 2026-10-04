extends GutTest
## Bontago-1pi.41: the Options gamepad Controls page must never show a blank
## row. rotate_yaw_ccw/cw and lock_vertical (and a few more) carry only
## keyboard/mouse events in the Input Map because the pad performs the same job
## through other actions (tests/unit/test_project_setup.gd DEVICE_EXCEPTIONS,
## spec 2.5). ui/KeyRebindRow.gd's PAD_STAND_INS / PAD_NOT_APPLICABLE tables
## say which, so this file checks (1) every stand-in resolves to a real pad
## event that really drives its action, (2) every listed gameplay row has a
## glyph or is hidden on the pad page, and (3) no two gameplay actions share a
## pad event unless that overlap is intentional and documented.

const KEY_REBIND_ROW_SCENE: PackedScene = preload("res://ui/KeyRebindRow.tscn")

## Gameplay actions that are not Options rows but still own pad events (pad-only
## gesture actions, throw, gift slot, stick axes). Debug/sandbox/menu/lobby
## actions are deliberately outside this set: they share buttons with gameplay
## on purpose and are only read in their own context (tools/bootstrap_project.gd).
const EXTRA_GAMEPLAY_ACTIONS: Array[StringName] = [
	&"rotate_snap", &"rotate_drag_pad", &"camera_zoom_modifier", &"throw_aim", &"use_gift_slot",
	&"ghost_move_left", &"ghost_move_right", &"ghost_move_forward", &"ghost_move_back",
	&"camera_look_left", &"camera_look_right", &"camera_look_up", &"camera_look_down",
]

## Each entry is one physical pad event deliberately bound to several gameplay
## actions, names sorted and joined with ",".
## - Left stick axes: ghost_move_* vs camera_pan_* (camera_modifier held pans
##   instead of moving; PlayerController zeroes the stick while it is held).
## - Left trigger: throw_aim vs camera_zoom_modifier (PlayerController decides by
##   whether the held piece is a throwable special).
const INTENTIONAL_SHARES: Array = [
	"camera_pan_left,ghost_move_left",
	"camera_pan_right,ghost_move_right",
	"camera_pan_forward,ghost_move_forward",
	"camera_pan_back,ghost_move_back",
	"camera_zoom_modifier,throw_aim",
]


func after_each() -> void:
	Settings.set_active_input_device_for_test(Settings.DEFAULT_ACTIVE_DEVICE)


# --- Resolution: the exact controls the pad page shows ---------------------------

func test_rotate_yaw_cw_resolves_to_the_b_snap_button() -> void:
	var events: Array[InputEvent] = KeyRebindRow.gamepad_events_for(&"rotate_yaw_cw")
	assert_eq(events.size(), 1)
	assert_true(events[0] is InputEventJoypadButton)
	assert_eq((events[0] as InputEventJoypadButton).button_index, JOY_BUTTON_B)


func test_rotate_yaw_ccw_resolves_to_the_right_trigger_free_rotation_axis() -> void:
	var events: Array[InputEvent] = KeyRebindRow.gamepad_events_for(&"rotate_yaw_ccw")
	assert_eq(events.size(), 1)
	assert_true(events[0] is InputEventJoypadMotion)
	assert_eq((events[0] as InputEventJoypadMotion).axis, JOY_AXIS_TRIGGER_RIGHT)


func test_lock_vertical_has_no_pad_function_and_is_hidden_not_blank() -> void:
	assert_true(KeyRebindRow.PAD_NOT_APPLICABLE.has(&"lock_vertical"))
	assert_eq(KeyRebindRow.gamepad_events_for(&"lock_vertical").size(), 0, "no pad event exists to show for lock_vertical")

	var row: KeyRebindRow = _make_row(&"lock_vertical")
	assert_true(row.visible, "keyboard/mouse page keeps the Lock height row")
	assert_true(row.is_available_on_active_device())
	Settings.set_active_input_device_for_test(Settings.DEVICE_GAMEPAD)
	assert_false(row.visible, "gamepad page hides the row instead of showing it blank")
	assert_false(row.is_available_on_active_device())
	Settings.set_active_input_device_for_test(Settings.DEVICE_KEYBOARD_MOUSE)
	assert_true(row.visible, "switching back to keyboard/mouse restores the row")


## A player who rebinds Rotate right on the pad page adds a real pad event to
## rotate_yaw_cw itself (KeyRebindRow's capture path is unchanged); the row must
## then show that binding, not the stand-in. The event is removed again so the
## real Input Map is left as bootstrap generated it.
func test_an_actions_own_pad_binding_wins_over_its_stand_in() -> void:
	var own: InputEventJoypadButton = InputEventJoypadButton.new()
	own.button_index = JOY_BUTTON_MISC1
	InputMap.action_add_event(&"rotate_yaw_cw", own)
	var events: Array[InputEvent] = KeyRebindRow.gamepad_events_for(&"rotate_yaw_cw")
	InputMap.action_erase_event(&"rotate_yaw_cw", own)
	assert_eq(events.size(), 1)
	assert_eq((events[0] as InputEventJoypadButton).button_index, JOY_BUTTON_MISC1)
	assert_eq(KeyRebindRow.gamepad_events_for(&"rotate_yaw_cw").size(), 1, "stand-in returns once the own event is gone")


func test_every_stand_in_source_exists_and_is_bound_on_the_pad() -> void:
	for action: StringName in KeyRebindRow.PAD_STAND_INS.keys():
		var sources: Array = KeyRebindRow.PAD_STAND_INS[action]
		assert_gt(sources.size(), 0, "%s needs at least one stand-in source" % action)
		for source: StringName in sources:
			assert_true(InputMap.has_action(source), "%s stand-in source %s must be a real Input Map action" % [action, source])
			assert_gt(
				KeyRebindRow.gamepad_events_for(source).size(), 0,
				"%s stand-in source %s must have a gamepad event" % [action, source]
			)
		assert_eq(
			KeyRebindRow.gamepad_events_for(action).size(), sources.size(),
			"%s must resolve one glyph event per stand-in source" % action
		)


## Every Options row either shows at least one pad glyph on the gamepad page or
## is hidden there -- the owner-reported "blank row" can never come back.
func test_every_rebindable_action_shows_a_pad_glyph_or_is_hidden_on_the_pad_page() -> void:
	Settings.set_active_input_device_for_test(Settings.DEVICE_GAMEPAD)
	for action: StringName in OptionsMenu.REBINDABLE_ACTIONS:
		var row: KeyRebindRow = _make_row(action)
		var glyph_row: HBoxContainer = row.get_node("%GlyphRow") as HBoxContainer
		if row.visible:
			assert_gt(glyph_row.get_child_count(), 0, "%s shows a blank row on the gamepad page" % action)
			assert_gt(KeyRebindRow.gamepad_events_for(action).size(), 0, "%s has no pad control to show" % action)
		else:
			assert_true(KeyRebindRow.PAD_NOT_APPLICABLE.has(action), "%s is hidden on the gamepad page without being declared PAD_NOT_APPLICABLE" % action)


func test_rows_render_the_stand_in_glyphs() -> void:
	Settings.set_active_input_device_for_test(Settings.DEVICE_GAMEPAD)
	assert_eq(_glyph_labels(_make_row(&"rotate_yaw_cw")), ["B"])
	assert_eq(_glyph_labels(_make_row(&"rotate_yaw_ccw")), ["RT"])
	assert_eq(_glyph_labels(_make_row(&"rotate_drag")), ["B", "RT"])
	assert_eq(_glyph_labels(_make_row(&"camera_orbit")), ["R Stick right"])
	assert_eq(_glyph_labels(_make_row(&"camera_zoom_in")), ["LT", "L Stick up"])


func test_keyboard_page_is_unchanged_by_the_stand_ins() -> void:
	var cw: KeyRebindRow = _make_row(&"rotate_yaw_cw")
	assert_eq(_glyph_labels(cw), ["S"], "keyboard/mouse page still shows only the real S binding")


# --- Synthetic input drives the stand-in actions ----------------------------------

## The stand-in glyphs are only honest if pressing those physical inputs really
## triggers the action they stand in for. Pushes each resolved event through
## Input.parse_input_event() and checks the source action reacts, then releases.
func test_synthetic_pad_events_drive_every_stand_in_source_action() -> void:
	for action: StringName in KeyRebindRow.PAD_STAND_INS.keys():
		var sources: Array = KeyRebindRow.PAD_STAND_INS[action]
		for event: InputEvent in KeyRebindRow.gamepad_events_for(action):
			_push(event, true)
			var driven: bool = false
			for source: StringName in sources:
				if Input.is_action_pressed(source):
					driven = true
			_push(event, false)
			assert_true(driven, "%s: pad event %s did not press any of its stand-in actions %s" % [action, event.as_text(), sources])
			for source: StringName in sources:
				assert_false(Input.is_action_pressed(source), "%s must be released after the synthetic release" % source)


# --- No unintended pad-event collisions among gameplay actions --------------------

func test_no_two_gameplay_actions_share_a_pad_event_unintentionally() -> void:
	var gameplay: Array[StringName] = []
	for action: StringName in OptionsMenu.REBINDABLE_ACTIONS:
		gameplay.append(action)
	for action: StringName in EXTRA_GAMEPLAY_ACTIONS:
		if not gameplay.has(action):
			gameplay.append(action)

	var by_event: Dictionary[String, Array] = {}
	for action: StringName in gameplay:
		assert_true(InputMap.has_action(action), "%s must exist in the Input Map" % action)
		for event: InputEvent in KeyRebindRow.events_of_family(action, true):
			var key: String = _pad_event_key(event)
			var users: Array = by_event.get(key, [])
			if not users.has(String(action)):
				users.append(String(action))
			by_event[key] = users

	assert_gt(by_event.size(), 0, "expected gameplay actions to own pad events")
	for key: String in by_event.keys():
		var users: Array = by_event[key]
		if users.size() < 2:
			continue
		users.sort()
		var joined: String = ",".join(PackedStringArray(users))
		assert_true(INTENTIONAL_SHARES.has(joined), "pad event %s is shared by gameplay actions [%s] without being a documented intentional overlap" % [key, joined])


# --- Helpers ---------------------------------------------------------------------------

func _make_row(action: StringName) -> KeyRebindRow:
	var row: KeyRebindRow = autofree(KEY_REBIND_ROW_SCENE.instantiate())
	add_child_autofree(row)
	row.setup(action)
	return row


func _glyph_labels(row: KeyRebindRow) -> Array[String]:
	var labels: Array[String] = []
	for child: Node in (row.get_node("%GlyphRow") as HBoxContainer).get_children():
		labels.append((child as InputGlyph).label_text())
	return labels


## Stable identity of one physical pad input: a button index, or an axis plus
## the sign of the deflection that triggers the action.
func _pad_event_key(event: InputEvent) -> String:
	if event is InputEventJoypadButton:
		return "button:%d" % (event as InputEventJoypadButton).button_index
	var motion: InputEventJoypadMotion = event as InputEventJoypadMotion
	return "axis:%d:%s" % [motion.axis, "+" if motion.axis_value > 0.0 else "-"]


func _push(event: InputEvent, pressed: bool) -> void:
	var synthetic: InputEvent = event.duplicate() as InputEvent
	synthetic.device = -1
	if synthetic is InputEventJoypadButton:
		(synthetic as InputEventJoypadButton).pressed = pressed
	elif synthetic is InputEventJoypadMotion:
		var motion: InputEventJoypadMotion = synthetic as InputEventJoypadMotion
		motion.axis_value = (event as InputEventJoypadMotion).axis_value if pressed else 0.0
	Input.parse_input_event(synthetic)
	Input.flush_buffered_events()
