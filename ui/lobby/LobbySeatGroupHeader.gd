class_name LobbySeatGroupHeader
extends HBoxContainer
## The rule above one team's seats in the TEAM GROUPS look of the lobby players list
## : a band of the team colour on the left, the group name in caps and the
## seat count on the right. Look only; the seats below it are ordinary LobbySeatRows.

var band: ColorRect = null
var label: UiText = null
var count_label: UiText = null


## [param title] is the group name ("Team 1", "Free for all"), [param tint] the band colour
## (transparent = neutral), [param seats] how many seats the group holds.
func build(layout_tuning: LobbyLayoutTuning, title: String, tint: Color, seats: int) -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	name = "GroupHeader"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	band = ColorRect.new()
	band.color = tint if tint.a > 0.0 else arcade.disc_500_color
	band.custom_minimum_size = Vector2(float(layout_tuning.seat_team_band_px), 0.0)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)
	label = UiText.make(UiText.Role.CAPTION, title.to_upper(), arcade.cream_color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(label)
	count_label = UiText.make(UiText.Role.CAPTION, "%d %s" % [seats, "seat" if seats == 1 else "seats"])
	add_child(count_label)
