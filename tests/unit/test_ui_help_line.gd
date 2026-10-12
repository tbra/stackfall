extends GutTest
## Bontago-1pi.159.35: UiHelpLine shows the focused / hovered option's explanation (text from
## config/option_help_table.tres), for keyboard, pad and mouse, and stays empty for untagged rows.

const OPTIONS_MENU_SCENE: PackedScene = preload("res://ui/OptionsMenu.tscn")
const LOBBY_SCENE: PackedScene = preload("res://ui/Lobby.tscn")
const SETTINGS_SCRIPT: GDScript = preload("res://autoload/Settings.gd")
const KEY_A: String = "alpha"
const KEY_B: String = "beta"
const SENTENCE_A: String = "Alpha explains itself."
const SENTENCE_B: String = "Beta explains itself."
const LONG_HELP_FRAMES: int = 3

var _root: Control = null
var _line: UiHelpLine = null
var _a: Button = null
var _b: Button = null
var _plain: Button = null
var _outside: Button = null
var _cfg_path: String = ""


func before_each() -> void:
	var table: OptionHelpTable = OptionHelpTable.new()
	table.entries = {KEY_A: SENTENCE_A, KEY_B: SENTENCE_B}
	_root = Control.new()
	add_child_autofree(_root)
	var column: VBoxContainer = VBoxContainer.new()
	_root.add_child(column)
	_a = _button(column, KEY_A)
	_b = _button(column, KEY_B)
	_plain = _button(column, "")
	_outside = Button.new()
	_root.add_child(_outside)
	_line = UiHelpLine.new()
	_line.table = table
	_root.add_child(_line)
	_line.bind(column)
	_a.focus_neighbor_bottom = _a.get_path_to(_b)
	_b.focus_neighbor_top = _b.get_path_to(_a)


func _button(parent: Control, key: String) -> Button:
	var button: Button = Button.new()
	button.text = key
	parent.add_child(button)
	if not key.is_empty():
		UiHelpLine.tag(button, key)
	return button


func test_focus_shows_the_focused_options_text() -> void:
	_a.grab_focus()
	_line.refresh()
	assert_eq(_line.label.text, SENTENCE_A)
	_b.grab_focus()
	_line.refresh()
	assert_eq(_line.label.text, SENTENCE_B)


func test_hover_wins_over_focus_and_focus_returns_when_the_mouse_leaves() -> void:
	_a.grab_focus()
	var hovered: Array[Control] = [_b]
	_line.hover_source = func() -> Control: return hovered[0]
	_line.refresh()
	assert_eq(_line.label.text, SENTENCE_B, "the hovered row is explained")
	hovered[0] = null
	_line.refresh()
	assert_eq(_line.label.text, SENTENCE_A, "back to the focused row")


func test_gamepad_dpad_moves_the_line_with_focus() -> void:
	_a.grab_focus()
	_line.refresh()
	var press: InputEventJoypadButton = InputEventJoypadButton.new()
	press.button_index = JOY_BUTTON_DPAD_DOWN
	press.pressed = true
	Input.parse_input_event(press)
	await wait_frames(LONG_HELP_FRAMES)
	press = press.duplicate() as InputEventJoypadButton
	press.pressed = false
	Input.parse_input_event(press)
	await wait_frames(LONG_HELP_FRAMES)
	assert_eq(get_viewport().gui_get_focus_owner(), _b, "the pad moved focus")
	assert_eq(_line.label.text, SENTENCE_B, "the line follows pad focus on its own")


func test_a_row_without_text_leaves_the_line_empty() -> void:
	_a.grab_focus()
	_line.refresh()
	_plain.grab_focus()
	_line.refresh()
	assert_eq(_line.label.text, "")


func test_controls_outside_the_scope_are_ignored() -> void:
	UiHelpLine.tag(_outside, KEY_A)
	_outside.grab_focus()
	_line.refresh()
	assert_eq(_line.label.text, "")


func test_a_tagged_ancestor_explains_its_inner_controls() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	_a.get_parent().add_child(row)
	UiHelpLine.tag(row, KEY_B)
	var inner: Button = Button.new()
	row.add_child(inner)
	inner.grab_focus()
	_line.refresh()
	assert_eq(_line.label.text, SENTENCE_B)


func test_item_text_follows_the_selected_item() -> void:
	var table: OptionHelpTable = OptionHelpTable.new()
	table.entries = {"row": "Row text.", "row/1": "Item one text."}
	var cycler: UiCycler = UiCycler.new()
	cycler.add_item("zero")
	cycler.add_item("one")
	_a.get_parent().add_child(cycler)
	UiHelpLine.tag(cycler, "row")
	_line.table = table
	cycler.select(0)
	cycler.grab_focus()
	_line.refresh()
	assert_eq(_line.label.text, "Row text.", "an item without its own text falls back to the row text")
	cycler.select(1)
	_line.refresh()
	assert_eq(_line.label.text, "Item one text.")


func test_table_prefers_item_entries_and_reports_missing_keys() -> void:
	var table: OptionHelpTable = OptionHelpTable.new()
	table.entries = {"k": "row", "k/2": "item"}
	assert_eq(table.text_for("k", 2), "item")
	assert_eq(table.text_for("k", 1), "row")
	assert_eq(table.text_for("k"), "row")
	assert_eq(table.text_for("missing", 0), "")
	assert_false(table.has_text("missing"))


func test_the_shipped_table_covers_the_unclear_options() -> void:
	var table: OptionHelpTable = OptionHelpTable.shared()
	for key: String in ["GameModeCol", "HoleCol", "GravityGroup", "DiscSizeCol", "GoalFlagCol", "BlockTimerGroup", "RoundTimerCol",
			"RoundTimerDominationCol", "MatchTimerCol", "GiftsToggleCol", "SpecialFreqGroup", "frame_cap_mode", "render_scale_3d",
			"WindowModeOption", "UiScaleSlider", "AdaptiveQualityCheck", "preset"]:
		assert_ne(table.text_for(key), "", "%s has help text" % key)
	for mode: int in MatchConfig.GAME_MODE_LABELS.size():
		assert_ne(table.text_for("GameModeCol", mode), table.text_for("GameModeCol"), "mode %d has its own sentence" % mode)
	for special: SpecialDef in SpecialDef.load_selectable_specials():
		assert_ne(table.text_for(OptionHelpTable.gift_key(special.id)), "", "gift %s has help text" % special.id)


# --- Lobby -------------------------------------------------------------------

func _make_lobby() -> Lobby:
	var lobby: Lobby = autofree(LOBBY_SCENE.instantiate())
	add_child_autofree(lobby)
	var fake: FakeNet = FakeNet.new()
	fake.is_host_value = true
	fake.is_offline_value = true
	lobby.net_provider = fake
	lobby._update_host_only_state()
	return lobby


func test_lobby_game_mode_focus_explains_the_selected_mode() -> void:
	var lobby: Lobby = _make_lobby()
	var line: UiHelpLine = lobby.get_node("%HelpLine") as UiHelpLine
	var mode: UiCycler = lobby.get_node("%GameModeOption") as UiCycler
	var table: OptionHelpTable = OptionHelpTable.shared()
	mode.select(MatchConfig.GameMode.ELIMINATION)
	mode.grab_focus()
	line.refresh()
	assert_eq(line.label.text, table.text_for("GameModeCol", MatchConfig.GameMode.ELIMINATION))
	mode.select(MatchConfig.GameMode.REACH_THE_SKY)
	line.refresh()
	assert_eq(line.label.text, table.text_for("GameModeCol", MatchConfig.GameMode.REACH_THE_SKY))
	assert_eq(mode.tooltip_text, "", "no duplicate tooltip")


func test_lobby_round_length_row_changes_text_in_domination() -> void:
	var lobby: Lobby = _make_lobby()
	var line: UiHelpLine = lobby.get_node("%HelpLine") as UiHelpLine
	var mode: UiCycler = lobby.get_node("%GameModeOption") as UiCycler
	mode.select(MatchConfig.GameMode.DOMINATION)
	mode.item_selected.emit(MatchConfig.GameMode.DOMINATION)
	var stepper: Control = lobby.get_node("%RoundTimerStepper") as Control
	line.hover_source = func() -> Control: return stepper
	line.refresh()
	assert_eq(line.label.text, OptionHelpTable.shared().text_for(Lobby.ROUND_HELP_KEY_DOMINATION))


func test_lobby_self_explanatory_row_has_no_text() -> void:
	var lobby: Lobby = _make_lobby()
	var line: UiHelpLine = lobby.get_node("%HelpLine") as UiHelpLine
	var weather: Control = lobby.get_node("%WeatherOption") as Control
	get_viewport().gui_release_focus()
	line.hover_source = func() -> Control: return weather
	line.refresh()
	assert_eq(line.label.text, "")


func test_lobby_gift_chip_explains_its_gift() -> void:
	var lobby: Lobby = _make_lobby()
	var line: UiHelpLine = lobby.get_node("%HelpLine") as UiHelpLine
	var chip: UiChipToggle = lobby._special_checkboxes[0]
	line.hover_source = func() -> Control: return chip
	line.refresh()
	assert_eq(line.label.text, OptionHelpTable.shared().text_for(OptionHelpTable.gift_key(lobby._special_ids[0])))


# --- Options -------------------------------------------------------------------

func _make_menu() -> OptionsMenu:
	_cfg_path = OS.get_user_data_dir().path_join("test_ui_help_line_tmp.cfg")
	if FileAccess.file_exists(_cfg_path):
		DirAccess.remove_absolute(_cfg_path)
	var settings: Node = autofree(SETTINGS_SCRIPT.new())
	add_child_autofree(settings)
	settings.set_config_path_for_test(_cfg_path)
	var menu: OptionsMenu = autofree(OPTIONS_MENU_SCENE.instantiate()) as OptionsMenu
	add_child_autofree(menu)
	menu.settings_provider = settings
	return menu


func after_each() -> void:
	if not _cfg_path.is_empty() and FileAccess.file_exists(_cfg_path):
		DirAccess.remove_absolute(_cfg_path)
	_cfg_path = ""


func test_options_game_tab_explains_unclear_rows_only() -> void:
	var menu: OptionsMenu = _make_menu()
	var line: UiHelpLine = menu.get_node("%HelpLine") as UiHelpLine
	var adaptive: Control = menu.get_node("%AdaptiveQualityCheck") as Control
	adaptive.grab_focus()
	line.refresh()
	assert_eq(line.label.text, OptionHelpTable.shared().text_for("AdaptiveQualityCheck"))
	assert_ne(adaptive.tooltip_text, line.label.text, "the sentence is not duplicated as a tooltip")
	var master: Control = menu.get_node("%MasterMuteButton") as Control
	master.grab_focus()
	line.refresh()
	assert_eq(line.label.text, "", "volume rows are self-explanatory")


func test_options_graphics_tab_explains_frame_cap_per_item() -> void:
	var menu: OptionsMenu = _make_menu()
	var line: UiHelpLine = menu.get_node("%HelpLine") as UiHelpLine
	menu._tabs.select(OptionsMenu.TAB_GRAPHICS)
	var page: GraphicsSettingsTab = menu.get_node("%GraphicsPage") as GraphicsSettingsTab
	var cap: UiDropdown = page.control_for(&"frame_cap_mode") as UiDropdown
	var table: OptionHelpTable = OptionHelpTable.shared()
	cap.select(GraphicsPreset.FrameCap.FIXED)
	cap.grab_focus()
	line.refresh()
	assert_eq(line.label.text, table.text_for("frame_cap_mode", GraphicsPreset.FrameCap.FIXED))
	assert_ne(line.label.text, table.text_for("frame_cap_mode"), "the shown item has its own sentence")

