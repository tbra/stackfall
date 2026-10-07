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


func test_sunset_theme_drives_a_lit_scene_through_apply_theme() -> void:
	var sunset: SkyThemeDef = load(SUNSET_PATH) as SkyThemeDef
	var parts: Array = _make_skybox(load(NIGHT_PATH) as SkyThemeDef)
	var skybox: Skybox = parts[0]
	var environment: Environment = parts[1]
	var light: DirectionalLight3D = parts[2]
	skybox.apply_theme(sunset)
	assert_almost_eq(light.light_energy, sunset.light_energy, 0.0001)
	assert_almost_eq(environment.ambient_light_energy, sunset.ambient_energy, 0.0001)
	assert_almost_eq(environment.glow_hdr_threshold, sunset.glow_hdr_threshold, 0.0001)
	assert_gt(sunset.light_energy, 0.0, "the sunset sun lights the field")
	assert_gt(sunset.light_energy, sunset.ambient_energy, "the sun outshines the ambient so shadows read")
	assert_gt(sunset.ambient_energy, 0.0)


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
		assert_eq(Skybox.PROBE_CULL_MASK & CloudSea.RENDER_LAYER_BIT, 0, "mirror camera must not see the puffs")


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
func test_every_theme_ships_one_consistent_cycle_length() -> void:
	var default_length: float = SkyThemeDef.new().cycle_length_seconds
	assert_gt(default_length, 0.0)
	var ids: PackedStringArray = Skybox.list_available_themes()
	for id: String in MatchConfig.SKY_THEME_IDS:
		assert_true(ids.has(id), "match theme %s must be a shipped theme" % id)
	for id: String in ids:
		var shipped: SkyThemeDef = ResourceLoader.load(
			"res://config/sky_themes/%s.tres" % id, "", ResourceLoader.CACHE_MODE_IGNORE) as SkyThemeDef
		assert_almost_eq(shipped.cycle_length_seconds, default_length, 0.001, "%s.tres does not override the shared cycle length" % id)


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
	# Bontago-59o.18: the cycle opens at SkyThemeDef.cycle_start_phase, not at dawn.
	var start: float = sunset.cycle_start_phase
	skybox.update_cycle_clock(75.0)
	assert_almost_eq(skybox.cycle_phase_at(75.0), fposmod(start + 0.25, 1.0), 0.0001, "a quarter of 5 min on")
	skybox.update_cycle_clock(150.0)
	assert_almost_eq(skybox.cycle_phase_at(150.0), fposmod(start + 0.5, 1.0), 0.0001)
	assert_almost_eq(skybox.cycle_phase_at(300.0), start, 0.0001, "a full cycle takes 300 s")
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
	var phases: Vector4 = theme.cycle_dusk_weight_phases
	assert_true(phases.x < phases.y and phases.y < phases.z and phases.z < phases.w, "dusk weight phases ascend")
	# Shipped themes keep the script defaults: nothing overrides the lock content.
	for theme_id: String in ["sunset", "dawn", "night", "storm"]:
		var shipped: SkyThemeDef = Skybox.load_theme(theme_id)
		assert_eq(shipped.cycle_start_phase, theme.cycle_start_phase, theme_id)
		assert_eq(shipped.locked_phase_for("dawn"), theme.cycle_locked_phase_dawn, theme_id)


## Bontago-59o.18 (C1a, docs/SKY_CYCLE_DEFAULT_PLAN.md s3): Cycle is the default sky
## and Sunset / Night / Dawn / Random are the same cycle locked at a phase.
func _configured_skybox(config: MatchConfig) -> Array:
	var parts: Array = _make_skybox(load(SUNSET_PATH) as SkyThemeDef)
	(parts[0] as Skybox).configure_match_sky(config)
	return parts


func _sun_elevation(skybox: Skybox) -> float:
	return ((skybox.theme.sky_material as ShaderMaterial).get_shader_parameter(&"sun_direction") as Vector3).y


func _night_mix(skybox: Skybox) -> float:
	return float((skybox.theme.sky_material as ShaderMaterial).get_shader_parameter(&"cycle_night_mix"))


func test_no_cycle_before_a_match_and_the_mutators_are_inert() -> void:
	var parts: Array = _make_skybox(load(SUNSET_PATH) as SkyThemeDef)
	var skybox: Skybox = parts[0]
	assert_false(skybox.is_cycle_active(), "no cycle before a match configures one")
	assert_eq(skybox.locked_phase(), -1.0)
	assert_eq(skybox.current_cycle_phase(), -1.0)
	skybox.set_locked_phase(0.5)
	skybox.refresh_cycle_sources()
	assert_false(skybox.is_cycle_active(), "locking or refreshing never starts a cycle")
	assert_eq(skybox.locked_phase(), -1.0)


func test_default_match_runs_the_cycle_from_the_start_phase() -> void:
	var config: MatchConfig = MatchConfig.new()
	assert_true(config.is_sky_cycle_running(), "the default match is a Cycle match")
	var parts: Array = _configured_skybox(config)
	var skybox: Skybox = parts[0]
	var environment: Environment = parts[1]
	var start: float = (load(SUNSET_PATH) as SkyThemeDef).cycle_start_phase
	assert_true(skybox.is_cycle_active())
	assert_eq(skybox.locked_phase(), -1.0, "the default cycle runs")
	assert_almost_eq(skybox.current_cycle_phase(), start, 0.0001, "opens at the start phase")
	assert_almost_eq(skybox.cycle_phase_at(0.0), start, 0.0001, "the shared clock starts at 0")
	assert_gt(_sun_elevation(skybox), 0.5, "morning: the sun is well up")
	assert_lt(_night_mix(skybox), 0.01, "the start phase is full day")
	assert_eq(environment.sky.process_mode, Sky.PROCESS_MODE_INCREMENTAL, "a running cycle keeps updating the radiance")
	skybox.update_cycle_clock(30.0)
	assert_almost_eq(skybox.current_cycle_phase(), fposmod(start + 30.0 / 300.0, 1.0), 0.0001, "the clock carries it on")


func test_each_sky_mode_locks_the_right_phase() -> void:
	var source: SkyThemeDef = load(SUNSET_PATH) as SkyThemeDef
	var cases: Array[Array] = [
		[MatchConfig.SkyThemeMode.DAY, "sunset", source.cycle_locked_phase_sunset],
		[MatchConfig.SkyThemeMode.NIGHT, "night", source.cycle_locked_phase_night],
		[MatchConfig.SkyThemeMode.DAWN, "dawn", source.cycle_locked_phase_dawn],
	]
	for roll: int in range(MatchConfig.SKY_THEME_IDS.size()):
		var random_config: MatchConfig = MatchConfig.new()
		random_config.sky_theme_mode = MatchConfig.SkyThemeMode.RANDOM
		random_config.resolve_sky_theme(roll)
		cases.append([MatchConfig.SkyThemeMode.RANDOM, random_config.sky_theme_resolved, source.locked_phase_for(random_config.sky_theme_resolved)])
	for entry: Array in cases:
		var config: MatchConfig = MatchConfig.new()
		config.sky_theme_mode = entry[0] as MatchConfig.SkyThemeMode
		config.resolve_sky_theme(MatchConfig.SKY_THEME_IDS.find(entry[1] as String))
		var label: String = "mode %s -> %s" % [entry[0], entry[1]]
		var expected: float = entry[2] as float
		var parts: Array = _configured_skybox(config)
		var skybox: Skybox = parts[0]
		var environment: Environment = parts[1]
		assert_true(skybox.is_cycle_active(), label)
		assert_almost_eq(skybox.locked_phase(), expected, 0.0001, "%s: locked phase" % label)
		assert_almost_eq(skybox.current_cycle_phase(), expected, 0.0001, "%s: applied phase" % label)
		for clock: float in [0.0, 41.0, 987654.0]:
			skybox.update_cycle_clock(clock)
			assert_almost_eq(skybox.current_cycle_phase(), expected, 0.0001, "%s: the clock is ignored at %s s" % [label, clock])
		assert_eq(environment.sky.process_mode, Sky.PROCESS_MODE_QUALITY, "%s: a locked sky stops incremental updates" % label)
		if entry[1] == "night":
			assert_gt(_night_mix(skybox), 0.99, "%s: midnight" % label)
			assert_lt(_sun_elevation(skybox), 0.0, "%s: sun below the horizon" % label)
		else:
			assert_lt(_night_mix(skybox), 0.05, "%s: still daylight" % label)
			assert_gt(_sun_elevation(skybox), 0.0, "%s: sun above the horizon" % label)


func test_host_and_client_configs_give_the_same_phase_at_the_same_clock() -> void:
	var modes: Array[MatchConfig.SkyThemeMode] = [
		MatchConfig.SkyThemeMode.CYCLE, MatchConfig.SkyThemeMode.DAY, MatchConfig.SkyThemeMode.NIGHT,
		MatchConfig.SkyThemeMode.DAWN, MatchConfig.SkyThemeMode.RANDOM]
	for mode: MatchConfig.SkyThemeMode in modes:
		var host_config: MatchConfig = MatchConfig.new()
		host_config.sky_theme_mode = mode
		host_config.resolve_sky_theme(2)
		# The client only ever sees the wire form of the host's resolved config.
		var client_config: MatchConfig = MatchConfig.from_dict(host_config.to_dict())
		var host: Skybox = _configured_skybox(host_config)[0] as Skybox
		var client: Skybox = _configured_skybox(client_config)[0] as Skybox
		assert_eq(client.locked_phase(), host.locked_phase(), "mode %s: same lock" % mode)
		for clock: float in [0.0, 37.5, 123.4, 299.0, 301.0, 12345.6]:
			host.update_cycle_clock(clock)
			client.update_cycle_clock(clock)
			assert_almost_eq(client.current_cycle_phase(), host.current_cycle_phase(), 0.00001,
				"mode %s at clock %s" % [mode, clock])
			assert_eq(client.cycle_phase_at(clock), host.cycle_phase_at(clock), "mode %s pure phase at %s" % [mode, clock])


func test_storm_blend_composes_while_locked() -> void:
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = MatchConfig.SkyThemeMode.NIGHT
	config.resolve_sky_theme(0)
	var parts: Array = _configured_skybox(config)
	var skybox: Skybox = parts[0]
	var environment: Environment = parts[1]
	var storm: SkyThemeDef = Skybox.load_theme("storm")
	var locked: float = skybox.locked_phase()
	skybox.set_storm_sky(1.0, storm)
	assert_true(environment.fog_light_color.is_equal_approx(storm.fog_color), "storm fog over the locked night")
	assert_almost_eq(environment.ambient_light_energy, storm.ambient_energy, 0.001, "storm ambient")
	skybox.update_cycle_clock(500.0)
	assert_true(environment.fog_light_color.is_equal_approx(storm.fog_color), "a clock update keeps the storm")
	assert_eq(skybox.locked_phase(), locked, "the storm does not move the lock")
	skybox.set_locked_phase(0.03)
	assert_true(environment.fog_light_color.is_equal_approx(storm.fog_color), "moving the lock keeps the storm")
	skybox.set_storm_sky(0.0, storm)
	assert_false(environment.fog_light_color.is_equal_approx(storm.fog_color), "the storm clears")
	assert_almost_eq(skybox.current_cycle_phase(), 0.03, 0.0001, "and the lock is still in force")


func test_cycle_length_edit_is_inert_while_locked_and_unlock_is_continuous() -> void:
	var sunset: SkyThemeDef = load(SUNSET_PATH) as SkyThemeDef
	var saved_length: float = sunset.cycle_length_seconds
	sunset.cycle_length_seconds = 300.0
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = MatchConfig.SkyThemeMode.DAY
	config.resolve_sky_theme(0)
	var skybox: Skybox = _configured_skybox(config)[0] as Skybox
	var locked: float = skybox.locked_phase()
	skybox.update_cycle_clock(100.0)
	skybox.set_cycle_length_seconds(900.0)
	assert_almost_eq(skybox.cycle_length_seconds(), 900.0, 0.001, "the length is stored")
	skybox.update_cycle_clock(190.0)
	assert_almost_eq(skybox.current_cycle_phase(), locked, 0.0001, "the locked phase ignores the edit")
	skybox.set_locked_phase(-1.0)
	assert_eq(skybox.locked_phase(), -1.0)
	assert_almost_eq(skybox.cycle_phase_at(190.0), locked, 0.0001, "unlock continues from the locked phase")
	skybox.update_cycle_clock(280.0)
	assert_almost_eq(skybox.current_cycle_phase(), fposmod(locked + 90.0 / 900.0, 1.0), 0.0001, "then runs at the new length")
	sunset.cycle_length_seconds = saved_length


func test_lock_and_unlock_a_running_cycle_keep_the_phase_continuous() -> void:
	var sunset: SkyThemeDef = load(SUNSET_PATH) as SkyThemeDef
	var saved_length: float = sunset.cycle_length_seconds
	sunset.cycle_length_seconds = 300.0
	var parts: Array = _configured_skybox(MatchConfig.new())
	var skybox: Skybox = parts[0]
	var environment: Environment = parts[1]
	skybox.update_cycle_clock(30.0)
	skybox.set_locked_phase(0.75)
	assert_almost_eq(skybox.locked_phase(), 0.75, 0.0001)
	assert_almost_eq(skybox.current_cycle_phase(), 0.75, 0.0001, "the lock applies at once")
	assert_eq(environment.sky.process_mode, Sky.PROCESS_MODE_QUALITY)
	assert_gt(_night_mix(skybox), 0.99)
	skybox.update_cycle_clock(60.0)
	assert_almost_eq(skybox.current_cycle_phase(), 0.75, 0.0001, "the clock does not move a locked sky")
	skybox.set_locked_phase(1.25)
	assert_almost_eq(skybox.locked_phase(), 0.25, 0.0001, "a lock wraps into 0..1")
	skybox.set_locked_phase(-1.0)
	assert_eq(environment.sky.process_mode, Sky.PROCESS_MODE_INCREMENTAL, "running again")
	assert_almost_eq(skybox.cycle_phase_at(60.0), 0.25, 0.0001, "no jump at the unlock")
	skybox.update_cycle_clock(90.0)
	assert_almost_eq(skybox.current_cycle_phase(), 0.35, 0.0001, "and it carries on at the cycle rate")
	skybox.set_locked_phase(-1.0)
	assert_almost_eq(skybox.current_cycle_phase(), 0.35, 0.0001, "unlocking a running cycle is a no-op")
	sunset.cycle_length_seconds = saved_length


func test_start_cycle_restarts_with_the_given_lock_or_start_phase() -> void:
	var parts: Array = _make_skybox(load(SUNSET_PATH) as SkyThemeDef)
	var skybox: Skybox = parts[0]
	var environment: Environment = parts[1]
	skybox.start_cycle()
	assert_true(skybox.is_cycle_active())
	assert_almost_eq(skybox.current_cycle_phase(), (load(SUNSET_PATH) as SkyThemeDef).cycle_start_phase, 0.0001, "default start phase")
	assert_eq(skybox.locked_phase(), -1.0)
	skybox.start_cycle(-1.0, 0.6)
	assert_almost_eq(skybox.current_cycle_phase(), 0.6, 0.0001, "explicit start phase")
	assert_eq(skybox.locked_phase(), -1.0)
	skybox.start_cycle(0.75)
	assert_almost_eq(skybox.locked_phase(), 0.75, 0.0001, "explicit lock")
	assert_eq(environment.sky.process_mode, Sky.PROCESS_MODE_QUALITY)
	skybox.start_cycle()
	assert_eq(skybox.locked_phase(), -1.0, "a restart without a lock runs")
	assert_eq(environment.sky.process_mode, Sky.PROCESS_MODE_INCREMENTAL)


func test_a_static_theme_ends_the_cycle_and_its_lock() -> void:
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = MatchConfig.SkyThemeMode.NIGHT
	config.resolve_sky_theme(0)
	var parts: Array = _configured_skybox(config)
	var skybox: Skybox = parts[0]
	assert_gt(skybox.locked_phase(), 0.0)
	assert_true(skybox.set_theme_by_id("dawn"))
	assert_false(skybox.is_cycle_active())
	assert_eq(skybox.locked_phase(), -1.0)
	assert_eq(skybox.current_cycle_phase(), -1.0)
	assert_true(skybox.set_theme_by_id(Skybox.CYCLE_THEME_ID), "the F4 'cycle' entry restarts it")
	assert_true(skybox.is_cycle_active())
	assert_eq(skybox.locked_phase(), -1.0, "as a running cycle")
	assert_eq(skybox.config.theme_name, Skybox.CYCLE_THEME_ID, "and is remembered like a theme pick")


func test_apply_theme_of_a_cycle_source_does_not_swap_the_live_material() -> void:
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = MatchConfig.SkyThemeMode.DAWN
	config.resolve_sky_theme(0)
	var parts: Array = _configured_skybox(config)
	var skybox: Skybox = parts[0]
	var environment: Environment = parts[1]
	var live: Material = environment.sky.sky_material
	var duplicate: SkyThemeDef = skybox.theme
	var sunset: SkyThemeDef = Skybox.load_theme("sunset")
	assert_ne(live, sunset.sky_material, "fixture: the live sky is the duplicate's own material")
	skybox.apply_theme(sunset)
	assert_same(environment.sky.sky_material, live, "an F4 edit of the source theme keeps the live material")
	assert_same(skybox.theme, duplicate, "and the live duplicate")
	assert_true(skybox.is_cycle_active())
	skybox.apply_theme(Skybox.load_theme("night"))
	assert_same(environment.sky.sky_material, live, "the night source is a cycle source too")


func test_refresh_cycle_sources_copies_source_edits_to_the_live_duplicate() -> void:
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = MatchConfig.SkyThemeMode.NIGHT
	config.resolve_sky_theme(0)
	var parts: Array = _configured_skybox(config)
	var skybox: Skybox = parts[0]
	var environment: Environment = parts[1]
	var source: SkyThemeDef = Skybox.load_theme("sunset")
	var live: Material = environment.sky.sky_material
	var saved_width: float = source.proc_horizon_glow_width
	var saved_start: float = source.cycle_start_phase
	var locked: float = skybox.locked_phase()
	var edited: float = saved_width + 0.07
	source.proc_horizon_glow_width = edited
	source.cycle_start_phase = 0.4
	assert_false(is_equal_approx(skybox.theme.proc_horizon_glow_width, edited), "fixture: the duplicate is independent")
	skybox.refresh_cycle_sources()
	assert_almost_eq(skybox.theme.proc_horizon_glow_width, edited, 0.0001, "the edit reached the duplicate")
	assert_almost_eq(float((live as ShaderMaterial).get_shader_parameter("proc_horizon_glow_width")), edited, 0.0001, "and the live sky shader")
	assert_same(environment.sky.sky_material, live, "one material throughout")
	assert_eq(skybox.theme.sky_look_procedural, true, "the cycle stays procedural")
	assert_eq(skybox.theme.procedural_sea_mix, 1.0)
	assert_almost_eq(skybox.locked_phase(), locked, 0.0001, "the lock survives the refresh")
	assert_almost_eq(skybox.current_cycle_phase(), locked, 0.0001, "and the phase is re-applied")
	assert_gt(_night_mix(skybox), 0.99, "still midnight")
	source.proc_horizon_glow_width = saved_width
	source.cycle_start_phase = saved_start


## Bontago-59o.18 (C1b, docs/SKY_CYCLE_DEFAULT_PLAN.md s2): the cycle's day half is the
## dawn palette by morning and noon, fading into the sunset palette on the setting
## side (SkyPalette), and the night mix on top is unchanged.
func _day_palette_skybox(mode: MatchConfig.SkyThemeMode) -> Array:
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = mode
	config.resolve_sky_theme(0)
	return _configured_skybox(config)


func _live_sky(skybox: Skybox) -> ShaderMaterial:
	return skybox.theme.sky_material as ShaderMaterial


func _sky_color(material: ShaderMaterial, uniform: StringName) -> Color:
	return material.get_shader_parameter(uniform) as Color


func _color_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


func _assert_day_palette(skybox: Skybox, expected: SkyThemeDef, label: String) -> void:
	var live: ShaderMaterial = _live_sky(skybox)
	var source: ShaderMaterial = expected.sky_material as ShaderMaterial
	for field: StringName in [&"proc_zenith_color", &"proc_mid_color", &"proc_horizon_color", &"proc_horizon_glow_color",
			&"proc_sea_color_near", &"proc_sea_color_far"]:
		assert_true((skybox.theme.get(field) as Color).is_equal_approx(expected.get(field) as Color), "%s: theme %s" % [label, field])
		assert_true(_sky_color(live, field).is_equal_approx(expected.get(field) as Color), "%s: sky uniform %s" % [label, field])
	for uniform: StringName in SkyPalette.SKY_UNIFORM_COLORS:
		assert_true(_sky_color(live, uniform).is_equal_approx(_sky_color(source, uniform)), "%s: sky %s" % [label, uniform])
	assert_almost_eq(float(live.get_shader_parameter(&"proc_horizon_glow_width")), expected.proc_horizon_glow_width, 0.0001, "%s: glow width" % label)
	assert_almost_eq(float(live.get_shader_parameter(&"proc_sun_glow_strength")), expected.proc_sun_glow_strength, 0.0001, "%s: sun glow" % label)


func test_morning_and_noon_wear_the_dawn_palette_not_the_sunset_one() -> void:
	var dawn: SkyThemeDef = Skybox.load_theme("dawn")
	var sunset: SkyThemeDef = Skybox.load_theme("sunset")
	assert_ne(dawn.proc_zenith_color, sunset.proc_zenith_color, "fixture: the palettes differ")
	var skybox: Skybox = _day_palette_skybox(MatchConfig.SkyThemeMode.CYCLE)[0] as Skybox
	# A default match opens at cycle_start_phase (morning).
	assert_almost_eq(skybox.current_cycle_phase(), sunset.cycle_start_phase, 0.0001)
	_assert_day_palette(skybox, dawn, "match start (morning)")
	for phase: float in [0.03, 0.10, 0.25, 0.30]:
		skybox.set_cycle_phase(phase)
		_assert_day_palette(skybox, dawn, "phase %s" % phase)
		assert_eq(skybox.theme.proc_zenith_color, dawn.proc_zenith_color, "exactly the dawn zenith at %s" % phase)


func test_noon_mixes_the_dawn_light_fog_and_puff_palette_with_no_night() -> void:
	var dawn: SkyThemeDef = Skybox.load_theme("dawn")
	var parts: Array = _day_palette_skybox(MatchConfig.SkyThemeMode.CYCLE)
	var skybox: Skybox = parts[0]
	var environment: Environment = parts[1]
	var light: DirectionalLight3D = parts[2]
	skybox.set_cycle_phase(0.25)
	assert_almost_eq(_night_mix(skybox), 0.0, 0.0001, "noon is full day")
	assert_true(environment.fog_light_color.is_equal_approx(dawn.fog_color), "dawn fog at noon")
	assert_true(skybox.theme.fog_color.is_equal_approx(dawn.fog_color))
	assert_true(light.light_color.is_equal_approx(dawn.light_color), "dawn light colour at noon")
	# Bontago-mp0.127: the high sun adds its contrast gain on the dawn key light and ambient.
	assert_almost_eq(skybox.theme.light_energy, dawn.light_energy * SunContrast.light_scale(
		skybox.sun_direction().y, dawn.cycle_sun_energy_gain, dawn.cycle_sun_contrast_full_sin), 0.0001, "dawn key light energy at noon")
	assert_almost_eq(environment.ambient_light_energy, dawn.ambient_energy * SunContrast.ambient_scale(
		skybox.sun_direction().y, dawn.cycle_day_ambient_scale, dawn.cycle_sun_contrast_full_sin), 0.0001, "dawn ambient at noon")
	var puffs: ShaderMaterial = skybox.get_cloud_sea().puff_material()
	assert_not_null(puffs, "fixture: the sunset structure builds puffs")
	for uniform: StringName in SkyPalette.PUFF_UNIFORM_COLORS:
		var want: Color = (dawn.cloud_puff_material as ShaderMaterial).get_shader_parameter(uniform) as Color
		assert_true(_sky_color(puffs, uniform).is_equal_approx(want), "puff %s is the dawn tone" % uniform)
	for uniform: StringName in [&"cloud_shadow_color", &"cloud_mid_color", &"cloud_lit_color", &"cloud_rim_color"]:
		var want_sky: Color = (dawn.sky_material as ShaderMaterial).get_shader_parameter(uniform) as Color
		assert_true(_sky_color(puffs, uniform).is_equal_approx(want_sky), "the sea's %s is the dawn tone" % uniform)
	assert_true(_sky_color(puffs, &"proc_sea_color_near").is_equal_approx(dawn.proc_sea_color_near), "and the far-fade sea colour")


func test_the_sunset_lock_wears_exactly_the_sunset_palette() -> void:
	var sunset: SkyThemeDef = Skybox.load_theme("sunset")
	var parts: Array = _day_palette_skybox(MatchConfig.SkyThemeMode.DAY)
	var skybox: Skybox = parts[0]
	assert_almost_eq(skybox.locked_phase(), sunset.cycle_locked_phase_sunset, 0.0001)
	assert_eq(SkyPalette.dusk_weight(skybox.locked_phase(), sunset.cycle_dusk_weight_phases), 1.0)
	assert_eq(skybox.theme.proc_zenith_color, sunset.proc_zenith_color, "bit-exact sunset zenith")
	assert_eq(skybox.theme.proc_horizon_color, sunset.proc_horizon_color)
	assert_eq(skybox.theme.sky_top_color, sunset.sky_top_color)
	_assert_day_palette(skybox, sunset, "locked Sunset")
	var puffs: ShaderMaterial = skybox.get_cloud_sea().puff_material()
	var night: float = _night_mix(skybox)
	assert_lt(night, 0.01, "locked Sunset is a day sky")
	var night_puffs: ShaderMaterial = Skybox.load_theme("night").cloud_puff_material as ShaderMaterial
	for uniform: StringName in SkyPalette.PUFF_UNIFORM_COLORS:
		var want: Color = (sunset.cloud_puff_material as ShaderMaterial).get_shader_parameter(uniform) as Color
		var night_tone: Color = night_puffs.get_shader_parameter(uniform) as Color
		assert_true(_sky_color(puffs, uniform).is_equal_approx(want.lerp(night_tone, night)), "puff %s: sunset tone, then the (tiny) night mix" % uniform)


func test_the_dawn_lock_wears_exactly_the_dawn_palette() -> void:
	var dawn: SkyThemeDef = Skybox.load_theme("dawn")
	var skybox: Skybox = _day_palette_skybox(MatchConfig.SkyThemeMode.DAWN)[0] as Skybox
	assert_almost_eq(skybox.locked_phase(), dawn.cycle_locked_phase_dawn, 0.0001)
	assert_eq(skybox.theme.proc_zenith_color, dawn.proc_zenith_color)
	_assert_day_palette(skybox, dawn, "locked Dawn")


func test_the_palette_fades_from_dawn_to_sunset_across_the_dusk_window() -> void:
	var dawn: SkyThemeDef = Skybox.load_theme("dawn")
	var sunset: SkyThemeDef = Skybox.load_theme("sunset")
	var skybox: Skybox = _day_palette_skybox(MatchConfig.SkyThemeMode.CYCLE)[0] as Skybox
	var window: Vector4 = sunset.cycle_dusk_weight_phases
	var middle: float = (window.x + window.y) * 0.5
	skybox.set_cycle_phase(middle)
	var halfway: Color = dawn.proc_zenith_color.lerp(sunset.proc_zenith_color, 0.5)
	assert_true(skybox.theme.proc_zenith_color.is_equal_approx(halfway), "half dawn, half sunset at the window middle")
	assert_true(_sky_color(_live_sky(skybox), &"proc_zenith_color").is_equal_approx(halfway), "and on the live sky")
	var previous: float = -1.0
	for step: int in range(0, 17):
		skybox.set_cycle_phase(window.x + (window.y - window.x) * float(step) / 16.0)
		var progress: float = _color_distance(skybox.theme.proc_zenith_color, dawn.proc_zenith_color)
		assert_gte(progress, previous - 0.00001, "the zenith drifts monotonically toward sunset (step %d)" % step)
		previous = progress
	skybox.set_cycle_phase(window.y)
	assert_eq(skybox.theme.proc_zenith_color, sunset.proc_zenith_color, "the sunset palette is complete at the window end")


func test_a_running_cycle_returns_to_the_dawn_palette_before_the_next_morning() -> void:
	var dawn: SkyThemeDef = Skybox.load_theme("dawn")
	var skybox: Skybox = _day_palette_skybox(MatchConfig.SkyThemeMode.CYCLE)[0] as Skybox
	skybox.set_cycle_phase(0.75)
	assert_eq(skybox.theme.proc_zenith_color, Skybox.load_theme("sunset").proc_zenith_color, "midnight carries the sunset palette")
	skybox.set_cycle_phase(0.99)
	assert_eq(skybox.theme.proc_zenith_color, dawn.proc_zenith_color, "back to the dawn palette (under the night mix)")
	skybox.set_cycle_phase(0.0)
	assert_eq(skybox.theme.proc_zenith_color, dawn.proc_zenith_color)


## The night mix is a function of the phase alone: the day palette neither shifts it
## nor is shifted by it. At midnight the fog, light and ambient are the night
## theme's, on the setting side the sunset palette mixed toward it, and the shader's
## night inputs are the night theme's colours throughout.
func test_the_night_mix_is_unchanged_by_the_day_palette() -> void:
	var night_theme: SkyThemeDef = Skybox.load_theme("night")
	var sunset: SkyThemeDef = Skybox.load_theme("sunset")
	var parts: Array = _day_palette_skybox(MatchConfig.SkyThemeMode.CYCLE)
	var skybox: Skybox = parts[0]
	var environment: Environment = parts[1]
	var width: float = sunset.cycle_twilight_width
	for phase: float in [0.0, 0.05, 0.25, 0.42, 0.47, 0.5, 0.55, 0.6, 0.75, 0.9, 0.97]:
		skybox.set_cycle_phase(phase)
		var expected: float = 1.0 - smoothstep(-width, width, sin(TAU * phase))
		assert_almost_eq(_night_mix(skybox), expected, 0.00001, "night mix at phase %s" % phase)
		assert_true(_sky_color(_live_sky(skybox), &"cycle_night_zenith").is_equal_approx(night_theme.sky_top_color))
		assert_true(_sky_color(_live_sky(skybox), &"cycle_night_horizon").is_equal_approx(night_theme.sky_horizon_color))
	skybox.set_cycle_phase(0.75)
	assert_almost_eq(_night_mix(skybox), 1.0, 0.0001)
	assert_true(environment.fog_light_color.is_equal_approx(night_theme.fog_color), "midnight fog is the night theme's")
	assert_almost_eq(environment.ambient_light_energy, night_theme.ambient_energy, 0.0001, "midnight ambient")
	assert_true(skybox.theme.light_color.is_equal_approx(night_theme.light_color), "midnight key light colour")
	assert_almost_eq(skybox.theme.light_energy, night_theme.light_energy * 0.2, 0.0001, "midnight key light energy")
	skybox.set_cycle_phase(0.5)
	var night: float = _night_mix(skybox)
	assert_between(night, 0.2, 0.8, "fixture: the horizon is mid-twilight")
	assert_true(environment.fog_light_color.is_equal_approx(sunset.fog_color.lerp(night_theme.fog_color, night)), "sunset fog x night mix")


func test_host_and_client_wear_the_same_palette_at_the_same_clock() -> void:
	var host: Skybox = _day_palette_skybox(MatchConfig.SkyThemeMode.CYCLE)[0] as Skybox
	var client: Skybox = _day_palette_skybox(MatchConfig.SkyThemeMode.CYCLE)[0] as Skybox
	for clock: float in [0.0, 41.0, 77.5, 120.0, 133.3, 187.0, 262.0, 299.0]:
		host.update_cycle_clock(clock)
		client.update_cycle_clock(clock)
		assert_eq(client.theme.proc_zenith_color, host.theme.proc_zenith_color, "zenith at clock %s" % clock)
		assert_eq(client.theme.fog_color, host.theme.fog_color, "fog at clock %s" % clock)
		assert_eq(_sky_color(_live_sky(client), &"cloud_lit_color"), _sky_color(_live_sky(host), &"cloud_lit_color"), "cloud tone at clock %s" % clock)
	for mode: MatchConfig.SkyThemeMode in [MatchConfig.SkyThemeMode.DAY, MatchConfig.SkyThemeMode.DAWN, MatchConfig.SkyThemeMode.NIGHT]:
		var locked_host: Skybox = _day_palette_skybox(mode)[0] as Skybox
		var locked_client: Skybox = _day_palette_skybox(mode)[0] as Skybox
		locked_host.update_cycle_clock(210.0)
		locked_client.update_cycle_clock(17.0)
		assert_eq(locked_client.theme.proc_zenith_color, locked_host.theme.proc_zenith_color, "locked mode %s ignores the clock" % mode)


func test_the_palette_survives_a_puff_rebuild_and_a_source_theme_edit() -> void:
	var dawn: SkyThemeDef = Skybox.load_theme("dawn")
	var skybox: Skybox = _day_palette_skybox(MatchConfig.SkyThemeMode.DAWN)[0] as Skybox
	# A puff rebuild (graphics preset change, apply_theme) resets the puff palette to the
	# duplicate's; the re-applied phase must restore the dawn tones.
	skybox.refresh_cycle_sources()
	var puffs: ShaderMaterial = skybox.get_cloud_sea().puff_material()
	var night: float = _night_mix(skybox)
	var night_puffs: ShaderMaterial = Skybox.load_theme("night").cloud_puff_material as ShaderMaterial
	for uniform: StringName in SkyPalette.PUFF_UNIFORM_COLORS:
		var want: Color = (dawn.cloud_puff_material as ShaderMaterial).get_shader_parameter(uniform) as Color
		var night_tone: Color = night_puffs.get_shader_parameter(uniform) as Color
		assert_true(_sky_color(puffs, uniform).is_equal_approx(want.lerp(night_tone, night)), "puff %s after a rebuild" % uniform)
	assert_eq(skybox.theme.proc_zenith_color, dawn.proc_zenith_color, "the live theme keeps the dawn zenith after a source refresh")
	_assert_day_palette(skybox, dawn, "after refresh_cycle_sources")
	# Applying the dawn source (an F4 edit of dawn.tres) refreshes the cycle; it never
	# swaps the static dawn material in.
	var live: Material = skybox.theme.sky_material
	var saved: Color = dawn.proc_zenith_color
	var edited: Color = Color(0.9, 0.1, 0.2, 1.0)
	dawn.proc_zenith_color = edited
	skybox.apply_theme(dawn)
	assert_same(skybox.theme.sky_material, live, "the live material stays")
	assert_true(skybox.is_cycle_active())
	assert_eq(skybox.theme.proc_zenith_color, edited, "the dawn edit reaches the locked-dawn sky")
	assert_true(_sky_color(live as ShaderMaterial, &"proc_zenith_color").is_equal_approx(edited))
	dawn.proc_zenith_color = saved


func test_the_storm_blend_composes_over_the_blended_day_palette() -> void:
	var storm: SkyThemeDef = Skybox.load_theme("storm")
	var dawn: SkyThemeDef = Skybox.load_theme("dawn")
	var sunset: SkyThemeDef = Skybox.load_theme("sunset")
	var skybox: Skybox = _day_palette_skybox(MatchConfig.SkyThemeMode.CYCLE)[0] as Skybox
	skybox.set_storm_sky(0.5, storm)
	var expected: Color = dawn.proc_zenith_color.lerp(storm.proc_zenith_color, 0.5)
	assert_true(_sky_color(_live_sky(skybox), &"proc_zenith_color").is_equal_approx(expected), "storm blends from the dawn palette in the morning")
	skybox.set_cycle_phase(0.46)
	var expected_dusk: Color = sunset.proc_zenith_color.lerp(storm.proc_zenith_color, 0.5)
	assert_true(_sky_color(_live_sky(skybox), &"proc_zenith_color").is_equal_approx(expected_dusk), "and from the sunset palette on the setting side")
	skybox.set_storm_sky(0.0, storm)
	assert_true(_sky_color(_live_sky(skybox), &"proc_zenith_color").is_equal_approx(sunset.proc_zenith_color), "the storm clears back to the day palette")


## Bontago-59o.18 (C1b variation, owner 2026-10-03: "lets add some variation and just set
## a range so it can vary"): the cycle's sky exposure and cloud coverage wander inside
## the SkyThemeDef.variation_* ranges as a smooth function of the match seed and the
## cycle phase (core/SkyVariation.gd); storm and overcast compose on top.
const VARIATION_SEED: int = 4242
const OVERCAST_EXPOSURE_SCALE: float = 0.4
const SWEEP_CLOCKS: Array[float] = [0.0, 13.0, 41.0, 77.5, 120.0, 133.3, 187.0, 224.0, 262.0, 299.0]


func _variation_skybox(mode: MatchConfig.SkyThemeMode, rng_seed: int = VARIATION_SEED) -> Array:
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = mode
	config.rng_seed = rng_seed
	config.resolve_sky_theme(0)
	return _configured_skybox(config)


## The live sky's three varying uniforms and the puff material's two, in one dictionary.
func _look(skybox: Skybox) -> Dictionary:
	var sky: ShaderMaterial = _live_sky(skybox)
	var puffs: ShaderMaterial = skybox.get_cloud_sea().puff_material()
	return {
		"exposure": float(sky.get_shader_parameter(&"exposure")),
		"cloud_coverage": float(sky.get_shader_parameter(&"cloud_coverage")),
		"sea_coverage": float(sky.get_shader_parameter(&"proc_sea_coverage")),
		"puff_exposure": float(puffs.get_shader_parameter(&"exposure")),
		"puff_sea_coverage": float(puffs.get_shader_parameter(&"proc_sea_coverage")),
	}


func _assert_same_look(a: Dictionary, b: Dictionary, label: String) -> void:
	for key: Variant in a.keys():
		assert_eq(a[key], b[key], "%s: %s" % [label, key])


func test_the_running_cycle_varies_exposure_and_coverage_inside_the_configured_ranges() -> void:
	var skybox: Skybox = _variation_skybox(MatchConfig.SkyThemeMode.CYCLE)[0] as Skybox
	var theme: SkyThemeDef = skybox.theme
	assert_true(theme.variation_enabled, "fixture: the shipped sunset varies the cycle")
	var lowest: float = INF
	var highest: float = -INF
	for second: int in range(0, 300, 2):
		skybox.update_cycle_clock(float(second))
		var look: Dictionary = _look(skybox)
		assert_between(look["exposure"], theme.variation_exposure_min, theme.variation_exposure_max, "exposure at %s s" % second)
		assert_between(look["cloud_coverage"], theme.variation_cloud_coverage_min, theme.variation_cloud_coverage_max, "cloud coverage at %s s" % second)
		assert_between(look["sea_coverage"], theme.variation_sea_coverage_min, theme.variation_sea_coverage_max, "sea coverage at %s s" % second)
		var phase: float = skybox.current_cycle_phase()
		assert_eq(look["exposure"], SkyVariation.exposure_at(theme, phase, VARIATION_SEED), "exposure is the pure function at %s s" % second)
		assert_eq(look["cloud_coverage"], SkyVariation.cloud_coverage_at(theme, phase, VARIATION_SEED), "coverage is the pure function at %s s" % second)
		assert_eq(look["sea_coverage"], SkyVariation.sea_coverage_at(theme, phase, VARIATION_SEED), "sea is the pure function at %s s" % second)
		assert_eq(look["puff_exposure"], look["exposure"], "the puffs' far fade shares the sky exposure at %s s" % second)
		assert_eq(look["puff_sea_coverage"], look["sea_coverage"], "and the sea coverage at %s s" % second)
		lowest = minf(lowest, look["exposure"])
		highest = maxf(highest, look["exposure"])
	assert_gt(highest - lowest, 0.4 * (theme.variation_exposure_max - theme.variation_exposure_min), "the exposure really moves over a cycle")


func test_the_variation_changes_smoothly_over_the_cycle() -> void:
	var skybox: Skybox = _variation_skybox(MatchConfig.SkyThemeMode.CYCLE)[0] as Skybox
	var theme: SkyThemeDef = skybox.theme
	var step_s: float = 0.5
	# slope <= 1.5 per lattice cell x knots, per unit of phase (core/SkyVariation.gd).
	var per_step: float = 1.5 * float(theme.variation_knots_per_cycle) * step_s / theme.cycle_length_seconds
	skybox.update_cycle_clock(0.0)
	var previous: Dictionary = _look(skybox)
	var clock: float = step_s
	while clock <= 2.0 * theme.cycle_length_seconds:
		skybox.update_cycle_clock(clock)
		var look: Dictionary = _look(skybox)
		assert_lte(absf(look["exposure"] - previous["exposure"]), per_step * (theme.variation_exposure_max - theme.variation_exposure_min) + 0.00001, "exposure step at %s s" % clock)
		assert_lte(absf(look["cloud_coverage"] - previous["cloud_coverage"]), per_step * (theme.variation_cloud_coverage_max - theme.variation_cloud_coverage_min) + 0.00001, "coverage step at %s s" % clock)
		assert_lte(absf(look["sea_coverage"] - previous["sea_coverage"]), per_step * (theme.variation_sea_coverage_max - theme.variation_sea_coverage_min) + 0.00001, "sea step at %s s" % clock)
		previous = look
		clock += step_s


func test_two_skyboxes_with_the_same_seed_and_clock_show_the_same_values() -> void:
	var host_config: MatchConfig = MatchConfig.new()
	host_config.rng_seed = VARIATION_SEED
	host_config.resolve_sky_theme(0)
	# The client only ever sees the wire form of the host's config.
	var client_config: MatchConfig = MatchConfig.from_dict(host_config.to_dict())
	var host: Skybox = _configured_skybox(host_config)[0] as Skybox
	var client: Skybox = _configured_skybox(client_config)[0] as Skybox
	var other: Skybox = _variation_skybox(MatchConfig.SkyThemeMode.CYCLE, VARIATION_SEED + 1)[0] as Skybox
	var other_differs: bool = false
	for clock: float in SWEEP_CLOCKS:
		host.update_cycle_clock(clock)
		client.update_cycle_clock(clock)
		other.update_cycle_clock(clock)
		_assert_same_look(_look(client), _look(host), "client at clock %s" % clock)
		if absf(_look(other)["exposure"] - _look(host)["exposure"]) > 0.001:
			other_differs = true
	assert_true(other_differs, "another match seed draws another sky")


func test_a_match_without_a_seed_uses_the_default_curve_on_every_peer() -> void:
	var first: Skybox = _variation_skybox(MatchConfig.SkyThemeMode.CYCLE, -1)[0] as Skybox
	var second: Skybox = _variation_skybox(MatchConfig.SkyThemeMode.CYCLE, -1)[0] as Skybox
	var seeded: Skybox = _variation_skybox(MatchConfig.SkyThemeMode.CYCLE, SkyVariation.DEFAULT_SEED)[0] as Skybox
	for clock: float in SWEEP_CLOCKS:
		first.update_cycle_clock(clock)
		second.update_cycle_clock(clock)
		seeded.update_cycle_clock(clock)
		_assert_same_look(_look(second), _look(first), "unseeded peers at clock %s" % clock)
		_assert_same_look(_look(seeded), _look(first), "-1 reads as the default seed at clock %s" % clock)


func test_locked_modes_hold_one_stable_value_inside_the_range() -> void:
	for mode: MatchConfig.SkyThemeMode in [MatchConfig.SkyThemeMode.DAY, MatchConfig.SkyThemeMode.DAWN, MatchConfig.SkyThemeMode.NIGHT]:
		var skybox: Skybox = _variation_skybox(mode)[0] as Skybox
		var theme: SkyThemeDef = skybox.theme
		var locked: float = skybox.locked_phase()
		assert_gte(locked, 0.0, "fixture: mode %s is locked" % mode)
		var opening: Dictionary = _look(skybox)
		assert_between(opening["exposure"], theme.variation_exposure_min, theme.variation_exposure_max, "mode %s exposure" % mode)
		assert_between(opening["cloud_coverage"], theme.variation_cloud_coverage_min, theme.variation_cloud_coverage_max, "mode %s coverage" % mode)
		assert_between(opening["sea_coverage"], theme.variation_sea_coverage_min, theme.variation_sea_coverage_max, "mode %s sea" % mode)
		assert_eq(opening["exposure"], SkyVariation.exposure_at(theme, locked, VARIATION_SEED), "mode %s: the value at its locked phase" % mode)
		for clock: float in SWEEP_CLOCKS:
			skybox.update_cycle_clock(clock)
			_assert_same_look(_look(skybox), opening, "mode %s at clock %s" % [mode, clock])
		# A host and a client of the same match lock the same sky whatever their clocks read.
		var client: Skybox = _variation_skybox(mode)[0] as Skybox
		client.update_cycle_clock(211.0)
		_assert_same_look(_look(client), opening, "mode %s client" % mode)


func test_scrubbing_the_locked_phase_moves_the_value_and_unlocking_continues_it() -> void:
	var skybox: Skybox = _variation_skybox(MatchConfig.SkyThemeMode.DAY)[0] as Skybox
	var theme: SkyThemeDef = skybox.theme
	skybox.set_locked_phase(0.30)
	assert_eq(_look(skybox)["exposure"], SkyVariation.exposure_at(theme, 0.30, VARIATION_SEED), "F4 Time of day scrub")
	skybox.set_locked_phase(-1.0)
	skybox.update_cycle_clock(0.0)
	assert_eq(_look(skybox)["exposure"], SkyVariation.exposure_at(theme, 0.30, VARIATION_SEED), "unlocking continues from the locked value")


func test_weather_overcast_scales_the_varying_exposure_from_its_current_value() -> void:
	var skybox: Skybox = _variation_skybox(MatchConfig.SkyThemeMode.CYCLE)[0] as Skybox
	var theme: SkyThemeDef = skybox.theme
	skybox.set_overcast(1.0, 0.5, 0.6, OVERCAST_EXPOSURE_SCALE, Color(0.4, 0.4, 0.5), 0.5)
	var distinct: Dictionary = {}
	for phase: float in [0.05, 0.12, 0.2, 0.33, 0.41, 0.6, 0.9]:
		skybox.set_cycle_phase(phase)
		var baseline: float = SkyVariation.exposure_at(theme, phase, VARIATION_SEED)
		distinct[snappedf(baseline, 0.0001)] = true
		var look: Dictionary = _look(skybox)
		assert_almost_eq(look["exposure"], baseline * OVERCAST_EXPOSURE_SCALE, 0.00001, "full overcast at phase %s darkens the varying baseline" % phase)
		assert_lt(look["exposure"], theme.variation_exposure_min, "and sits under the lowest clear-sky exposure")
		assert_eq(look["puff_exposure"], baseline, "the puffs keep the unscaled baseline (weather dims them through CloudLighting)")
	assert_gt(distinct.size(), 3, "fixture: the baseline really varies across those phases")
	# A half overcast with a half storm still composes with the baseline, never replaces it.
	skybox.set_overcast(0.5, 0.5, 0.6, OVERCAST_EXPOSURE_SCALE, Color(0.4, 0.4, 0.5), 0.5)
	skybox.set_storm_sky(0.5, Skybox.load_theme("storm"))
	skybox.set_cycle_phase(0.18)
	assert_almost_eq(_look(skybox)["exposure"], SkyVariation.exposure_at(theme, 0.18, VARIATION_SEED) * lerpf(1.0, OVERCAST_EXPOSURE_SCALE, 0.5), 0.00001, "half overcast under a storm")
	# Clearing the weather returns the baseline exactly.
	skybox.set_storm_sky(0.0, Skybox.load_theme("storm"))
	skybox.set_overcast(0.0, 1.0, 1.0, 1.0, Color.WHITE, 0.0)
	assert_eq(_look(skybox)["exposure"], SkyVariation.exposure_at(theme, 0.18, VARIATION_SEED), "overcast cleared: the varying baseline is back")


func test_a_running_cycle_under_overcast_keeps_varying_with_the_clock() -> void:
	var skybox: Skybox = _variation_skybox(MatchConfig.SkyThemeMode.CYCLE)[0] as Skybox
	var theme: SkyThemeDef = skybox.theme
	skybox.set_overcast(1.0, 0.5, 0.6, OVERCAST_EXPOSURE_SCALE, Color(0.4, 0.4, 0.5), 0.5)
	for clock: float in SWEEP_CLOCKS:
		skybox.update_cycle_clock(clock)
		var baseline: float = SkyVariation.exposure_at(theme, skybox.current_cycle_phase(), VARIATION_SEED)
		assert_almost_eq(_look(skybox)["exposure"], baseline * OVERCAST_EXPOSURE_SCALE, 0.00001, "overcast at clock %s" % clock)


func test_variation_off_keeps_the_sunset_fixed_values() -> void:
	var sunset: SkyThemeDef = Skybox.load_theme("sunset")
	var source: ShaderMaterial = sunset.sky_material as ShaderMaterial
	var skybox: Skybox = _variation_skybox(MatchConfig.SkyThemeMode.CYCLE)[0] as Skybox
	sunset.variation_enabled = false
	skybox.refresh_cycle_sources()
	for clock: float in SWEEP_CLOCKS:
		skybox.update_cycle_clock(clock)
		var look: Dictionary = _look(skybox)
		assert_eq(look["exposure"], float(source.get_shader_parameter(&"exposure")), "fixed exposure at clock %s" % clock)
		assert_eq(look["cloud_coverage"], float(source.get_shader_parameter(&"cloud_coverage")), "fixed coverage at clock %s" % clock)
		assert_eq(look["sea_coverage"], float(source.get_shader_parameter(&"proc_sea_coverage")), "fixed sea coverage at clock %s" % clock)
		assert_eq(look["puff_exposure"], look["exposure"])
	sunset.variation_enabled = true
	skybox.refresh_cycle_sources()
	assert_ne(_look(skybox)["exposure"], float(source.get_shader_parameter(&"exposure")), "switching it back on varies the sky again")


func test_an_f4_edit_of_the_ranges_reaches_the_live_cycle() -> void:
	var sunset: SkyThemeDef = Skybox.load_theme("sunset")
	var saved: Array[float] = [sunset.variation_exposure_min, sunset.variation_exposure_max, sunset.variation_sea_coverage_min, sunset.variation_sea_coverage_max]
	var skybox: Skybox = _variation_skybox(MatchConfig.SkyThemeMode.CYCLE)[0] as Skybox
	skybox.update_cycle_clock(40.0)
	sunset.variation_exposure_min = 1.1
	sunset.variation_exposure_max = 1.1
	sunset.variation_sea_coverage_min = 0.6
	sunset.variation_sea_coverage_max = 0.6
	skybox.apply_theme(sunset)
	var look: Dictionary = _look(skybox)
	assert_eq(look["exposure"], 1.1, "a collapsed exposure range is a fixed exposure")
	assert_eq(look["sea_coverage"], 0.6, "and so is the sea coverage")
	assert_eq(look["puff_exposure"], 1.1, "the rebuilt puffs follow it")
	sunset.variation_exposure_min = saved[0]
	sunset.variation_exposure_max = saved[1]
	sunset.variation_sea_coverage_min = saved[2]
	sunset.variation_sea_coverage_max = saved[3]
	skybox.apply_theme(sunset)
	assert_between(_look(skybox)["exposure"], saved[0], saved[1], "the restored range applies again")


func test_the_variation_never_writes_the_shipped_theme_materials_and_reset_restores_the_launch_sky() -> void:
	var sunset: SkyThemeDef = Skybox.load_theme("sunset")
	var source: ShaderMaterial = sunset.sky_material as ShaderMaterial
	var launch_exposure: float = float(source.get_shader_parameter(&"exposure"))
	var launch_coverage: float = float(source.get_shader_parameter(&"cloud_coverage"))
	var launch_sea: float = float(source.get_shader_parameter(&"proc_sea_coverage"))
	var parts: Array = _variation_skybox(MatchConfig.SkyThemeMode.CYCLE)
	var skybox: Skybox = parts[0] as Skybox
	var environment: Environment = parts[1] as Environment
	for clock: float in SWEEP_CLOCKS:
		skybox.update_cycle_clock(clock)
	skybox.set_overcast(1.0, 0.5, 0.6, OVERCAST_EXPOSURE_SCALE, Color(0.4, 0.4, 0.5), 0.5)
	assert_eq(float(source.get_shader_parameter(&"exposure")), launch_exposure, "the cycle varies its own duplicate, not sunset.tres")
	assert_eq(float(source.get_shader_parameter(&"cloud_coverage")), launch_coverage)
	assert_eq(float(source.get_shader_parameter(&"proc_sea_coverage")), launch_sea)
	skybox.reset_to_launch()
	assert_false(skybox.is_cycle_active(), "reset: back on the static launch theme")
	var restored: ShaderMaterial = environment.sky.sky_material as ShaderMaterial
	assert_eq(float(restored.get_shader_parameter(&"exposure")), launch_exposure, "reset: the launch exposure, no overcast, no variation")
	assert_eq(float(restored.get_shader_parameter(&"cloud_coverage")), launch_coverage)
	assert_eq(float(restored.get_shader_parameter(&"proc_sea_coverage")), launch_sea)
	# And a new match after the reset draws its own seed's sky, not the previous one's.
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = MatchConfig.SkyThemeMode.DAY
	config.rng_seed = VARIATION_SEED + 9
	config.resolve_sky_theme(0)
	skybox.configure_match_sky(config)
	assert_eq(_look(skybox)["exposure"], SkyVariation.exposure_at(skybox.theme, skybox.locked_phase(), VARIATION_SEED + 9))
