extends GutTest
## Bontago-adt.1: night theme resource, theme-driven light/environment,
## cloud sea layers and distant bird flocks.

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
	assert_not_null(night.cloud_sea_material)
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


func test_cloud_sea_builds_one_mesh_per_layer_up_to_the_limit() -> void:
	var sunset: SkyThemeDef = load(SUNSET_PATH) as SkyThemeDef
	var sea: CloudSea = CloudSea.new()
	add_child_autofree(sea)
	sea.configure(sunset, 2)
	assert_eq(sea.layer_count(), 2)
	sea.configure(sunset, 99)
	assert_eq(sea.layer_count(), sunset.cloud_sea_layer_heights_m.size())
	sea.configure(sunset, 0)
	assert_eq(sea.layer_count(), 0)
	assert_false(sea.visible)


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
