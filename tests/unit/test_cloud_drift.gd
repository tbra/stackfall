extends GutTest
## Bontago-mp0.92: the shared cloud drift. Per-layer parallax rates ordered by depth, a
## per-match calm heading, storm drift easing onto the storm wind, the wrap / dissolve rules,
## and the puffs, the occlusion bounds and the cloud shadows all reading the same drift.

const CONFIG_PATH: String = "res://config/cloud_drift.tres"
const STEP_S: float = 1.0 / 30.0
const SETTLE_STEPS: int = 600


func _config() -> CloudDriftConfig:
	return load(CONFIG_PATH) as CloudDriftConfig


func test_layer_rates_are_ordered_by_depth() -> void:
	var config: CloudDriftConfig = _config()
	var upper: float = CloudDriftMath.layer_rate(CloudDriftMath.KIND_UPPER, config)
	var sea: float = CloudDriftMath.layer_rate(CloudDriftMath.KIND_SEA, config)
	var bank: float = CloudDriftMath.layer_rate(CloudDriftMath.KIND_BANK, config)
	var far: float = CloudDriftMath.layer_rate(CloudDriftMath.KIND_FAR, config)
	assert_gt(upper, sea, "the layer above the disc (nearest) is faster than the sea")
	assert_gt(sea, bank, "the sea is faster than the distant banks")
	assert_gt(bank, far, "the banks are faster than the farthest sea")
	assert_gt(far, 0.0, "every layer still moves")


func test_built_clump_speeds_follow_their_layer_rate() -> void:
	var theme: SkyThemeDef = Skybox.load_theme("sunset").duplicate() as SkyThemeDef
	theme.cloud_drift_speed_min_mps = 1.0
	theme.cloud_drift_speed_max_mps = 1.0
	theme.cloud_clump_count = 2
	theme.cloud_bank_count = 2
	theme.proc_far_count = 2 if theme.sky_look_procedural else 0
	var sea: CloudSea = CloudSea.new()
	sea.upper_tuning = load("res://config/weather/ceiling.tres") as WeatherCeilingTuning
	add_child_autofree(sea)
	sea.configure(theme, 1.0, null, 1)
	var config: CloudDriftConfig = sea.drift_config
	var seen: Dictionary[float, bool] = {}
	for index: int in range(sea.occlusion_clump_count()):
		seen[snappedf(sea._occ_speed[index], 0.001)] = true
	assert_true(seen.has(snappedf(config.sea_rate, 0.001)), "sea clumps move at the sea rate")
	assert_true(seen.has(snappedf(config.bank_rate, 0.001)), "bank clumps move at the bank rate")
	assert_true(seen.has(snappedf(config.upper_rate, 0.001)), "upper clumps move at the upper rate")
	assert_gt(seen.size(), 2, "layers differ in speed")


func test_calm_heading_is_consistent_per_seed_and_varies_between_seeds() -> void:
	var config: CloudDriftConfig = _config()
	var a: Vector2 = CloudDriftMath.calm_heading(1234, config)
	assert_eq(a, CloudDriftMath.calm_heading(1234, config), "same match, same direction")
	assert_almost_eq(a.length(), 1.0, 0.0001)
	var differs: bool = false
	for seed_value: int in range(1, 9):
		if CloudDriftMath.calm_heading(seed_value, config).distance_to(a) > 0.01:
			differs = true
	assert_true(differs, "other matches pick other headings")
	for seed_value: int in range(1, 50):
		var angle: float = rad_to_deg(CloudDriftMath.calm_heading(seed_value, config).angle())
		assert_lte(absf(angle_difference(deg_to_rad(angle), deg_to_rad(config.calm_heading_deg))),
				deg_to_rad(config.calm_heading_jitter_deg) + 0.001, "stays within the jitter")


func test_calm_state_drifts_along_the_calm_heading_at_base_speed() -> void:
	var state: CloudDriftState = CloudDriftState.new(_config())
	state.reset(77)
	for i: int in range(SETTLE_STEPS):
		state.step(STEP_S, 0.0)
	assert_almost_eq(state.speed_mult, 1.0, 0.0001)
	assert_gt(state.offset.normalized().dot(state.calm_heading()), 0.9999, "offset runs along the calm wind")
	assert_almost_eq(state.offset.length(), SETTLE_STEPS * STEP_S, 0.01, "one unit of speed per second")


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


func test_storm_wind_eases_in_and_out_with_the_storm_amount() -> void:
	var config: CloudDriftConfig = _config()
	var state: CloudDriftState = CloudDriftState.new(config)
	state.reset(5)
	var calm: Vector2 = state.calm_heading()
	state.set_storm_wind(-calm)
	state.step(STEP_S, 0.0)
	assert_gt(state.heading.dot(calm), 0.9999, "no storm amount: the wind is ignored")
	state.step(STEP_S, 0.2)
	assert_gt(state.speed_mult, 1.0)
	assert_lt(state.speed_mult, config.storm_speed_mult, "partway into the storm")
	assert_gt(state.heading.dot(calm), 0.0, "the turn is gradual, not a jump to the storm wind")
	for i: int in range(SETTLE_STEPS):
		state.step(STEP_S, 1.0)
	assert_gt(state.heading.dot(-calm), 0.99, "full storm: opposite wind reached the long way round")
	for i: int in range(SETTLE_STEPS * 2):
		state.step(STEP_S, 0.0)
	assert_gt(state.heading.dot(calm), 0.99, "storm over: back to the calm heading")
	assert_almost_eq(state.speed_mult, 1.0, 0.01)


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
	for decal: Decal in shadows.decals():
		if decal.visible:
			along = decal.global_transform.basis.x
	assert_gt(along.length(), 0.5, "fixture: a shadow layer is shown")
	var ground: Vector2 = Vector2(along.x, along.z).normalized()
	assert_gt(ground.dot(wind), 0.999, "shadows sweep along the clouds' wind, not the config heading")
	assert_eq(shadows._wind, skybox.cloud_wind_dir(), "the node took the skybox's drift heading")
	# The puffs read the same integral the skybox accumulated.
	assert_gt(skybox.cloud_drift().offset.normalized().dot(wind), 0.0, "the shared integral points downwind")


func test_puffs_and_occlusion_share_the_pushed_offset() -> void:
	var sea: CloudSea = CloudSea.new()
	add_child_autofree(sea)
	sea.set_drift_offset(Vector2(3.0, -4.0))
	assert_eq(sea.drift_offset(), Vector2(3.0, -4.0))
