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


# --- Bontago-xtq.12: the ReflectionProbe wired via reflection_probe_path ----
# (owner: "isn't very reflective, like at all") is configured from
# config/TerritoryVisuals.gd's reflection_probe_* fields once at _ready().

func _make_skybox_with_probe(visuals: TerritoryVisuals) -> Dictionary:
	var skybox: Skybox = Skybox.new()
	skybox.config = SkyboxConfig.new()
	var probe: ReflectionProbe = ReflectionProbe.new()
	probe.name = "Probe"
	skybox.add_child(probe)
	skybox.reflection_probe_path = NodePath("Probe")
	skybox.visuals = visuals
	add_child_autofree(skybox)
	return {"skybox": skybox, "probe": probe}


func test_reflection_probe_sized_from_visuals_and_the_largest_map_radius() -> void:
	var visuals: TerritoryVisuals = TerritoryVisuals.new()
	visuals.reflection_probe_margin_m = 5.0
	visuals.reflection_probe_height_m = 20.0
	var wired: Dictionary = _make_skybox_with_probe(visuals)
	var probe: ReflectionProbe = wired["probe"] as ReflectionProbe

	var expected_half_width: float = MapDef.RADIUS_LARGE + 5.0
	assert_almost_eq(probe.size.x, expected_half_width * 2.0, 0.001)
	assert_almost_eq(probe.size.z, expected_half_width * 2.0, 0.001)
	assert_almost_eq(probe.size.y, 20.0, 0.001)
	assert_true(probe.box_projection, "a flat static disk should use box-corrected reflections.")


func test_reflection_probe_update_always_when_visuals_says_so() -> void:
	var visuals: TerritoryVisuals = TerritoryVisuals.new()
	visuals.reflection_probe_update_always = true
	var wired: Dictionary = _make_skybox_with_probe(visuals)
	var probe: ReflectionProbe = wired["probe"] as ReflectionProbe

	assert_eq(probe.update_mode, ReflectionProbe.UPDATE_ALWAYS)


func test_reflection_probe_update_once_when_visuals_says_so() -> void:
	var visuals: TerritoryVisuals = TerritoryVisuals.new()
	visuals.reflection_probe_update_always = false
	var wired: Dictionary = _make_skybox_with_probe(visuals)
	var probe: ReflectionProbe = wired["probe"] as ReflectionProbe

	assert_eq(probe.update_mode, ReflectionProbe.UPDATE_ONCE)


func test_reflection_probe_disabled_hides_it() -> void:
	var visuals: TerritoryVisuals = TerritoryVisuals.new()
	visuals.reflection_probe_enabled = false
	var wired: Dictionary = _make_skybox_with_probe(visuals)
	var probe: ReflectionProbe = wired["probe"] as ReflectionProbe

	assert_false(probe.visible)


func test_reflection_probe_excludes_the_disc_mirror_layer() -> void:
	# Bontago-xtq.20 (owner, 2026-09-23 20:12: "graphics flickering"):
	# fail-before this fix -- a fresh ReflectionProbe's default cull_mask
	# includes every layer, including DiscMirror.DISC_LAYER_BIT (the layer
	# game/DiscMirror.gd moves the disc onto in _ready() so its OWN mirror
	# camera cannot see it). Left unset, the probe would still bake the disc's
	# own shader (which samples SCREEN_UV of a SubViewport rendered for the
	# main camera's projection, meaningless from a cubemap face's own
	# projection) into its cubemap every UPDATE_ALWAYS frame -- an incoherent
	# image that changes every frame, i.e. flicker.
	var visuals: TerritoryVisuals = TerritoryVisuals.new()
	var wired: Dictionary = _make_skybox_with_probe(visuals)
	var probe: ReflectionProbe = wired["probe"] as ReflectionProbe

	assert_eq(
		probe.cull_mask & DiscMirror.DISC_LAYER_BIT, 0,
		"the reflection probe must not see the layer the disc's planar-mirror material lives on.",
	)
	assert_eq(
		probe.cull_mask, DiscMirror.MIRROR_CULL_MASK,
		"the probe should exclude exactly the same layer DiscMirror's own mirror camera already excludes.",
	)


func test_reflection_probe_configuration_is_a_noop_with_no_path_wired() -> void:
	# before_each()'s plain _skybox never wires reflection_probe_path or a
	# probe child -- _ready() already ran in before_each() without error, so
	# this just pins that this stays true rather than relying on it silently.
	assert_true(is_instance_valid(_skybox), "an unwired skybox must not error during _ready().")


# --- Bontago-xtq.12 step 2: SSR configuration and the TUNING_GROUP live-apply
# door (owner: "the disc isn't very reflective, like at all?") -- game/
# Skybox.gd's configure_ssr()/refresh_from_visuals() push config/
# TerritoryVisuals.gd's ssr_* fields onto the wired Environment, mirroring
# configure_reflection_probe()'s own contract above.


func test_configure_ssr_pushes_visuals_fields_onto_the_environment() -> void:
	var wired: Dictionary = _make_wired_skybox()
	var skybox: Skybox = wired["skybox"] as Skybox
	var environment: Environment = wired["environment"] as Environment
	var visuals: TerritoryVisuals = TerritoryVisuals.new()
	visuals.ssr_enabled = true
	visuals.ssr_max_steps = 12
	visuals.ssr_fade_in = 0.33
	visuals.ssr_fade_out = 1.23
	visuals.ssr_depth_tolerance = 0.44
	skybox.visuals = visuals

	skybox.configure_ssr()

	assert_true(environment.ssr_enabled)
	assert_eq(environment.ssr_max_steps, 12)
	assert_almost_eq(environment.ssr_fade_in, 0.33, 0.0001)
	assert_almost_eq(environment.ssr_fade_out, 1.23, 0.0001)
	assert_almost_eq(environment.ssr_depth_tolerance, 0.44, 0.0001)


func test_configure_ssr_disabled_turns_off_ssr_in_the_environment() -> void:
	var wired: Dictionary = _make_wired_skybox()
	var skybox: Skybox = wired["skybox"] as Skybox
	var environment: Environment = wired["environment"] as Environment
	var visuals: TerritoryVisuals = TerritoryVisuals.new()
	visuals.ssr_enabled = false
	skybox.visuals = visuals

	skybox.configure_ssr()

	assert_false(environment.ssr_enabled)


func test_configure_ssr_and_refresh_are_noops_without_a_wired_environment() -> void:
	# before_each()'s plain _skybox never wires `environment` (only the tests
	# above build their own via _make_wired_skybox()) or a
	# reflection_probe_path -- configure_ssr()/refresh_from_visuals() must not
	# error with nothing wired, the same no-op contract
	# configure_reflection_probe() already has (see the test right above this
	# section).
	_skybox.configure_ssr()
	_skybox.refresh_from_visuals()
	assert_true(
		is_instance_valid(_skybox),
		"configure_ssr()/refresh_from_visuals() must not error with no Environment/probe wired."
	)


func test_refresh_from_visuals_reapplies_probe_and_ssr_after_a_visuals_change() -> void:
	var wired: Dictionary = _make_wired_skybox()
	var skybox: Skybox = wired["skybox"] as Skybox
	var environment: Environment = wired["environment"] as Environment
	var probe: ReflectionProbe = ReflectionProbe.new()
	probe.name = "Probe"
	skybox.add_child(probe)
	skybox.reflection_probe_path = NodePath("Probe")
	var visuals: TerritoryVisuals = TerritoryVisuals.new()
	visuals.ssr_enabled = true
	visuals.reflection_probe_enabled = true
	skybox.visuals = visuals
	skybox.refresh_from_visuals()

	visuals.ssr_enabled = false
	visuals.ssr_max_steps = 7
	visuals.reflection_probe_enabled = false

	skybox.refresh_from_visuals()

	assert_false(environment.ssr_enabled, "SSR must be re-applied from the changed visuals.")
	assert_eq(environment.ssr_max_steps, 7)
	assert_false(
		probe.visible,
		"refresh_from_visuals() must re-apply the reflection probe settings too, not only SSR."
	)


# --- Bontago-xtq.22: apply_set()/list_available_sets() -- the F4 "Skybox"
# dropdown (owner: disc reflectivity is "hard to judge with that texture --
# add an option to F4 to change the skybox").

func test_apply_set_loads_the_named_set_and_records_it_on_config() -> void:
	_write_fixture_set("beach_like", _skybox.config.face_names)

	var result: bool = _skybox.apply_set("beach_like", FIXTURE_ROOT)

	assert_true(result)
	assert_false(_skybox.fallback_active)
	assert_eq(_skybox.config.default_set, "beach_like")
	assert_true(_skybox.config.enabled)


func test_apply_set_with_an_unknown_name_falls_back_cleanly() -> void:
	var result: bool = _skybox.apply_set("does-not-exist", FIXTURE_ROOT)

	assert_false(result)
	assert_true(_skybox.fallback_active, "an unknown/missing set must fall back, not error.")
	# The owner's request is still remembered (round-trips through the F4
	# override the same as every other tunable), even though it never loaded.
	assert_eq(_skybox.config.default_set, "does-not-exist")


func test_apply_set_switches_from_one_loaded_set_to_another() -> void:
	_write_fixture_set("beach_like", _skybox.config.face_names)
	_write_fixture_set("mountain_like", _skybox.config.face_names)
	assert_true(_skybox.apply_set("beach_like", FIXTURE_ROOT))

	var result: bool = _skybox.apply_set("mountain_like", FIXTURE_ROOT)

	assert_true(result)
	assert_false(_skybox.fallback_active)
	assert_eq(_skybox.config.default_set, "mountain_like")


func test_apply_set_with_the_procedural_id_disables_the_skybox() -> void:
	_write_fixture_set("beach_like", _skybox.config.face_names)
	assert_true(_skybox.apply_set("beach_like", FIXTURE_ROOT), "fixture: a real set must load first.")

	var result: bool = _skybox.apply_set(Skybox.PROCEDURAL_SET_ID, FIXTURE_ROOT)

	assert_false(result)
	assert_true(_skybox.fallback_active)
	assert_false(_skybox.config.enabled, "the Procedural/none entry must flip config.enabled off.")


func test_list_available_sets_returns_sorted_subfolders_of_the_root() -> void:
	_write_fixture_set("zzz_last", _skybox.config.face_names)
	_write_fixture_set("aaa_first", _skybox.config.face_names)

	var sets: PackedStringArray = Skybox.list_available_sets(FIXTURE_ROOT)

	assert_eq(sets, PackedStringArray(["aaa_first", "zzz_last"]))


func test_list_available_sets_is_empty_for_a_missing_root() -> void:
	var sets: PackedStringArray = Skybox.list_available_sets(FIXTURE_ROOT.path_join("no-such-root"))

	assert_eq(sets.size(), 0)


func test_skybox_is_in_the_tuning_group_after_ready() -> void:
	assert_true(
		_skybox.is_in_group(Skybox.TUNING_GROUP),
		"ui/TuningPanel.gd's refresh_territory_visuals_live() reaches every live Skybox via this group."
	)


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
