extends GutTest
## Bontago-1pi.11.77.3 (S2b): LateScripts path table and the activation hook.

const SOURCE_PATH: String = "res://autoload/LateScripts.gd"
const FORBIDDEN_TOKENS: PackedStringArray = [
		"preload(", "Match.", "Net.", "Events.", "MatchFeed.", "CatController.", "BlockFactory.",
		"SpecialDef.", "HoneyCoat.", "WeatherNet.",
]


class ActivationProbe:
	extends Node
	var calls: int = 0

	func late_activate() -> void:
		calls += 1


func test_every_path_loads() -> void:
	for path: String in LateScripts.paths():
		assert_not_null(load(path), "loads %s" % path)


func test_paths_cover_every_string_const_path() -> void:
	var paths: PackedStringArray = LateScripts.paths()
	var script: GDScript = load(SOURCE_PATH) as GDScript
	var consts: Dictionary = script.get_script_constant_map()
	var found: int = 0
	for key: String in consts:
		var value: Variant = consts[key]
		if value is String and (value as String).begins_with("res://"):
			if (value as String) == LateScripts.BOOT_SCRIPT_PATH:
				continue
			found += 1
			assert_true(paths.has(value), "paths() lists %s" % key)
	assert_eq(found, paths.size(), "no duplicate or extra entries")


func test_source_names_no_class() -> void:
	var text: String = FileAccess.get_file_as_string(SOURCE_PATH)
	for line: String in text.split("\n"):
		var code: String = line.strip_edges()
		if code.begins_with("#") or code.begins_with("##") or code.begins_with("const ") or code.begins_with("class_name"):
			continue
		for token: String in FORBIDDEN_TOKENS:
			assert_false(code.contains(token), "no class reference %s in: %s" % [token, code])


func test_boot_defers_false_headless() -> void:
	assert_false(LateScripts.boot_defers_activation(get_tree()), "headless never defers")
	assert_false(LateScripts.boot_defers_activation(null), "no tree never defers")


func test_activate_autoloads_calls_late_activate_on_root_children() -> void:
	var probe: ActivationProbe = ActivationProbe.new()
	get_tree().root.add_child(probe)
	LateScripts.activate_autoloads(get_tree())
	assert_eq(probe.calls, 1)
	probe.queue_free()
