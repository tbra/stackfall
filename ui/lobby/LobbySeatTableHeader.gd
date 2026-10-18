class_name LobbySeatTableHeader
extends UiPlate
## The icon header of the TABLE look of the lobby players list: "PLAYER" over the name column and one icon over
## each cell column (team, skill, chat), on the same cell widths and gaps as LobbySeatRow's table line so every
## column lines up. Look only.

var player_label: UiText = null
var line: Container = null


## Shows a column icon only for the columns the rows carry: [param team] (teams on), [param skill] (a bot is
## seated), [param chat] (a chatting session), [param remove] (the host's X column).
func build(layout_tuning: LobbyLayoutTuning, team: bool, skill: bool, chat: bool, remove: bool) -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	name = "TableHeader"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paint(Color.TRANSPARENT, 0, arcade.space_3_px, arcade.space_1_px, arcade.disc_600_color, 0, arcade.section_rule_px)
	var bar: UiBar = UiBar.new()
	bar.gap_px = arcade.space_2_px
	line = bar
	add_child(line)
	var marker_gap: Control = Control.new()
	marker_gap.custom_minimum_size = Vector2(layout_tuning.color_box_size_px.x, 0.0)
	marker_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(marker_gap)
	player_label = UiText.make(UiText.Role.CAPTION, "PLAYER")
	player_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(player_label)
	var art: UiArtTable = UiArtTable.shared()
	if team:
		_add_cell(art.lobby_icon(UiArtTable.KEY_TEAMS), arcade)
	if skill:
		_add_cell(art.difficulty_icon(MatchConfig.AiDifficulty.NORMAL), arcade)
	if chat:
		_add_cell(LobbySeatRow.SPEAKER_ON_ICON, arcade)
	if remove:
		_add_cell(null, arcade)
	_add_cell(null, arcade, LobbySeatRow.state_cell_width())


## One column cell of the row-item width (or [param width]); empty without an icon.
func _add_cell(icon: Texture2D, arcade: ArcadeVisualTuning, width: float = -1.0) -> void:
	var cell: CenterContainer = CenterContainer.new()
	cell.custom_minimum_size.x = width if width > 0.0 else float(UiRowItem.metrics().row_height_px)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if icon != null:
		var glyph: TextureRect = TextureRect.new()
		glyph.texture = icon
		glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		glyph.custom_minimum_size = Vector2.ONE * float(UiArtTable.shared().lobby_icon_px)
		glyph.modulate = arcade.dust_color
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(glyph)
	line.add_child(cell)
