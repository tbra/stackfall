extends GutTest
## Every shape has a distinct player-facing name and the map has a name and a blurb.


func test_every_shape_has_a_non_empty_distinct_display_name() -> void:
	var seen: Dictionary = {}
	for shape: BlockShape in BlockShape.load_all_shapes():
		assert_ne(shape.display_name, "", "%s has no display_name" % shape.id)
		assert_false(seen.has(shape.display_name), "duplicate name %s" % shape.display_name)
		seen[shape.display_name] = true
		assert_eq(DisplayNames.shape(shape.id), shape.display_name)


func test_unknown_shape_falls_back_to_capitalised_id() -> void:
	assert_eq(DisplayNames.shape(&"mystery_block"), "Mystery Block")


func test_every_map_has_a_name_and_blurb() -> void:
	var dir: DirAccess = DirAccess.open("res://config/match/maps/")
	assert_not_null(dir)
	var found: int = 0
	for file_name: String in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var map: MapDef = load("res://config/match/maps/" + file_name) as MapDef
		assert_not_null(map)
		assert_ne(map.display_name, "", file_name)
		assert_ne(map.blurb, "", file_name)
		found += 1
	assert_gt(found, 0)
