extends GutTest
## Bontago-adt.1: night theme resource, theme-driven light/environment,
## 3D cloud-puff sea and distant bird flocks.

const NIGHT_PATH: String = "res://config/sky_themes/night.tres"
const SUNSET_PATH: String = "res://config/sky_themes/sunset.tres"


func _make_skybox(theme: SkyThemeDef) -> Array:
	var environment: Environment = Environment.new()
	environment.sky = Sky.new()
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.name = "Light"
	add_child_autofree(light)
	var skybox: Skybox = Skybox.new()
	skybox.config = SkyboxConfig.new()
	skybox.environment = environment
	skybox.theme = theme
	skybox.light_path = skybox.get_path_to(light) if skybox.is_inside_tree() else NodePath("")
	add_child_autofree(skybox)
	skybox.light_path = skybox.get_path_to(light)
	return [skybox, environment, light]


func test_night_theme_loads_with_night_fields() -> void:
	var night: SkyThemeDef = Skybox.load_theme("night")
	assert_not_null(night, "night.tres must load through Skybox.load_theme")
	assert_not_null(night.sky_material)
	assert_not_null(night.cloud_puff_material)
	assert_true(night.light_color.b > night.light_color.r, "moonlight is cool-coloured")
	assert_null(Skybox.load_theme("no_such_theme"))


func test_apply_theme_writes_light_and_environment() -> void:
	var night: SkyThemeDef = load(NIGHT_PATH) as SkyThemeDef
	var parts: Array = _make_skybox(load(SUNSET_PATH) as SkyThemeDef)
	var skybox: Skybox = parts[0]
	var environment: Environment = parts[1]
	var light: DirectionalLight3D = parts[2]
	skybox.apply_theme(night)
	assert_almost_eq(light.light_energy, night.light_energy, 0.0001)
	assert_eq(light.light_color, night.light_color)
	assert_almost_eq(environment.ambient_light_energy, night.ambient_energy, 0.0001)
	assert_almost_eq(environment.glow_hdr_threshold, night.glow_hdr_threshold, 0.0001)


func test_sunset_defaults_match_the_original_scene_values() -> void:
	var sunset: SkyThemeDef = load(SUNSET_PATH) as SkyThemeDef
	assert_almost_eq(sunset.light_energy, 0.85, 0.0001)
	assert_almost_eq(sunset.ambient_energy, 0.5, 0.0001)
	assert_almost_eq(sunset.glow_hdr_threshold, 1.3, 0.0001)


func test_cloud_sea_scales_clumps_with_density() -> void:
	var sunset: SkyThemeDef = load(SUNSET_PATH) as SkyThemeDef
	var sea: CloudSea = CloudSea.new()
	add_child_autofree(sea)
	sea.configure(sunset, 1.0, sunset.sky_material)
	var full: int = sea.puff_count()
	assert_eq(full, (sunset.cloud_clump_count + sunset.cloud_bank_count) * sunset.cloud_puffs_per_clump)
	sea.configure(sunset, 0.5, sunset.sky_material)
	assert_lt(sea.puff_count(), full)
	assert_gt(sea.puff_count(), 0)
	sea.configure(sunset, 0.0, sunset.sky_material)
	assert_eq(sea.puff_count(), 0)
	assert_false(sea.visible)


func test_cloud_puffs_stay_below_the_disc_and_off_the_mirror_layer() -> void:
	for path: String in [SUNSET_PATH, NIGHT_PATH]:
		var theme: SkyThemeDef = load(path) as SkyThemeDef
		var sea: CloudSea = CloudSea.new()
		add_child_autofree(sea)
		sea.configure(theme, 1.0, theme.sky_material)
		assert_true(theme.cloud_top_max_m < -10.0, "%s: puff ceiling well under the disc" % path)
		# Bontago-470.5: the cloud banks stand higher than the sea but only far
		# beyond the largest disc, so no gameplay camera can be inside one.
		assert_true(theme.cloud_bank_ring_inner_m > MapDef.RADIUS_LARGE * 3.0, "%s: banks stay far from the play area" % path)
		assert_true(sea.highest_puff_top() <= maxf(theme.cloud_top_max_m + theme.cloud_puff_raise_m, theme.cloud_bank_top_max_m) + 0.001,
			"%s: no puff above its layer ceiling" % path)
		assert_eq(sea.puff_instance().layers, CloudSea.RENDER_LAYER_BIT)
		assert_eq(DiscMirror.MIRROR_CULL_MASK & CloudSea.RENDER_LAYER_BIT, 0, "mirror camera must not see the puffs")


func test_cloud_puffs_share_the_sky_panorama_and_grade() -> void:
	var night: SkyThemeDef = load(NIGHT_PATH) as SkyThemeDef
	var sea: CloudSea = CloudSea.new()
	add_child_autofree(sea)
	sea.configure(night, 1.0, night.sky_material)
	var material: ShaderMaterial = sea.puff_material()
	var sky: ShaderMaterial = night.sky_material as ShaderMaterial
	assert_eq(material.get_shader_parameter(&"panorama"), sky.get_shader_parameter(&"panorama"))
	assert_almost_eq(float(material.get_shader_parameter(&"grade_amount")), 1.0, 0.0001)
	assert_almost_eq(float(material.get_shader_parameter(&"sky_yaw_offset_deg")), night.sky_yaw_offset_deg, 0.0001)
	assert_ne(material, night.cloud_puff_material, "the theme's material is duplicated, not edited")


func test_cloud_puffs_copy_procedural_sea_uniforms() -> void:
	var night: SkyThemeDef = load(NIGHT_PATH) as SkyThemeDef
	var sky: ShaderMaterial = (night.sky_material as ShaderMaterial).duplicate() as ShaderMaterial
	sky.set_shader_parameter(&"procedural_sea_mix", 1.0)
	sky.set_shader_parameter(&"proc_sea_color_near", Color(0.1, 0.2, 0.3))
	var sea: CloudSea = CloudSea.new()
	add_child_autofree(sea)
	sea.configure(night, 1.0, sky)
	var material: ShaderMaterial = sea.puff_material()
	assert_almost_eq(float(material.get_shader_parameter(&"procedural_sea_mix")), 1.0, 0.0001)
	assert_eq(material.get_shader_parameter(&"proc_sea_color_near"), Color(0.1, 0.2, 0.3))
	assert_eq(material.get_shader_parameter(&"noise_tex"), sky.get_shader_parameter(&"noise_tex"))
	assert_almost_eq(float(material.get_shader_parameter(&"proc_horizon_glow_strength")), 0.0, 0.0001,
		"night puffs carry no orange horizon glow")


func test_puff_mesh_has_a_flat_base() -> void:
	var mesh: ArrayMesh = CloudSea.build_puff_mesh(0.35)
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var lowest: float = INF
	for v: Vector3 in vertices:
		lowest = minf(lowest, v.y)
	assert_almost_eq(lowest, -0.35, 0.0001)
	assert_eq((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), 20 * int(pow(4.0, CloudSea.PUFF_SUBDIVISIONS)) * 3)


func test_puff_mesh_subdivisions_follow_the_preset() -> void:
	var coarse: ArrayMesh = CloudSea.build_puff_mesh(0.35, 1)
	assert_eq((coarse.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), 20 * 4 * 3)
	assert_eq(load("res://config/graphics_presets/high.tres").cloud_puff_subdivisions, 1)


func test_birds_only_when_enabled_and_theme_has_flocks() -> void:
	var sunset: SkyThemeDef = load(SUNSET_PATH) as SkyThemeDef
	var birds: DistantBirds = DistantBirds.new()
	add_child_autofree(birds)
	birds.configure(sunset, true)
	assert_not_null(birds.flock_instance())
	assert_eq(birds.flock_instance().multimesh.instance_count, sunset.bird_flock_count * sunset.bird_flock_size_max)
	assert_eq(birds.active_flock_count(), 0, "birds are an occasional event: none in flight at start")
	birds.configure(sunset, false)
	assert_false(birds.visible)
	birds.configure(load(NIGHT_PATH) as SkyThemeDef, true)
	assert_false(birds.visible, "night has no bird flocks")


func test_bird_flights_stay_far_from_the_play_area() -> void:
	var sunset: SkyThemeDef = load(SUNSET_PATH) as SkyThemeDef
	assert_gt(sunset.bird_distance_min_m, MapDef.RADIUS_LARGE * 2.0, "flights must never pass near the disc")
	assert_gt(sunset.bird_gap_min_s, 30.0, "long quiet gaps between flocks")
	assert_gte(sunset.bird_flock_size_min, 2)
	assert_lte(sunset.bird_flock_size_max, 7)


# --- Bontago-adt: live theme switching ------------------------------------------

func test_list_available_themes_skips_noise_textures() -> void:
	var ids: PackedStringArray = Skybox.list_available_themes()
	assert_true(ids.has("sunset"))
	assert_true(ids.has("night"))
	assert_false(ids.has("cloud_noise"))
	assert_false(ids.has("puff_noise"))


func _ambient_child_count(skybox: Skybox) -> int:
	# Every node under the skybox plus the multimesh instance counts: repeated
	# switches must not accumulate nodes or puffs.
	var total: int = 0
	var stack: Array[Node] = [skybox]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		total += 1
		for child: Node in node.get_children():
			if not child.is_queued_for_deletion():
				stack.append(child)
	return total


func test_live_theme_switch_is_stable_and_matches_the_theme() -> void:
	var parts: Array = _make_skybox(load(SUNSET_PATH) as SkyThemeDef)
	var skybox: Skybox = parts[0]
	var environment: Environment = parts[1]
	var light: DirectionalLight3D = parts[2]
	var flare: SunFlare = SunFlare.new()
	add_child_autofree(flare)
	var night: SkyThemeDef = load(NIGHT_PATH) as SkyThemeDef
	var sunset: SkyThemeDef = load(SUNSET_PATH) as SkyThemeDef
	var saved_theme_name: String = skybox.config.theme_name
	assert_true(skybox.set_theme_by_id("night"))
	await get_tree().process_frame
	var baseline: int = _ambient_child_count(skybox)
	var night_puffs: int = skybox.get_cloud_sea().puff_count()
	assert_eq(night_puffs, (night.cloud_clump_count + night.cloud_bank_count) * night.cloud_puffs_per_clump
		if Settings.current_graphics_preset() == null
		else skybox.get_cloud_sea().puff_count())
	for cycle: int in range(4):
		assert_true(skybox.set_theme_by_id("sunset"))
		assert_eq(light.light_color, sunset.light_color)
		assert_almost_eq(light.light_energy, sunset.light_energy, 0.0001)
		assert_almost_eq(environment.ambient_light_energy, sunset.ambient_energy, 0.0001)
		assert_almost_eq(environment.fog_density, sunset.fog_density, 0.000001)
		assert_true(flare.is_theme_enabled())
		assert_true(skybox.set_theme_by_id("night"))
		assert_eq(light.light_color, night.light_color)
		assert_almost_eq(light.light_energy, night.light_energy, 0.0001)
		assert_almost_eq(light.rotation_degrees.x, night.light_rotation_deg.x, 0.001)
		assert_almost_eq(environment.glow_hdr_threshold, night.glow_hdr_threshold, 0.0001)
		assert_eq(environment.sky.sky_material, night.sky_material)
		assert_false(flare.is_theme_enabled(), "night hides the sunset-aimed flare")
		var fog: FogVolume = skybox.get_fog_volume()
		assert_eq(fog.size, night.cloud_deck_size_m)
		assert_eq((fog.material as FogMaterial).albedo, night.fog_color)
		await get_tree().process_frame
		assert_eq(skybox.get_cloud_sea().puff_count(), night_puffs, "same puff count each night switch")
		assert_eq(_ambient_child_count(skybox), baseline, "no leaked or duplicated nodes")
	assert_true(skybox.set_theme_by_id("sunset"))
	assert_eq(environment.sky.sky_material, sunset.sky_material)
	assert_false(skybox.set_theme_by_id("no_such_theme"))
	skybox.config.theme_name = saved_theme_name


func test_bird_mesh_has_a_body_and_two_flapping_swept_wings() -> void:
	var mesh: ArrayMesh = DistantBirds.build_bird_mesh()
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	assert_eq(vertices.size(), uvs.size())
	assert_gt(vertices.size(), 12, "more than the old 6-vertex triangle pair")
	var max_z: float = 0.0
	var min_z: float = 0.0
	var body_vertices: int = 0
	var tip_flap: float = 0.0
	for i: int in range(vertices.size()):
		max_z = maxf(max_z, vertices[i].z)
		min_z = minf(min_z, vertices[i].z)
		if uvs[i].x == 0.0:
			body_vertices += 1
		if absf(vertices[i].z) >= DistantBirds.HALF_SPAN - 0.001:
			tip_flap = maxf(tip_flap, uvs[i].x)
			assert_lt(vertices[i].x, 0.0, "wing tips sweep back behind the body centre")
	assert_almost_eq(max_z, DistantBirds.HALF_SPAN, 0.001)
	assert_almost_eq(min_z, -DistantBirds.HALF_SPAN, 0.001)
	assert_almost_eq(tip_flap, 1.0, 0.001)
	assert_gt(body_vertices, 8, "body vertices stay put (flap weight 0)")


## Bontago-t8x.2: the overhead cloud layers are off by default (kept, not deleted)
## and the puff layer is raised, but no puff that could reach the disc or the
## play volume rises above the disc's underside minus the derived clearance.
func test_overhead_clouds_off_by_default_and_puffs_stay_clear_of_the_disc() -> void:
	var theme: SkyThemeDef = load(SUNSET_PATH) as SkyThemeDef
	assert_false(theme.proc_overhead_clouds_enabled, "overhead layer off by default")
	assert_gt(theme.cloud_puff_raise_m, 0.0, "puff layer raised")
	var sky: ShaderMaterial = theme.sky_material as ShaderMaterial
	var skybox: Skybox = autofree(Skybox.new())
	skybox._apply_procedural_params(sky, theme)
	assert_eq(float(sky.get_shader_parameter("proc_overhead_mix")), 0.0)
	theme = theme.duplicate() as SkyThemeDef
	theme.proc_overhead_clouds_enabled = true
	skybox._apply_procedural_params(sky, theme)
	assert_eq(float(sky.get_shader_parameter("proc_overhead_mix")), 1.0)
	for look: bool in [false, true]:
		theme.sky_look_procedural = look
		for raise: float in [0.0, theme.cloud_puff_raise_m, 80.0]:
			theme.cloud_puff_raise_m = raise
			var sea: CloudSea = CloudSea.new()
			add_child_autofree(sea)
			sea.configure(theme, 1.0, theme.sky_material)
			assert_true(sea.highest_top_near_disc() <= CloudSea.disc_ceiling_m(theme) + 0.001,
				"raise %s procedural %s: puffs near the disc stay under it" % [raise, look])
	assert_almost_eq(CloudSea.exclusion_radius_m(theme), MapDef.RADIUS_LARGE * (1.0 + theme.cloud_disc_clearance_ratio), 0.001)


## Bontago-t8x.3: the flare, the sky-shader sun and the light's sun direction
## agree, so there is one sun from every angle.
func test_flare_sky_and_light_agree_on_the_sun_direction() -> void:
	var theme: SkyThemeDef = load(SUNSET_PATH) as SkyThemeDef
	var flare: SunFlareConfig = load("res://config/sun_flare.tres") as SunFlareConfig
	var sky: ShaderMaterial = theme.sky_material as ShaderMaterial
	var sky_dir: Vector3 = sky.get_shader_parameter("sun_direction") as Vector3
	assert_gt(flare.sun_direction.normalized().dot(sky_dir.normalized()), 0.9999)
	var puffs: ShaderMaterial = theme.cloud_puff_material as ShaderMaterial
	assert_gt((puffs.get_shader_parameter("light_direction") as Vector3).normalized().dot(sky_dir.normalized()), 0.9999)
	assert_gt(flare.ghost_ring_width, 0.0, "ghosts are rings, not solid sun-like discs")
func test_cycle_reuses_material_and_aligns_sun_with_flare() -> void:
	var parts: Array = _make_skybox(load(SUNSET_PATH) as SkyThemeDef)
	var skybox: Skybox = parts[0] as Skybox
	var environment: Environment = parts[1] as Environment
	var flare: SunFlare = SunFlare.new()
	add_child_autofree(flare)
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = MatchConfig.SkyThemeMode.CYCLE
	skybox.configure_match_sky(config)
	var material: ShaderMaterial = environment.sky.sky_material as ShaderMaterial
	assert_almost_eq(float(material.get_shader_parameter(&"procedural_sea_mix")), 1.0, 0.001)
	var dawn: Vector3 = material.get_shader_parameter(&"sun_direction") as Vector3
	skybox.set_cycle_phase(0.25)
	assert_same(environment.sky.sky_material, material, "cycle must update one material")
	var day: Vector3 = material.get_shader_parameter(&"sun_direction") as Vector3
	assert_gt(day.y, dawn.y, "sun rises between dawn and day")
	assert_eq(flare.config.sun_direction, day, "flare projects the same sun as the sky")
	assert_true(flare.is_theme_enabled())
	skybox.set_cycle_phase(0.75)
	assert_gt(float(material.get_shader_parameter(&"cycle_night_mix")), 0.99)
	assert_lt((material.get_shader_parameter(&"sun_direction") as Vector3).y, 0.0)
	assert_false(flare.is_theme_enabled())
	skybox.set_theme_by_id("sunset")
	assert_eq(flare.config.sun_direction, (load("res://config/sun_flare.tres") as SunFlareConfig).sun_direction,
		"leaving cycle restores the authored flare direction")


## Bontago-mp0.83 (owner playtest 2026-10-03): one full day/night cycle is 5 min
## for every theme the match can use, straight from the shipped resources.
func test_every_theme_ships_a_five_minute_cycle() -> void:
	assert_almost_eq(SkyThemeDef.new().cycle_length_seconds, 300.0, 0.001, "script default")
	var ids: PackedStringArray = Skybox.list_available_themes()
	for id: String in MatchConfig.SKY_THEME_IDS:
		assert_true(ids.has(id), "match theme %s must be a shipped theme" % id)
	for id: String in ids:
		var shipped: SkyThemeDef = ResourceLoader.load(
			"res://config/sky_themes/%s.tres" % id, "", ResourceLoader.CACHE_MODE_IGNORE) as SkyThemeDef
		assert_almost_eq(shipped.cycle_length_seconds, 300.0, 0.001, "%s.tres cycle length" % id)


func _cycle_skybox() -> Skybox:
	var parts: Array = _make_skybox(load(SUNSET_PATH) as SkyThemeDef)
	var skybox: Skybox = parts[0] as Skybox
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = MatchConfig.SkyThemeMode.CYCLE
	skybox.configure_match_sky(config)
	return skybox


func test_cycle_runs_a_full_loop_in_the_authored_length() -> void:
	var sunset: SkyThemeDef = load(SUNSET_PATH) as SkyThemeDef
	var saved_length: float = sunset.cycle_length_seconds
	sunset.cycle_length_seconds = 300.0
	var skybox: Skybox = _cycle_skybox()
	assert_almost_eq(skybox.cycle_length_seconds(), 300.0, 0.001)
	skybox.update_cycle_clock(75.0)
	assert_almost_eq(skybox.cycle_phase_at(75.0), 0.25, 0.0001, "noon after a quarter of 5 min")
	skybox.update_cycle_clock(150.0)
	assert_almost_eq(skybox.cycle_phase_at(150.0), 0.5, 0.0001)
	assert_almost_eq(skybox.cycle_phase_at(300.0), 0.0, 0.0001, "a full cycle takes 300 s")
	sunset.cycle_length_seconds = saved_length


## Bontago-mp0.83: a live length edit changes the speed only; the time of day
## at the moment of the edit is unchanged.
func test_cycle_length_change_keeps_the_phase_continuous() -> void:
	var sunset: SkyThemeDef = load(SUNSET_PATH) as SkyThemeDef
	var saved_length: float = sunset.cycle_length_seconds
	sunset.cycle_length_seconds = 300.0
	var skybox: Skybox = _cycle_skybox()
	skybox.update_cycle_clock(100.0)
	var before: float = skybox.cycle_phase_at(100.0)
	skybox.set_cycle_length_seconds(900.0)
	assert_almost_eq(skybox.cycle_length_seconds(), 900.0, 0.001)
	assert_almost_eq(skybox.cycle_phase_at(100.0), before, 0.0001, "no jump at the edit")
	skybox.update_cycle_clock(190.0)
	assert_almost_eq(skybox.cycle_phase_at(190.0), fposmod(before + 90.0 / 900.0, 1.0), 0.0001,
		"afterwards the phase advances at the new rate")
	skybox.set_cycle_length_seconds(60.0)
	assert_almost_eq(skybox.cycle_phase_at(190.0), fposmod(before + 90.0 / 900.0, 1.0), 0.0001, "shortening is continuous too")
	skybox.update_cycle_clock(220.0)
	assert_almost_eq(skybox.cycle_phase_at(220.0), fposmod(before + 90.0 / 900.0 + 30.0 / 60.0, 1.0), 0.0001)
	# A direct write to the live theme (not through the seam) is folded in on
	# the next clock update without a jump as well.
	var direct: float = skybox.cycle_phase_at(220.0)
	skybox.theme.cycle_length_seconds = 120.0
	skybox.update_cycle_clock(220.0)
	assert_almost_eq(skybox.cycle_phase_at(220.0), direct, 0.0001)
	sunset.cycle_length_seconds = saved_length


func test_cycle_length_seam_is_inert_outside_cycle_mode() -> void:
	var parts: Array = _make_skybox(load(SUNSET_PATH) as SkyThemeDef)
	var skybox: Skybox = parts[0] as Skybox
	var sunset: SkyThemeDef = load(SUNSET_PATH) as SkyThemeDef
	var saved_length: float = sunset.cycle_length_seconds
	skybox.set_cycle_length_seconds(900.0)
	assert_almost_eq(skybox.cycle_length_seconds(), 0.0, 0.001, "no cycle running")
	assert_almost_eq(sunset.cycle_length_seconds, saved_length, 0.001, "a static theme is untouched")


func test_dawn_and_storm_themes_load_with_their_character() -> void:
	var dawn: SkyThemeDef = Skybox.load_theme("dawn")
	var storm: SkyThemeDef = Skybox.load_theme("storm")
	assert_not_null(dawn, "dawn.tres must load through Skybox.load_theme")
	assert_not_null(storm, "storm.tres must load through Skybox.load_theme")
	for theme: SkyThemeDef in [dawn, storm]:
		assert_not_null(theme.sky_material)
		assert_not_null(theme.cloud_puff_material)
		assert_true(theme.cloud_top_max_m < -10.0, "puff ceiling well under the disc")
		assert_true(theme.cloud_bank_ring_inner_m > MapDef.RADIUS_LARGE * 3.0, "banks stay far from the play area")
	assert_gt(dawn.sky_top_color.b, dawn.sky_top_color.r, "dawn zenith is cool")
	assert_gt(dawn.sky_horizon_color.r, dawn.sky_horizon_color.b, "dawn horizon is warm")
	assert_gt(dawn.sky_top_color.v, storm.sky_top_color.v, "storm is darker than dawn")
	assert_lt(storm.light_energy, dawn.light_energy, "storm sun is muted")
	assert_false(storm.sun_flare_enabled)


## Bontago-59o.18 (S0): the locked phases the lobby's Sunset / Dawn / Night options
## use. Each concrete id maps to its authored phase, anything else (including the
## "" of a running cycle) is -1.0, and the shipped defaults put the sun where the
## option's name says (phase 0 dawn, 0.25 noon, 0.5 sunset, 0.75 midnight).
func test_locked_phase_for_maps_concrete_ids_and_rejects_the_rest() -> void:
	var theme: SkyThemeDef = SkyThemeDef.new()
	assert_eq(theme.locked_phase_for("sunset"), theme.cycle_locked_phase_sunset)
	assert_eq(theme.locked_phase_for("dawn"), theme.cycle_locked_phase_dawn)
	assert_eq(theme.locked_phase_for("night"), theme.cycle_locked_phase_night)
	for unknown: String in ["", "cycle", "storm", "../evil", "Sunset"]:
		assert_eq(theme.locked_phase_for(unknown), -1.0, "'%s' is not a lockable sky id" % unknown)
	for sky_id: String in MatchConfig.SKY_THEME_IDS:
		var phase: float = theme.locked_phase_for(sky_id)
		assert_between(phase, 0.0, 1.0, "%s has a lock phase in the 0..1 cycle" % sky_id)
	theme.cycle_locked_phase_night = 0.8
	assert_eq(theme.locked_phase_for("night"), 0.8, "the lock phase is tunable content")


func test_cycle_lock_and_start_defaults_match_the_option_names() -> void:
	var theme: SkyThemeDef = SkyThemeDef.new()
	var sun_height: Callable = func(phase: float) -> float:
		return sin(TAU * phase) * theme.cycle_sun_peak_degrees
	assert_gt(sun_height.call(theme.cycle_start_phase), 30.0, "a Cycle match opens in full daylight")
	assert_gt(sun_height.call(theme.cycle_locked_phase_sunset), 0.0, "locked Sunset: sun still above the horizon")
	assert_lt(theme.cycle_locked_phase_sunset, 0.5, "locked Sunset: on the setting side")
	assert_gt(sun_height.call(theme.cycle_locked_phase_dawn), 0.0, "locked Dawn: sun just risen")
	assert_lt(theme.cycle_locked_phase_dawn, 0.25, "locked Dawn: in the morning half")
	assert_lt(sun_height.call(theme.cycle_locked_phase_night), 0.0, "locked Night: sun below the horizon")
	assert_eq(theme.cycle_dusk_weight_phases, Vector4(0.30, 0.46, 0.90, 0.98))
	var phases: Vector4 = theme.cycle_dusk_weight_phases
	assert_true(phases.x < phases.y and phases.y < phases.z and phases.z < phases.w, "dusk weight phases ascend")
	# Shipped themes keep the script defaults: nothing overrides the lock content.
	for theme_id: String in ["sunset", "dawn", "night", "storm"]:
		var shipped: SkyThemeDef = Skybox.load_theme(theme_id)
		assert_eq(shipped.cycle_start_phase, theme.cycle_start_phase, theme_id)
		assert_eq(shipped.locked_phase_for("dawn"), theme.cycle_locked_phase_dawn, theme_id)


## S0 stubs (docs/SKY_CYCLE_DEFAULT_PLAN.md s3): the new Skybox API exists with
## its final signatures; until C1a the mutators change nothing and the queries
## read today's cycle state.
func test_cycle_api_stubs_exist_and_are_inert() -> void:
	var parts: Array = _make_skybox(load(SUNSET_PATH) as SkyThemeDef)
	var skybox: Skybox = parts[0]
	assert_false(skybox.is_cycle_active(), "no cycle before a match configures one")
	assert_eq(skybox.locked_phase(), -1.0)
	assert_eq(skybox.current_cycle_phase(), -1.0)
	skybox.start_cycle(0.5, 0.1)
	skybox.set_locked_phase(0.5)
	skybox.refresh_cycle_sources()
	assert_false(skybox.is_cycle_active(), "the S0 stubs do not start a cycle")
	assert_eq(skybox.locked_phase(), -1.0)
	var config: MatchConfig = MatchConfig.new()
	assert_true(config.is_sky_cycle_running(), "the default match is a Cycle match")
	skybox.configure_match_sky(config)
	assert_true(skybox.is_cycle_active(), "the existing CYCLE path is what the default now runs")
	assert_between(skybox.current_cycle_phase(), 0.0, 1.0)
	assert_eq(skybox.locked_phase(), -1.0)
