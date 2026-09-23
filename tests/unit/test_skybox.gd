extends GutTest
## game/Skybox.gd (spec 2.10): load_set() against a temp fixture root, so
## these tests never touch the real (gitignored, third-party)
## assets/original/textures folder. Config/MapDef.gd's skybox_set field is
## covered here too, since Skybox.load_set() is the only consumer of it.

const FIXTURE_ROOT: String = "user://skybox_test_fixture"

var _skybox: Skybox = null


func before_each() -> void:
	_skybox = Skybox.new()
	_skybox.config = SkyboxConfig.new()
	add_child_autofree(_skybox)


func after_each() -> void:
	_remove_dir_recursive(FIXTURE_ROOT)


func test_load_set_returns_true_and_produces_a_texture_per_face() -> void:
	_write_fixture_set("beach_like", _skybox.config.face_names)

	var result: bool = _skybox.load_set("beach_like", FIXTURE_ROOT)

	assert_true(result)
	assert_false(_skybox.fallback_active)
	for face_name: String in _skybox.config.face_names:
		var texture: ImageTexture = _skybox.get_face_texture(face_name)
		assert_not_null(texture, "expected a texture for face '%s'" % face_name)


func test_load_set_with_missing_face_returns_false_and_sets_fallback() -> void:
	var faces: PackedStringArray = _skybox.config.face_names
	var partial: PackedStringArray = PackedStringArray()
	for i: int in range(faces.size() - 1):
		partial.append(faces[i])
	_write_fixture_set("partial", partial)

	var result: bool = _skybox.load_set("partial", FIXTURE_ROOT)

	assert_false(result)
	assert_true(_skybox.fallback_active)
	assert_null(_skybox.get_face_texture(faces[faces.size() - 1]))


func test_load_set_with_missing_folder_returns_false_and_sets_fallback() -> void:
	var result: bool = _skybox.load_set("does-not-exist", FIXTURE_ROOT)

	assert_false(result)
	assert_true(_skybox.fallback_active)


## DECISION (tests/unit/test_skybox.gd): case-insensitive face lookup is NOT
## tested here (and NOT implemented in Skybox.load_set(), which does one
## exact FileAccess.file_exists() check per config.face_names entry).
## tools/install_original_assets.ps1 (owned by another package) already
## lowercases every face file it copies, so ordinary use never needs it. A
## real behavioral test would also be platform-dependent in a way that would
## make it flaky here: Windows' filesystem resolves a mismatched-case path
## anyway (with an engine warning), while a case-sensitive export target
## would fail the exact same missing-face path the tests above already
## cover. Documented instead of pinned.


func test_map_def_skybox_set_defaults_to_beach() -> void:
	var map: MapDef = MapDef.new()
	assert_eq(map.skybox_set, "beach")


func test_map_resources_carry_their_assigned_skybox_set() -> void:
	var small: MapDef = load("res://config/maps/round_small.tres") as MapDef
	var medium: MapDef = load("res://config/maps/round_medium.tres") as MapDef
	var large: MapDef = load("res://config/maps/round_large.tres") as MapDef
	assert_eq(small.skybox_set, "beach")
	assert_eq(medium.skybox_set, "lake")
	assert_eq(large.skybox_set, "mountain")


# --- Bontago-xtq.8: the WorldEnvironment's Sky must match the loaded set -----
# (owner: "it reflects whatever light source you've put in but not the
# skybox we added recently") -- game/Skybox.gd now also installs a
# `shader_type sky` material (shaders/cubemap_sky.gdshader) onto the wired
# Environment's Sky whenever load_set() succeeds, and restores the original
# ProceduralSkyMaterial whenever it falls back, the same moment the box
# itself hides.

const CUBEMAP_SKY_SHADER: Shader = preload("res://shaders/cubemap_sky.gdshader")


## A fresh Skybox + Environment pair, independent of before_each()'s plain
## `_skybox` (which every existing test above relies on staying unwired --
## Skybox.gd's own doc: environment is optional and every sky-material write
## no-ops without it).
func _make_wired_skybox() -> Dictionary:
	var procedural: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	var sky: Sky = Sky.new()
	sky.sky_material = procedural
	var environment: Environment = Environment.new()
	environment.sky = sky

	var skybox: Skybox = Skybox.new()
	skybox.config = SkyboxConfig.new()
	skybox.environment = environment
	add_child_autofree(skybox)

	return {"skybox": skybox, "environment": environment, "procedural": procedural}


func test_load_set_installs_a_cubemap_sky_material_referencing_the_faces() -> void:
	var wired: Dictionary = _make_wired_skybox()
	var skybox: Skybox = wired["skybox"] as Skybox
	var environment: Environment = wired["environment"] as Environment
	_write_fixture_set("beach_like", skybox.config.face_names)

	var result: bool = skybox.load_set("beach_like", FIXTURE_ROOT)

	assert_true(result)
	var material: ShaderMaterial = environment.sky.sky_material as ShaderMaterial
	assert_not_null(material, "load_set() success must install a ShaderMaterial on the Sky.")
	assert_eq(material.shader, CUBEMAP_SKY_SHADER)
	assert_ne(environment.sky.sky_material, wired["procedural"], "the procedural sky must no longer be what the Sky shows.")
	for face_name: String in skybox.config.face_names:
		var param: Variant = material.get_shader_parameter(face_name + "_tex")
		assert_not_null(param, "expected a %s_tex shader parameter" % face_name)
		assert_eq(param, skybox.get_face_texture(face_name))


func test_sky_material_carries_the_configured_face_rotation_and_flip() -> void:
	var wired: Dictionary = _make_wired_skybox()
	var skybox: Skybox = wired["skybox"] as Skybox
	var environment: Environment = wired["environment"] as Environment
	_write_fixture_set("beach_like", skybox.config.face_names)
	skybox.load_set("beach_like", FIXTURE_ROOT)

	var material: ShaderMaterial = environment.sky.sky_material as ShaderMaterial
	for index: int in range(skybox.config.face_names.size()):
		var face_name: String = skybox.config.face_names[index]
		assert_eq(
			int(material.get_shader_parameter(face_name + "_rotation")),
			skybox.config.face_rotations[index],
			"%s rotation" % face_name
		)
		assert_eq(
			bool(material.get_shader_parameter(face_name + "_flip_u")),
			skybox.config.face_flip_u[index] != 0,
			"%s flip_u" % face_name
		)
		assert_eq(
			bool(material.get_shader_parameter(face_name + "_flip_v")),
			skybox.config.face_flip_v[index] != 0,
			"%s flip_v" % face_name
		)


func test_missing_set_keeps_the_procedural_sky_material() -> void:
	var wired: Dictionary = _make_wired_skybox()
	var skybox: Skybox = wired["skybox"] as Skybox
	var environment: Environment = wired["environment"] as Environment

	var result: bool = skybox.load_set("does-not-exist", FIXTURE_ROOT)

	assert_false(result)
	assert_eq(environment.sky.sky_material, wired["procedural"], "a missing set must leave the Sky's own material untouched.")


func test_a_later_failure_restores_the_procedural_sky_after_a_successful_load() -> void:
	var wired: Dictionary = _make_wired_skybox()
	var skybox: Skybox = wired["skybox"] as Skybox
	var environment: Environment = wired["environment"] as Environment
	_write_fixture_set("beach_like", skybox.config.face_names)
	assert_true(skybox.load_set("beach_like", FIXTURE_ROOT), "fixture: first load must succeed.")
	assert_ne(environment.sky.sky_material, wired["procedural"], "fixture: the cubemap sky must be installed first.")

	var result: bool = skybox.load_set("does-not-exist", FIXTURE_ROOT)

	assert_false(result)
	assert_eq(
		environment.sky.sky_material, wired["procedural"],
		"switching to a missing set must restore the procedural sky, not leave the previous set's sky showing."
	)


# --- Fixture helpers ---------------------------------------------------------

func _write_fixture_set(set_name: String, faces: PackedStringArray) -> void:
	var dir_path: String = FIXTURE_ROOT.path_join(set_name)
	DirAccess.make_dir_recursive_absolute(dir_path)
	var image: Image = Image.create(4, 4, false, Image.FORMAT_RGB8)
	image.fill(Color.BLUE)
	for face_name: String in faces:
		image.save_jpg(dir_path.path_join(face_name + ".jpg"))


func _remove_dir_recursive(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var full: String = path.path_join(entry)
			if dir.current_is_dir():
				_remove_dir_recursive(full)
			else:
				dir.remove(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)
