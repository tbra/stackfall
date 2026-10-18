extends GutTest
## The shipped sky data (config/sky/sky_cycle.tres, storm_overlay.tres, sky_dome.tres,
## cloud_puffs.tres) equals what SkyThemeMigration derives from the old theme files, owns its
## materials, and the golden fixture is well formed.

const Live := preload("res://tests/unit/sky/test_sky_parity_live.gd")
const CYCLE_PATH: String = "res://config/sky/sky_cycle.tres"
const OVERLAY_PATH: String = "res://config/sky/storm_overlay.tres"
const DOME_PATH: String = "res://config/sky/sky_dome.tres"
const PUFFS_PATH: String = "res://config/sky/cloud_puffs.tres"
const THEME_DIR: String = "res://config/sky/themes/"
const SUNSET_PATH: String = THEME_DIR + "sunset.tres"
const DAWN_PATH: String = THEME_DIR + "dawn.tres"
const NIGHT_PATH: String = THEME_DIR + "night.tres"
const STORM_PATH: String = THEME_DIR + "storm.tres"
## Textures the new materials may still reference in the old themes folder (kept where they are).
const SHARED_TEXTURES: Array[String] = ["cloud_noise.tres", "puff_noise.tres"]
const REQUIRED_RETIRED: Array[String] = [
	"sky_yaw_offset_deg", "sky_pitch_offset_deg", "cloud_layer_opacity", "cloud_warp_amount",
	"cloud_light_probe", "cloud_light_contrast", "cloud_rim_width", "proc_strata2_stretch",
	"cloud_cards", "sun_core_intensity", "sun_halo_intensity",
]
const MIN_STATES: int = 60
const GOLDEN_GROUPS: Array[String] = ["L_", "W_", "P_", "R"]


## A fresh copy from disk: other suites edit the cached theme resources in place.
func _theme(path: String) -> SkyThemeDef:
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as SkyThemeDef


func _migrated() -> SkyCycleDef:
	return SkyThemeMigration.cycle_from_themes(_theme(SUNSET_PATH), _theme(DAWN_PATH), _theme(NIGHT_PATH))


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


## Field-by-field equality of two resources of one script; nested keyframes recurse, shader
## materials compare by shader path and every uniform, other resources by path.
func _assert_same_values(want: Object, got: Object, label: String) -> int:
	var checked: int = 0
	for field: StringName in _script_vars(want):
		var a: Variant = want.get(field)
		var b: Variant = got.get(field)
		var where: String = "%s.%s" % [label, field]
		if a is ShaderMaterial:
			assert_true(b is ShaderMaterial, where)
			if b is ShaderMaterial:
				assert_eq((a as ShaderMaterial).shader.resource_path, (b as ShaderMaterial).shader.resource_path, where)
				assert_eq(_material_values(a as ShaderMaterial), _material_values(b as ShaderMaterial), where)
		elif a is Array:
			var left: Array = a as Array
			var right: Array = b as Array
			assert_eq(left.size(), right.size(), where + " size")
			for i: int in mini(left.size(), right.size()):
				checked += _assert_same_values(left[i] as Object, right[i] as Object, "%s[%d]" % [where, i])
		elif a is Resource and (a as Resource).resource_path == "":
			checked += _assert_same_values(a as Object, b as Object, where)
		elif a is Resource:
			assert_eq((a as Resource).resource_path, (b as Resource).resource_path, where)
		else:
			assert_eq(b, a, where)
		checked += 1
	return checked


func test_structure_fields_exist_on_the_cycle_def() -> void:
	# A set() on a name SkyCycleDef lacks is a silent no-op, so the copy list must be checked.
	var def: SkyCycleDef = SkyCycleDef.new()
	var present: Array[StringName] = _script_vars(def)
	for field: StringName in SkyThemeMigration.STRUCTURE_FIELDS:
		assert_true(field in present, "SkyCycleDef has %s" % field)
	var theme_vars: Array[StringName] = _script_vars(_theme(SUNSET_PATH))
	for field: StringName in SkyThemeMigration.STRUCTURE_FIELDS:
		assert_true(field in theme_vars, "SkyThemeDef has %s" % field)


func test_sky_cycle_resource_equals_the_migrated_themes() -> void:
	var saved: SkyCycleDef = load(CYCLE_PATH) as SkyCycleDef
	assert_not_null(saved, "sky_cycle.tres loads as SkyCycleDef")
	var checked: int = _assert_same_values(_migrated(), saved, "sky_cycle")
	assert_gt(checked, 150, "every cycle field, keyframe field and night field compared")
	assert_eq(saved.day_keyframes.size(), 2)
	assert_not_null(saved.night)


func test_storm_overlay_resource_equals_the_migrated_storm_theme() -> void:
	var saved: SkyOverlayDef = load(OVERLAY_PATH) as SkyOverlayDef
	assert_not_null(saved, "storm_overlay.tres loads as SkyOverlayDef")
	var checked: int = _assert_same_values(SkyThemeMigration.overlay_from_theme(_theme(STORM_PATH)), saved, "storm_overlay")
	assert_gt(checked, 20)


func test_dome_and_puffs_hold_the_sunset_material_values() -> void:
	var sunset: SkyThemeDef = _theme(SUNSET_PATH)
	var dome: ShaderMaterial = load(DOME_PATH) as ShaderMaterial
	var puffs: ShaderMaterial = load(PUFFS_PATH) as ShaderMaterial
	assert_not_null(dome)
	assert_not_null(puffs)
	assert_eq(_material_values(dome), _material_values(sunset.sky_material as ShaderMaterial))
	assert_eq(_material_values(puffs), _material_values(sunset.cloud_puff_material as ShaderMaterial))
	assert_ne(dome, sunset.sky_material, "the dome is its own resource")
	assert_ne(puffs, sunset.cloud_puff_material, "the puffs are their own resource")


func test_cycle_owns_its_materials() -> void:
	var saved: SkyCycleDef = load(CYCLE_PATH) as SkyCycleDef
	var sunset: SkyThemeDef = _theme(SUNSET_PATH)
	assert_eq(saved.sky_material.resource_path, DOME_PATH)
	assert_eq(saved.cloud_puff_material.resource_path, PUFFS_PATH)
	assert_ne(saved.sky_material, sunset.sky_material, "no shared sunset sky material")
	assert_ne(saved.cloud_puff_material, sunset.cloud_puff_material, "no shared sunset puff material")
	assert_ne(saved.bird_material, sunset.bird_material, "no shared sunset bird material")
	for path: String in [CYCLE_PATH, OVERLAY_PATH, DOME_PATH, PUFFS_PATH]:
		var text: String = FileAccess.get_file_as_string(path)
		for line: String in text.split("\n"):
			if not line.contains(THEME_DIR):
				continue
			var shared: bool = false
			for texture: String in SHARED_TEXTURES:
				shared = shared or line.contains(THEME_DIR + texture)
			assert_true(shared, "%s refers back into the old themes folder: %s" % [path, line])


func test_golden_fixture_is_well_formed() -> void:
	var golden: Dictionary = Live.load_golden()
	assert_false(golden.is_empty(), "fixture loads")
	var states: Dictionary = golden.get("states", {}) as Dictionary
	assert_gte(states.size(), MIN_STATES)
	for prefix: String in GOLDEN_GROUPS:
		var found: int = 0
		for state: String in states.keys():
			found += 1 if state.begins_with(prefix) else 0
		assert_gt(found, 0, "group %s present" % prefix)
	var retired: Array = golden.get("retired_uniforms", []) as Array
	for uniform_name: String in REQUIRED_RETIRED:
		assert_true(retired.has(uniform_name), "retired list names %s" % uniform_name)
	var dome: ShaderMaterial = load(DOME_PATH) as ShaderMaterial
	var declared: Array[String] = []
	for entry: Dictionary in dome.shader.get_shader_uniform_list():
		declared.append(str(entry["name"]))
	for uniform_name: String in retired:
		assert_true(uniform_name in declared, "%s is a real sky uniform today" % uniform_name)
	for key: String in ["sky", "puff", "env", "light", "fog_volume", "lighting", "flare", "life_is_night", "globals", "facade"]:
		assert_true((states["L_0.25"] as Dictionary).has(key), "state group %s" % key)
	var aurora: Dictionary = (states["W_match_night_aurora_seed"] as Dictionary)["sky"] as Dictionary
	assert_gt(float(aurora["aurora_visibility"]), 0.0, "the aurora seed shows the aurora")
	for preset: String in ["low", "medium", "high"]:
		assert_true(states.has("P_%s_boot" % preset), "preset %s boot state" % preset)


func test_evaluate_of_the_shipped_cycle_equals_the_golden() -> void:
	pending("enabled by SKY-15")
