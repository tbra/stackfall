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

## 0 = buttons + badges, 1 = toggles, chips, steppers and tabs (C1b). One page fits one capture.
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


func _panel(title: String, rows: Array[Control]) -> PanelContainer:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.add_theme_stylebox_override("panel", MenuStyleFactory.make_plate())
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", arcade.space_3_px)
	var heading: Label = Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", arcade.font_size_heading_px)
	heading.add_theme_color_override("font_color", arcade.cream_color)
	column.add_child(heading)
	for row: Control in rows:
		column.add_child(row)
	panel.add_child(column)
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
