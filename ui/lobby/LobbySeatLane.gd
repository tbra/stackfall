class_name LobbySeatLane
extends UiPlate
## One lane of the VERSUS BOARD look of the lobby players list: a field tinted with the team's colour, a cap
## filled with that colour (team name left, seat count right; none for the neutral free-for-all lanes) and the
## seats of the team under it. Look only; the seats are ordinary LobbySeatRows.

const EMPTY_TEXT: String = "No players yet"

var cap: UiPlate = null
var title_label: UiText = null
var count_label: UiText = null
var rows_box: UiStack = null


## [param title] is the cap's text ("" = no cap), [param tint] the team colour (transparent = neutral), [param seats]
## how many seats the lane holds.
func build(layout_tuning: LobbyLayoutTuning, title: String, tint: Color, seats: int) -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	name = "Lane"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	if tint.a > 0.0:
		paint(arcade.disc_800_color.lerp(tint, layout_tuning.seat_board_lane_tint_mix), arcade.radius_block_px, arcade.space_2_px, arcade.space_2_px, tint, arcade.section_rule_px)
	else:
		paint(arcade.disc_900_color, arcade.radius_block_px, arcade.space_2_px, arcade.space_2_px)
	var body: UiStack = UiStack.new()
	body.gap_px = arcade.space_2_px
	add_child(body)
	if not title.is_empty():
		_build_cap(body, arcade, title, tint, seats)
	rows_box = UiStack.new()
	rows_box.gap_px = 0
	body.add_child(rows_box)
	if seats == 0:
		var empty: UiText = UiText.make(UiText.Role.CAPTION, EMPTY_TEXT, arcade.dust_color)
		empty.name = "EmptyNote"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rows_box.add_child(empty)


func add_row(row: Control) -> void:
	rows_box.add_child(row)


func _build_cap(body: Container, arcade: ArcadeVisualTuning, title: String, tint: Color, seats: int) -> void:
	cap = UiPlate.new()
	cap.name = "LaneCap"
	var face: Color = tint if tint.a > 0.0 else arcade.disc_500_color
	cap.paint(face, arcade.radius_chip_px, arcade.space_2_px, arcade.space_1_px)
	var line: UiBar = UiBar.new()
	cap.add_child(line)
	title_label = UiText.make(UiText.Role.CAPTION, title.to_upper())
	title_label.set_face(face)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.clip_text = true
	line.add_child(title_label)
	count_label = UiText.make(UiText.Role.CAPTION, "%d" % seats)
	count_label.set_face(face)
	line.add_child(count_label)
	body.add_child(cap)
