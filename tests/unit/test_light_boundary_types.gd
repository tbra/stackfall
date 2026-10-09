extends GutTest
## Autoload decoupling S2a: BlockBody, GiftWirePhase and ResultsValidation are
## light boundary types. They may name only core/, config/ and game/world/
## classes, and the heavy scripts that moved onto them behave as before.

const LIGHT_FILES: Array[String] = [
	"res://game/world/BlockBody.gd",
	"res://core/gifts/GiftWirePhase.gd",
	"res://core/rules/ResultsValidation.gd",
]
const ALLOWED_DIRS: Array[String] = ["res://core/", "res://config/", "res://game/world/"]
const SCAN_ROOTS: Array[String] = ["res://core", "res://config", "res://game", "res://autoload", "res://net", "res://ui", "res://vfx"]
const BLOCK_SCENE: PackedScene = preload("res://game/Block.tscn")


func _strip(source: String) -> String:
	var kept: PackedStringArray = []
	for line: String in source.split("\n"):
		var cut: int = line.find("#")
		kept.append(line if cut < 0 else line.substr(0, cut))
	return "\n".join(kept)


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


func test_light_files_name_no_heavy_class() -> void:
	var classes: Dictionary = {}
	for root: String in SCAN_ROOTS:
		_collect_class_names(root, classes)
	for path: String in LIGHT_FILES:
		var source: String = _strip(FileAccess.get_file_as_string(path))
		assert_false(source.is_empty(), "%s readable" % path)
		for class_id: String in classes:
			var defined_in: String = classes[class_id]
			if defined_in == path:
				continue
			var allowed: bool = false
			for dir_path: String in ALLOWED_DIRS:
				allowed = allowed or defined_in.begins_with(dir_path)
			if allowed:
				continue
			var regex: RegEx = RegEx.create_from_string("\b%s\b" % class_id)
			assert_null(regex.search(source), "%s must not name %s (%s)" % [path, class_id, defined_in])


func test_block_is_a_block_body_and_moved_exports_load() -> void:
	var block: Block = BLOCK_SCENE.instantiate() as Block
	assert_not_null(block)
	assert_true(block is BlockBody)
	assert_eq(block.net_id, -1)
	assert_eq(block.owner_slot, -1)
	assert_eq(block.gift_id, &"")
	var names: PackedStringArray = []
	for prop: Dictionary in block.get_property_list():
		names.append(String(prop["name"]))
	for exported: String in ["shape_id", "owner_slot", "net_id", "cube_count"]:
		assert_true(names.has(exported), exported)
	block.free()


func test_audio_statics_live_on_block_body() -> void:
	var speed: float = BlockBody.impact_speed_min
	var enabled: bool = BlockBody.impacts_enabled
	Block.impact_speed_min = 3.5
	Block.impacts_enabled = false
	assert_eq(BlockBody.impact_speed_min, 3.5)
	assert_false(BlockBody.impacts_enabled)
	BlockBody.impact_speed_min = speed
	BlockBody.impacts_enabled = enabled


func test_block_overrides_every_stub() -> void:
	var block: Block = BLOCK_SCENE.instantiate() as Block
	var body: BlockBody = block
	body.set_frozen_visual(true)
	assert_true(body.is_frozen_visual(), "Block override reached through the base type")
	body.request_freeze_static(&"t")
	assert_true(body.is_freeze_static())
	body.release_freeze_static(&"t")
	assert_false(body.is_freeze_static())
	block.free()


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
	assert_eq(ResultsValidation.validate_mode_state(state), ModeObjective.validate_state(state))
	assert_false(ResultsValidation.validate_mode_state(state).is_empty())
	assert_true(ResultsValidation.validate_mode_state("nope").is_empty())
	assert_true(ResultsValidation.validate_mode_state({"mode_id": 99}).is_empty())
	assert_eq(ResultsValidation.clean_scores([1, "x"]), [null])
	assert_null(ResultsValidation.clean_scalars({"k": Vector2.ZERO}))
	assert_eq(ResultsValidation.validate_results_payload("x"), MatchStats.validate_results_payload("x"))
