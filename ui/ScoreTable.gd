class_name ScoreTable
extends RefCounted
## Bontago-1pi.69: the stats table shared by ui/ResultsScreen.gd (end of round)
## and ui/ScoreboardOverlay.gd (hold-to-show, live round). Extracted from the
## results screen unchanged so both render the same columns from the same
## payload shape (autoload/match/MatchStats.gd: results/live payload).

## Column ids; columns() picks which are shown. Headers and ratios live beside
## the id so header and data cells can never drift apart.
enum Column { PLAYER, TEAM, PLACED, LOST, GIFTS, HEIGHT, MODE_STAT, TERRITORY, STATUS, WINS }
const _COLUMN_HEADERS: Dictionary = {
	Column.PLAYER: "Player", Column.TEAM: "Team", Column.PLACED: "Placed", Column.LOST: "Lost",
	Column.GIFTS: "Gifts", Column.HEIGHT: "Height", Column.MODE_STAT: "Points", Column.TERRITORY: "Territory",
	Column.STATUS: "Status", Column.WINS: "Wins",
}
## _make_cell()'s size_flags_stretch_ratio per column.
const _COLUMN_RATIOS: Dictionary = {
	Column.PLAYER: 3.0, Column.TEAM: 1.4, Column.PLACED: 1.0, Column.LOST: 1.0,
	Column.GIFTS: 1.0, Column.HEIGHT: 1.1, Column.MODE_STAT: 1.2, Column.TERRITORY: 1.2, Column.STATUS: 1.6,
	Column.WINS: 0.9,
}


## Replaces `rows_list`'s children with a header row plus one row per player.
static func populate(
	rows_list: VBoxContainer, results: Dictionary, tuning: MenuVisualTuning,
	team_numbers: PackedInt32Array = PackedInt32Array(), match_provider: Variant = null
) -> void:
	for child: Node in rows_list.get_children():
		rows_list.remove_child(child)
		child.queue_free()
	var winner_kind: String = ResultsPayload.winner_kind(results)
	var show_team: bool = winner_kind == ResultsPayload.WINNER_KIND_TEAM
	var show_mode_stat: bool = ResultsScreen.has_mode_stat(results)
	rows_list.add_child(build_header_row(show_team, ResultsScreen.mode_stat_header(results), tuning, show_mode_stat))
	for row: Dictionary in ResultsScreen.sorted_rows(results):
		rows_list.add_child(build_data_row(row, show_team, tuning, team_numbers, results, match_provider, show_mode_stat))


## Bontago-1pi.72.1: the Team column exists only when the match played in teams
## (payload winner_kind == team); in free-for-all every slot is its own team.
## Bontago-1pi.82: the mode column (CTF points, Reach the Sky team best) exists only
## for modes that have a score of their own; the old "Peak %" column is gone.
static func columns(show_team: bool, show_mode_stat: bool = false) -> Array[int]:
	var columns: Array[int] = [Column.PLAYER]
	if show_team:
		columns.append(Column.TEAM)
	columns.append_array([
		Column.PLACED, Column.LOST, Column.GIFTS, Column.HEIGHT,
	])
	if show_mode_stat:
		columns.append(Column.MODE_STAT)
	columns.append_array([Column.TERRITORY, Column.STATUS, Column.WINS])
	return columns


## Columns whose cells are numbers: right-aligned so digits line up (tabular).
const _NUMERIC_COLUMNS: Array[int] = [
	Column.PLACED, Column.LOST, Column.GIFTS, Column.HEIGHT, Column.MODE_STAT, Column.TERRITORY, Column.WINS,
]
## Columns drawn in the Bungee display face (the headline numbers of a row).
const _DISPLAY_COLUMNS: Array[int] = [Column.TERRITORY]

static var _table_tuning: ResultsTableTuning = null


## The shared Arcade table numbers (config/results_table_tuning.tres).
static func table_tuning() -> ResultsTableTuning:
	if _table_tuning == null:
		_table_tuning = load("res://config/results_table_tuning.tres") as ResultsTableTuning
	return _table_tuning


static func build_header_row(show_team: bool, mode_header: String, _tuning: MenuVisualTuning, show_mode_stat: bool = false) -> HBoxContainer:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var look: ResultsTableTuning = table_tuning()
	var header: HBoxContainer = HBoxContainer.new()
	header.name = "HeaderRow"
	# Same side padding as a data row so header and data columns line up.
	header.add_theme_constant_override("separation", 0)
	for column: int in columns(show_team, show_mode_stat):
		var header_text: String = mode_header if column == Column.MODE_STAT else String(_COLUMN_HEADERS[column])
		var cell: Label = make_cell(header_text, float(_COLUMN_RATIOS[column]))
		cell.theme_type_variation = &"CaptionLabel"
		cell.add_theme_color_override("font_color", arcade.dust_color)
		cell.add_theme_font_size_override("font_size", arcade.font_size_label_px)
		if _NUMERIC_COLUMNS.has(column):
			cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var pad: StyleBoxEmpty = StyleBoxEmpty.new()
		pad.content_margin_left = float(look.row_pad_x_px) + look.marker_size_px + float(look.marker_gap_px) if column == Column.PLAYER else float(arcade.space_4_px)
		pad.content_margin_right = float(look.row_pad_x_px) if column == Column.WINS else 0.0
		cell.add_theme_stylebox_override("normal", pad)
		header.add_child(cell)
	return header


static func build_data_row(
	row: Dictionary, show_team: bool, tuning: MenuVisualTuning, team_numbers: PackedInt32Array = PackedInt32Array(), results: Dictionary = {}, match_provider: Variant = null,
	show_mode_stat: bool = false
) -> PanelContainer:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var look: ResultsTableTuning = table_tuning()
	var panel: PanelContainer = PanelContainer.new()
	var is_winner: bool = ResultsPayload.bool_of(row, ResultsPayload.KEY_IS_WINNER)
	panel.set_meta(&"slot_id", ResultsPayload.int_of(row, ResultsPayload.KEY_SLOT_ID, -1))
	panel.set_meta(&"is_winner", is_winner)
	panel.add_theme_stylebox_override("panel", row_style(is_winner))

	var box: HBoxContainer = HBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	panel.add_child(box)

	var eliminated_at: float = ResultsPayload.float_of(row, ResultsPayload.KEY_ELIMINATED_AT, ResultsPayload.NOT_ELIMINATED)
	# DECISION (Bontago-1pi.69): a live snapshot says "Alive", not "Survived".
	var alive_text: String = "Alive" if ResultsPayload.is_live(results) else "Survived"
	var status_text: String = alive_text if eliminated_at < 0.0 else "Out @ %ds" % int(round(eliminated_at))
	var territory_text: String = "%d%%" % int(round(ResultsPayload.float_of(row, ResultsPayload.KEY_TERRITORY_SHARE) * 100.0))

	# DECISION (Bontago-1pi.72.1, orchestrator): one "Gifts" column showing gifts
	# USED (specials_used); gifts_claimed stays in the stats payload untouched.
	var cell_text_by_column: Dictionary = {
		Column.PLAYER: ResultsScreen.row_name_text(row),
		Column.TEAM: PlayerNames.team_label(ResultsScreen.team_number_in(team_numbers, ResultsPayload.int_of(row, ResultsPayload.KEY_TEAM_ID))),
		Column.PLACED: str(ResultsPayload.int_of(row, ResultsPayload.KEY_BLOCKS_PLACED)),
		Column.LOST: str(ResultsPayload.int_of(row, ResultsPayload.KEY_BLOCKS_LOST)),
		Column.GIFTS: str(ResultsPayload.int_of(row, ResultsPayload.KEY_SPECIALS_USED)),
		Column.HEIGHT: "%s m" % String.num(ResultsPayload.float_of(row, ResultsPayload.KEY_HEIGHT), 1),
		Column.MODE_STAT: ResultsScreen.mode_stat_text(results, row),
		Column.TERRITORY: territory_text,
		Column.STATUS: status_text,
		Column.WINS: str(ResultsPayload.int_of(row, ResultsPayload.KEY_WINS)),
	}
	for column: int in columns(show_team, show_mode_stat):
		var cell: Label = make_cell(String(cell_text_by_column[column]), float(_COLUMN_RATIOS[column]))
		var primary: bool = column == Column.PLAYER or column == Column.TERRITORY
		cell.add_theme_color_override("font_color", arcade.cream_color if primary else arcade.sand_color)
		if _NUMERIC_COLUMNS.has(column):
			cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if _DISPLAY_COLUMNS.has(column):
			cell.theme_type_variation = &"DisplayLabel"
			cell.add_theme_font_size_override("font_size", look.number_font_size_px)
		if column == Column.PLAYER:
			_mark_with_slot_colour(cell, slot_color(ResultsPayload.int_of(row, ResultsPayload.KEY_SLOT_ID, -1), match_provider), tuning)
		else:
			# Columns breathe: a gap before every non-name cell so a right-aligned number never touches the next column.
			var gap: StyleBoxEmpty = StyleBoxEmpty.new()
			gap.content_margin_left = float(arcade.space_4_px)
			cell.add_theme_stylebox_override("normal", gap)
		box.add_child(cell)
	return panel


## A table row face: a disc-700 strip (radius-block); a winner is tinted toward rim with a
## winner_edge_px rim edge on its left.
static func row_style(is_winner: bool) -> StyleBoxFlat:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var look: ResultsTableTuning = table_tuning()
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = arcade.disc_700_color.lerp(arcade.rim_color, look.winner_tint_mix) if is_winner else arcade.disc_700_color
	box.set_corner_radius_all(arcade.radius_block_px)
	if is_winner:
		box.border_width_left = look.winner_edge_px
		box.border_color = arcade.rim_color
	box.content_margin_left = float(look.row_pad_x_px)
	box.content_margin_right = float(look.row_pad_x_px)
	box.content_margin_top = float(look.row_pad_y_px)
	box.content_margin_bottom = float(look.row_pad_y_px)
	return box


## Bontago-1pi.78: the HUD's colour source (ui/HUD.gd _color_for_slot): the live
## PlayerSlot.color from Match, else MatchConfig's default palette. `match_provider`
## is a test seam; null means the Match autoload when it exists.
static func slot_color(slot_id: int, match_provider: Variant = null) -> Color:
	var provider: Variant = match_provider
	if provider == null:
		var loop: MainLoop = Engine.get_main_loop()
		if loop is SceneTree:
			provider = (loop as SceneTree).root.get_node_or_null("Match")
	if provider == null:
		return SlotColors.resolve(slot_id, null, MatchConfig.new().player_colors)
	if provider.has_method(&"slot_color"):
		return provider.slot_color(slot_id) as Color
	var slot: PlayerSlot = provider.slot(slot_id) as PlayerSlot
	var config: MatchConfig = provider.config as MatchConfig
	var palette: PackedColorArray = config.player_colors if config != null else MatchConfig.new().player_colors
	return SlotColors.resolve(slot_id, slot.color if slot != null else null, palette)


## Bontago-1pi.81: the shared SlotDiamond (ui/SlotDiamond.tscn) at the left of the name
## cell, which stays a plain Label whose left margin leaves room for it.
static func _mark_with_slot_colour(cell: Label, color: Color, _tuning: MenuVisualTuning) -> void:
	var diamond: SlotDiamond = SlotDiamond.create(color, table_tuning().marker_size_px)
	diamond.name = "SlotDiamond"
	var edge: float = diamond.diamond_size_px()
	diamond.anchor_top = 0.5
	diamond.anchor_bottom = 0.5
	diamond.offset_left = 0.0
	diamond.offset_right = edge
	diamond.offset_top = -edge * 0.5
	diamond.offset_bottom = edge * 0.5
	cell.add_child(diamond)
	var gutter: StyleBoxEmpty = StyleBoxEmpty.new()
	gutter.content_margin_left = edge + float(table_tuning().marker_gap_px)
	cell.add_theme_stylebox_override("normal", gutter)
	cell.set_meta(&"slot_color", color)


static func make_cell(text: String, ratio: float) -> Label:
	var cell: Label = Label.new()
	cell.text = text
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.size_flags_stretch_ratio = ratio
	cell.clip_text = true
	return cell
