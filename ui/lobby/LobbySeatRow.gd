class_name LobbySeatRow
extends PanelContainer
## One seat of the lobby's right-hand panel (Bontago-1pi.53, package PL1a, docs/
## LOBBY_REWORK_PLAN.md "Right panel"): the raised white pill the roster always drew,
## now carrying the host's per-seat controls --
##   [colour box] [name / subtitle] [team number] [difficulty] [x] [ready badge]
## - the colour box is a Button: a click / ui_accept asks for the next palette colour,
##   a right click the previous one (Bontago-1pi.93: ui_left / ui_right only move focus; the panel applies it through
##   LobbySeats.cycle_color, which swaps on a clash);
## - the team button exists only with teams on and cycles 1..cap then Random ("?")
##   the same way (LobbySeats.cycle_team);
## - a bot row has a difficulty dropdown (Easy / Normal / Hard) and, for the host, a
##   remove button.
##
## The row is a view: it never touches the seat table. It reports what the player
## asked for through the four request signals and the LobbyPlayersPanel (which owns
## the table) applies it and redraws -- or, for a client's own row, sends it to the host. A row is immutable once built(); a change of
## seat, colour, team mode or editable state is a fresh row.
##
## Gamepad / keyboard: every control the player may use is focusable (the panel hands
## them to the Lobby's focus loop through focus_entries()); ui_accept presses and
## a right click goes back; ui_left / ui_right (held, echoed or pad) only move focus
## (Bontago-1pi.94), as do ui_up / ui_down through the loop. Every control's left / right
## neighbours are the row's previous / next control.

## Cycle the seat's colour; `backwards` = previous colour.
signal color_cycle_requested(key: int, backwards: bool)
## Cycle the seat's team pick; `backwards` = previous number.
signal team_cycle_requested(key: int, backwards: bool)
## The dropdown picked a MatchConfig.AiDifficulty for bot seat `key`.
signal difficulty_chosen(key: int, difficulty: int)
## The remove button of bot seat `key` was pressed.
signal remove_requested(key: int)

## Which control of a row holds focus: lets the panel put focus back on the same
## control after it redraws the rows.
const KIND_COLOR: StringName = &"color"
const KIND_TEAM: StringName = &"team"
const KIND_DIFFICULTY: StringName = &"difficulty"
const KIND_REMOVE: StringName = &"remove"

## Difficulty labels in MatchConfig.AiDifficulty enum order (EASY, NORMAL, HARD).
const DIFFICULTY_LABELS: Array[String] = ["Easy", "Normal", "Hard"]
## What the team button shows for MatchConfig.TEAM_PICK_RANDOM.
const TEAM_RANDOM_TEXT: String = "?"

# --- Set by the panel before build() ----------------------------------------------
## LobbySeats key of the seat (human_key / bot_key), KEY_NONE for a seat-less row
## (a spectator), whose colour box is a plain, inert swatch.
var seat_key: int = LobbySeats.KEY_NONE
var display_name: String = ""
var subtitle: String = ""
var seat_color: Color = Color.GRAY
## Team pick (0 = Random, 1..4) and whether the team button is shown (teams on).
var team_pick: int = MatchConfig.TEAM_PICK_RANDOM
var show_team: bool = false
## MatchConfig.AiDifficulty; only read for a bot.
var difficulty: int = MatchConfig.AiDifficulty.NORMAL
var is_bot: bool = false
var is_ready: bool = false
## The host's row: no Ready toggle exists for the host (Start is its consent), so the badge
## slot shows a crown instead of the Ready / Not ready pill.
var is_host: bool = false
## The controls work: the host's on every seat, a client's on its OWN row only (colour and
## team; PL1b -- the panel turns its clicks into Net.request_seat_pref). Anyone else's row
## is the same row, read-only.
var editable: bool = false

# --- Built by build() ------------------------------------------------------------------
var layout: HBoxContainer = null
var color_button: Button = null
## The shared colour diamond inside color_button (ui/SlotDiamond.tscn).
var color_diamond: SlotDiamond = null
var name_label: Label = null
var subtitle_label: Label = null
## null unless `show_team` and the row has a seat.
var team_button: CycleSelector = null
## null for a human.
var difficulty_option: CycleSelector = null
## null unless the row is a bot's and `editable`.
var remove_button: Button = null
var badge: PanelContainer = null
var badge_label: Label = null

var _tuning: MenuVisualTuning = null
var _layout_tuning: LobbyLayoutTuning = null


const HOST_TOOLTIP: String = "Host"


## The accessible text of a Ready / Not ready pill (the pill itself shows only its icon).
static func ready_tooltip(ready: bool) -> String:
	return ReadyPill.tooltip_for(ready)


## Text of the team button for a pick: "?" for Random, else the number.
static func team_text(pick: int) -> String:
	if pick <= MatchConfig.TEAM_PICK_RANDOM:
		return TEAM_RANDOM_TEXT
	return str(pick)


## Bontago-1pi.95: with clip_text the label's own minimum width is 0, so on a narrow card the
## fixed-width controls took every pixel and a short bot name ("Velocity") showed as one
## letter. Once in the tree (the theme font is known) the name asks for its own text width,
## capped by seat_name_max_width_px; only a longer name still ends in an ellipsis.
func _ready() -> void:
	if name_label == null or _layout_tuning == null:
		return
	var font: Font = name_label.get_theme_font(&"font")
	var font_size: int = name_label.get_theme_font_size(&"font_size")
	var text_width: float = ceilf(font.get_string_size(name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x)
	name_label.custom_minimum_size.x = minf(text_width, float(_layout_tuning.seat_name_max_width_px))


## Builds the row's controls from the fields above.
func build(tuning: MenuVisualTuning, layout_tuning: LobbyLayoutTuning) -> void:
	_tuning = tuning
	_layout_tuning = layout_tuning
	# Bontago-mp0.3.5 (review r3, problem 5): make_flat_list() draws
	# pill_cream_hover_color, which is the *exact same* Color as card_cream_color --
	# the row blended invisibly into %PlayersCard's own background instead of reading
	# as a raised white pill (mockup 11). tuning.pill_white_color is a real near-white
	# the card can never match.
	# Arcade (Bontago-hfa.5): a PlayerSlot row is a flat disc-700 block inside the disc-800 plate.
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var row_box: StyleBoxFlat = MenuStyleFactory.make_flat_list(tuning)
	row_box.content_margin_left = float(arcade.space_3_px)
	row_box.content_margin_right = float(arcade.space_3_px)
	row_box.content_margin_top = float(arcade.space_2_px)
	row_box.content_margin_bottom = float(arcade.space_2_px)
	add_theme_stylebox_override("panel", row_box)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if layout_tuning.seat_row_min_height_px > 0:
		custom_minimum_size = Vector2(0.0, float(layout_tuning.seat_row_min_height_px))
	layout = HBoxContainer.new()
	layout.add_theme_constant_override("separation", layout_tuning.seat_row_separation_px)
	add_child(layout)

	_build_color_button()
	_build_text_column()
	if show_team and seat_key != LobbySeats.KEY_NONE:
		_build_team_button()
	if is_bot:
		_build_difficulty_option()
		if editable:
			_build_remove_button()
	_build_badge()
	_wire_horizontal_focus()


## The controls the player may use, in visual order: what the panel offers the Lobby's
## focus loop. Empty for a read-only row.
func focusable_controls() -> Array[Control]:
	var controls: Array[Control] = []
	if not editable or seat_key == LobbySeats.KEY_NONE:
		return controls
	controls.append(color_button)
	if team_button != null:
		controls.append(team_button)
	if difficulty_option != null:
		controls.append(difficulty_option)
	if remove_button != null:
		controls.append(remove_button)
	return controls


## Which KIND_* `control` is in this row, or &"" for none.
func kind_of(control: Node) -> StringName:
	if control == null:
		return &""
	if control == color_button or color_button.is_ancestor_of(control):
		return KIND_COLOR
	if team_button != null and (control == team_button or team_button.is_ancestor_of(control)):
		return KIND_TEAM
	if difficulty_option != null and (control == difficulty_option or difficulty_option.is_ancestor_of(control)):
		return KIND_DIFFICULTY
	if remove_button != null and (control == remove_button or remove_button.is_ancestor_of(control)):
		return KIND_REMOVE
	return &""


## The control of `kind`, or null when this row has none.
func control_of(kind: StringName) -> Control:
	match kind:
		KIND_COLOR:
			return color_button
		KIND_TEAM:
			return team_button
		KIND_DIFFICULTY:
			return difficulty_option
		KIND_REMOVE:
			return remove_button
	return null


# --- Building --------------------------------------------------------------------------

## The colour box: a Button holding the shared SlotDiamond in the seat's colour (lit on
## hover when live, ringed on focus), so a read-only row looks just like a live one.
func _build_color_button() -> void:
	color_button = Button.new()
	color_button.name = "ColorButton"
	color_button.custom_minimum_size = _layout_tuning.color_box_size_px
	color_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	color_button.focus_mode = Control.FOCUS_ALL if editable and seat_key != LobbySeats.KEY_NONE else Control.FOCUS_NONE
	var radius: int = _layout_tuning.color_box_corner_radius_px
	var normal: StyleBoxFlat = _color_box(Color.TRANSPARENT, radius, 0, Color.TRANSPARENT)
	var hover: StyleBoxFlat = _color_box(_tuning.pill_cream_hover_color, radius, 0, Color.TRANSPARENT)
	var focus: StyleBoxFlat = _color_box(Color.TRANSPARENT, radius, _layout_tuning.seat_color_focus_border_px, _tuning.focus_outline_color)
	color_button.add_theme_stylebox_override("normal", normal)
	color_button.add_theme_stylebox_override("hover", hover if editable else normal)
	color_button.add_theme_stylebox_override("pressed", normal)
	color_button.add_theme_stylebox_override("hover_pressed", normal)
	color_button.add_theme_stylebox_override("disabled", normal)
	color_button.add_theme_stylebox_override("focus", focus)
	# Bontago-1pi.81: the seat colour is the shared SlotDiamond, centred in the button.
	color_diamond = SlotDiamond.create(seat_color)
	color_diamond.name = "SlotDiamond"
	var half: float = color_diamond.diamond_size_px() * 0.5
	color_diamond.anchor_left = 0.5
	color_diamond.anchor_right = 0.5
	color_diamond.anchor_top = 0.5
	color_diamond.anchor_bottom = 0.5
	color_diamond.offset_left = -half
	color_diamond.offset_right = half
	color_diamond.offset_top = -half
	color_diamond.offset_bottom = half
	color_button.add_child(color_diamond)
	color_button.disabled = not editable or seat_key == LobbySeats.KEY_NONE
	if editable and seat_key != LobbySeats.KEY_NONE:
		color_button.tooltip_text = "Click to change colour (right click: previous)"
		color_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		color_button.pressed.connect(_on_color_pressed)
		color_button.gui_input.connect(_on_cycle_gui_input.bind(KIND_COLOR))
	layout.add_child(color_button)


func _build_text_column() -> void:
	var text_column: VBoxContainer = VBoxContainer.new()
	text_column.add_theme_constant_override("separation", _layout_tuning.seat_text_separation_px)
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label = Label.new()
	name_label.theme_type_variation = &"TitleLabel"
	name_label.add_theme_font_size_override("font_size", _layout_tuning.seat_name_font_size)
	name_label.text = display_name
	# Bontago-1pi.95: long names / subtitles clip so a row's minimum width is its controls only.
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	subtitle_label = Label.new()
	subtitle_label.theme_type_variation = &"CaptionLabel"
	subtitle_label.text = subtitle
	subtitle_label.clip_text = true
	subtitle_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text_column.add_child(name_label)
	text_column.add_child(subtitle_label)
	layout.add_child(text_column)


## The team number pill: "1".."4" or "?" (Random), a cream-blue pill like the other
## small pills on the screen.
func _build_team_button() -> void:
	team_button = CycleSelector.new()
	# The pick lives in the panel's seat table: the pill only reports the click and the row is rebuilt.
	team_button.auto_advance = false
	team_button.name = "TeamButton"
	team_button.text = team_text(team_pick)
	team_button.custom_minimum_size = _layout_tuning.seat_team_button_min_size_px
	team_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	team_button.tooltip_text = PlayerNames.team_label(team_pick) if team_pick > MatchConfig.TEAM_PICK_RANDOM else "Random team"
	_style_pill(team_button, _tuning.pill_powder_blue_color, _tuning.pill_powder_blue_hover_color, _tuning.ink_color)
	team_button.disabled = not editable
	team_button.focus_mode = Control.FOCUS_ALL if editable else Control.FOCUS_NONE
	if editable:
		team_button.tooltip_text += " (click to change, right click: previous)"
		team_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		team_button.cycled.connect(_on_team_cycled)
	layout.add_child(team_button)


## A bot's own difficulty. Read-only (disabled) for a client; the host's pill cycles on
## click / ui_accept (right click: previous), like every CycleSelector.
func _build_difficulty_option() -> void:
	difficulty_option = CycleSelector.new()
	difficulty_option.name = "DifficultyOption"
	for label_index: int in range(DIFFICULTY_LABELS.size()):
		difficulty_option.add_item(DIFFICULTY_LABELS[label_index])
		difficulty_option.set_item_icon(label_index, UiArtTable.shared().difficulty_icon(label_index))
	difficulty_option.add_theme_constant_override("icon_max_width", UiArtTable.shared().lobby_icon_px)
	difficulty_option.select(clampi(difficulty, 0, DIFFICULTY_LABELS.size() - 1))
	# Bontago-1pi.95: clip so the dropdown's minimum is this tuned width, not its widest item.
	difficulty_option.custom_minimum_size = Vector2(
		float(_layout_tuning.seat_difficulty_min_width_px), float(_layout_tuning.seat_control_height_px)
	)
	difficulty_option.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	difficulty_option.tooltip_text = "This bot's difficulty"
	_style_pill(difficulty_option, _tuning.pill_cream_color, _tuning.pill_cream_hover_color, _tuning.ink_color)
	# Bontago-1pi.150: tighter side margins so "Normal" is never clipped on the narrow mockup-scale canvas.
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box: StyleBox = difficulty_option.get_theme_stylebox(state)
		if box != null:
			box.content_margin_left = minf(box.content_margin_left, float(_layout_tuning.seat_difficulty_margin_px))
			box.content_margin_right = minf(box.content_margin_right, float(_layout_tuning.seat_difficulty_margin_px))
	difficulty_option.disabled = not editable
	difficulty_option.focus_mode = Control.FOCUS_ALL if editable else Control.FOCUS_NONE
	if editable:
		difficulty_option.item_selected.connect(_on_difficulty_selected)
	layout.add_child(difficulty_option)


func _build_remove_button() -> void:
	remove_button = Button.new()
	remove_button.name = "RemoveButton"
	remove_button.text = ""
	UiArtTable.shared().apply_button_icon(remove_button, UiArtTable.shared().lobby_icon(UiArtTable.KEY_BOT_REMOVE))
	remove_button.custom_minimum_size = _layout_tuning.seat_remove_button_min_size_px
	remove_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	remove_button.tooltip_text = "Remove this bot"
	_style_pill(remove_button, _tuning.pill_coral_color, _tuning.pill_coral_hover_color, _tuning.label_ink_light_color)
	# The pill's text margins would eat the whole icon-only circle: zero them so the x gets the full box.
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var box: StyleBox = remove_button.get_theme_stylebox(state)
		box.content_margin_left = 0.0
		box.content_margin_right = 0.0
	remove_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	remove_button.pressed.connect(_on_remove_pressed)
	layout.add_child(remove_button)


## The host's crown pill: a yellow pill (Bontago-1pi.120, LobbyLayoutTuning.host_crown_pill_color)
## holding the crown icon (UiArtTable).
func _build_host_crown_badge() -> void:
	badge.add_theme_stylebox_override("panel", MenuStyleFactory.make_badge(_layout_tuning.host_crown_pill_color, _tuning))
	badge.tooltip_text = HOST_TOOLTIP
	var crown: TextureRect = TextureRect.new()
	var table: UiArtTable = UiArtTable.shared()
	crown.texture = table.lobby_icon(UiArtTable.KEY_HOST_CROWN)
	crown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crown.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	crown.custom_minimum_size = Vector2.ONE * float(table.lobby_icon_px)
	# The pill face is bright yellow: ink, never the cream the menu ink token now resolves to.
	crown.modulate = MenuStyleFactory.ink_for_face(_layout_tuning.host_crown_pill_color)
	crown.name = "HostCrown"
	badge.add_child(crown)
	layout.add_child(badge)


func _build_badge() -> void:
	# Bontago-1pi.146: the badge is the same height as the team / difficulty / remove pills (not stretched
	# to the row), and as wide as the remove button.
	var badge_size: Vector2 = Vector2(float(_layout_tuning.seat_badge_width_px), float(_layout_tuning.seat_control_height_px))
	if is_host:
		badge = PanelContainer.new()
		badge.custom_minimum_size = badge_size
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_build_host_crown_badge()
		return
	# Bontago-1pi.158: the Ready / Not ready pill is the shared ui/ReadyPill.gd component.
	var pill: ReadyPill = ReadyPill.create(is_ready, badge_size)
	badge = pill
	badge_label = pill.label
	layout.add_child(badge)


## A pill look that stays the same when the control is disabled (a client's read-only
## row), so only the host sees live controls but both see the same row.
func _style_pill(button: Button, color: Color, hover_color: Color, ink: Color) -> void:
	MenuStyleFactory.apply_pill(button, color, hover_color, ink, _tuning)
	button.add_theme_stylebox_override("disabled", MenuStyleFactory.make_badge(color, _tuning))
	button.add_theme_color_override("font_disabled_color", ink)


static func _color_box(color: Color, radius: int, border_px: int, border_color: Color) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	if border_px > 0:
		box.set_border_width_all(border_px)
		box.border_color = border_color
	return box


## Every control of the row gets its neighbours as explicit left / right focus targets.
func _wire_horizontal_focus() -> void:
	var controls: Array[Control] = focusable_controls()
	for index: int in range(controls.size()):
		var control: Control = controls[index]
		if index > 0:
			control.focus_neighbor_left = control.get_path_to(controls[index - 1])
		if index < controls.size() - 1:
			control.focus_neighbor_right = control.get_path_to(controls[index + 1])


# --- Input -------------------------------------------------------------------------------

func _on_color_pressed() -> void:
	color_cycle_requested.emit(seat_key, false)


func _on_team_cycled(backwards: bool) -> void:
	team_cycle_requested.emit(seat_key, backwards)


func _on_remove_pressed() -> void:
	remove_requested.emit(seat_key)


func _on_difficulty_selected(index: int) -> void:
	difficulty_chosen.emit(seat_key, index)


## Right click = previous colour. The matching event is consumed BEFORE the request goes
## out: handling it redraws the rows, and this control then leaves the tree. Connected to the
## control's `gui_input` signal (not _gui_input) so tests can drive it with a plain emit, like
## the timer sliders in ui/Lobby.gd. (The team pill is a CycleSelector and does the same itself.)
func _on_cycle_gui_input(event: InputEvent, _kind: StringName) -> void:
	if not (event is InputEventMouseButton):
		# Bontago-1pi.93: ui_left / ui_right (held, echoed or pad) only move focus; a click /
		# ui_accept (pressed) cycles the colour.
		return
	var click: InputEventMouseButton = event as InputEventMouseButton
	if not click.pressed or click.button_index != MOUSE_BUTTON_RIGHT:
		return
	accept_event()
	color_cycle_requested.emit(seat_key, true)
