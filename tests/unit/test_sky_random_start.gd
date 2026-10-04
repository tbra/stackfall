extends GutTest
## Bontago-1pi.75: a Cycle match opens at a host-rolled, seed-derived random phase that
## replicates through MatchConfig.to_dict(); locked presets stay fixed.

const SEED_COUNT: int = 12
const SEED_BASE: int = 7000
const SEED_STEP: int = 13
const PHASE_EPSILON: float = 0.0001

var _def: SkyThemeDef = Skybox.load_theme(Skybox.DEFAULT_THEME_ID)


func _config(match_seed: int, mode: MatchConfig.SkyThemeMode = MatchConfig.SkyThemeMode.CYCLE) -> MatchConfig:
	var config: MatchConfig = MatchConfig.new()
	config.sky_theme_mode = mode
	config.rng_seed = match_seed
	config.resolve_sky_start_phase(0, _def.cycle_random_start_min, _def.cycle_random_start_max)
	return config


func _opening_phase(config: MatchConfig) -> float:
	var environment: Environment = Environment.new()
	environment.sky = Sky.new()
	environment.sky.sky_material = ProceduralSkyMaterial.new()
	var skybox: Skybox = Skybox.new()
	skybox.config = SkyboxConfig.new()
	skybox.environment = environment
	skybox.theme = SkyThemeDef.new()
	add_child_autofree(skybox)
	skybox.configure_match_sky(config)
	return skybox.current_cycle_phase()


func test_same_seed_same_phase_and_different_seeds_differ_within_range() -> void:
	assert_almost_eq(_config(SEED_BASE).sky_start_phase, _config(SEED_BASE).sky_start_phase, PHASE_EPSILON)
	var seen: Dictionary = {}
	for i: int in SEED_COUNT:
		var phase: float = _config(SEED_BASE + i * SEED_STEP).sky_start_phase
		assert_between(phase, _def.cycle_random_start_min, _def.cycle_random_start_max)
		seen[snappedf(phase, 0.001)] = true
	assert_gt(seen.size(), SEED_COUNT / 2, "different seeds start at different phases")


func test_unseeded_match_uses_the_roll_and_resolves_once() -> void:
	var config: MatchConfig = MatchConfig.new()
	config.resolve_sky_start_phase(123, 0.1, 0.5)
	var first: float = config.sky_start_phase
	assert_between(first, 0.1, 0.5)
	config.resolve_sky_start_phase(456, 0.1, 0.5)
	assert_eq(config.sky_start_phase, first, "resolving is once per match")


func test_client_agrees_with_host_through_the_wire_dict() -> void:
	var host: MatchConfig = _config(SEED_BASE)
	var client: MatchConfig = MatchConfig.from_dict(host.to_dict())
	assert_almost_eq(client.sky_start_phase, host.sky_start_phase, PHASE_EPSILON)
	assert_almost_eq(_opening_phase(client), _opening_phase(host), PHASE_EPSILON)
	assert_almost_eq(_opening_phase(host), host.sky_start_phase, PHASE_EPSILON, "skybox opens at the chosen phase")


func test_unresolved_phase_falls_back_and_bad_wire_data_is_safe() -> void:
	var config: MatchConfig = MatchConfig.new()
	assert_eq(config.sky_start_phase, MatchConfig.SKY_START_PHASE_UNRESOLVED)
	assert_almost_eq(_opening_phase(config), _def.cycle_start_phase, PHASE_EPSILON)
	assert_eq(MatchConfig.from_dict({"sky_start_phase": "x"}).sky_start_phase, -1.0)
	assert_eq(MatchConfig.from_dict({"sky_start_phase": 5.0}).sky_start_phase, 1.0)


func test_fixed_presets_ignore_the_random_start() -> void:
	var config: MatchConfig = _config(SEED_BASE, MatchConfig.SkyThemeMode.NIGHT)
	assert_eq(config.sky_start_phase, MatchConfig.SKY_START_PHASE_UNRESOLVED, "locked sky is never rolled")
	assert_almost_eq(_opening_phase(config), _def.cycle_locked_phase_night, PHASE_EPSILON)


func test_loading_backdrop_follows_the_chosen_phase() -> void:
	var screen: LoadingScreen = load("res://ui/LoadingScreen.tscn").instantiate() as LoadingScreen
	add_child_autofree(screen)
	var config: MatchConfig = MatchConfig.new()
	config.sky_start_phase = _def.cycle_locked_phase_sunset
	assert_eq(screen._backdrop_theme_id(config), "sunset")
	config.sky_start_phase = _def.cycle_locked_phase_dawn
	assert_eq(screen._backdrop_theme_id(config), "dawn")
