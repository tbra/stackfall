extends GutTest
## game/main/TuningOverrides.gd: the persisted F4 resource list (SECTIONS), the save/apply
## round trip, the Copy text, reset and the exported-field predicate. The save file is the
## per-PID GUT path (TuningOverrides.save_path()), never the owner's real overrides file.
## The tuning resources are process-wide singletons, so every field a test touches is
## snapshotted in before_each and restored in after_each.

var _snapshots: Dictionary = {}


func before_each() -> void:
	_remove_save_file()
	_snapshots.clear()
	for label: String in TuningOverrides.SECTIONS:
		_snapshots[label] = _field_values(_live(label))


func after_each() -> void:
	for label: String in _snapshots:
		var resource: Resource = _live(label)
		var values: Dictionary = _snapshots[label]
		for key: String in values:
			resource.set(key, values[key])
	_remove_save_file()


func _remove_save_file() -> void:
	var path: String = TuningOverrides.save_path()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _live(label: String) -> Resource:
	return load(TuningOverrides.SECTIONS[label] as String) as Resource


## name -> value of every exported field of the resource.
func _field_values(resource: Resource) -> Dictionary:
	var values: Dictionary = {}
	for prop: Dictionary in resource.get_property_list():
		if TuningOverrides.is_exported_field(prop):
			var prop_name: String = str(prop.get("name", ""))
			values[prop_name] = resource.get(prop_name)
	return values


## First exported field of `resource` with the given Variant type, or "" when none.
func _first_field_of(resource: Resource, type: int) -> String:
	for prop: Dictionary in resource.get_property_list():
		if TuningOverrides.is_exported_field(prop) and int(prop.get("type", TYPE_NIL)) == type:
			return str(prop.get("name", ""))
	return ""


## [label, field] of the first exported field of `type` in any SECTIONS resource.
func _find_field(type: int) -> Array[String]:
	for label: String in TuningOverrides.SECTIONS:
		var field: String = _first_field_of(_live(label), type)
		if field != "":
			return [label, field]
	return []


## Moves the first float, int, bool or String field of the resource and returns its name ("" when it has neither).
func _bump(resource: Resource) -> String:
	var field: String = _first_field_of(resource, TYPE_FLOAT)
	if field != "":
		resource.set(field, float(resource.get(field)) + 3.0)
		return field
	field = _first_field_of(resource, TYPE_INT)
	if field != "":
		resource.set(field, int(resource.get(field)) + 3)
		return field
	field = _first_field_of(resource, TYPE_BOOL)
	if field != "":
		resource.set(field, not bool(resource.get(field)))
		return field
	field = _first_field_of(resource, TYPE_STRING)
	if field != "":
		resource.set(field, str(resource.get(field)) + "_changed")
	return field


## Label -> an independent copy of each live resource (so Copy tests never touch the singletons).
func _copies() -> Dictionary:
	var copies: Dictionary = {}
	for label: String in TuningOverrides.SECTIONS:
		copies[label] = _live(label).duplicate()
	return copies


## The lines of one "# Label" block of copy_text output (empty when absent).
func _block_lines(text: String, label: String) -> PackedStringArray:
	for block: String in text.split("\n\n"):
		var lines: PackedStringArray = block.split("\n")
		if lines.size() > 0 and lines[0] == "# %s" % label:
			return lines
	return PackedStringArray()


## (a) every listed path is a real Resource.
func test_every_section_path_loads_a_resource() -> void:
	assert_eq(TuningOverrides.SECTIONS.size(), 8, "eight persisted resources")
	assert_true(TuningOverrides.SECTIONS.has("ArenaSideStyle"), "ArenaSideStyle is persisted")
	for label: String in TuningOverrides.SECTIONS:
		assert_not_null(_live(label), "%s loads" % label)


## (b) write_sections, mutate, apply_saved restores every section.
func test_write_then_apply_restores_every_section() -> void:
	var config: ConfigFile = ConfigFile.new()
	var instances: Dictionary = {}
	for label: String in TuningOverrides.SECTIONS:
		instances[label] = _live(label)
	TuningOverrides.write_sections(config, instances)
	assert_eq(config.save(TuningOverrides.save_path()), OK)
	var mutated: Dictionary = {}
	for label: String in TuningOverrides.SECTIONS:
		var resource: Resource = _live(label)
		var field: String = _bump(resource)
		assert_ne(field, "", "%s has a numeric field to mutate" % label)
		mutated[label] = field
	TuningOverrides.apply_saved()
	for label: String in TuningOverrides.SECTIONS:
		var field: String = mutated[label]
		assert_eq(_live(label).get(field), (_snapshots[label] as Dictionary)[field], "%s.%s restored" % [label, field])


func test_arena_side_style_round_trips_a_changed_value() -> void:
	var style: Resource = _live("ArenaSideStyle")
	var field: String = _first_field_of(style, TYPE_FLOAT)
	var original: float = float(style.get(field))
	style.set(field, original + 2.0)
	var config: ConfigFile = ConfigFile.new()
	TuningOverrides.write_sections(config, {"ArenaSideStyle": style})
	assert_true(config.has_section("ArenaSideStyle"), "section written")
	assert_eq(float(config.get_value("ArenaSideStyle", field, -1.0)), original + 2.0)
	config.save(TuningOverrides.save_path())
	style.set(field, original)
	TuningOverrides.apply_saved()
	assert_eq(float(style.get(field)), original + 2.0, "apply_saved restores the saved value")


func test_write_sections_skips_labels_not_in_instances() -> void:
	var config: ConfigFile = ConfigFile.new()
	TuningOverrides.write_sections(config, {"CameraTuning": _live("CameraTuning")})
	assert_true(config.has_section("CameraTuning"))
	assert_false(config.has_section("PhysicsTuning"), "absent instance writes no section")


func test_write_sections_ignores_labels_outside_sections() -> void:
	var config: ConfigFile = ConfigFile.new()
	TuningOverrides.write_sections(config, {"NotASection": _live("CameraTuning")})
	assert_eq(config.get_sections().size(), 0)


## (c) a stale key is ignored, valid keys in the same section still apply.
func test_stale_key_in_file_is_ignored() -> void:
	var camera: Resource = _live("CameraTuning")
	var field: String = _first_field_of(camera, TYPE_FLOAT)
	var original: float = float(camera.get(field))
	var config: ConfigFile = ConfigFile.new()
	config.set_value("CameraTuning", "removed_in_an_older_build", 5)
	config.set_value("CameraTuning", field, original + 1.5)
	config.save(TuningOverrides.save_path())
	TuningOverrides.apply_saved()
	assert_eq(float(camera.get(field)), original + 1.5, "valid key applied")
	assert_null(camera.get("removed_in_an_older_build"), "stale key never reached the resource")


func test_apply_saved_without_file_changes_nothing() -> void:
	TuningOverrides.apply_saved()
	for label: String in TuningOverrides.SECTIONS:
		assert_eq(_field_values(_live(label)), _snapshots[label], "%s unchanged" % label)


## (d) headers in SECTIONS order, one "# Label" block per section.
func test_copy_text_lists_headers_in_sections_order() -> void:
	var text: String = TuningOverrides.copy_text(_copies())
	var found: Array[String] = []
	for line: String in text.split("\n"):
		if line.begins_with("# "):
			found.append(line.substr(2))
	var expected: Array[String] = []
	for label: String in TuningOverrides.SECTIONS:
		expected.append(label)
	assert_eq(found, expected)


## (d) value-exact formatting, one field per type.
func test_copy_text_formats_each_value_type() -> void:
	var copies: Dictionary = _copies()
	var camera: Resource = copies["CameraTuning"]
	var bool_field: String = _first_field_of(camera, TYPE_BOOL)
	var float_field: String = _first_field_of(camera, TYPE_FLOAT)
	var int_pick: Array[String] = _find_field(TYPE_INT)
	assert_eq(int_pick.size(), 2, "some section has an int field")
	var ints: Resource = copies[int_pick[0]]
	var int_field: String = int_pick[1]
	var visuals: Resource = copies["TerritoryVisuals"]
	var color_field: String = _first_field_of(visuals, TYPE_COLOR)
	var sky: Resource = copies["SkyboxConfig"]
	var string_field: String = _first_field_of(sky, TYPE_STRING)
	for field: String in [bool_field, float_field]:
		assert_ne(field, "", "CameraTuning has a bool and a float field")
	assert_ne(color_field, "", "TerritoryVisuals has a Color field")
	assert_ne(string_field, "", "SkyboxConfig has a String field")
	camera.set(bool_field, true)
	ints.set(int_field, 7)
	camera.set(float_field, 2.0)
	visuals.set(color_field, Color(0.5, 0.25, 0.125, 1.0))
	sky.set(string_field, "abc")
	var text: String = TuningOverrides.copy_text(copies)
	var camera_lines: PackedStringArray = _block_lines(text, "CameraTuning")
	assert_has(camera_lines, "%s = true" % bool_field)
	assert_has(_block_lines(text, int_pick[0]), "%s = 7" % int_field)
	assert_has(camera_lines, "%s = 2.0" % float_field)
	assert_has(_block_lines(text, "TerritoryVisuals"), "%s = Color(0.5, 0.25, 0.125, 1)" % color_field)
	assert_has(_block_lines(text, "SkyboxConfig"), "%s = \"abc\"" % string_field)
	camera.set(bool_field, false)
	assert_has(_block_lines(TuningOverrides.copy_text(copies), "CameraTuning"), "%s = false" % bool_field)


## reset_resource reloads the file defaults onto the live instance.
func test_reset_resource_restores_file_values() -> void:
	var camera: Resource = _live("CameraTuning")
	var field: String = _first_field_of(camera, TYPE_FLOAT)
	var original: float = float(camera.get(field))
	camera.set(field, original + 4.0)
	TuningOverrides.reset_resource(camera)
	assert_eq(float(camera.get(field)), original)


func test_reset_resource_tolerates_null_and_unsaved_resources() -> void:
	TuningOverrides.reset_resource(null)
	var unsaved: Resource = _live("CameraTuning").duplicate()
	unsaved.resource_path = ""
	var field: String = _first_field_of(unsaved, TYPE_FLOAT)
	unsaved.set(field, 9.0)
	TuningOverrides.reset_resource(unsaved)
	assert_eq(float(unsaved.get(field)), 9.0, "a resource with no file is left alone")


func test_is_exported_field() -> void:
	var exported: int = PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_SCRIPT_VARIABLE
	assert_true(TuningOverrides.is_exported_field({"usage": exported}))
	assert_false(TuningOverrides.is_exported_field({"usage": PROPERTY_USAGE_SCRIPT_VARIABLE}), "plain var")
	assert_false(TuningOverrides.is_exported_field({"usage": PROPERTY_USAGE_STORAGE}))
	assert_false(TuningOverrides.is_exported_field({}))


## (e) a TuningPanel's save_overrides writes exactly the SECTIONS sections, read back from the file.
func test_panel_save_overrides_writes_every_section() -> void:
	var panel: TuningPanel = load("res://ui/debug/TuningPanel.tscn").instantiate()
	add_child_autofree(panel)
	assert_eq(panel.save_overrides(), OK)
	var config: ConfigFile = ConfigFile.new()
	assert_eq(config.load(TuningOverrides.save_path()), OK)
	for label: String in TuningOverrides.SECTIONS:
		assert_true(config.has_section(label), "%s saved" % label)
		assert_gt(config.get_section_keys(label).size(), 0, "%s has keys" % label)
