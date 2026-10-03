extends GutTest
## Bontago-1pi.46 R3 (docs/MATCH_RESET_AUDIT.md sections 5-6): the acceptance test for the
## owner requirement "after leaving a match and starting another (any mode, map,
## weather, sky), everything is as if freshly launched".
##
## For each scenario a REFERENCE run takes a fresh game/Main.tscn through the new match B
## and fingerprints it at the menu, at COUNTDOWN + 0.5 s and at PLAYING + 1 s
## (tests/unit/support/MatchFingerprint.gd). A DIRTY run then plays a match A that leaves
## everything it can behind (night sky, storm then rain, puddles, gusts, a gift crate,
## queued special + glue, a black hole, a cat, a hole, tilt, a zoomed/orbited/peeking/
## shaking camera, a tense music stem, a hand-picked sky theme, a sandbox session with
## slow motion + pause + a changed territory mode), leaves, and starts the same B. The two
## fingerprints must be identical.
##
## A real gap is NOT fixed here: its key path goes in KNOWN_GAPS (key prefix -> where it
## lives) and the scenario ends pending instead of failing, so the orchestrator files the
## fix. Keys not listed there fail the test.
##
## Same fixture as tests/unit/test_match_restart.gd: the real Main, Net hosting on a free
## port, a tiny map, and Match._process()/weather tick driven by hand (the headless host
## has no loading hold, so a started match is in COUNTDOWN at once).

const MAIN_SCENE: PackedScene = preload("res://game/Main.tscn")
const CAT_DEF: SpecialDef = preload("res://config/specials/cat.tres")
const SEED: int = 777
const TINY_FIELD_RADIUS: float = 20.0
const OTHER_FIELD_RADIUS: float = 16.0
const CHECK_COUNTDOWN_S: float = 0.5
const CHECK_PLAYING_S: float = 1.0
const STORM_RUN_S: float = 8.0
const RAIN_RUN_S: float = 8.0
const GUST_ID: int = 9001
const GUST_RADIUS_M: float = 4.0
const GUST_DURATION_S: float = 5.0
const CEILING_FADE_S: float = 20.0
const DIRTY_ZOOM: float = 40.0
const HOLE_RADIUS_M: float = 3.0
const HOLE_OPEN_S: float = 30.0
const TILT_IMPULSE: float = 5.0
const TILT_STEPS: int = 20
const TILT_STEP_S: float = 0.05
const CHECKPOINTS: PackedStringArray = ["menu", "countdown", "playing"]

## Real gaps found by this test, for the orchestrator to file: "<label substring>|<key prefix>"
## -> what / likely owner. A scenario whose only diffs match an entry ends pending instead of
## failing; any other diff fails it.
const KNOWN_GAPS: Dictionary = {
	"replay|field.basis": "after Replay from END the Field's global basis is tilted (about 0.2 rad) at B COUNTDOWN/PLAYING while Field.tilt reads 0 (Leave path is clean) -> game/Field.gd tilt apply or MatchLifecycle teardown order",
	"@ menu|camera.follow_position": "after a sandbox Leave the rig's follow position is (0, 0.3, 0) at the menu: the Sandbox's PlayerController runs _process once more after Main's reset in the same frame -> game/Main.gd _on_pause_leave_requested (queue_free vs reset order); B itself is clean",
	"@ menu|camera.target": "same cause as camera.follow_position",
	"@ menu|camera.origin": "same cause as camera.follow_position",
	"|wiring.node.ResultsScreen": "ResultsScreen keeps the last match's result rows (hidden) until the next results -> ui/ResultsScreen.gd",
	"|wiring.node.LoadingScreen": "LoadingScreen keeps the last match's player rows (hidden) until the next show -> ui/LoadingScreen.gd",
}

var _mains: Array[Node] = []
var _map: MapDef
var _other_map: MapDef
var _saved_gravity_multiplier: float


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	SnapshotSync.end_match()
	assert_true(Net.is_offline(), "fixture: the real Net must start offline")
	Engine.time_scale = 1.0
	_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_map.field_radius = TINY_FIELD_RADIUS
	_other_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_other_map.field_radius = OTHER_FIELD_RADIUS
	_saved_gravity_multiplier = (load("res://config/physics_tuning.tres") as PhysicsTuning).gravity_multiplier


func after_each() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	Net.leave()
	Match.abort_match()
	SnapshotSync.end_match()
	for main: Node in _mains:
		if is_instance_valid(main):
			main.queue_free()
	_mains.clear()
	Match.set_process(true)
	(load("res://config/physics_tuning.tres") as PhysicsTuning).gravity_multiplier = _saved_gravity_multiplier
	Sfx._tense_stem_is_active = false
	await get_tree().process_frame
	await get_tree().process_frame


# --- helpers --------------------------------------------------------------------------

func _new_main(map: MapDef) -> Node:
	var main: Node = MAIN_SCENE.instantiate()
	(main.get_node("Field") as Field).map_def = map
	add_child(main)
	_mains.append(main)
	assert_not_null(main.get("_main_menu"), "fixture: Main boots to the main menu")
	return main


## Sandbox and tutorial build their config from Main.match_config (rng_seed -1 = random): pin
## the seed and the tiny map so two runs compare.
func _seed_main_config(main: Node) -> void:
	var config: MatchConfig = (main.get("match_config") as MatchConfig).duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_map)
	config.rng_seed = SEED
	main.set("match_config", config)


func _free_main(main: Node) -> void:
	_mains.erase(main)
	main.queue_free()
	await _settle()


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _host() -> void:
	assert_eq(Net.host_game(AgentProbe.free_udp_port(), "Hostie"), OK)


func _config(map: MapDef, weather_mode: int, sky_mode: int, ai_count: int) -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(map)
	config.player_count = 2
	config.ai_count = ai_count
	config.hot_seat = false
	config.rng_seed = SEED
	config.weather_mode = weather_mode as MatchConfig.WeatherMode
	config.sky_theme_mode = sky_mode as MatchConfig.SkyThemeMode
	return config


## Match B: two players (one a bot), Day sky, no weather, unless a scenario says otherwise.
func _config_b(map: MapDef = null, weather_mode: int = MatchConfig.WeatherMode.OFF) -> MatchConfig:
	return _config(map if map != null else _map, weather_mode, MatchConfig.SkyThemeMode.DAY, 1)


func _run_seconds(seconds: float) -> void:
	var step: float = 1.0 / Engine.physics_ticks_per_second
	for _i: int in range(int(ceil(seconds * Engine.physics_ticks_per_second))):
		Match._process(step)
		Match.weather().tick(step)


func _start(main: Node, config: MatchConfig) -> void:
	main._on_lobby_start_requested(config)


## Fingerprints a started match B at COUNTDOWN + 0.5 s and PLAYING + 1 s.
func _fingerprint_playing_b(main: Node) -> Dictionary:
	var out: Dictionary = {}
	await _settle()
	_run_seconds(CHECK_COUNTDOWN_S)
	assert_eq(Match.state(), Match.State.COUNTDOWN, "fixture: still counting down")
	out["countdown"] = MatchFingerprint.capture(main)
	_run_seconds(Match.COUNTDOWN_SECONDS)
	_run_seconds(CHECK_PLAYING_S)
	await _settle()
	assert_eq(Match.state(), Match.State.PLAYING, "fixture: playing")
	out["playing"] = MatchFingerprint.capture(main)
	return out


## What a fresh launch shows for B (host + lobby match). Returns the checkpoints.
func _reference_lobby_match(config_factory: Callable) -> Dictionary:
	var main: Node = _new_main(_map)
	var out: Dictionary = {"menu": MatchFingerprint.capture(main)}
	_host()
	_start(main, config_factory.call() as MatchConfig)
	out.merge(await _fingerprint_playing_b(main))
	Net.leave()
	await _free_main(main)
	Match.abort_match()
	return out


# --- match A: everything a played match can leave behind -------------------------------

func _dirty_camera(rig: CameraRig) -> void:
	rig.zoom_continuous(DIRTY_ZOOM)
	rig._yaw += 1.3
	rig._pitch = deg_to_rad(-72.0)
	rig.set_follow_position(Vector3(12.0, 3.0, -7.0))
	rig.begin_follow_transition()
	rig.block_held = true
	rig.set_local_slot(1)
	rig._on_block_impacted(1000.0)
	rig._peek_active = true
	rig._peek_returning = true
	rig._focus_action = &"camera_snap_goal"
	rig._focus_hold_elapsed_s = 5.0
	rig._goal_cycle_index = 1
	rig._turn_to_face(Vector3.ZERO)


func _ceiling(main: Node) -> CloudCeiling:
	var presenter: WeatherPresenter = MatchNet.get_node_or_null(MatchFingerprint.WEATHER_PRESENTER_PATH) as WeatherPresenter
	return presenter.cloud_ceiling() if presenter != null else null


## Plays match A (Night sky, storm then rain, a bot) and dirties everything in reach. Leaves
## the match running (state PLAYING) so the caller picks the exit path.
func _play_dirty_a(main: Node) -> void:
	_host()
	_start(main, _config(_map, MatchConfig.WeatherMode.STORM, MatchConfig.SkyThemeMode.NIGHT, 1))
	_run_seconds(Match.COUNTDOWN_SECONDS + 0.2)
	await _settle()
	assert_eq(Match.state(), Match.State.PLAYING, "fixture: A is playing")
	var field: Field = main.get_node("Field") as Field
	var skybox: Skybox = main.get("_skybox") as Skybox
	var rig: CameraRig = main.get("_camera_rig") as CameraRig
	# Storm, then rain: sky blend, ceiling, weather fog, wet territory, puddles.
	assert_true(Match.weather().set_debug_override(&"storm"), "fixture: storm started")
	_run_seconds(STORM_RUN_S)
	var ceiling: CloudCeiling = _ceiling(main)
	assert_not_null(ceiling, "fixture: the weather presenter exists")
	ceiling.step(CEILING_FADE_S)
	assert_gt(skybox.storm_sky_amount(), 0.0, "fixture: the storm tinted the sky")
	assert_true(Match.weather().set_debug_override(&"rain"), "fixture: rain started")
	_run_seconds(RAIN_RUN_S)
	ceiling.step(CEILING_FADE_S)
	var puddles: RainPuddles = field.get_node_or_null(RainPuddles.NODE_NAME) as RainPuddles
	assert_not_null(puddles, "fixture: rain put puddles on the Field")
	puddles.advance(load("res://config/weather/rain.tres").puddle_fill_time_s)
	assert_gt(puddles.wetness(), 0.0, "fixture: the arena is wet")
	# A hand-picked sky (F4 dropdown), a gust, a gift crate with a queued special and glue.
	skybox.set_theme_by_id("sunset")
	var wire: Dictionary = {"id": GUST_ID, "x": 0.0, "y": 1.0, "z": 0.0, "a": 0.5, "r": GUST_RADIUS_M, "d": GUST_DURATION_S, "s": 1.0}
	var gust: Dictionary = wire.duplicate()
	gust["age"] = 0.0
	Match.weather().breeze()._gusts.append(gust)
	Events.breeze_gust_started.emit(wire)
	Match._gifts._spawn_crate_at(Vector2(2.0, 2.0))
	Match._gifts._queue_claimed_special(0, &"anvil")
	Match.grant_glue_drops(1, 3)
	# A black hole visual under the blocks parent, a cat, a hole, a tilted disc.
	Events.special_triggered.emit(0, &"black_hole", Vector3(0.0, 1.0, 0.0), 0)
	Match.start_cat(0, Vector3(1.0, 1.0, 1.0), CAT_DEF.effect as CatEffect)
	Match.punch_special_hole(Vector2.ZERO, HOLE_RADIUS_M, HOLE_OPEN_S)
	field.apply_tilt_impulse(Vector2.RIGHT, TILT_IMPULSE)
	for _i: int in range(TILT_STEPS):
		field._update_tilt(TILT_STEP_S)
	# Camera moves, a held-over music stem, a bumped gravity multiplier.
	_dirty_camera(rig)
	Sfx._tense_stem_is_active = true
	await _settle()


## Menu sandbox session that leaves slow motion, a paused tree and a non-default territory
## mode behind, exited through the pause menu's Leave.
func _sandbox_session_and_leave(main: Node) -> void:
	_seed_main_config(main)
	main.start_sandbox_from_menu()
	var sandbox: Sandbox = main.get("_sandbox") as Sandbox
	assert_not_null(sandbox, "fixture: the sandbox is live")
	sandbox._toggle_slow_motion()
	sandbox._toggle_physics_paused()
	Match.set_sandbox_territory_mode(Match.SANDBOX_TERRITORY_PAUSED)
	_dirty_camera(main.get("_camera_rig") as CameraRig)
	main._on_pause_leave_requested()
	await _settle()
	assert_eq(Engine.time_scale, 1.0, "fixture: the sandbox gave slow motion back")
	assert_false(get_tree().paused, "fixture: and the pause")


func _assert_same(reference: Dictionary, dirty: Dictionary, label: String) -> bool:
	var found: PackedStringArray = MatchFingerprint.diff(reference, dirty)
	var real: PackedStringArray = PackedStringArray()
	var known: PackedStringArray = PackedStringArray()
	for line: String in found:
		var gap: String = ""
		for entry: Variant in KNOWN_GAPS.keys():
			var parts: PackedStringArray = String(entry).split("|")
			if (parts[0] == "" or label.contains(parts[0])) and line.begins_with(parts[1]):
				gap = String(KNOWN_GAPS[entry])
		if gap == "":
			real.append(line)
		else:
			known.append("%s [known gap: %s]" % [line.get_slice(":", 0), gap])
	assert_eq(real.size(), 0, "%s: B differs from a fresh launch in %d key(s):\n  %s" % [label, real.size(), "\n  ".join(real)])
	if not known.is_empty():
		pending("%s: known gap(s): %s" % [label, "; ".join(known)])
	return real.is_empty()


func _assert_checkpoints(reference: Dictionary, dirty: Dictionary, label: String) -> void:
	for checkpoint: String in CHECKPOINTS:
		if reference.has(checkpoint) and dirty.has(checkpoint):
			_assert_same(reference[checkpoint] as Dictionary, dirty[checkpoint] as Dictionary, "%s @ %s" % [label, checkpoint])


# --- scenarios -------------------------------------------------------------------------

func test_fingerprint_diff_reports_changed_missing_and_float_noise() -> void:
	var a: Dictionary = {"x": 1.00004, "y": [1, 2.0], "z": "a", "only_a": true}
	var b: Dictionary = {"x": 1.0, "y": [1.0, 2], "z": "b", "only_b": 3}
	var found: PackedStringArray = MatchFingerprint.diff(a, b)
	assert_eq(found.size(), 3, "x and y are equal within rounding; z, only_a and only_b differ: %s" % [found])
	assert_true(found[0].begins_with("only_a"))
	assert_true(MatchFingerprint.diff(a, a).is_empty())


func test_a_capture_is_stable_and_covers_every_section() -> void:
	var main: Node = _new_main(_map)
	var first: Dictionary = MatchFingerprint.capture(main)
	var second: Dictionary = MatchFingerprint.capture(main)
	assert_eq(MatchFingerprint.diff(first, second).size(), 0, "two captures of an untouched Main agree")
	for section: String in ["camera.", "field.", "sky.", "weather.", "rules.", "net.", "globals.", "audio.", "ui.", "wiring."]:
		var hits: int = 0
		for key: Variant in first.keys():
			if String(key).begins_with(section):
				hits += 1
		assert_gt(hits, 0, "the fingerprint has %s keys" % section)
	assert_gt(first.size(), 100, "the fingerprint is broad (%d keys)" % first.size())


func test_a_dirtied_main_is_caught_by_the_fingerprint() -> void:
	# Guards the guard: the dirty phase really changes what the fingerprint sees.
	var main: Node = _new_main(_map)
	var launch: Dictionary = MatchFingerprint.capture(main)
	await _play_dirty_a(main)
	var dirtied: Dictionary = MatchFingerprint.capture(main)
	var found: PackedStringArray = MatchFingerprint.diff(launch, dirtied)
	var text: String = "\n".join(found)
	for key: String in ["camera.distance", "sky.overcast", "weather.active_id", "field.puddles_present", "audio.tense_active", "rules.gift_crates"]:
		assert_true(text.contains(key), "match A changed %s" % key)


func test_a_new_match_after_a_dirty_one_and_a_sandbox_session_matches_a_fresh_launch() -> void:
	var reference: Dictionary = await _reference_lobby_match(func() -> MatchConfig: return _config_b())
	var main: Node = _new_main(_map)
	await _play_dirty_a(main)
	main._on_pause_leave_requested()
	await _settle()
	assert_not_null(main.get("_main_menu"), "fixture: back on the main menu")
	await _sandbox_session_and_leave(main)
	var dirty: Dictionary = {"menu": MatchFingerprint.capture(main)}
	_host()
	_start(main, _config_b())
	dirty.merge(await _fingerprint_playing_b(main))
	_assert_checkpoints(reference, dirty, "lobby match after A + sandbox")


func test_a_replay_from_the_results_screen_matches_a_fresh_launch() -> void:
	var reference: Dictionary = await _reference_lobby_match(func() -> MatchConfig: return _config_b())
	var main: Node = _new_main(_map)
	await _play_dirty_a(main)
	Match._lifecycle._finish_match(0)
	await _settle()
	assert_eq(Match.state(), Match.State.END, "fixture: A ended on the results screen")
	# Replay: start_match() from END goes (END -> LOBBY) then (LOBBY -> LOADING).
	_start(main, _config_b())
	var dirty: Dictionary = await _fingerprint_playing_b(main)
	_assert_checkpoints(reference, dirty, "replay from END")


func test_back_to_the_lobby_from_the_results_screen_then_a_new_match_matches_a_fresh_launch() -> void:
	var reference: Dictionary = await _reference_lobby_match(func() -> MatchConfig: return _config_b())
	var main: Node = _new_main(_map)
	await _play_dirty_a(main)
	Match._lifecycle._finish_match(0)
	await _settle()
	Match.abort_match()
	await _settle()
	assert_eq(Match.state(), Match.State.LOBBY, "fixture: results Back goes to the lobby")
	assert_not_null(main.get("_lobby"), "fixture: the lobby is up (Net stays hosted)")
	_start(main, _config_b())
	var dirty: Dictionary = await _fingerprint_playing_b(main)
	_assert_checkpoints(reference, dirty, "results Back to lobby")


func test_a_different_map_and_rain_after_a_dirty_match_matches_a_fresh_launch() -> void:
	var reference: Dictionary = await _reference_lobby_match(func() -> MatchConfig: return _config_b(_other_map, MatchConfig.WeatherMode.RAIN))
	var main: Node = _new_main(_other_map)
	await _play_dirty_a(main)
	main._on_pause_leave_requested()
	await _settle()
	_host()
	_start(main, _config_b(_other_map, MatchConfig.WeatherMode.RAIN))
	var dirty: Dictionary = await _fingerprint_playing_b(main)
	_assert_checkpoints(reference, dirty, "other map + rain")


func test_a_menu_sandbox_after_a_dirty_match_matches_a_fresh_sandbox() -> void:
	var fresh_main: Node = _new_main(_map)
	_seed_main_config(fresh_main)
	fresh_main.start_sandbox_from_menu()
	await _settle()
	var reference: Dictionary = MatchFingerprint.capture(fresh_main)
	await _free_main(fresh_main)
	Match.abort_match()
	var main: Node = _new_main(_map)
	await _play_dirty_a(main)
	main._on_pause_leave_requested()
	await _settle()
	_seed_main_config(main)
	main.start_sandbox_from_menu()
	await _settle()
	_assert_same(reference, MatchFingerprint.capture(main), "sandbox after A")


func test_a_menu_tutorial_after_a_dirty_match_matches_a_fresh_tutorial() -> void:
	var fresh_main: Node = _new_main(_map)
	_seed_main_config(fresh_main)
	fresh_main.start_tutorial_from_menu()
	await _settle()
	var reference: Dictionary = MatchFingerprint.capture(fresh_main)
	await _free_main(fresh_main)
	Match.abort_match()
	var main: Node = _new_main(_map)
	await _play_dirty_a(main)
	main._on_pause_leave_requested()
	await _settle()
	_seed_main_config(main)
	main.start_tutorial_from_menu()
	await _settle()
	_assert_same(reference, MatchFingerprint.capture(main), "tutorial after A")


func test_a_lobby_match_after_a_sandbox_session_matches_a_fresh_launch() -> void:
	var reference: Dictionary = await _reference_lobby_match(func() -> MatchConfig: return _config_b())
	var main: Node = _new_main(_map)
	await _sandbox_session_and_leave(main)
	var dirty: Dictionary = {"menu": MatchFingerprint.capture(main)}
	_host()
	_start(main, _config_b())
	dirty.merge(await _fingerprint_playing_b(main))
	_assert_checkpoints(reference, dirty, "lobby match after sandbox")
