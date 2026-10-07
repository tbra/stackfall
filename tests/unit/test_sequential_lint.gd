extends GutTest
## SEQUENTIAL_PREDICATE lint (Bontago-fca.36.11): the project is clean of hand-written
## hot_seat/turn_based pairs outside MatchConfig.


func test_no_hand_written_pair_in_game_code() -> void:
	var offenders: PackedStringArray = PackedStringArray()
	for dir: String in ["autoload", "net", "game", "ui"]:
		_scan("res://" + dir, offenders)
	assert_eq(offenders.size(), 0, "use MatchConfig.is_sequential_play(): %s" % [offenders])


func _scan(path: String, offenders: PackedStringArray) -> void:
	for sub: String in DirAccess.get_directories_at(path):
		_scan(path + "/" + sub, offenders)
	var pair: RegEx = RegEx.create_from_string(
		"\bhot_seat\b\s+(?:or|and)\s+(?:not\s+)?\w*\.?turn_based\b|\bturn_based\b\s+(?:or|and)\s+(?:not\s+)?\w*\.?hot_seat\b")
	for file: String in DirAccess.get_files_at(path):
		if not file.ends_with(".gd"):
			continue
		var text: String = FileAccess.get_file_as_string(path + "/" + file)
		if pair.search(text) != null:
			offenders.append(path + "/" + file)
