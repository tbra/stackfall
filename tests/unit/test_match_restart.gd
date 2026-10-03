extends GutTest
## Bontago-1pi.46 (owner playtest 2026-10-03: "leaving match and starting a new
## match doesn't reset properly, when i tried it my camera and zoom level were
## the same as when i left the old match and the arena still had rain puddles").
##
## The CameraRig and the Field's RainPuddles layer are persistent children of
## game/Main.tscn, so a second match inherited the first one's zoom/pitch and
## whatever wetness had not dried yet. These drive the real Main scene, Net and
## Match autoloads (same fixture as test_match_lifecycle.gd) through
## play -> leave -> start a new match, and pin the unit seams under it:
## CameraRig.reset_view() and RainPuddles.clear_on().

const MAIN_SCENE: PackedScene = preload("res://game/Main.tscn")
const CAMERA_RIG_SCENE: PackedScene = preload("res://game/CameraRig.tscn")
const RAIN_TUNING: RainTuning = preload("res://config/weather/rain.tres")
const SCHEDULE: WeatherScheduleTuning = preload("res://config/weather_schedule.tres")

var _main: Variant = null
var _tiny_map: MapDef
var _saved_gravity_multiplier: float


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	SnapshotSync.end_match()
	assert_true(Net.is_offline(), "fixture: the real Net must start offline")
	_main = MAIN_SCENE.instantiate()
	_tiny_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	(_main.get_node("Field") as Field).map_def = _tiny_map
	add_child_autofree(_main)
	assert_not_null(_main._main_menu, "fixture: Main boots to the main menu with no command-line flags")
	_saved_gravity_multiplier = (load("res://config/physics_tuning.tres") as PhysicsTuning).gravity_multiplier


func after_each() -> void:
	Net.leave()
	Match.abort_match()
	SnapshotSync.end_match()
	Match.set_process(true)
	(load("res://config/physics_tuning.tres") as PhysicsTuning).gravity_multiplier = _saved_gravity_multiplier
	await get_tree().process_frame
	await get_tree().process_frame


# --- helpers ------------------------------------------------------------------

func _host() -> void:
	assert_eq(Net.host_game(AgentProbe.free_udp_port(), "Hostie"), OK)
	assert_not_null(_main._lobby, "hosting swaps the menu for the lobby synchronously")


func _config(weather_mode: int) -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.hot_seat = false
	config.rng_seed = 777
	config.weather_mode = weather_mode as MatchConfig.WeatherMode
	return config


func _start(weather_mode: int) -> void:
	_main._on_lobby_start_requested(_config(weather_mode))


## Match._process() drives the countdown and states; the weather schedule is
## ticked from Match._physics_process() in the game, so tick it here directly.
func _run_seconds(seconds: float) -> void:
	var step: float = 1.0 / Engine.physics_ticks_per_second
	for _i: int in range(int(ceil(seconds * Engine.physics_ticks_per_second))):
		Match._process(step)
		Match.weather().tick(step)


## Countdown, then the constant-rain delay and its ramp-in: rain is at full
## intensity afterwards, so the Field carries a puddle layer.
func _run_until_raining() -> void:
	_run_seconds(Match.COUNTDOWN_SECONDS + 0.2)
	_run_seconds(SCHEDULE.constant_start_delay_s + RAIN_TUNING.ramp_in_s + 1.0)


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _rig() -> CameraRig:
	return _main._camera_rig as CameraRig


func _field() -> Field:
	return _main.get_node("Field") as Field


func _puddles() -> RainPuddles:
	return _field().get_node_or_null(RainPuddles.NODE_NAME) as RainPuddles


func _fresh_rig() -> CameraRig:
	var rig: CameraRig = CAMERA_RIG_SCENE.instantiate() as CameraRig
	add_child_autofree(rig)
	return rig


## Everything a played match can leave on the rig: zoom, orbit, a peek, a
## shake, a queued turn.
func _dirty(rig: CameraRig) -> void:
	rig.zoom_continuous(40.0)
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


func _assert_launch_view(rig: CameraRig, fresh: CameraRig, label: String) -> void:
	assert_almost_eq(rig.get_distance(), fresh.get_distance(), 0.0001, "%s: zoom distance is the launch value" % label)
	assert_almost_eq(rig.get_pitch(), fresh.get_pitch(), 0.0001, "%s: pitch is the launch value" % label)


# --- CameraRig.reset_view() ---------------------------------------------------

func test_reset_view_puts_every_field_back_to_a_fresh_rigs_values() -> void:
	var fresh: CameraRig = _fresh_rig()
	var rig: CameraRig = _fresh_rig()
	_dirty(rig)
	assert_ne(rig.get_distance(), fresh.get_distance(), "fixture: the zoom changed")
	assert_true(rig.shake_offset() != Vector3.ZERO or not Settings.camera_shake_enabled(), "fixture: shaking")

	rig.reset_view()

	assert_almost_eq(rig.get_distance(), fresh.get_distance(), 0.0001)
	assert_almost_eq(rig.get_pitch(), fresh.get_pitch(), 0.0001)
	assert_almost_eq(rig.get_yaw(), fresh.get_yaw(), 0.0001)
	assert_eq(rig.get_target(), fresh.get_target())
	assert_eq(rig.shake_offset(), Vector3.ZERO, "no shake carries over")
	assert_false(rig.is_peeking())
	assert_false(rig.block_held)
	assert_eq(rig._follow_position, fresh._follow_position)
	assert_eq(rig._local_slot, fresh._local_slot)
	assert_false(rig._drop_recovering)
	assert_false(rig._peek_returning)
	assert_eq(rig._focus_action, &"")
	assert_eq(rig._goal_cycle_index, 0)
	assert_true(rig.get_camera().global_transform.origin.is_equal_approx(fresh.get_camera().global_transform.origin), "same camera position")
	assert_true(rig.get_camera().global_transform.basis.is_equal_approx(fresh.get_camera().global_transform.basis), "same camera orientation")


func test_reset_view_stops_an_in_flight_turn_tween() -> void:
	var rig: CameraRig = _fresh_rig()
	rig.set_follow_position(Vector3(10.0, 0.0, 0.0))
	rig._turn_to_face(Vector3.ZERO)
	assert_eq(rig._view_tweens.size(), 1, "the turn is tracked")

	rig.reset_view()
	var yaw_after_reset: float = rig.get_yaw()
	await wait_seconds(rig.tuning.focus_turn_duration_s + 0.2)

	assert_eq(rig._view_tweens.size(), 0)
	assert_almost_eq(rig.get_yaw(), yaw_after_reset, 0.0001, "the old turn does not keep rotating the next match's view")


func test_finished_tweens_are_dropped_from_the_tracking_list() -> void:
	var rig: CameraRig = _fresh_rig()
	rig.set_follow_position(Vector3(10.0, 0.0, 0.0))
	rig._turn_to_face(Vector3.ZERO)
	await wait_seconds(rig.tuning.focus_turn_duration_s + 0.2)
	rig._turn_to_face(Vector3(0.0, 0.0, 10.0))
	assert_eq(rig._view_tweens.size(), 1, "the finished one was pruned when the next was tracked")


# --- RainPuddles.clear_on() ---------------------------------------------------

func test_clear_on_removes_the_layer_and_a_new_one_builds_dry() -> void:
	var holder: Node3D = Node3D.new()
	add_child_autofree(holder)
	var map_def: MapDef = MapDef.new()
	var puddles: RainPuddles = RainPuddles.ensure_on(holder, map_def, RAIN_TUNING, 1.0)
	puddles.set_rain(1.0)
	puddles.advance(RAIN_TUNING.puddle_fill_time_s)
	assert_eq(puddles.wetness(), 1.0, "fixture: fully wet")

	assert_true(RainPuddles.clear_on(holder))

	assert_false(is_instance_valid(puddles), "freed at once, not at end of frame")
	assert_null(holder.get_node_or_null(RainPuddles.NODE_NAME))
	assert_false(RainPuddles.clear_on(holder), "nothing left to clear")
	assert_false(RainPuddles.clear_on(null))
	var rebuilt: RainPuddles = RainPuddles.ensure_on(holder, map_def, RAIN_TUNING, 1.0)
	assert_eq(rebuilt.wetness(), 0.0, "a new layer starts dry")
	assert_eq(rebuilt.name, RainPuddles.NODE_NAME, "and takes the plain name, not an auto-renamed one")


# --- play -> leave -> start a new match (real Main) -----------------------------

func test_a_new_match_after_leaving_starts_from_the_launch_camera_and_a_dry_arena() -> void:
	var fresh: CameraRig = _fresh_rig()
	_host()
	_start(MatchConfig.WeatherMode.RAIN)
	_run_until_raining()
	var rig: CameraRig = _rig()
	assert_eq(Match.weather().active_id(), &"rain", "fixture: it is raining")
	var wet: RainPuddles = _puddles()
	assert_not_null(wet, "fixture: rain put a puddle layer on the Field")
	wet.advance(RAIN_TUNING.puddle_fill_time_s)
	assert_almost_eq(wet.wetness(), 1.0, 0.001, "fixture: the arena is soaked")
	_assert_launch_view(rig, fresh, "first match")
	var match_yaw: float = rig.get_yaw()
	assert_ne(match_yaw, 0.0, "fixture: the match start aimed the camera from the home beacon")
	_dirty(rig)
	assert_ne(rig.get_distance(), fresh.get_distance(), "fixture: the player zoomed out")

	_main._on_pause_leave_requested()
	await _settle()

	assert_true(Net.is_offline())
	assert_not_null(_main._main_menu, "back on the main menu")
	_assert_launch_view(rig, fresh, "menu after leaving")
	assert_almost_eq(rig.get_yaw(), fresh.get_yaw(), 0.0001, "menu after leaving: launch yaw")
	assert_null(_puddles(), "the soaked layer is gone with the match")

	_host()
	_start(MatchConfig.WeatherMode.OFF)
	_run_seconds(Match.COUNTDOWN_SECONDS + 0.2)
	await _settle()

	assert_eq(Match.state(), Match.State.PLAYING)
	_assert_launch_view(rig, fresh, "second match")
	assert_almost_eq(rig.get_yaw(), match_yaw, 0.0001, "second match: the same orientation the first match started with")
	assert_false(rig.is_peeking())
	var layer: RainPuddles = _puddles()
	assert_true(layer == null or layer.wetness() == 0.0, "clear weather: no wetness at the start")
	_run_seconds(SCHEDULE.constant_start_delay_s + 5.0)
	layer = _puddles()
	assert_true(layer == null or layer.wetness() == 0.0, "and none appears while it stays clear")


func test_the_new_match_entry_resets_even_when_the_teardown_left_state_behind() -> void:
	var fresh: CameraRig = _fresh_rig()
	_host()
	_start(MatchConfig.WeatherMode.OFF)
	var rig: CameraRig = _rig()
	var match_yaw: float = rig.get_yaw()
	Net.leave()
	await _settle()
	# Whatever survives the teardown (a late weather event, a stray tween, an
	# older build without the teardown reset) must still not reach the next match.
	_dirty(rig)
	var soaked: RainPuddles = RainPuddles.ensure_on(_field(), _tiny_map, RAIN_TUNING, 1.0)
	soaked.set_rain(1.0)
	soaked.advance(RAIN_TUNING.puddle_fill_time_s)
	assert_almost_eq(soaked.wetness(), 1.0, 0.001, "fixture: wet again")

	_host()
	_start(MatchConfig.WeatherMode.OFF)

	_assert_launch_view(rig, fresh, "new match entry")
	assert_almost_eq(rig.get_yaw(), match_yaw, 0.0001, "the home-beacon orientation, not the dirtied one")
	assert_false(is_instance_valid(soaked), "the wet layer is dropped when the new world builds")
	assert_null(_puddles())


func test_a_live_rain_presentation_rebuilds_a_dry_layer_after_the_reset() -> void:
	_host()
	_start(MatchConfig.WeatherMode.RAIN)
	_run_until_raining()
	var presenter: WeatherPresenter = get_tree().root.find_child("WeatherPresenter", true, false) as WeatherPresenter
	assert_not_null(presenter)
	var presentation: RainPresentation = presenter.presentation_for(&"rain")
	assert_not_null(presentation, "fixture: the rain presentation is alive")
	var old_layer: RainPuddles = _puddles()
	assert_not_null(old_layer)

	_main._reset_match_presentation(false)
	assert_false(is_instance_valid(old_layer))
	presentation.set_intensity(1.0)

	var new_layer: RainPuddles = _puddles()
	assert_not_null(new_layer, "rain that is still falling builds a fresh layer instead of keeping a dead reference")
	assert_eq(new_layer.wetness(), 0.0, "which starts dry and fills from zero")
