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
	assert_eq(full, sunset.cloud_clump_count * sunset.cloud_puffs_per_clump)
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
		assert_true(sea.highest_puff_top() <= theme.cloud_top_max_m + 0.001, "%s: no puff above the ceiling" % path)
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


func test_puff_mesh_has_a_flat_base() -> void:
	var mesh: ArrayMesh = CloudSea.build_puff_mesh(0.35)
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var lowest: float = INF
	for v: Vector3 in vertices:
		lowest = minf(lowest, v.y)
	assert_almost_eq(lowest, -0.35, 0.0001)
	assert_eq((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), 20 * int(pow(4.0, CloudSea.PUFF_SUBDIVISIONS)) * 3)


func test_birds_only_when_enabled_and_theme_has_flocks() -> void:
	var sunset: SkyThemeDef = load(SUNSET_PATH) as SkyThemeDef
	var birds: DistantBirds = DistantBirds.new()
	add_child_autofree(birds)
	birds.configure(sunset, true)
	assert_not_null(birds.flock_instance())
	assert_eq(birds.flock_instance().multimesh.instance_count, sunset.bird_flock_count * sunset.birds_per_flock)
	birds.configure(sunset, false)
	assert_false(birds.visible)
	birds.configure(load(NIGHT_PATH) as SkyThemeDef, true)
	assert_false(birds.visible, "night has no bird flocks")


func test_bird_flocks_stay_far_from_the_play_area() -> void:
	var sunset: SkyThemeDef = load(SUNSET_PATH) as SkyThemeDef
	var nearest: float = sunset.bird_distance_min_m - sunset.bird_orbit_radius_max_m
	assert_gt(nearest, MapDef.RADIUS_LARGE * 2.0, "flocks must never orbit near the disc")
