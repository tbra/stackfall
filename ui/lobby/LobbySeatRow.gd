class_name LobbySeatRow
extends PanelContainer
## One seat of the lobby's right-hand panel, carrying the host's per-seat controls --
##   [colour box] [name / subtitle] [team number] [difficulty] [x] [ready badge]
## - the colour box is a Button: a click / ui_accept asks for the next palette colour,
##   a right click the previous one (ui_left / ui_right only move focus; the panel applies it through
##   LobbySeats.cycle_color, which swaps on a clash);
## - the team button exists only with teams on and cycles 1..cap then Random ("?")
##   the same way (LobbySeats.cycle_team);
## - a bot row has a difficulty cycler (Easy / Normal / Hard) and, for the host, a
##   remove button.
##
## Every control is a ui/components row item: the team selector is a UiDropdown (popup list), the difficulty a
## UiCycler, the remove X a UiIconButton
## (DANGER), the Ready / host badge a UiStatusBadge, so they all share one height
## (ComponentMetrics.row_height_px). Only the colour diamond keeps its own flat, borderless button.
##
## The row is a view: it never touches the seat table. It reports what the player
## asked for through the four request signals and the LobbyPlayersPanel (which owns
## the table) applies it and redraws -- or, for a client's own row, sends it to the host.
## A row is immutable once built(); a change of seat, colour, team mode or editable
## state is a fresh row.
##
## Gamepad / keyboard: every control the player may use is focusable (the panel hands
## them to the Lobby's focus loop through focus_entries()); ui_accept presses and
## a right click goes back; ui_left / ui_right (held, echoed or pad) only move focus,
## as do ui_up / ui_down through the loop. Every control's left / right
## neighbours are the row's previous / next control.

## Cycle the seat's colour; `backwards` = previous colour.
signal color_cycle_requested(key: int, backwards: bool)
## Cycle the seat's team pick; `backwards` = previous number.
signal team_cycle_requested(key: int, backwards: bool)
## The team dropdown picked `pick` (TEAM_PICK_RANDOM or 1..TEAM_PICK_MAX).
signal team_chosen(key: int, pick: int)
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
const KIND_MUTE: StringName = &"mute"

## Chat mute button texts.
const MUTE_TEXT: String = "Mute"
const UNMUTE_TEXT: String = "Unmute"
## The mute icon block's glyphs: heard / muted.
const SPEAKER_ON_ICON: Texture2D = preload("res://assets/ui/icons/speaker_high.svg")
const SPEAKER_OFF_ICON: Texture2D = preload("res://assets/ui/icons/speaker_muted.svg")

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
## team; the panel turns its clicks into Net.request_seat_pref). Anyone else's row
## is the same row, read-only.
var editable: bool = false
## Some row of the list is a bot's: a human row keeps the empty room of the bot's difficulty and
## remove columns so every row's team selector and badge line up.
var align_bot_columns: bool = false
## The list's bot rows carry a remove button (the host's view): human rows reserve its room too. A
## client's own (editable) row must not decide this from its own `editable`.
var align_remove_column: bool = false
## which look this row builds (LobbySeatVariants.Style); the panel sets it, CLASSIC is the shipped row.
var variant: int = LobbySeatVariants.Style.CLASSIC
## The lobby team cap (picks run 1..team_cap, then Random); the BOARD mover names the team it sends the seat to.
var team_cap: int = 0
## TABLE: every other row is striped.
var stripe: bool = false

# --- Built by build() ------------------------------------------------------------------
var layout: Container = null
var color_button: Button = null
## The shared colour diamond inside color_button (ui/hud/SlotDiamond.tscn).
var color_diamond: SlotDiamond = null
var name_label: Label = null
var subtitle_label: Label = null
## null unless `show_team` and the row has a seat.
var team_button: UiDropdown = null
## null for a human.
var difficulty_option: UiCycler = null
## null unless the row is a bot's and `editable`.
var remove_button: UiIconButton = null
## Chat mute toggle: only on a networked, seated human row that is not the local player's.
var mute_button: Button = null
## Test seam: returns whether this row's session can chat (default: networked, not the private host).
var mute_column_override: Callable = Callable()
var badge: UiStatusBadge = null
## Variant controls (TILES / TABLE / BOARD): the team as ONE block that cycles in place (click / accept = next,
## right click = previous; painted in the team colour, or in the destination team's colour on the BOARD mover) and
## a bot's difficulty as ONE icon block that cycles the same way. No popups, no < > steppers.
var team_cycle_button: UiBlockButton = null
var skill_button: UiIconButton = null

var _table_box: StyleBoxFlat = null
var _tuning: MenuVisualTuning = null
var _layout_tuning: LobbyLayoutTuning = null


const HOST_TOOLTIP: String = "Host"


## The accessible text of a Ready / Not ready pill (the pill itself shows only its icon).
static func ready_tooltip(ready: bool) -> String:
	return "Ready" if ready else "Not ready"


## Text of the team button for a pick: "?" for Random, else the number.
static func team_text(pick: int) -> String:
	if pick <= MatchConfig.TEAM_PICK_RANDOM:
		return TEAM_RANDOM_TEXT
	return str(pick)

## With clip_text the label's own minimum width is 0, so on a narrow card the
## fixed-width controls would take every pixel and a short bot name ("Velocity") would
## show as one letter. Once in the tree (the theme font is known) the name asks for its
## own text width, capped by seat_name_max_width_px; only a longer name ends in an ellipsis.
func _ready() -> void:
	if name_label == null or _layout_tuning == null or variant != LobbySeatVariants.Style.CLASSIC:
		return  # the new looks let the name take what its cells leave (ellipsis past that)
	var font: Font = name_label.get_theme_font(&"font")
	var font_size: int = name_label.get_theme_font_size(&"font_size")
	var text_width: float = ceilf(font.get_string_size(name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x)
	name_label.custom_minimum_size.x = minf(text_width, float(_layout_tuning.seat_name_max_width_px))


## Builds the row's controls from the fields above.
func build(tuning: MenuVisualTuning, layout_tuning: LobbyLayoutTuning) -> void:
	_tuning = tuning
	_layout_tuning = layout_tuning
	# Arcade: a PlayerSlot row is a flat disc-700 block inside the disc-800 plate.
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
	layout.add_theme_constant_override("separation", arcade.space_2_px)
	match variant:
		LobbySeatVariants.Style.TILES:
			_build_tile(row_box)
		LobbySeatVariants.Style.TABLE:
			add_child(layout)
			_build_table_line(row_box)
		LobbySeatVariants.Style.BOARD:
			_build_board_row(row_box)
		_:
			add_child(layout)
			_build_color_button()
			_build_text_column()
			if show_team and seat_key != LobbySeats.KEY_NONE:
				_build_team_button()
			if is_bot:
				_build_difficulty_option()
				if editable:
					_build_remove_button()
			elif align_bot_columns and show_team and seat_key != LobbySeats.KEY_NONE:
				_build_bot_column_spacers()
			_build_mute_slot()
			_build_badge()
	_wire_horizontal_focus()


## The controls the player may use, in visual order: what the panel offers the Lobby's
## focus loop. Empty for a read-only row.
func focusable_controls() -> Array[Control]:
	var controls: Array[Control] = []
	if seat_key == LobbySeats.KEY_NONE:
		return controls
	# The mute button is a chat reader's control, not a seat edit: a read-only row offers it too.
	if not editable:
		if mute_button != null:
			controls.append(mute_button)
		return controls
	controls.append(color_button)
	var ordered: Array[Control] = []
	match variant:
		LobbySeatVariants.Style.TILES:
			# the tile's top-right control (X or mute), then its footer (team, skill)
			ordered = [remove_button, mute_button, team_cycle_button, skill_button]
		LobbySeatVariants.Style.TABLE:
			ordered = [team_cycle_button, skill_button, mute_button, remove_button]
		LobbySeatVariants.Style.BOARD:
			ordered = [team_cycle_button, skill_button, remove_button, mute_button]
		_:
			ordered = [team_button, difficulty_option, remove_button, mute_button]
	for control: Control in ordered:
		if control != null:
			controls.append(control)
	return controls


## Which KIND_* `control` is in this row, or &"" for none.
func kind_of(control: Node) -> StringName:
	if control == null:
		return &""
	if control == color_button or color_button.is_ancestor_of(control):
		return KIND_COLOR
	var team_control: Control = team_control_of_row()
	if team_control != null and (control == team_control or team_control.is_ancestor_of(control)):
		return KIND_TEAM
	var skill: Control = difficulty_control()
	if skill != null and (control == skill or skill.is_ancestor_of(control)):
		return KIND_DIFFICULTY
	if remove_button != null and (control == remove_button or remove_button.is_ancestor_of(control)):
		return KIND_REMOVE
	if mute_button != null and (control == mute_button or mute_button.is_ancestor_of(control)):
		return KIND_MUTE
	return &""


## The control of `kind`, or null when this row has none.
func control_of(kind: StringName) -> Control:
	match kind:
		KIND_COLOR:
			return color_button
		KIND_TEAM:
			return team_control_of_row()
		KIND_DIFFICULTY:
			return difficulty_control()
		KIND_REMOVE:
			return remove_button
		KIND_MUTE:
			return mute_button
	return null


## The row's team control: the classic team dropdown or a look's cycling team block; null for none.
func team_control_of_row() -> Control:
	return team_cycle_button if team_cycle_button != null else team_button


## The row's bot difficulty control (the classic cycler or a look's icon block); null for a human.
func difficulty_control() -> Control:
	return skill_button if skill_button != null else difficulty_option


# --- Building --------------------------------------------------------------------------

## The colour box: a Button holding the shared SlotDiamond in the seat's colour (lit on
## hover when live, ringed on focus), so a read-only row looks just like a live one.
func _build_color_button(box_px: Vector2 = Vector2.ZERO, diamond_px: float = -1.0) -> void:
	color_button = Button.new()
	color_button.name = "ColorButton"
	color_button.custom_minimum_size = box_px if box_px.x > 0.0 else _layout_tuning.color_box_size_px
	color_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	color_button.focus_mode = Control.FOCUS_ALL if editable and seat_key != LobbySeats.KEY_NONE else Control.FOCUS_NONE
	var radius: int = _layout_tuning.color_box_corner_radius_px
	var normal: StyleBoxFlat = _color_box(Color.TRANSPARENT, radius, 0, Color.TRANSPARENT)
	var hover: StyleBoxFlat = _color_box(MenuStyleFactory.arcade_tuning().disc_600_color, radius, 0, Color.TRANSPARENT)
	var focus: StyleBoxFlat = _color_box(Color.TRANSPARENT, radius, _layout_tuning.seat_color_focus_border_px, _tuning.focus_outline_color)
	var faces: Dictionary = {
		"normal": normal, "hover": hover if editable else normal, "pressed": normal,
		"hover_pressed": normal, "disabled": normal, "focus": focus,
	}
	for state: String in faces:
		color_button.add_theme_stylebox_override(state, faces[state] as StyleBox)
	# the seat colour is the shared SlotDiamond, centred in the button.
	color_diamond = SlotDiamond.create(seat_color, diamond_px)
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
		color_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		color_button.pressed.connect(_on_color_pressed)
		color_button.gui_input.connect(_on_cycle_gui_input.bind(KIND_COLOR))
	layout.add_child(color_button)


func _build_text_column() -> void:
	var text_column: UiStack = UiStack.new()
	text_column.gap_px = _layout_tuning.seat_text_separation_px
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label = Label.new()
	name_label.theme_type_variation = &"TitleLabel"
	name_label.add_theme_font_size_override("font_size", _layout_tuning.seat_name_font_size)
	name_label.text = display_name
	# long names / subtitles clip so a row's minimum width is its controls only.
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	subtitle_label = Label.new()
	subtitle_label.theme_type_variation = &"CaptionLabel"
	subtitle_label.text = subtitle if variant == LobbySeatVariants.Style.CLASSIC else _sub_text()
	subtitle_label.clip_text = true
	subtitle_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text_column.add_child(name_label)
	text_column.add_child(subtitle_label)
	layout.add_child(text_column)


## The team selector: a compact UiDropdown showing "?" (Random) or "1".."4" that opens a list.
## DECISION: seat pills are popups, not UiCyclers (a cycler's two blocks would
## not fit a seat row). Items run Random, 1..TEAM_PICK_MAX so the item index is the pick itself;
## the pick lives in the panel's seat table, so the dropdown only reports the choice
## ([signal team_chosen]) and the row is rebuilt.
func _build_team_button() -> void:
	team_button = UiDropdown.new()
	team_button.show_chevron = false
	team_button.name = "TeamButton"
	for pick: int in range(MatchConfig.TEAM_PICK_RANDOM, MatchConfig.TEAM_PICK_MAX + 1):
		team_button.add_item(team_text(pick))
	team_button.select(clampi(team_pick, MatchConfig.TEAM_PICK_RANDOM, MatchConfig.TEAM_PICK_MAX))
	_compact(team_button, _layout_tuning.seat_team_button_min_size_px.x, false)
	team_button.disabled = not editable
	team_button.focus_mode = Control.FOCUS_ALL if editable else Control.FOCUS_NONE
	if editable:
		team_button.item_selected.connect(_on_team_selected)
	layout.add_child(team_button)


## A bot's own difficulty: a UiCycler ("<" value ">"), read-only (disabled) for
## a client. ui_left / ui_right step it, the blocks click.
func _build_difficulty_option() -> void:
	difficulty_option = UiCycler.new()
	difficulty_option.name = "DifficultyOption"
	var art: UiArtTable = UiArtTable.shared()
	for label_index: int in range(DIFFICULTY_LABELS.size()):
		difficulty_option.add_item(DIFFICULTY_LABELS[label_index], false, art.difficulty_icon(label_index))
	difficulty_option.select(clampi(difficulty, 0, DIFFICULTY_LABELS.size() - 1))
	difficulty_option.custom_minimum_size.x = _difficulty_width()  # the tuned floor, grown to the content
	difficulty_option.disabled = not editable
	difficulty_option.focus_mode = Control.FOCUS_ALL if editable else Control.FOCUS_NONE
	if editable:
		difficulty_option.item_selected.connect(_on_difficulty_selected)
	layout.add_child(difficulty_option)


## The width the difficulty selector needs (a UiCycler's own minimum width: both blocks, the icon,
## the longest label and its padding). Computed from a scratch cycler so the empty room of a human
## row matches a bot row's exactly.
func _difficulty_width() -> float:
	var probe: UiCycler = UiCycler.new()
	var art: UiArtTable = UiArtTable.shared()
	for label_index: int in range(DIFFICULTY_LABELS.size()):
		probe.add_item(DIFFICULTY_LABELS[label_index], false, art.difficulty_icon(label_index))
	var width: float = probe.get_combined_minimum_size().x
	probe.free()
	return maxf(float(_layout_tuning.seat_difficulty_min_width_px), width)


## Fits a dropdown to a seat row: the tuned width (never below its row-item minimum height) and
## the token side margins (`space_2`; the chevron's side keeps room for it).
func _compact(dropdown: UiDropdown, width_px: float, keeps_chevron: bool) -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	dropdown.custom_minimum_size.x = width_px
	var right: float = float(arcade.space_2_px + (arcade.space_4_px if keeps_chevron else 0))
	for state: String in UiDropdown.STATES:
		var box: StyleBox = dropdown.get_theme_stylebox(state)
		box.content_margin_left = float(arcade.space_2_px)
		box.content_margin_right = right


func _build_remove_button() -> void:
	remove_button = UiIconButton.new()
	remove_button.name = "RemoveButton"
	remove_button.tone = UiIconButton.Tone.DANGER
	var art: UiArtTable = UiArtTable.shared()
	remove_button.set_icon_texture(art.lobby_icon(UiArtTable.KEY_BOT_REMOVE))
	remove_button.pressed.connect(_on_remove_pressed)
	layout.add_child(remove_button)


## True when this row carries (or reserves room for) the chat mute column: a networked session that
## can chat (not offline, not the private local host).
func _mute_column_on() -> bool:
	if mute_column_override.is_valid():
		return mute_column_override.call() as bool
	return mute_column_active(Callable())


## The row's non-local seated human gets the mute toggle; every other row of a chat session reserves
## the same room (`reserve_room`) so the badge column stays aligned.
func _build_mute_slot(reserve_room: bool = true) -> void:
	if not _mute_column_on():
		return
	var can_mute: bool = not is_bot and seat_key > LobbySeats.KEY_NONE and seat_key != Net.local_peer_id()
	if not can_mute:
		if reserve_room:
			_add_spacer(_mute_width())
		return
	mute_button = _make_mute_button()
	layout.add_child(mute_button)


## CLASSIC: a "Mute" / "Unmute" block; the other looks: a speaker icon block that shows whether the player is heard.
func _make_mute_button() -> Button:
	var button: Button = null
	if variant == LobbySeatVariants.Style.CLASSIC:
		var block: UiBlockButton = UiBlockButton.new()
		block.custom_minimum_size.x = _mute_width()
		block.toggle_mode = false
		button = block
	else:
		button = UiIconButton.new()
	button.name = "MuteButton"
	button.tooltip_text = "Hide this player's chat on your screen"
	button.pressed.connect(_on_mute_pressed)
	mute_button = button
	_refresh_mute_text()
	return button


func _refresh_mute_text() -> void:
	var muted: bool = ChatMute.is_muted(seat_key)
	if mute_button is UiIconButton:
		(mute_button as UiIconButton).set_icon_texture(SPEAKER_OFF_ICON if muted else SPEAKER_ON_ICON)
		return
	mute_button.text = UNMUTE_TEXT if muted else MUTE_TEXT


## Wide enough for the longer of the two labels (an icon block: one row-height square).
func _mute_width() -> float:
	if variant != LobbySeatVariants.Style.CLASSIC:
		return float(UiRowItem.metrics().row_height_px)
	var probe: UiBlockButton = UiBlockButton.new()
	probe.text = UNMUTE_TEXT
	var width: float = probe.get_combined_minimum_size().x
	probe.free()
	return width


func _on_mute_pressed() -> void:
	ChatMute.toggle(seat_key)
	_refresh_mute_text()


## Empty room where a bot row has its difficulty / remove controls, so the team selectors and the
## badges of every row stay in their columns.
func _build_bot_column_spacers() -> void:
	var widths: Array[float] = [_difficulty_width()]
	if align_remove_column:
		widths.append(float(UiRowItem.metrics().row_height_px))
	for width: float in widths:
		var spacer: Control = Control.new()
		spacer.name = "ColumnSpacer"
		spacer.custom_minimum_size = Vector2(width, 0.0)
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layout.add_child(spacer)


## The badge slot: the host's crown (UiStatusBadge HOST) or the Ready / Not ready tile (an icon-only
## UiStatusBadge READY / NOT_READY). Both are row items: the same height as every other control of the row.
## One width for the crown and the Ready tile (the crown's icon plus the badge's side padding), so every row's
## badge column lines up.
static func state_cell_width() -> float:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	return maxf(float(UiRowItem.metrics().badge_icon_only_min_width_px), float(UiArtTable.shared().lobby_icon_px + 2 * arcade.space_3_px))


func _build_badge() -> void:
	layout.add_child(_make_badge())


func _make_badge() -> UiStatusBadge:
	var badge_size: Vector2 = Vector2(state_cell_width(), float(UiRowItem.metrics().row_height_px))
	if is_host:
		badge = UiStatusBadge.new()
		badge.icon_only = true
		badge.variant = UiStatusBadge.Look.HOST
		badge.text = HOST_TOOLTIP
		badge.label.visible = false
		var crown: TextureRect = TextureRect.new()
		var table: UiArtTable = UiArtTable.shared()
		crown.texture = table.lobby_icon(UiArtTable.KEY_HOST_CROWN)
		crown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		crown.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		crown.custom_minimum_size = Vector2.ONE * float(table.lobby_icon_px)
		# The badge face is bright (rim): ink, never the cream the menu ink token resolves to.
		crown.modulate = MenuStyleFactory.ink_for_face(UiStatusBadge.face_for(UiStatusBadge.Look.HOST))
		crown.name = "HostCrown"
		badge.custom_minimum_size = badge_size
		crown.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_child(crown)
		return badge
	# the Ready / Not ready tile is an icon-only UiStatusBadge (tick / hourglass).
	var pill: UiStatusBadge = UiStatusBadge.new()
	pill.icon_only = true
	pill.custom_minimum_size = badge_size
	pill.variant = UiStatusBadge.Look.READY if is_ready else UiStatusBadge.Look.NOT_READY
	pill.text = ready_tooltip(is_ready)
	badge = pill
	return pill


# --- Looks: TILES / TABLE / BOARD --------------------------------------------------------

## The team's colour (tuning list, wrapping), or Color.TRANSPARENT for Random / FFA / a seat-less row.
func team_color() -> Color:
	if not show_team or seat_key == LobbySeats.KEY_NONE or team_pick <= MatchConfig.TEAM_PICK_RANDOM:
		return Color.TRANSPARENT
	return team_color_of(_layout_tuning, team_pick)


static func team_color_of(layout_tuning: LobbyLayoutTuning, pick: int) -> Color:
	var colors: PackedColorArray = layout_tuning.seat_team_colors
	return colors[posmod(pick - 1, colors.size())]


## The shared mute-column rule of the panel's table header and every row: a networked session that can chat.
static func mute_column_active(override: Callable) -> bool:
	if override.is_valid():
		return override.call() as bool
	return not Net.is_offline() and not Net.is_private_session()


## The sub line of the new looks: a bot's also names its skill ("AI · Normal"), because the skill block is an icon.
func _sub_text() -> String:
	if is_bot:
		return "%s · %s" % [subtitle, DIFFICULTY_LABELS[clampi(difficulty, 0, DIFFICULTY_LABELS.size() - 1)]]
	return subtitle


## Paints a block button in `face` (hover, pressed, lip and ink follow from it) at the row-item height.
func _paint_block(button: Button, face: Color) -> void:
	MenuStyleFactory.apply_block(button, face, MenuStyleFactory.ink_for_face(face), true)
	UiBlockButton.fit_row_height(button, MenuStyleFactory.arcade_tuning())


## The team as one block that cycles in place: `label_text` on a block in `tint` (neutral when transparent).
func _make_team_cycle(label_text: String, tint: Color, min_width: float) -> UiBlockButton:
	var block: UiBlockButton = UiBlockButton.new()
	block.name = "TeamCycle"
	block.text = label_text
	block.custom_minimum_size.x = min_width
	block.tooltip_text = "Team (click: next, right click: previous)"
	if tint.a > 0.0:
		_paint_block(block, tint)
	block.disabled = not editable
	block.focus_mode = Control.FOCUS_ALL if editable else Control.FOCUS_NONE
	if editable:
		block.pressed.connect(_on_team_move_pressed)
		block.gui_input.connect(_on_cycle_gui_input.bind(KIND_TEAM))
	team_cycle_button = block
	return block


## The seat's team block: the team number in the team's colour ("?" neutral for Random).
func _make_seat_team_cycle() -> UiBlockButton:
	return _make_team_cycle(team_text(team_pick), team_color(), float(UiRowItem.metrics().row_height_px))


## A bot's skill as one icon block: shows the skill's icon, click / accept = next, right click = previous.
func _make_skill_button() -> UiIconButton:
	var index: int = clampi(difficulty, 0, DIFFICULTY_LABELS.size() - 1)
	skill_button = UiIconButton.new()
	skill_button.name = "SkillButton"
	skill_button.set_icon_texture(UiArtTable.shared().difficulty_icon(index))
	skill_button.tooltip_text = "Bot skill: %s (click: next, right click: previous)" % DIFFICULTY_LABELS[index]
	skill_button.disabled = not editable
	skill_button.focus_mode = Control.FOCUS_ALL if editable else Control.FOCUS_NONE
	if editable:
		skill_button.pressed.connect(_on_skill_pressed)
		skill_button.gui_input.connect(_on_cycle_gui_input.bind(KIND_DIFFICULTY))
	return skill_button


func _add_spacer(width: float) -> void:
	var spacer: Control = Control.new()
	spacer.name = "ColumnSpacer"
	spacer.custom_minimum_size = Vector2(width, 0.0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(spacer)


func _add_expander() -> void:
	var expander: Control = Control.new()
	expander.name = "Expander"
	expander.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	expander.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(expander)


## TILES: one upright tile. Top line: state tile left, the bot's X (or a human's mute) right; then the hero
## marker on a wash of the player's colour, name and sub line, and a footer of the team and skill blocks.
func _build_tile(box: StyleBoxFlat) -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	box.bg_color = arcade.disc_700_color.lerp(seat_color, _layout_tuning.seat_tile_tint_mix)
	box.set_content_margin_all(float(arcade.space_2_px))
	var body: UiStack = UiStack.new()
	body.gap_px = arcade.space_1_px
	add_child(body)
	var top: HBoxContainer = HBoxContainer.new()
	body.add_child(top)
	layout = top
	_build_badge()
	_add_expander()
	if is_bot and editable:
		_build_remove_button()
	else:
		_build_mute_slot(false)
	var marker_line: CenterContainer = CenterContainer.new()
	body.add_child(marker_line)
	layout = marker_line
	var marker_px: float = float(_layout_tuning.seat_tile_marker_px)
	_build_color_button(Vector2.ONE * marker_px, marker_px)
	layout = body
	_build_text_column()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var footer: UiBar = UiBar.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.custom_minimum_size.y = float(UiRowItem.metrics().row_height_px)  # every tile keeps one height
	footer.gap_px = arcade.space_1_px
	body.add_child(footer)
	layout = footer
	if show_team and seat_key != LobbySeats.KEY_NONE:
		footer.add_child(_make_seat_team_cycle())
	if is_bot:
		footer.add_child(_make_skill_button())
	layout = body


## TABLE: one flat line of aligned cells -- marker, name over sub line, then the icon cells (team, skill, chat,
## remove) and the state tile. A cell a seat does not use stays empty so every column lines up with the header.
func _build_table_line(box: StyleBoxFlat) -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	box.set_corner_radius_all(arcade.radius_cell_px)
	box.content_margin_top = float(arcade.space_1_px)
	box.content_margin_bottom = float(arcade.space_1_px)
	_table_box = box
	set_stripe(stripe)
	var cell: float = float(UiRowItem.metrics().row_height_px)
	_build_color_button()
	_build_text_column()
	if show_team:
		if seat_key != LobbySeats.KEY_NONE:
			layout.add_child(_make_seat_team_cycle())
		else:
			_add_spacer(cell)
	if is_bot:
		layout.add_child(_make_skill_button())
	elif align_bot_columns:
		_add_spacer(cell)
	_build_mute_slot()
	if align_bot_columns and align_remove_column:
		if is_bot and editable:
			_build_remove_button()
		else:
			_add_spacer(cell)
	_build_badge()


## Zebra: a striped row shows the token stripe colour, the others stay on the card.
func set_stripe(on: bool) -> void:
	stripe = on
	if _table_box == null:
		return
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	_table_box.bg_color = arcade.disc_700_color if on else Color.TRANSPARENT


## BOARD: a flat row inside a lane -- marker, name over sub line and the state tile; under them (only when the
## viewer may use one) the controls: the team mover painted in the DESTINATION team's colour, the skill block and
## the bot's X / a human's mute.
func _build_board_row(box: StyleBoxFlat) -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	box.bg_color = Color.TRANSPARENT
	box.set_corner_radius_all(0)
	box.border_color = arcade.disc_600_color
	box.border_width_bottom = arcade.section_rule_px
	box.content_margin_left = float(arcade.space_1_px)
	box.content_margin_right = float(arcade.space_1_px)
	var body: UiStack = UiStack.new()
	body.gap_px = arcade.space_1_px
	add_child(body)
	var top: UiBar = UiBar.new()
	top.gap_px = arcade.space_2_px
	body.add_child(top)
	layout = top
	_build_color_button()
	_build_text_column()
	_build_badge()
	var controls: UiBar = UiBar.new()
	controls.name = "BoardControls"
	controls.alignment = BoxContainer.ALIGNMENT_END
	controls.gap_px = arcade.space_1_px
	layout = controls
	if show_team and editable and seat_key != LobbySeats.KEY_NONE:
		var next_pick: int = TeamAssigner.next_pick(team_pick, maxi(team_cap, 1), false)
		var next_tint: Color = Color.TRANSPARENT
		if next_pick > MatchConfig.TEAM_PICK_RANDOM:
			next_tint = team_color_of(_layout_tuning, next_pick)
		_make_team_cycle("> %s" % team_text(next_pick), next_tint, 0.0)
		controls.add_child(team_cycle_button)
	if is_bot:
		controls.add_child(_make_skill_button())
		if editable:
			_build_remove_button()
	else:
		_build_mute_slot(false)
	layout = body
	if controls.get_child_count() > 0:
		body.add_child(controls)
	else:
		controls.free()


func _on_team_move_pressed() -> void:
	team_cycle_requested.emit(seat_key, false)


func _on_skill_pressed() -> void:
	difficulty_chosen.emit(seat_key, posmod(difficulty + 1, DIFFICULTY_LABELS.size()))


static func _color_box(color: Color, radius: int, border_px: int, border_color: Color) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	if border_px > 0:
		box.set_border_width_all(border_px)
		box.border_color = border_color
	return box


## Every control of the row gets its neighbours as explicit left / right focus targets; the ends
## point at themselves, so sideways navigation never leaves the row (a UiToggle or UiStepper
## elsewhere on the screen would otherwise catch the focus and read the next ui_right as its own).
func _wire_horizontal_focus() -> void:
	var controls: Array[Control] = focusable_controls()
	for index: int in range(controls.size()):
		var control: Control = controls[index]
		control.focus_neighbor_left = control.get_path_to(controls[maxi(index - 1, 0)])
		control.focus_neighbor_right = control.get_path_to(controls[mini(index + 1, controls.size() - 1)])


# --- Input -------------------------------------------------------------------------------

func _on_color_pressed() -> void:
	color_cycle_requested.emit(seat_key, false)


func _on_team_selected(pick: int) -> void:
	team_chosen.emit(seat_key, pick)


func _on_remove_pressed() -> void:
	remove_requested.emit(seat_key)


func _on_difficulty_selected(index: int) -> void:
	difficulty_chosen.emit(seat_key, index)


## Right click = previous colour. The matching event is consumed BEFORE the request goes
## out: handling it redraws the rows, and this control then leaves the tree. Connected to the
## control's `gui_input` signal (not _gui_input) so tests can drive it with a plain emit, like
## the timer sliders in ui/lobby/Lobby.gd. 
func _on_cycle_gui_input(event: InputEvent, kind: StringName) -> void:
	if not (event is InputEventMouseButton):
		# ui_left / ui_right (held, echoed or pad) only move focus; a click /
		# ui_accept (pressed) cycles the colour.
		return
	var click: InputEventMouseButton = event as InputEventMouseButton
	if not click.pressed or click.button_index != MOUSE_BUTTON_RIGHT:
		return
	accept_event()
	if kind == KIND_TEAM:
		team_cycle_requested.emit(seat_key, true)
		return
	if kind == KIND_DIFFICULTY:
		difficulty_chosen.emit(seat_key, posmod(difficulty - 1, DIFFICULTY_LABELS.size()))
		return
	color_cycle_requested.emit(seat_key, true)
