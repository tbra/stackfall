extends GutTest
## game/Skybox.gd (spec 2.10): load_set() against a temp fixture root, so
## these tests never touch the real (gitignored, third-party)
## assets/original/textures folder. Config/MapDef.gd's skybox_set field is
## covered here too, since Skybox.load_set() is the only consumer of it.

const FIXTURE_ROOT: String = "user://skybox_test_fixture"

var _skybox: Skybox = null

## Bontago-xtq.28: saved/restored the same way tests/unit/test_main_graphics_
## preset.gd's own _original_preset_id does -- the real "Settings" autoload
## outlives this script, so a FogVolume-gating test that calls
## Settings.set_graphics_preset() must not leak a changed preset into whatever
## test file the runner loads next in the same process.
var _original_preset_id: StringName


func before_each() -> void:
	_original_preset_id = Settings.current_graphics_preset().id
	_skybox = Skybox.new()
	_skybox.config = SkyboxConfig.new()
	add_child_autofree(_skybox)


func after_each() -> void:
	Settings.set_graphics_preset(_original_preset_id)
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
	skybox.theme = SkyThemeDef.new()
	add_child_autofree(skybox)

	return {"skybox": skybox, "environment": environment, "procedural": procedural}


func test_cycle_key_light_and_flare_follow_the_sun() -> void:
	var wired: Dictionary = _make_wired_skybox()
	var skybox: Skybox = wired["skybox"] as Skybox
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.name = "CycleKey"
	skybox.add_child(light)
	skybox.light_path = NodePath("CycleKey")
	var flare: SunFlare = SunFlare.new()
	add_child_autofree(flare)
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = MatchConfig.SkyThemeMode.CYCLE
	skybox.configure_match_sky(config)
	for phase: float in [0.0, 0.25, 0.5, 0.75]:
		skybox.set_cycle_phase(phase)
		var material: ShaderMaterial = skybox.theme.sky_material as ShaderMaterial
		var sun: Vector3 = material.get_shader_parameter(&"sun_direction") as Vector3
		assert_true(light.light_energy >= 0.0)
		assert_true(light.global_basis.z.y >= -0.001, "key light must never shine from below")
		assert_true(flare.config.sun_direction.is_equal_approx(sun), "flare must track the sky disc")
		if sun.y < -0.01:
			assert_true(light.light_energy < 0.5, "night key must stay dim")
			assert_false(flare.is_theme_enabled())


## Bontago-59o.18: F4's "cycle" Theme entry persists as theme_name "cycle" and
## _ready() runs the cycle from boot (it is not a theme file); any other name
## still loads its static theme.
func test_ready_starts_the_cycle_for_theme_name_cycle() -> void:
	var sky: Sky = Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	var environment: Environment = Environment.new()
	environment.sky = sky
	var skybox: Skybox = Skybox.new()
	skybox.config = SkyboxConfig.new()
	skybox.config.theme_name = Skybox.CYCLE_THEME_ID
	skybox.environment = environment
	add_child_autofree(skybox)
	assert_true(skybox.is_cycle_active(), "the persisted cycle entry runs at boot")
	assert_eq(skybox.locked_phase(), -1.0)
	assert_almost_eq(skybox.current_cycle_phase(), (Skybox.load_theme("sunset") as SkyThemeDef).cycle_start_phase, 0.0001)
	assert_eq(environment.sky.process_mode, Sky.PROCESS_MODE_INCREMENTAL)
	assert_not_null(skybox.get_cloud_sea(), "the layers the cycle drives exist")

	var static_skybox: Skybox = Skybox.new()
	static_skybox.config = SkyboxConfig.new()
	static_skybox.config.theme_name = "night"
	static_skybox.environment = Environment.new()
	static_skybox.environment.sky = Sky.new()
	add_child_autofree(static_skybox)
	assert_false(static_skybox.is_cycle_active(), "a named theme stays a static theme")
	assert_eq(static_skybox.theme.resource_path, "res://config/sky_themes/night.tres")


## Bontago-59o.18 (C1b variation): a cycle started outside a match (boot theme "cycle",
## F4's Theme entry) varies inside the configured ranges from the default seed, and the
## varying exposure is the baseline weather overcast scales (never a fixed 0.8).
func test_a_boot_cycle_varies_inside_the_ranges_from_the_default_seed() -> void:
	var sky: Sky = Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	var environment: Environment = Environment.new()
	environment.sky = sky
	var skybox: Skybox = Skybox.new()
	skybox.config = SkyboxConfig.new()
	skybox.config.theme_name = Skybox.CYCLE_THEME_ID
	skybox.environment = environment
	add_child_autofree(skybox)
	var theme: SkyThemeDef = skybox.theme
	var seen: Dictionary = {}
	for phase: float in [0.0, 0.1, 0.2, 0.3, 0.45, 0.6, 0.75, 0.9]:
		skybox.set_cycle_phase(phase)
		var material: ShaderMaterial = skybox.theme.sky_material as ShaderMaterial
		var exposure: float = float(material.get_shader_parameter(&"exposure"))
		assert_between(exposure, theme.variation_exposure_min, theme.variation_exposure_max, "exposure at phase %s" % phase)
		assert_eq(exposure, SkyVariation.exposure_at(theme, phase, SkyVariation.DEFAULT_SEED), "default seed at phase %s" % phase)
		assert_between(float(material.get_shader_parameter(&"cloud_coverage")), theme.variation_cloud_coverage_min, theme.variation_cloud_coverage_max)
		assert_between(float(material.get_shader_parameter(&"proc_sea_coverage")), theme.variation_sea_coverage_min, theme.variation_sea_coverage_max)
		seen[snappedf(exposure, 0.0001)] = true
	assert_gt(seen.size(), 3, "the boot cycle's exposure changes over the day")
	skybox.set_overcast(1.0, 0.5, 0.6, 0.4, Color(0.4, 0.4, 0.5), 0.5)
	skybox.set_cycle_phase(0.33)
	var dimmed: float = float((skybox.theme.sky_material as ShaderMaterial).get_shader_parameter(&"exposure"))
	assert_almost_eq(dimmed, SkyVariation.exposure_at(theme, 0.33, SkyVariation.DEFAULT_SEED) * 0.4, 0.00001, "overcast scales the varying baseline")


## Bontago-59o.18 (C1b follow-up): a running cycle sky configured from `config`, with
## the clock at `clock`; returns [exposure, cloud coverage, sea coverage] of its live
## sky material.
func _cycle_look(config: MatchConfig, clock: float) -> Array[float]:
	var skybox: Skybox = _make_wired_skybox()["skybox"] as Skybox
	skybox.configure_match_sky(config)
	skybox.update_cycle_clock(clock)
	var material: ShaderMaterial = skybox.theme.sky_material as ShaderMaterial
	return [
		float(material.get_shader_parameter(&"exposure")),
		float(material.get_shader_parameter(&"cloud_coverage")),
		float(material.get_shader_parameter(&"proc_sea_coverage")),
	]


func _resolved_config(variation_seed: int) -> MatchConfig:
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = MatchConfig.SkyThemeMode.CYCLE
	config.resolve_sky_variation_seed(variation_seed)
	return config


## Bontago-59o.18 (C1b follow-up): the host-rolled MatchConfig.sky_variation_seed drives
## the sky. Two skyboxes with the same resolved seed (the host's, and a client built from
## its wire dict) draw the same sky; a different seed draws a different one; the seed the
## skybox reports is the config's.
func test_skyboxes_with_the_same_resolved_sky_variation_seed_match_and_different_seeds_differ() -> void:
	var host_config: MatchConfig = _resolved_config(5551)
	var client_config: MatchConfig = MatchConfig.from_dict(host_config.to_dict())
	var other_config: MatchConfig = _resolved_config(5552)
	var host: Skybox = _make_wired_skybox()["skybox"] as Skybox
	host.configure_match_sky(host_config)
	assert_eq(host.variation_seed(), 5551, "the skybox draws from the host's resolved seed")
	var differs: bool = false
	for clock: float in [0.0, 40.0, 95.0, 150.0, 210.0, 280.0]:
		var host_look: Array[float] = _cycle_look(host_config, clock)
		assert_eq(_cycle_look(client_config, clock), host_look, "same seed, same sky at clock %s" % clock)
		if not is_equal_approx(_cycle_look(other_config, clock)[0], host_look[0]):
			differs = true
	assert_true(differs, "a different resolved seed draws a different curve")
	var theme: SkyThemeDef = Skybox.load_theme(Skybox.DEFAULT_THEME_ID)
	assert_eq(host_config.effective_sky_variation_seed(), 5551)
	assert_eq(_cycle_look(host_config, 0.0)[0], SkyVariation.exposure_at(theme, host.cycle_phase_at(0.0), 5551), "it is SkyVariation's function of that seed")


## The rng_seed >= 0 path is unchanged (the match seed is the sky seed, no roll), an
## explicit sky_variation_seed wins, and a config with neither shares the default curve.
func test_the_rng_seed_path_is_unchanged_and_an_unresolved_config_uses_the_default_seed() -> void:
	var seeded: MatchConfig = MatchConfig.new()
	seeded.rng_seed = 4242
	seeded.resolve_sky_variation_seed(99)
	var skybox: Skybox = _make_wired_skybox()["skybox"] as Skybox
	skybox.configure_match_sky(seeded)
	assert_eq(skybox.variation_seed(), 4242, "a seeded match still draws from rng_seed")
	var explicit: MatchConfig = MatchConfig.new()
	explicit.rng_seed = 4242
	explicit.sky_variation_seed = 7
	skybox.configure_match_sky(explicit)
	assert_eq(skybox.variation_seed(), 7, "the host-resolved variation seed wins over rng_seed")
	var unresolved: MatchConfig = MatchConfig.new()
	skybox.configure_match_sky(unresolved)
	assert_eq(skybox.variation_seed(), SkyVariation.DEFAULT_SEED, "nothing resolved: the shared default curve")
	assert_eq(_cycle_look(unresolved, 60.0), _cycle_look(MatchConfig.new(), 60.0), "unresolved peers still agree")


func test_authored_theme_returns_after_switching_back_from_legacy_skybox() -> void:
	var wired: Dictionary = _make_wired_skybox()
	var skybox: Skybox = wired["skybox"] as Skybox
	var environment: Environment = wired["environment"] as Environment
	var sunset: SkyThemeDef = load("res://config/sky_themes/sunset.tres")
	skybox.apply_theme(sunset)
	assert_eq(environment.sky.sky_material, sunset.sky_material)
	_write_fixture_set("beach_like", skybox.config.face_names)
	assert_true(skybox.apply_set("beach_like", FIXTURE_ROOT))
	assert_ne(environment.sky.sky_material, sunset.sky_material)
	skybox.apply_set("", FIXTURE_ROOT)
	assert_eq(environment.sky.sky_material, sunset.sky_material)
	assert_true(skybox.fallback_active)


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


## Bontago-xtq.28 -----------------------------------------------------------

func test_apply_theme_writes_sky_ground_and_fog_fields() -> void:
	var wired: Dictionary = _make_wired_skybox()
	var skybox: Skybox = wired["skybox"] as Skybox
	var environment: Environment = wired["environment"] as Environment
	var procedural: ProceduralSkyMaterial = wired["procedural"] as ProceduralSkyMaterial
	var theme: SkyThemeDef = SkyThemeDef.new()
	theme.sky_top_color = Color(0.11, 0.22, 0.33)
	theme.sky_horizon_color = Color(0.44, 0.55, 0.66)
	theme.ground_bottom_color = Color(0.71, 0.82, 0.93)
	theme.ground_horizon_color = Color(0.15, 0.25, 0.35)
	theme.sun_angle_min_max = Vector2(6.0, 14.0)
	theme.fog_color = Color(0.91, 0.52, 0.23)
	theme.fog_density = 0.021
	theme.fog_sky_affect = 0.3
	theme.volumetric_fog_density = 0.0012
	theme.volumetric_fog_albedo = Color(0.81, 0.42, 0.19)

	skybox.apply_theme(theme)

	assert_eq(procedural.sky_top_color, theme.sky_top_color, "sky_top_color")
	assert_eq(procedural.sky_horizon_color, theme.sky_horizon_color, "sky_horizon_color")
	assert_eq(procedural.ground_bottom_color, theme.ground_bottom_color, "ground_bottom_color")
	assert_eq(procedural.ground_horizon_color, theme.ground_horizon_color, "ground_horizon_color")
	assert_almost_eq(
		procedural.sun_angle_max, theme.sun_angle_min_max.y, 0.001,
		"sun_angle_max must take sun_angle_min_max's wider/softer glow edge (.y), not .x"
	)
	assert_true(environment.fog_enabled, "apply_theme() must turn on the Environment's basic depth fog")
	assert_eq(environment.fog_light_color, theme.fog_color, "fog_light_color")
	assert_almost_eq(environment.fog_density, theme.fog_density, 0.0001, "fog_density")
	assert_almost_eq(
		environment.fog_sky_affect, theme.fog_sky_affect, 0.0001,
		"fog_sky_affect must come from the theme, not sit at the Environment engine default (1.0), or the "
		+ "depth fog fully replaces the rendered sky gradient with flat fog_light_color"
	)
	assert_almost_eq(
		environment.volumetric_fog_density, theme.volumetric_fog_density, 0.0001,
		"volumetric_fog_density must come from the theme, not sit at the Environment engine default (0.05), "
		+ "or the whole frustum shows a uniform grey haze regardless of the FogVolume cloud deck's placement"
	)
	assert_eq(
		environment.volumetric_fog_albedo, theme.volumetric_fog_albedo,
		"volumetric_fog_albedo"
	)


func test_apply_theme_is_a_noop_with_no_environment_wired() -> void:
	# The file-level before_each() fixture's `_skybox` never wires `environment`
	# -- apply_theme() must not push an error/crash for the common "unwired
	# fixture" shape every other test in this file already relies on.
	_skybox.apply_theme(_skybox.theme)
	assert_true(true, "apply_theme() must no-op silently with environment == null")


func test_apply_theme_updates_sky_yaw_pitch_offsets_on_shared_sky_material() -> void:
	var wired: Dictionary = _make_wired_skybox()
	var skybox: Skybox = wired["skybox"] as Skybox
	var environment: Environment = wired["environment"] as Environment
	var theme: SkyThemeDef = SkyThemeDef.new()
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load("res://shaders/sunset_clouds.gdshader")
	theme.sky_material = material
	theme.sky_yaw_offset_deg = 184.058612
	theme.sky_pitch_offset_deg = 3.0
	skybox.apply_theme(theme)
	assert_eq(environment.sky.sky_material, material, "Background and sky reflections share the aligned material.")
	assert_almost_eq(float(material.get_shader_parameter("sky_yaw_offset_deg")), theme.sky_yaw_offset_deg, 0.0001)
	assert_almost_eq(float(material.get_shader_parameter("sky_pitch_offset_deg")), 3.0, 0.0001)
	theme.sky_yaw_offset_deg = 12.0
	skybox.apply_theme(theme)
	assert_almost_eq(float(material.get_shader_parameter("sky_yaw_offset_deg")), 12.0, 0.0001, "F4 reapply updates live sampling.")


func test_apply_theme_writes_procedural_sky_params_to_material() -> void:
	var wired: Dictionary = _make_wired_skybox()
	var skybox: Skybox = wired["skybox"] as Skybox
	var theme: SkyThemeDef = SkyThemeDef.new()
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load("res://shaders/sunset_clouds.gdshader")
	theme.sky_material = material
	theme.procedural_sea_mix = 0.75
	theme.proc_horizon_color = Color(0.1, 0.2, 0.3)
	theme.proc_strata_scale = 2.5
	skybox.apply_theme(theme)
	assert_true(theme.sky_look_procedural, "the toggle defaults to on.")
	theme.sky_look_procedural = false
	skybox.apply_theme(theme)
	assert_almost_eq(float(material.get_shader_parameter("procedural_sea_mix")), 0.75, 0.0001, "Painted panorama is gone: the flag no longer zeroes the sky mix (a 0 mix is a black sky).")
	theme.sky_look_procedural = true
	skybox.apply_theme(theme)
	assert_almost_eq(float(material.get_shader_parameter("procedural_sea_mix")), 0.75, 0.0001)
	assert_eq(material.get_shader_parameter("proc_horizon_color"), Color(0.1, 0.2, 0.3))
	assert_almost_eq(float(material.get_shader_parameter("proc_strata_scale")), 2.5, 0.0001)


func test_fog_volume_is_created_but_hidden_on_low_preset() -> void:
	Settings.set_graphics_preset(&"low")
	var skybox: Skybox = Skybox.new()
	skybox.config = SkyboxConfig.new()
	add_child_autofree(skybox)

	var fog_volume: FogVolume = skybox.get_fog_volume()
	assert_not_null(fog_volume, "a FogVolume child must always be created, only its visibility is gated")
	assert_false(fog_volume.visible, "low preset must hide the cloud-deck FogVolume")


func test_fog_volume_is_visible_on_medium_and_high_preset() -> void:
	Settings.set_graphics_preset(&"medium")
	var medium_skybox: Skybox = Skybox.new()
	medium_skybox.config = SkyboxConfig.new()
	add_child_autofree(medium_skybox)
	assert_true(medium_skybox.get_fog_volume().visible, "medium preset must show the cloud-deck FogVolume")

	Settings.set_graphics_preset(&"high")
	var high_skybox: Skybox = Skybox.new()
	high_skybox.config = SkyboxConfig.new()
	add_child_autofree(high_skybox)
	assert_true(high_skybox.get_fog_volume().visible, "high preset must show the cloud-deck FogVolume")


func test_fog_volume_uses_the_theme_cloud_deck_size_and_height() -> void:
	Settings.set_graphics_preset(&"high")
	var custom_theme: SkyThemeDef = SkyThemeDef.new()
	custom_theme.cloud_deck_size_m = Vector3(120.0, 20.0, 140.0)
	custom_theme.cloud_deck_height_m = -55.0
	var skybox: Skybox = Skybox.new()
	skybox.config = SkyboxConfig.new()
	skybox.theme = custom_theme
	add_child_autofree(skybox)

	var fog_volume: FogVolume = skybox.get_fog_volume()
	assert_eq(fog_volume.size, custom_theme.cloud_deck_size_m, "FogVolume.size must come from the theme")
	assert_almost_eq(
		fog_volume.position.y, custom_theme.cloud_deck_height_m, 0.001,
		"FogVolume.position.y must come from the theme, not a Skybox.gd constant"
	)


func test_sunset_theme_cloud_deck_sits_entirely_below_the_disk() -> void:
	var sunset: SkyThemeDef = load("res://config/sky_themes/sunset.tres") as SkyThemeDef
	var deck_top_y: float = sunset.cloud_deck_height_m + sunset.cloud_deck_size_m.y * 0.5
	assert_lt(
		deck_top_y, 0.0,
		"the shipped sunset cloud deck's top edge must sit below world y == 0 (the disk's top surface), "
		+ "not enclose the disk/gameplay camera in fog"
	)


func test_fog_volume_visibility_reacts_live_to_graphics_preset_changed() -> void:
	Settings.set_graphics_preset(&"high")
	var skybox: Skybox = Skybox.new()
	skybox.config = SkyboxConfig.new()
	add_child_autofree(skybox)
	assert_true(skybox.get_fog_volume().visible, "fixture: starts visible on high")

	Settings.set_graphics_preset(&"low")

	assert_false(
		skybox.get_fog_volume().visible,
		"an already-created Skybox must hide its FogVolume live when the preset changes, not just at boot"
	)


## Bontago-59o.18 (C1a review fix): a graphics-preset change (the settings menu or the
## adaptive governor) rebuilds the cloud puffs and ambient life from the DAY
## palette. A running cycle heals on its next frame, but a locked cycle never
## re-runs set_cycle_phase() on its own, so the match stayed dressed as day inside
## a locked Night until the lock changed.
func _make_locked_night_skybox() -> Skybox:
	Settings.set_graphics_preset(&"high")
	var skybox: Skybox = _make_wired_skybox()["skybox"] as Skybox
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = MatchConfig.SkyThemeMode.NIGHT
	config.resolve_sky_theme(0)
	skybox.configure_match_sky(config)
	return skybox


## Asserts the cloud puffs and ambient life of a sky locked at full night.
func _assert_locked_night_dressing(skybox: Skybox, label: String) -> void:
	var night: SkyThemeDef = Skybox.load_theme(Skybox.CYCLE_NIGHT_THEME_ID)
	var night_puffs: ShaderMaterial = night.cloud_puff_material as ShaderMaterial
	var puffs: ShaderMaterial = skybox.get_cloud_sea().puff_material()
	assert_not_null(puffs, "%s: the cloud sea has puffs" % label)
	if puffs == null:
		return
	assert_true(skybox.locked_phase() >= 0.0, "%s: the sky stays locked" % label)
	var grade: Variant = puffs.get_shader_parameter(&"grade_amount")
	assert_true(grade is float and is_equal_approx(grade as float, 1.0), "%s: puff grade is the night value (got %s)" % [label, grade])
	for parameter: StringName in [&"shadow_color", &"mid_color", &"lit_color", &"rim_color"]:
		var colour: Color = puffs.get_shader_parameter(parameter) as Color
		assert_true(colour.is_equal_approx(night_puffs.get_shader_parameter(parameter) as Color), "%s: puff %s is the night mix" % [label, parameter])
	var sun: Vector3 = (skybox.theme.sky_material as ShaderMaterial).get_shader_parameter(&"sun_direction") as Vector3
	assert_true((puffs.get_shader_parameter(&"light_direction") as Vector3).is_equal_approx(sun), "%s: puffs are lit from the cycle sun, not the authored one" % label)
	assert_false(skybox.get_birds().visible, "%s: no distant day birds at night" % label)
	assert_false(skybox.get_perching_birds().is_enabled(), "%s: the night life config has no perching birds" % label)
	assert_true(skybox.get_fireflies().visible, "%s: fireflies swarm at night" % label)


func test_graphics_preset_change_keeps_a_locked_night_dressed_as_night() -> void:
	var skybox: Skybox = _make_locked_night_skybox()
	_assert_locked_night_dressing(skybox, "before the change")

	# The real signal path: Settings emits graphics_preset_changed to the live Skybox.
	Settings.set_graphics_preset(&"medium")
	_assert_locked_night_dressing(skybox, "after the preset change")

	# The handler itself (what the adaptive governor's level change ends up calling).
	skybox._on_graphics_preset_changed(Settings.current_graphics_preset())
	_assert_locked_night_dressing(skybox, "after the handler")


## The re-apply is a no-op for the clock: a locked sky keeps its phase, and a
## running cycle keeps following the clock after the same rebuild.
func test_graphics_preset_change_keeps_the_phase_locked_or_running() -> void:
	var locked: Skybox = _make_locked_night_skybox()
	var held: float = locked.locked_phase()
	Settings.set_graphics_preset(&"medium")
	assert_almost_eq(locked.locked_phase(), held, 0.0001, "the lock survives a preset change")
	assert_almost_eq(locked.current_cycle_phase(), held, 0.0001, "and the phase written is still the locked one")

	var running: Skybox = _make_wired_skybox()["skybox"] as Skybox
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = MatchConfig.SkyThemeMode.CYCLE
	running.configure_match_sky(config)
	running.update_cycle_clock(40.0)
	var phase: float = running.current_cycle_phase()
	Settings.set_graphics_preset(&"high")
	assert_eq(running.locked_phase(), -1.0, "a running cycle stays running")
	assert_almost_eq(running.current_cycle_phase(), phase, 0.0001, "the phase is re-applied unchanged")


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


func test_effective_probe_mode_maps_preset_and_overrides() -> void:
	var visuals: TerritoryVisuals = TerritoryVisuals.new()
	var preset: GraphicsPreset = GraphicsPreset.new()
	for mode: int in [
		GraphicsPreset.ReflectionProbeMode.OFF, GraphicsPreset.ReflectionProbeMode.ONCE,
		GraphicsPreset.ReflectionProbeMode.INTERVAL, GraphicsPreset.ReflectionProbeMode.ALWAYS,
	]:
		preset.reflection_probe_mode = mode as GraphicsPreset.ReflectionProbeMode
		assert_eq(Skybox.effective_probe_mode(visuals, preset), mode)
	assert_eq(Skybox.effective_probe_mode(visuals, null), GraphicsPreset.ReflectionProbeMode.INTERVAL)
	preset.reflection_probe_mode = GraphicsPreset.ReflectionProbeMode.OFF
	visuals.reflection_probe_update_always = true
	assert_eq(Skybox.effective_probe_mode(visuals, preset), GraphicsPreset.ReflectionProbeMode.ALWAYS)
	visuals.reflection_probe_enabled = false
	assert_eq(Skybox.effective_probe_mode(visuals, preset), GraphicsPreset.ReflectionProbeMode.OFF)


func test_shipped_presets_pick_probe_glow_and_shadow_costs() -> void:
	var low: GraphicsPreset = load("res://config/graphics_presets/low.tres") as GraphicsPreset
	var medium: GraphicsPreset = load("res://config/graphics_presets/medium.tres") as GraphicsPreset
	var high: GraphicsPreset = load("res://config/graphics_presets/high.tres") as GraphicsPreset
	assert_eq(low.reflection_probe_mode, GraphicsPreset.ReflectionProbeMode.OFF)
	assert_eq(medium.reflection_probe_mode, GraphicsPreset.ReflectionProbeMode.INTERVAL)
	assert_gt(medium.reflection_probe_interval_s, high.reflection_probe_interval_s)
	assert_eq(high.reflection_probe_mode, GraphicsPreset.ReflectionProbeMode.INTERVAL)
	assert_false(low.glow_enabled)
	assert_true(medium.glow_enabled and high.glow_enabled)
	assert_lt(low.sun_shadow_mode, medium.sun_shadow_mode)
	assert_lt(low.sun_shadow_max_distance, medium.sun_shadow_max_distance)


func test_interval_mode_rerenders_the_probe_only_when_blocks_changed() -> void:
	var visuals: TerritoryVisuals = TerritoryVisuals.new()
	var wired: Dictionary = _make_skybox_with_probe(visuals)
	var skybox: Skybox = wired["skybox"] as Skybox
	var probe: ReflectionProbe = wired["probe"] as ReflectionProbe
	var registry: BlockRegistry = BlockRegistry.new()
	add_child_autofree(registry)
	skybox._probe_registry = registry
	skybox._probe_mode = GraphicsPreset.ReflectionProbeMode.INTERVAL
	skybox._probe_interval_s = 0.5
	var y0: float = probe.position.y
	skybox._step_probe_interval(0.4)
	assert_eq(probe.position.y, y0, "before the interval nothing happens")
	skybox._step_probe_interval(0.2)
	assert_ne(probe.position.y, y0, "first interval renders once (new revision)")
	var y1: float = probe.position.y
	skybox._step_probe_interval(0.6)
	assert_eq(probe.position.y, y1, "unchanged blocks do not re-render")
	registry.mark_territory_dirty()
	skybox._step_probe_interval(0.6)
	assert_ne(probe.position.y, y1, "a block change re-renders")


func test_off_and_once_modes_never_retrigger() -> void:
	var visuals: TerritoryVisuals = TerritoryVisuals.new()
	var wired: Dictionary = _make_skybox_with_probe(visuals)
	var skybox: Skybox = wired["skybox"] as Skybox
	var probe: ReflectionProbe = wired["probe"] as ReflectionProbe
	var registry: BlockRegistry = BlockRegistry.new()
	add_child_autofree(registry)
	skybox._probe_registry = registry
	var y0: float = probe.position.y
	for mode: int in [GraphicsPreset.ReflectionProbeMode.OFF, GraphicsPreset.ReflectionProbeMode.ONCE]:
		skybox._probe_mode = mode
		registry.mark_territory_dirty()
		skybox._step_probe_interval(100.0)
		assert_eq(probe.position.y, y0)


func test_reflection_probe_disabled_hides_it() -> void:
	var visuals: TerritoryVisuals = TerritoryVisuals.new()
	visuals.reflection_probe_enabled = false
	var wired: Dictionary = _make_skybox_with_probe(visuals)
	var probe: ReflectionProbe = wired["probe"] as ReflectionProbe

	assert_false(probe.visible)


func test_reflection_probe_excludes_the_disc_mirror_layer() -> void:
	# Bontago-xtq.20 (owner, 2026-09-23 20:12: "graphics flickering"):
	# fail-before this fix -- a fresh ReflectionProbe's default cull_mask
	# includes every layer, including TerritoryOverlay.DISC_LAYER_BIT (the layer
	# the removed DiscMirror moves the disc onto in _ready() so its OWN mirror
	# camera cannot see it). Left unset, the probe would still bake the disc's
	# own shader (which samples SCREEN_UV of a SubViewport rendered for the
	# main camera's projection, meaningless from a cubemap face's own
	# projection) into its cubemap every UPDATE_ALWAYS frame -- an incoherent
	# image that changes every frame, i.e. flicker.
	var visuals: TerritoryVisuals = TerritoryVisuals.new()
	var wired: Dictionary = _make_skybox_with_probe(visuals)
	var probe: ReflectionProbe = wired["probe"] as ReflectionProbe

	assert_eq(
		probe.cull_mask & TerritoryOverlay.DISC_LAYER_BIT, 0,
		"the reflection probe must not see the layer the disc's planar-mirror material lives on.",
	)
	assert_eq(
		probe.cull_mask, Skybox.PROBE_CULL_MASK,
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


func test_configure_ssr_writes_ssao_fields_and_defaults_off() -> void:
	var wired: Dictionary = _make_wired_skybox()
	var skybox: Skybox = wired["skybox"] as Skybox
	var environment: Environment = wired["environment"] as Environment
	var visuals: TerritoryVisuals = TerritoryVisuals.new()
	assert_false(visuals.ssao_enabled, "SSAO must default off so the shipped look is unchanged.")
	skybox.visuals = visuals
	skybox.configure_ssr()
	assert_false(environment.ssao_enabled)

	visuals.ssao_enabled = true
	visuals.ssao_radius = 1.7
	visuals.ssao_intensity = 3.5
	visuals.ssao_power = 2.2
	visuals.ssao_detail = 0.7
	visuals.ssao_horizon = 0.1
	visuals.ssao_sharpness = 0.9
	visuals.ssao_light_affect = 0.3
	visuals.ssao_ao_channel_affect = 0.4
	skybox.refresh_from_visuals()

	assert_true(environment.ssao_enabled)
	assert_almost_eq(environment.ssao_radius, 1.7, 0.0001)
	assert_almost_eq(environment.ssao_intensity, 3.5, 0.0001)
	assert_almost_eq(environment.ssao_power, 2.2, 0.0001)
	assert_almost_eq(environment.ssao_detail, 0.7, 0.0001)
	assert_almost_eq(environment.ssao_horizon, 0.1, 0.0001)
	assert_almost_eq(environment.ssao_sharpness, 0.9, 0.0001)
	assert_almost_eq(environment.ssao_light_affect, 0.3, 0.0001)
	assert_almost_eq(environment.ssao_ao_channel_affect, 0.4, 0.0001)


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
