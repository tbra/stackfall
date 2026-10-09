extends GutTest
## Bontago-1pi.86 concept M: labels never empty, tables line up with the enums.


func test_mode_labels_and_tips_cover_every_mode() -> void:
	for mode_id: int in range(MatchConfig.GAME_MODE_LABELS.size()):
		assert_eq(DisplayNames.mode(mode_id), MatchConfig.GAME_MODE_LABELS[mode_id])
		assert_ne(DisplayNames.mode_tip(mode_id), DisplayNames.UNKNOWN_LABEL)
	assert_eq(DisplayNames.MODE_TIPS.size(), MatchConfig.GAME_MODE_LABELS.size())
	assert_eq(DisplayNames.mode(99), DisplayNames.UNKNOWN_LABEL)


func test_sky_weather_map_labels() -> void:
	assert_eq(DisplayNames.SKY_THEME_LABELS.size(), MatchConfig.SkyThemeMode.size())
	assert_eq(DisplayNames.sky_theme(MatchConfig.SkyThemeMode.DAY), "Sunset")
	assert_eq(DisplayNames.sky_theme(-1), DisplayNames.UNKNOWN_LABEL)
	assert_eq(DisplayNames.weather(MatchConfig.WeatherMode.STORM), "Storm")
	assert_eq(DisplayNames.map_variant(MatchConfig.MapVariant.ROUND), "Round")
	assert_eq(DisplayNames.map_size(MapDef.MapSize.MEDIUM), "Medium")
	assert_eq(DisplayNames.map_size(42), DisplayNames.UNKNOWN_LABEL)


func test_special_names() -> void:
	assert_eq(DisplayNames.special(&"jumping_bean"), "Jumping Bean")
	assert_eq(DisplayNames.special(MatchGifts.PENDING_SPECIAL_ID), "Special")
	assert_eq(DisplayNames.special(&"not_a_gift"), "Not A Gift")
	assert_eq(DisplayNames.special(&""), DisplayNames.special(MatchGifts.PENDING_SPECIAL_ID))


func test_weather_key_and_id_label() -> void:
	assert_eq(DisplayNames.weather_key(MatchConfig.WeatherMode.STORM), &"storm")
	assert_eq(DisplayNames.weather_key(-1), &"")
	assert_eq(DisplayNames.weather_key(999), &"")
	assert_eq(DisplayNames.weather_id_label(&"storm"), "Storm")
