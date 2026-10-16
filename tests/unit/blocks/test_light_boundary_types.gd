extends GutTest
## Autoload decoupling S2a: BlockBody, GiftWirePhase and ResultsValidation are
## light boundary types. They may name only core/, config/ and game/world/
## classes, and the heavy scripts that moved onto them behave as before.

const LIGHT_FILES: Array[String] = [
	"res://game/world/BlockBody.gd",
	"res://core/gifts/GiftWirePhase.gd",
	"res://core/rules/ResultsValidation.gd",
]


func _collect_class_names(dir_path: String, out: Dictionary) -> void:
	for file_name: String in DirAccess.get_files_at(dir_path):
		if not file_name.ends_with(".gd"):
			continue
		var path: String = dir_path.path_join(file_name)
		for line: String in FileAccess.get_file_as_string(path).split("\n"):
			if line.begins_with("class_name "):
				out[line.substr(11).strip_edges().get_slice(" ", 0)] = path
				break
	for sub: String in DirAccess.get_directories_at(dir_path):
		_collect_class_names(dir_path.path_join(sub), out)


func test_gift_wire_phase_numbering_and_reexport() -> void:
	assert_eq(MatchGifts.FALLING, GiftWirePhase.FALLING)
	assert_eq(MatchGifts.LANDED, GiftWirePhase.LANDED)
	assert_eq(MatchGifts.WIRE_LEGACY, GiftWirePhase.WIRE_LEGACY)
	assert_eq(MatchGifts.WIRE_REMOVED, GiftWirePhase.WIRE_REMOVED)
	assert_true(GiftWirePhase.is_valid_wire_phase(GiftWirePhase.WIRE_REMOVED))
	assert_false(GiftWirePhase.is_valid_wire_phase(-1))
	assert_false(GiftWirePhase.is_valid_wire_phase(GiftWirePhase.WIRE_REMOVED + 1))


func test_validation_forwards_agree() -> void:
	var state: Dictionary = {"mode_id": MatchConfig.GameMode.ELIMINATION, "scores": [1, 2.5], "extra": {"a": 1}, "round_left": 3.0}
	assert_false(ResultsValidation.validate_mode_state(state).is_empty())
	assert_true(ResultsValidation.validate_mode_state("nope").is_empty())
	assert_true(ResultsValidation.validate_mode_state({"mode_id": 99}).is_empty())
	assert_eq(ResultsValidation.clean_scores([1, "x"]), [null])
	assert_null(ResultsValidation.clean_scalars({"k": Vector2.ZERO}))
