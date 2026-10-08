extends GutTest
## Bontago-1pi.131 (owner playtest: the aurora showed every night): the aurora is a per-night
## roll against SkyThemeDef.aurora_night_chance (default 10%), a pure function of the
## replicated match seed, so the host and every client agree and each night re-rolls.

const NIGHTS: int = 4000
const SEEDS: Array[int] = [0, 7, 90210, 123456789]
## 4 sigma of a binomial(NIGHTS, 0.1), in nights.
const SIGMA_BOUND: float = 4.0
const NIGHT_PHASE: float = 0.75
const START_PHASE: float = 0.3
const PHASE_NUDGE: float = 0.01
const SAMPLED_NIGHTS: int = 40


func test_default_chance_is_ten_percent() -> void:
	assert_almost_eq(SkyThemeDef.new().aurora_night_chance, 0.1, 0.0001)
	var shipped: SkyThemeDef = Skybox.load_theme(Skybox.DEFAULT_THEME_ID)
	assert_almost_eq(shipped.aurora_night_chance, 0.1, 0.0001)


func test_rate_over_many_seeded_nights_is_about_ten_percent() -> void:
	var chance: float = SkyThemeDef.new().aurora_night_chance
	var expected: float = float(NIGHTS) * chance
	var bound: float = SIGMA_BOUND * sqrt(float(NIGHTS) * chance * (1.0 - chance))
	for seed_value: int in SEEDS:
		var shown: int = 0
		for night: int in NIGHTS:
			if SkyVariation.aurora_night_shown(seed_value, night, chance):
				shown += 1
		assert_between(float(shown), expected - bound, expected + bound, "seed %d: %d of %d nights" % [seed_value, shown, NIGHTS])


func test_chance_extremes() -> void:
	for night: int in 50:
		assert_false(SkyVariation.aurora_night_shown(5, night, 0.0))
		assert_true(SkyVariation.aurora_night_shown(5, night, 1.0))


func test_nights_re_roll_independently() -> void:
	var seen: Dictionary = {}
	for night: int in 200:
		seen[SkyVariation.aurora_night_shown(11, night, 0.5)] = true
	assert_eq(seen.size(), 2, "both outcomes occur across nights")


func _cycle_skybox(seed_value: int) -> Skybox:
	var environment: Environment = Environment.new()
	environment.sky = Sky.new()
	environment.sky.sky_material = ProceduralSkyMaterial.new()
	var skybox: Skybox = Skybox.new()
	skybox.config = SkyboxConfig.new()
	skybox.environment = environment
	skybox.theme = SkyThemeDef.new()
	add_child_autofree(skybox)
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = MatchConfig.SkyThemeMode.CYCLE
	config.rng_seed = seed_value
	config.sky_start_phase = START_PHASE
	skybox.configure_match_sky(config)
	return skybox


func _visibility_at_night(skybox: Skybox, night: int) -> float:
	var length: float = Skybox.load_theme(Skybox.DEFAULT_THEME_ID).cycle_length_seconds
	# set_cycle_phase() skips an unchanged phase, so alternate nights sit a hair apart.
	var phase: float = NIGHT_PHASE + float(night % 2) * PHASE_NUDGE
	skybox.update_cycle_clock((float(night) + phase - START_PHASE) * length)
	return float((skybox.environment.sky.sky_material as ShaderMaterial).get_shader_parameter(&"aurora_visibility"))


func test_host_and_client_agree_and_follow_the_seeded_roll() -> void:
	var previous_preset: StringName = Settings.current_graphics_preset().id
	Settings.set_graphics_preset(&"high")
	var chance: float = Skybox.load_theme(Skybox.DEFAULT_THEME_ID).aurora_night_chance
	var host: Skybox = _cycle_skybox(SEEDS[2])
	var client: Skybox = _cycle_skybox(SEEDS[2])
	var shown: int = 0
	for night: int in SAMPLED_NIGHTS:
		var host_value: float = _visibility_at_night(host, night)
		var client_value: float = _visibility_at_night(client, night)
		assert_almost_eq(host_value, client_value, 0.0001, "night %d host == client" % night)
		var rolled: bool = SkyVariation.aurora_night_shown(SkyVariation.seed_for(SEEDS[2]), night, chance)
		assert_eq(host_value > 0.5, rolled, "night %d follows the seeded roll" % night)
		if rolled:
			shown += 1
	assert_lt(shown, SAMPLED_NIGHTS, "not every night shows it")
	Settings.set_graphics_preset(previous_preset)
