extends GutTest
## Bontago-1pi.86 D1: live colour, then palette, then fallback.

const PALETTE: PackedColorArray = [Color.RED, Color.GREEN]


func test_live_color_wins_over_palette() -> void:
	assert_eq(SlotColors.resolve(0, Color.BLUE, PALETTE), Color.BLUE)


func test_palette_used_without_live_color() -> void:
	assert_eq(SlotColors.resolve(1, null, PALETTE), Color.GREEN)


func test_fallback_when_out_of_range() -> void:
	assert_eq(SlotColors.resolve(5, null, PALETTE, Color.GRAY), Color.GRAY)
	assert_eq(SlotColors.resolve(-1, null, PALETTE), Color.WHITE)
	assert_eq(SlotColors.palette_color(2, PALETTE, Color.BLACK), Color.BLACK)


func test_match_slot_color_delegates_and_falls_back() -> void:
	assert_eq(Match.slot_color(99, Color.GRAY), Color.GRAY)
	var live: PlayerSlot = Match.slot(0)
	if live != null:
		assert_eq(Match.slot_color(0, Color.GRAY), live.color)
	else:
		assert_eq(Match.slot_color(0, Color.GRAY), MatchConfig.default_player_colors()[0])
