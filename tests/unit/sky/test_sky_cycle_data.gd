extends GutTest
## The shipped sky data (config/sky/sky_cycle.tres, storm_overlay.tres, sky_dome.tres,
## cloud_puffs.tres) loads and owns its materials. Shipped art values are not pinned field by field;
## the live parity golden (test_sky_parity_live.gd) catches a changed rendered state.

const CYCLE_PATH: String = "res://config/sky/sky_cycle.tres"
const OVERLAY_PATH: String = "res://config/sky/storm_overlay.tres"
const DOME_PATH: String = "res://config/sky/sky_dome.tres"
const PUFFS_PATH: String = "res://config/sky/cloud_puffs.tres"
const RES_PREFIX: String = "res://"
const MIN_CYCLE_FIELDS: int = 100

func _script_vars(object: Object) -> Array[StringName]:
	var names: Array[StringName] = []
	for property: Dictionary in object.get_property_list():
		if (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			names.append(StringName(str(property["name"])))
	return names


func _material_values(material: ShaderMaterial) -> Dictionary:
	var values: Dictionary = {}
	for entry: Dictionary in material.shader.get_shader_uniform_list():
		var uniform_name: StringName = StringName(str(entry["name"]))
		var value: Variant = material.get_shader_parameter(uniform_name)
		if value is Texture2D:
			value = (value as Texture2D).resource_path
		values[uniform_name] = value
	return values


func test_shipped_cycle_and_overlay_load_with_their_structure() -> void:
	var saved: SkyCycleDef = load(CYCLE_PATH) as SkyCycleDef
	assert_not_null(saved, "sky_cycle.tres loads as SkyCycleDef")
	assert_eq(saved.day_keyframes.size(), 2)
	assert_not_null(saved.night)
	assert_not_null(saved.ambient_life)
	assert_gt(_script_vars(saved).size(), MIN_CYCLE_FIELDS)
	var overlay: SkyOverlayDef = load(OVERLAY_PATH) as SkyOverlayDef
	assert_not_null(overlay, "storm_overlay.tres loads as SkyOverlayDef")


func test_dome_and_puffs_are_shader_materials_the_cycle_owns() -> void:
	var dome: ShaderMaterial = load(DOME_PATH) as ShaderMaterial
	var puffs: ShaderMaterial = load(PUFFS_PATH) as ShaderMaterial
	assert_not_null(dome)
	assert_not_null(puffs)
	assert_not_null(dome.shader, "the dome has its shader")
	assert_not_null(puffs.shader, "the puffs have their shader")
	assert_gt(_material_values(dome).size(), 0)
	assert_gt(_material_values(puffs).size(), 0)


func test_cycle_owns_its_materials() -> void:
	var saved: SkyCycleDef = load(CYCLE_PATH) as SkyCycleDef
	assert_eq(saved.sky_material.resource_path, DOME_PATH)
	assert_eq(saved.cloud_puff_material.resource_path, PUFFS_PATH)
	assert_not_null(saved.bird_material, "the cycle carries the bird material")
	for path: String in [CYCLE_PATH, OVERLAY_PATH, DOME_PATH, PUFFS_PATH]:
		var text: String = FileAccess.get_file_as_string(path)
		assert_ne(text, "", "%s is readable" % path)
		for line: String in text.split("\n"):
			if not line.begins_with("[ext_resource"):
				continue
			var start: int = line.find(RES_PREFIX)
			var end: int = line.find("\"", start)
			assert_true(start >= 0 and end > start and ResourceLoader.exists(line.substr(start, end - start)),
				"%s references a missing resource: %s" % [path, line])

