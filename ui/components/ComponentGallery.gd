class_name ComponentGallery
extends Control
## The component gallery (docs/UI_COMPONENTS_PLAN.md section 3.3): every built ui/components/
## component in each state on a disc-800 panel. It is the visual contract for sign-off: capture it
## off-screen at 1280x720 and 1920x1080 and compare with docs/ui_reskin/components.md. C1b / C2 add
## their rows. States that need a pointer (hover, pressed) or focus are previewed by borrowing the
## button's own hover / pressed / focus style, so the picture is the component's real styling.

const STATE_NORMAL: StringName = &"normal"
const STATE_HOVER: StringName = &"hover"
const STATE_PRESSED: StringName = &"pressed"
const STATE_FOCUS: StringName = &"focus"
const STATE_DISABLED: StringName = &"disabled"
const BUTTON_STATES: Array[StringName] = [STATE_NORMAL, STATE_HOVER, STATE_PRESSED, STATE_FOCUS, STATE_DISABLED]
const STATE_LABELS: Dictionary = {
	STATE_NORMAL: "NORMAL", STATE_HOVER: "HOVER", STATE_PRESSED: "PRESSED", STATE_FOCUS: "FOCUS", STATE_DISABLED: "OFF",
}
## The states a toggle / chip can show (no pressed look: the toggled-on block is the pressed one).
const SWITCH_STATES: Array[StringName] = [STATE_NORMAL, STATE_HOVER, STATE_FOCUS, STATE_DISABLED]
const SWITCH_LABELS: Dictionary = {STATE_NORMAL: "NORMAL", STATE_HOVER: "HOVER", STATE_FOCUS: "FOCUS", STATE_DISABLED: "DISABLED"}
const PAGE_INPUTS: int = 2
const PAGE_STRUCTURE: int = 3
const DROPDOWN_CYCLE_ITEMS: PackedStringArray = ["Classic", "Sprint", "Marathon", "Chaos"]
const DROPDOWN_LIST_ITEMS: PackedStringArray = ["Dawn", "Noon", "Dusk", "Night", "Storm", "Aurora", "Fog"]
const DROPDOWN_OPEN_SELECTED: int = 2
const METER_STEPS: int = 10
const METER_MID: int = 6
const METER_PERCENT_PER_CELL: int = 10
const STEPPER_MAX: int = 10
const STEPPER_LOW: int = 3
const STEPPER_MID: int = 5
const STEPPER_FORMATTED: int = 4
const BLOCK_LOOKS: Dictionary = {
	"PRIMARY": UiBlockButton.Look.PRIMARY, "SECONDARY": UiBlockButton.Look.SECONDARY,
	"MINT": UiBlockButton.Look.MINT, "RIM": UiBlockButton.Look.RIM,
}
const BADGES: Array[Dictionary] = [
	{"name": "NEUTRAL", "look": UiStatusBadge.Look.NEUTRAL, "text": "VS BOTS", "live": false, "icon": false},
	{"name": "NEUTRAL LIVE", "look": UiStatusBadge.Look.NEUTRAL, "text": "HOSTING - LAN", "live": true, "icon": false},
	{"name": "READY", "look": UiStatusBadge.Look.READY, "text": "READY", "live": false, "icon": false},
	{"name": "ALL READY (RIM)", "look": UiStatusBadge.Look.ALL_READY, "text": "ALL PLAYERS READY", "live": true, "icon": false},
	{"name": "NOT READY", "look": UiStatusBadge.Look.NOT_READY, "text": "NOT READY", "live": false, "icon": false},
	{"name": "HOST", "look": UiStatusBadge.Look.HOST, "text": "HOST", "live": false, "icon": false},
	{"name": "ICON-ONLY READY", "look": UiStatusBadge.Look.READY, "text": "Ready", "live": false, "icon": true},
	{"name": "ICON-ONLY WAITING", "look": UiStatusBadge.Look.NOT_READY, "text": "Not ready", "live": false, "icon": true},
]

## 0 = buttons + badges, 1 = toggles, chips, steppers and tabs (C1b), 2 = dropdown, field and
## segment meter, 3 = section, panel and title row (C2). One page fits one capture.
@export var page: int = 0


func _ready() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var ground: ColorRect = ColorRect.new()
	ground.color = arcade.disc_900_color
	ground.set_anchors_preset(Control.PRESET_FULL_RECT)
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ground)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, arcade.space_5_px)
	add_child(margin)
	var columns: HBoxContainer = HBoxContainer.new()
	columns.add_theme_constant_override("separation", arcade.space_4_px)
	margin.add_child(columns)
	if page == 0:
		columns.add_child(_panel("BUTTONS", _button_rows()))
		columns.add_child(_panel("BADGES AND ROW CONTRACT", _badge_rows()))
	elif page == PAGE_INPUTS:
		var inputs_left: VBoxContainer = VBoxContainer.new()
		inputs_left.add_child(_panel("DROPDOWN", _dropdown_rows()))
		columns.add_child(inputs_left)
		var inputs_right: VBoxContainer = VBoxContainer.new()
		inputs_right.add_theme_constant_override("separation", arcade.space_4_px)
		inputs_right.add_child(_panel("FIELD", _field_rows()))
		inputs_right.add_child(_panel("SEGMENT METER", _meter_rows()))
		columns.add_child(inputs_right)
	elif page == PAGE_STRUCTURE:
		var structure_left: VBoxContainer = VBoxContainer.new()
		structure_left.add_theme_constant_override("separation", arcade.space_4_px)
		structure_left.add_child(_panel("SECTION", _section_rows()))
		structure_left.add_child(_panel("TITLE ROW", _title_row_rows()))
		columns.add_child(structure_left)
		columns.add_child(_sample_panel())
	else:
		var left: VBoxContainer = VBoxContainer.new()
		left.add_theme_constant_override("separation", arcade.space_4_px)
		left.add_child(_panel("TOGGLE", _toggle_rows()))
		left.add_child(_panel("CHIP TOGGLE", _chip_rows()))
		columns.add_child(left)
		var right: VBoxContainer = VBoxContainer.new()
		right.add_theme_constant_override("separation", arcade.space_4_px)
		right.add_child(_panel("STEPPER", _stepper_rows()))
		right.add_child(_panel("TABS", _tab_rows()))
		columns.add_child(right)


func _panel(title: String, rows: Array[Control]) -> UiPanel:
	var panel: UiPanel = UiPanel.new()
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.heading = title
	for row: Control in rows:
		panel.content.add_child(row)
	return panel


func _button_rows() -> Array[Control]:
	var rows: Array[Control] = []
	for look_name: String in BLOCK_LOOKS:
		var row: UiRow = UiRow.new().setup("BLOCK " + look_name)
		for state: StringName in BUTTON_STATES:
			var button: UiBlockButton = UiBlockButton.new()
			button.variant = BLOCK_LOOKS[look_name] as UiBlockButton.Look
			button.text = STATE_LABELS[state] as String
			row.add_item(button)
			show_state(button, state)
		rows.append(row)
	for tone: UiIconButton.Tone in [UiIconButton.Tone.SECONDARY, UiIconButton.Tone.DANGER]:
		var row: UiRow = UiRow.new().setup("ICON " + ("DANGER (KICK)" if tone == UiIconButton.Tone.DANGER else "SECONDARY"))
		for state: StringName in BUTTON_STATES:
			var icon_button: UiIconButton = UiIconButton.new()
			icon_button.tone = tone
			icon_button.tooltip_text = "Remove"
			row.add_item(icon_button)
			show_state(icon_button, state)
		rows.append(row)
	return rows


func _badge_rows() -> Array[Control]:
	var rows: Array[Control] = []
	for entry: Dictionary in BADGES:
		var badge: UiStatusBadge = UiStatusBadge.new()
		badge.text = entry["text"] as String
		badge.variant = entry["look"] as UiStatusBadge.Look
		badge.live = entry["live"] as bool
		badge.icon_only = entry["icon"] as bool
		rows.append(UiRow.new().setup(entry["name"] as String, badge))
	# The row-height contract on show: a button, an icon button and a badge side by side.
	var contract: UiRow = UiRow.new().setup("ROW CONTRACT")
	var add_bot: UiBlockButton = UiBlockButton.new()
	add_bot.text = "ADD BOT"
	contract.add_item(add_bot)
	contract.add_item(UiIconButton.new())
	var tag: UiStatusBadge = UiStatusBadge.new()
	tag.text = "READY"
	tag.variant = UiStatusBadge.Look.READY
	contract.add_item(tag)
	rows.append(contract)
	return rows


func _toggle_rows() -> Array[Control]:
	var rows: Array[Control] = []
	for state: StringName in SWITCH_STATES:
		var row: UiRow = UiRow.new().setup(SWITCH_LABELS[state] as String)
		for on: bool in [false, true]:
			var toggle: UiToggle = UiToggle.new()
			toggle.caption = "Sudden death"
			row.add_item(toggle)
			toggle.set_on_silent(on)
			match state:
				STATE_HOVER:
					toggle.preview_hover = true
				STATE_FOCUS:
					show_state(toggle, STATE_FOCUS)
				STATE_DISABLED:
					toggle.disabled = true
		rows.append(row)
	return rows


func _chip_rows() -> Array[Control]:
	var rows: Array[Control] = []
	for state: StringName in SWITCH_STATES:
		var row: UiRow = UiRow.new().setup(SWITCH_LABELS[state] as String)
		for on: bool in [false, true]:
			var chip: UiChipToggle = UiChipToggle.new()
			chip.label = "Black hole"
			row.add_item(chip)
			chip.set_on_silent(on)
			match state:
				STATE_HOVER:
					chip.add_theme_stylebox_override("pressed" if on else "normal", chip.get_theme_stylebox("hover_pressed" if on else "hover"))
				STATE_FOCUS:
					show_state(chip, STATE_FOCUS)
				STATE_DISABLED:
					chip.set_available(false, "Switched off for this match")
		rows.append(row)
	return rows


func _stepper_rows() -> Array[Control]:
	var rows: Array[Control] = []
	var cases: Array[Dictionary] = [
		{"name": "NORMAL", "value": STEPPER_LOW}, {"name": "AT MIN", "value": 0}, {"name": "AT MAX", "value": STEPPER_MAX},
		{"name": "FOCUS", "value": STEPPER_MID}, {"name": "DISABLED", "value": STEPPER_MID}, {"name": "FORMATTED", "value": STEPPER_MID},
	]
	for entry: Dictionary in cases:
		var stepper: UiStepper = UiStepper.new()
		stepper.min_value = 0
		stepper.max_value = STEPPER_MAX
		stepper.value = entry["value"] as int
		match entry["name"] as String:
			"FOCUS":
				stepper.preview_focus = true
			"DISABLED":
				stepper.disabled = true
			"FORMATTED":
				stepper.formatter = func(v: int) -> String: return "%d:00" % v
				stepper.value = STEPPER_FORMATTED
		rows.append(UiRow.new().setup(entry["name"] as String, stepper))
	return rows


func _tab_rows() -> Array[Control]:
	var rows: Array[Control] = []
	var top: UiTabs = UiTabs.new()
	for tab_name: String in ["game", "graphics", "controls", "mods"]:
		top.add_tab(StringName(tab_name), tab_name)
	rows.append(UiRow.new().setup("TOP TABS", top))
	show_state(top.get_tab(&"graphics"), STATE_HOVER)
	show_state(top.get_tab(&"controls"), STATE_FOCUS)
	top.set_tab_disabled(&"mods", true)
	var side: UiTabs = UiTabs.new()
	side.orientation = UiTabs.Orientation.VERTICAL
	for tab_name: String in ["settings", "controls"]:
		side.add_tab(StringName(tab_name), tab_name)
	rows.append(UiRow.new().setup("SIDE TABS", side))
	return rows


func _dropdown_rows() -> Array[Control]:
	var rows: Array[Control] = []
	for state: StringName in BUTTON_STATES:
		var dropdown: UiDropdown = _sample_dropdown(UiDropdown.Mode.CYCLE, DROPDOWN_CYCLE_ITEMS)
		rows.append(UiRow.new().setup(STATE_LABELS[state] as String, dropdown))
		show_state(dropdown, state)
	var long_list: UiDropdown = _sample_dropdown(UiDropdown.Mode.AUTO, DROPDOWN_LIST_ITEMS)
	rows.append(UiRow.new().setup("LONG LIST (AUTO)", long_list))
	var open_list: UiDropdown = _sample_dropdown(UiDropdown.Mode.POPUP, DROPDOWN_LIST_ITEMS)
	open_list.select(DROPDOWN_OPEN_SELECTED)
	rows.append(UiRow.new().setup("OPEN", open_list))
	open_list.open.call_deferred(false)
	return rows


func _sample_dropdown(mode: UiDropdown.Mode, items: PackedStringArray) -> UiDropdown:
	var dropdown: UiDropdown = UiDropdown.new()
	dropdown.mode = mode
	for item: String in items:
		dropdown.add_item(item)
	return dropdown


func _field_rows() -> Array[Control]:
	var rows: Array[Control] = []
	var empty: UiField = UiField.new()
	empty.placeholder = "Your name"
	rows.append(UiRow.new().setup("PLACEHOLDER", empty))
	var filled: UiField = UiField.new()
	filled.text = "Tester"
	rows.append(UiRow.new().setup("FILLED", filled))
	var focused: UiField = UiField.new()
	focused.text = "192.168.0.7"
	rows.append(UiRow.new().setup("FOCUS", focused))
	show_field_focus(focused)
	var locked: UiField = UiField.new()
	locked.text = "ABCD-1234"
	locked.editable = false
	rows.append(UiRow.new().setup("READ-ONLY", locked))
	var captioned: UiField = UiField.new()
	captioned.label_text = "DIRECT IP"
	captioned.placeholder = "0.0.0.0:7777"
	rows.append(UiRow.new().setup("WITH LABEL", captioned))
	return rows


func _meter_rows() -> Array[Control]:
	var rows: Array[Control] = []
	var cases: Array[Dictionary] = [
		{"name": "EMPTY", "value": 0}, {"name": "MID", "value": METER_MID}, {"name": "FULL", "value": METER_STEPS},
		{"name": "FOCUS", "value": METER_MID}, {"name": "MUTED", "value": METER_MID},
	]
	for entry: Dictionary in cases:
		var meter: UiSegmentMeter = _sample_meter(entry["value"] as int)
		match entry["name"] as String:
			"FOCUS":
				meter.preview_focus = true
			"MUTED":
				meter.editable = false
		rows.append(UiRow.new().setup(entry["name"] as String, meter))
	return rows


func _sample_meter(cells: int) -> UiSegmentMeter:
	var meter: UiSegmentMeter = UiSegmentMeter.new()
	meter.step_count = METER_STEPS
	meter.value = cells
	meter.formatter = func(v: int) -> String: return "%d%%" % (v * METER_PERCENT_PER_CELL)
	return meter


func _section_rows() -> Array[Control]:
	var rows: Array[Control] = []
	rows.append(_sample_section("GAME", "Classic - Round - Medium", false))
	rows.append(_sample_section("ROUND", "15 min - Sudden death off", true))
	return rows


func _sample_section(title: String, summary: String, open: bool) -> UiSection:
	var section: UiSection = UiSection.new()
	section.title = title
	var body: VBoxContainer = VBoxContainer.new()
	body.name = UiSection.BODY_NAME
	body.add_child(UiRow.new().setup("MODE", _sample_dropdown(UiDropdown.Mode.CYCLE, DROPDOWN_CYCLE_ITEMS)))
	section.add_child(body)
	var advanced: MarginContainer = MarginContainer.new()
	advanced.name = UiSection.ADVANCED_NAME
	var chips: HBoxContainer = HBoxContainer.new()
	chips.add_theme_constant_override("separation", MenuStyleFactory.arcade_tuning().space_2_px)
	for chip_name: String in ["Black hole", "Gust"]:
		var chip: UiChipToggle = UiChipToggle.new()
		chip.label = chip_name
		chips.add_child(chip)
		chip.set_on_silent(chip_name == "Gust")
	advanced.add_child(chips)
	section.add_child(advanced)
	section.set_summary.call_deferred(summary)
	section.set_advanced_open.call_deferred(open)
	return section


func _title_row_rows() -> Array[Control]:
	var rows: Array[Control] = []
	var title_row: UiTitleRow = UiTitleRow.new()
	title_row.title = "Lobby"
	var badge: UiStatusBadge = UiStatusBadge.new()
	badge.text = "HOSTING - LAN"
	badge.live = true
	title_row.add_trailing(badge)
	var back: UiBlockButton = UiBlockButton.new()
	back.text = "BACK"
	title_row.add_trailing(back)
	rows.append(title_row)
	return rows


## A whole panel as a screen builds it: heading + trailing badge, rows of row items.
func _sample_panel() -> UiPanel:
	var panel: UiPanel = UiPanel.new()
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.heading = "Match settings"
	var badge: UiStatusBadge = UiStatusBadge.new()
	badge.text = "VS BOTS"
	panel.header.add_trailing(badge)
	var toggle: UiToggle = UiToggle.new()
	toggle.caption = "Sudden death"
	panel.content.add_child(UiRow.new().setup("SUDDEN DEATH", toggle))
	var stepper: UiStepper = UiStepper.new()
	stepper.min_value = 0
	stepper.max_value = STEPPER_MAX
	stepper.value = STEPPER_MID
	panel.content.add_child(UiRow.new().setup("BOTS", stepper))
	panel.content.add_child(UiRow.new().setup("VOLUME", _sample_meter(METER_MID)))
	panel.content.add_child(UiRow.new().setup("SKY", _sample_dropdown(UiDropdown.Mode.CYCLE, DROPDOWN_CYCLE_ITEMS)))
	var name_field: UiField = UiField.new()
	name_field.text = "Tester"
	panel.content.add_child(UiRow.new().setup("NAME", name_field))
	return panel


## Previews the focus look on [param field] (a captured control cannot hold real focus).
static func show_field_focus(field: UiField) -> void:
	var outline: Panel = Panel.new()
	outline.set_anchors_preset(Control.PRESET_FULL_RECT)
	outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outline.add_theme_stylebox_override("panel", field.edit.get_theme_stylebox("focus", "LineEdit"))
	field.edit.add_child(outline)


## Previews [param state] on [param button] (which must already be in a tree-bound row): hover and
## pressed borrow the matching style as the resting look, focus overlays the theme's focus box.
static func show_state(button: Button, state: StringName) -> void:
	match state:
		STATE_HOVER, STATE_PRESSED:
			button.add_theme_stylebox_override("normal", button.get_theme_stylebox(state))
		STATE_FOCUS:
			var outline: Panel = Panel.new()
			outline.set_anchors_preset(Control.PRESET_FULL_RECT)
			outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
			outline.add_theme_stylebox_override("panel", button.get_theme_stylebox("focus"))
			button.add_child(outline)
		STATE_DISABLED:
			button.disabled = true
