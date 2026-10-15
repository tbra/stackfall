extends GutTest
## Bontago-1pi.41: the Options gamepad Controls page must never show a blank
## row. rotate_yaw_ccw/cw and lock_vertical (and a few more) carry only
## keyboard/mouse events in the Input Map because the pad performs the same job
## through other actions (tests/unit/main/test_project_setup.gd DEVICE_EXCEPTIONS,
## spec 2.5). ui/menus/KeyRebindRow.gd's PAD_ONLY_ACTIONS / PAD_NOT_APPLICABLE tables
## say which, so this file checks (1) every pad row resolves to a real pad
## event that really drives its action, (2) every listed gameplay row has a
## glyph or is hidden on the pad page, and (3) no two gameplay actions share a
## pad event unless that overlap is intentional and documented.

const KEY_REBIND_ROW_SCENE: PackedScene = preload("res://ui/menus/KeyRebindRow.tscn")

## Gameplay actions that are not Options rows but still own pad events (pad-only
## gesture actions, throw, gift slot, stick axes). Debug/sandbox/menu/lobby
## actions are deliberately outside this set: they share buttons with gameplay
## on purpose and are only read in their own context (tools/bootstrap_project.gd).
const EXTRA_GAMEPLAY_ACTIONS: Array[StringName] = [
	&"rotate_snap", &"rotate_drag_pad", &"camera_zoom_modifier", &"use_gift_slot",
	&"ghost_move_left", &"ghost_move_right", &"ghost_move_forward", &"ghost_move_back",
	&"camera_look_left", &"camera_look_right", &"camera_look_up", &"camera_look_down",
]

## Each entry is one physical pad event deliberately bound to several gameplay
## actions, names sorted and joined with ",".
## - X: use_gift_slot vs camera_snap_goal (Bontago-1pi.18.12); snap is inert while
##   CameraTuning.snap_enabled is false, so X is free in a match.
## - Left stick axes: ghost_move_* vs camera_pan_* (camera_modifier held pans
##   instead of moving; PlayerController zeroes the stick while it is held).
const INTENTIONAL_SHARES: Array = [
	"camera_snap_goal,use_gift_slot",
	"camera_reset,camera_snap_home",
	"camera_pan_left,ghost_move_left",
	"camera_pan_right,ghost_move_right",
	"camera_pan_forward,ghost_move_forward",
	"camera_pan_back,ghost_move_back",
]


func after_each() -> void:
	Settings.set_active_input_device_for_test(Settings.DEFAULT_ACTIVE_DEVICE)


# --- Resolution: the exact controls the pad page shows ---------------------------

func test_rotate_snap_resolves_to_the_b_button() -> void:
	var events: Array[InputEvent] = KeyRebindRow.gamepad_events_for(&"rotate_snap")
	assert_eq(events.size(), 1)
	assert_true(events[0] is InputEventJoypadButton)
	assert_eq((events[0] as InputEventJoypadButton).button_index, JOY_BUTTON_B)


func test_rotate_drag_pad_resolves_to_the_right_trigger_free_rotation_axis() -> void:
	var events: Array[InputEvent] = KeyRebindRow.gamepad_events_for(&"rotate_drag_pad")
	assert_eq(events.size(), 1)
	assert_true(events[0] is InputEventJoypadMotion)
	assert_eq((events[0] as InputEventJoypadMotion).axis, JOY_AXIS_TRIGGER_RIGHT)


## Bontago-1pi.159.22 (owner 2026-10-11): camera rows that make no sense to remap
## are absent on the pad page, still listed on the keyboard page; snap rows are
## hidden on both pages while CameraTuning.snap_enabled is false.
func test_pad_page_hides_fixed_camera_rows_and_snap_rows_are_hidden_everywhere() -> void:
	var hidden_on_pad: Array[StringName] = [
		&"camera_mode", &"camera_modifier", &"camera_pan_left", &"camera_pan_right",
		&"camera_pan_forward", &"camera_pan_back", &"camera_zoom_in", &"camera_zoom_out",
	]
	for action: StringName in hidden_on_pad:
		var row: KeyRebindRow = _make_row(action)
		assert_true(row.is_available_on_active_device(), "%s stays on the keyboard page" % action)
		Settings.set_active_input_device_for_test(Settings.DEVICE_GAMEPAD)
		assert_false(row.is_available_on_active_device(), "%s hidden on the pad page" % action)
		assert_false(row.visible)
		Settings.set_active_input_device_for_test(Settings.DEVICE_KEYBOARD_MOUSE)
	Settings.set_active_input_device_for_test(Settings.DEVICE_GAMEPAD)
	assert_false(_make_row(&"camera_orbit").is_available_on_active_device(), "Orbit camera is keyboard/mouse only (Bontago-1pi.159.63)")

	for action: StringName in KeyRebindRow.SNAP_ACTIONS:
		var row: KeyRebindRow = _make_row(action)
		var tuning: CameraTuning = row.camera_tuning.duplicate() as CameraTuning
		row.camera_tuning = tuning
		tuning.snap_enabled = false
		assert_false(row.is_available_on_active_device(), "%s hidden on the pad page" % action)
		Settings.set_active_input_device_for_test(Settings.DEVICE_KEYBOARD_MOUSE)
		assert_false(row.is_available_on_active_device(), "%s hidden on the keyboard page" % action)
		tuning.snap_enabled = true
		assert_true(row.is_available_on_active_device(), "%s returns when snap is re-enabled" % action)
		Settings.set_active_input_device_for_test(Settings.DEVICE_GAMEPAD)


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
			assert_true(KeyRebindRow.PAD_NOT_APPLICABLE.has(action) or KeyRebindRow.SNAP_ACTIONS.has(action), "%s is hidden on the gamepad page without being declared PAD_NOT_APPLICABLE" % action)


## The glyphs are only honest if pressing those physical inputs really triggers the
## action the row stands for.
func test_synthetic_pad_events_drive_the_pad_only_actions() -> void:
	for action: StringName in KeyRebindRow.PAD_ONLY_ACTIONS:
		for event: InputEvent in KeyRebindRow.gamepad_events_for(action):
			_push(event, true)
			var driven: bool = Input.is_action_pressed(action)
			_push(event, false)
			assert_true(driven, "%s: pad event %s did not press the action" % [action, event.as_text()])
			assert_false(Input.is_action_pressed(action), "%s must be released after the synthetic release" % action)


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
