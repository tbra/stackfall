extends GutTest
## Single-source guard: MatchConfig.MapVariant is MapDef.MapShape, and the sky
## theme ids are owned by MatchConfig. Stored ints/ids must never change.


func test_map_variant_ordinals_pinned() -> void:
	assert_eq(MatchConfig.MapVariant.ROUND, 0)
	assert_eq(MatchConfig.MapVariant.OVAL, 1)
	assert_eq(MatchConfig.MapVariant.RING, 2)
	assert_eq(MatchConfig.MapVariant.TWIN, 3)
	assert_eq(MatchConfig.MapVariant.CROSS, 4)
	assert_eq(MatchConfig.MapVariant.keys(), ["ROUND", "OVAL", "RING", "TWIN", "CROSS"])


func test_map_variant_matches_map_shape() -> void:
	assert_eq(MatchConfig.MapVariant.keys(), MapDef.MapShape.keys())
	assert_eq(MatchConfig.MapVariant.values(), MapDef.MapShape.values())


func test_shape_ids_and_paths_pinned() -> void:
	var ids: Array[String] = ["round", "oval", "ring", "twin", "cross"]
	for i: int in range(ids.size()):
		assert_eq(MapDef.shape_id(i), ids[i])
	assert_eq(MapDef.shape_id(5), "")
	assert_eq(MapDef.shape_id(-1), "")
	assert_eq(MapDef.variant_resource_path(MatchConfig.MapVariant.RING, MapDef.MapSize.SMALL), "res://config/maps/ring_small.tres")


func test_loading_backdrop_ids_follow_map_shape() -> void:
	var tuning: LoadingScreenTuning = LoadingScreenTuning.new()
	for i: int in range(MapDef.MapShape.size()):
		assert_true(tuning.backdrop_path(i, "sunset").contains("/%s_sunset" % MapDef.shape_id(i)))


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
