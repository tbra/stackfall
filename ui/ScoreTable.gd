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
	Column.GIFTS: "Gifts", Column.HEIGHT: "Height", Column.MODE_STAT: "Peak", Column.TERRITORY: "Territory",
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
	team_numbers: PackedInt32Array = PackedInt32Array()
) -> void:
	for child: Node in rows_list.get_children():
		rows_list.remove_child(child)
		child.queue_free()
	var winner_kind: String = String(results.get("winner_kind", MatchStats.WINNER_KIND_SLOT))
	var show_team: bool = winner_kind == MatchStats.WINNER_KIND_TEAM
	rows_list.add_child(build_header_row(show_team, ResultsScreen.mode_stat_header(results), tuning))
	for row: Dictionary in ResultsScreen.sorted_rows(results):
		rows_list.add_child(build_data_row(row, show_team, tuning, team_numbers, results))


## Bontago-1pi.72.1: the Team column exists only when the match played in teams
## (payload winner_kind == team); in free-for-all every slot is its own team.
static func columns(show_team: bool) -> Array[int]:
	var columns: Array[int] = [Column.PLAYER]
	if show_team:
		columns.append(Column.TEAM)
	columns.append_array([
		Column.PLACED, Column.LOST, Column.GIFTS, Column.HEIGHT, Column.MODE_STAT, Column.TERRITORY, Column.STATUS,
		Column.WINS,
	])
	return columns


static func build_header_row(show_team: bool, mode_header: String, tuning: MenuVisualTuning) -> HBoxContainer:
	var header: HBoxContainer = HBoxContainer.new()
	header.name = "HeaderRow"
	for column: int in columns(show_team):
		var header_text: String = mode_header if column == Column.MODE_STAT else String(_COLUMN_HEADERS[column])
		var cell: Label = make_cell(header_text, float(_COLUMN_RATIOS[column]))
		cell.add_theme_color_override("font_color", tuning.label_muted_color)
		header.add_child(cell)
	return header


static func build_data_row(
	row: Dictionary, show_team: bool, tuning: MenuVisualTuning, team_numbers: PackedInt32Array = PackedInt32Array(), results: Dictionary = {}
) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	var is_winner: bool = bool(row.get("is_winner", false))
	panel.set_meta(&"slot_id", int(row.get("slot_id", -1)))
	panel.set_meta(&"is_winner", is_winner)
	panel.add_theme_stylebox_override(
		"panel",
		MenuStyleFactory.make_badge(tuning.pill_mint_color if is_winner else tuning.pill_cream_color, tuning)
	)

	var box: HBoxContainer = HBoxContainer.new()
	panel.add_child(box)

	var eliminated_at: float = float(row.get("eliminated_at", MatchStats.NOT_ELIMINATED))
	# DECISION (Bontago-1pi.69): a live snapshot says "Alive", not "Survived".
	var alive_text: String = "Alive" if bool(results.get("live", false)) else "Survived"
	var status_text: String = alive_text if eliminated_at < 0.0 else "Out @ %ds" % int(round(eliminated_at))
	var territory_text: String = "%d%%" % int(round(float(row.get("territory_share", 0.0)) * 100.0))

	# DECISION (Bontago-1pi.72.1, orchestrator): one "Gifts" column showing gifts
	# USED (specials_used); gifts_claimed stays in the stats payload untouched.
	var cell_text_by_column: Dictionary = {
		Column.PLAYER: ResultsScreen.row_name_text(row),
		Column.TEAM: "Team %d" % ResultsScreen.team_number_in(team_numbers, int(row.get("team_id", 0))),
		Column.PLACED: str(int(row.get("blocks_placed", 0))),
		Column.LOST: str(int(row.get("blocks_lost", 0))),
		Column.GIFTS: str(int(row.get("specials_used", 0))),
		Column.HEIGHT: "%s m" % String.num(float(row.get("height", 0.0)), 1),
		Column.MODE_STAT: ResultsScreen.mode_stat_text(results, row),
		Column.TERRITORY: territory_text,
		Column.STATUS: status_text,
		Column.WINS: str(int(row.get("wins", 0))),
	}
	for column: int in columns(show_team):
		var cell: Label = make_cell(String(cell_text_by_column[column]), float(_COLUMN_RATIOS[column]))
		cell.add_theme_color_override("font_color", tuning.ink_color)
		box.add_child(cell)
	return panel


static func make_cell(text: String, ratio: float) -> Label:
	var cell: Label = Label.new()
	cell.text = text
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.size_flags_stretch_ratio = ratio
	cell.clip_text = true
	return cell
