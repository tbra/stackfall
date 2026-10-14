extends GutTest
## Single-source guard: the sky theme ids are owned by MatchConfig. Stored ints/ids must never change.


func test_sky_theme_ids_pinned() -> void:
	assert_eq(MatchConfig.SKY_THEME_IDS, PackedStringArray(["sunset", "night", "dawn"]))
	assert_eq(MatchConfig.SkyThemeMode.DAY, 0)
	assert_eq(MatchConfig.SkyThemeMode.NIGHT, 1)
	assert_eq(MatchConfig.SkyThemeMode.RANDOM, 2)
	assert_eq(MatchConfig.SkyThemeMode.CYCLE, 3)
	assert_eq(MatchConfig.SkyThemeMode.DAWN, 4)


func test_every_sky_id_has_a_locked_phase() -> void:
	var def: SkyThemeDef = SkyThemeDef.new()
	for id: String in MatchConfig.SKY_THEME_IDS:
		assert_ne(def.locked_phase_for(id), -1.0, id)
	assert_eq(def.locked_phase_for(""), -1.0)
