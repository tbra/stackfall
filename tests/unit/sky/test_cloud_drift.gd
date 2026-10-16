extends GutTest
## the shared cloud drift. Per-layer parallax rates ordered by depth, a
## per-match calm heading, storm drift easing onto the storm wind, the wrap / dissolve rules,
## and the puffs, the occlusion bounds and the cloud shadows all reading the same drift.

const CONFIG_PATH: String = "res://config/sky/cloud_drift.tres"
const STEP_S: float = 1.0 / 30.0
const SETTLE_STEPS: int = 600


func _config() -> CloudDriftConfig:
	return load(CONFIG_PATH) as CloudDriftConfig


func test_storm_drift_turns_onto_the_wind_and_speeds_up() -> void:
	var config: CloudDriftConfig = _config()
	var state: CloudDriftState = CloudDriftState.new(config)
	state.reset(77)
	var wind: Vector2 = Vector2.from_angle(deg_to_rad(250.0))
	state.set_storm_wind(wind)
	for i: int in range(SETTLE_STEPS):
		state.step(STEP_S, 1.0)
	assert_gt(state.heading.dot(wind), 0.999, "the cloud heading aligns with the wind direction")
	assert_almost_eq(state.speed_mult, config.storm_speed_mult, 0.01, "full storm blows storm_speed_mult times faster")
	var before: Vector2 = state.offset
	for i: int in range(60):
		state.step(STEP_S, 1.0)
	assert_gt((state.offset - before).normalized().dot(wind), 0.999, "new drift runs along the wind")


func test_wrap_keeps_clumps_in_the_domain_and_dissolves_at_the_edge() -> void:
	var config: CloudDriftConfig = _config()
	var domain: float = 600.0
	var wrapped: Vector2 = CloudDriftMath.wrapped_position(Vector2(500.0, 0.0), Vector2(200.0, -50.0), domain)
	assert_almost_eq(wrapped.x, -500.0, 0.001, "leaves one side, re-enters on the other")
	assert_almost_eq(wrapped.y, -50.0, 0.001)
	assert_eq(CloudDriftMath.visibility(Vector2(domain, 0.0), domain, 0.0, config), 0.0, "fully dissolved at the wrap")
	assert_eq(CloudDriftMath.visibility(Vector2(0.0, 300.0), domain, 0.0, config), 1.0, "solid mid-domain")
	var gone_at: float = 200.0
	assert_eq(CloudDriftMath.visibility(Vector2(gone_at, 0.0), domain, gone_at, config), 0.0, "gone before the play volume")
	assert_eq(CloudDriftMath.visibility(Vector2(gone_at + config.exclusion_fade_m, 0.0), domain, gone_at, config), 1.0)


func test_shadows_use_the_same_drift_vector_as_the_clouds() -> void:
	var environment: Environment = Environment.new()
	environment.sky = Sky.new()
	var skybox: Skybox = Skybox.new()
	skybox.config = SkyboxConfig.new()
	skybox.environment = environment
	skybox.theme = Skybox.load_theme("sunset")
	add_child_autofree(skybox)
	var wind: Vector2 = Vector2.from_angle(deg_to_rad(200.0))
	skybox.set_cloud_storm_wind(wind)
	var config: CloudDriftConfig = skybox.cloud_drift().config
	skybox.set_storm_sky(1.0, Skybox.load_theme("storm"))
	for i: int in range(SETTLE_STEPS):
		skybox._step_cloud_drift(STEP_S)
	assert_gt(skybox.cloud_wind_dir().dot(wind), 0.999, "storm: the skybox's cloud wind is the storm wind")
	var calm_speed: float = absf(skybox.theme.cloud_drift_speed_min_mps + skybox.theme.cloud_drift_speed_max_mps) * 0.5
	assert_almost_eq(skybox.cloud_drift_speed_mps(), calm_speed * config.storm_speed_mult, 0.01, "and its speed")

	var shadows: CloudShadows = CloudShadows.new()
	add_child_autofree(shadows)
	var noon: Vector3 = Vector3(0.0, 1.0, 0.0)
	shadows.step(STEP_S, noon, 1.0, skybox.cloud_drift_speed_mps(), skybox.cloud_wind_dir())
	var along: Vector3 = Vector3.ZERO
	for child: Node in shadows.get_children():
		if child is Decal and (child as Decal).visible:
			along = (child as Decal).global_transform.basis.x
	assert_gt(along.length(), 0.5, "fixture: a shadow layer is shown")
	var ground: Vector2 = Vector2(along.x, along.z).normalized()
	assert_gt(ground.dot(wind), 0.999, "shadows sweep along the clouds' wind, not the config heading")
	assert_eq(shadows._wind, skybox.cloud_wind_dir(), "the node took the skybox's drift heading")
	# The puffs read the same integral the skybox accumulated.
	assert_gt(skybox.cloud_drift().offset.normalized().dot(wind), 0.0, "the shared integral points downwind")

