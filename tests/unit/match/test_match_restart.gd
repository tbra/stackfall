extends GutTest
## ("leaving match and starting a new
## match doesn't reset properly, when i tried it my camera and zoom level were
## the same as when i left the old match and the arena still had rain puddles").

const MAIN_SCENE: PackedScene = preload("res://game/main/Main.tscn")
const CAMERA_RIG_SCENE: PackedScene = preload("res://game/player/CameraRig.tscn")
const RAIN_TUNING: RainTuning = preload("res://config/weather/rain.tres")
const SCHEDULE: WeatherScheduleTuning = preload("res://config/weather/weather_schedule.tres")

var _main: Variant = null
var _tiny_map: MapDef
var _saved_gravity_multiplier: float


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	SnapshotSync.end_match()
	assert_true(Net.is_offline(), "fixture: the real Net must start offline")
	_main = MAIN_SCENE.instantiate()
	_tiny_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	(_main.get_node("Field") as Field).map_def = _tiny_map
	add_child_autofree(_main)
	assert_not_null(_main._main_menu, "fixture: Main boots to the main menu with no command-line flags")
	_saved_gravity_multiplier = (load("res://config/physics/physics_tuning.tres") as PhysicsTuning).gravity_multiplier


func after_each() -> void:
	Net.leave()
	Match.abort_match()
	SnapshotSync.end_match()
	Match.set_process(true)
	(load("res://config/physics/physics_tuning.tres") as PhysicsTuning).gravity_multiplier = _saved_gravity_multiplier
	await get_tree().process_frame
	await get_tree().process_frame


# --- helpers ------------------------------------------------------------------

func _host() -> void:
	assert_eq(Net.host_game(AgentProbe.free_udp_port(), "Hostie"), OK)
	assert_not_null(_main._lobby, "hosting swaps the menu for the lobby synchronously")


func _config(weather_mode: int) -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
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
	rig._on_special_triggered(1, &"bomb", Vector3.ZERO, 0)
	rig._peek_active = true
	rig._peek_returning = true
	rig._focus_action = &"camera_snap_goal"
	rig._focus_hold_elapsed_s = 5.0
	rig._goal_cycle_index = 1


func _assert_launch_view(rig: CameraRig, fresh: CameraRig, label: String) -> void:
	assert_almost_eq(rig.get_distance(), fresh.get_distance(), 0.0001, "%s: zoom distance is the launch value" % label)
	assert_almost_eq(rig.get_pitch(), fresh.get_pitch(), 0.0001, "%s: pitch is the launch value" % label)


# --- CameraRig.reset_view() ---------------------------------------------------

# --- RainPuddles.clear_on() ---------------------------------------------------

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
	assert_almost_eq(_wetness(wet), 1.0, 0.001, "fixture: the arena is soaked")
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
	assert_true(_wetness(layer) == 0.0, "clear weather: no wetness at the start")
	_run_seconds(SCHEDULE.constant_start_delay_s + 5.0)
	layer = _puddles()
	assert_true(_wetness(layer) == 0.0, "and none appears while it stays clear")


# --- Events.match_scope_reset hub (R0) ---------------------------

const SCOPE_SIGNAL: String = "match_scope_reset"


func test_the_scope_reset_signal_fires_once_per_build_and_once_per_teardown() -> void:
	_host()
	watch_signals(Events)

	_start(MatchConfig.WeatherMode.OFF)
	assert_true(_main._world_built, "fixture: the world was built")
	assert_signal_emit_count(Events, SCOPE_SIGNAL, 1, "one world build, one reset")

	Match.abort_match()
	assert_false(_main._world_built, "fixture: the world came down")
	assert_signal_emit_count(Events, SCOPE_SIGNAL, 2, "the teardown adds exactly one")


func test_a_lobby_match_after_a_menu_sandbox_has_gamepad_home_focus_again() -> void:
	var rig: CameraRig = _rig()
	assert_false(rig.suppress_pad_home_focus, "fixture: a fresh launch lets pad Back focus home")
	_main.start_sandbox_from_menu()
	assert_true(rig.suppress_pad_home_focus, "fixture: the sandbox owns pad Back for next-slot")

	_main._on_pause_leave_requested()
	await _settle()
	assert_not_null(_main._main_menu, "fixture: back on the main menu")
	assert_false(rig.suppress_pad_home_focus, "leaving the sandbox hands pad Back back to the camera")

	_host()
	_start(MatchConfig.WeatherMode.OFF)

	assert_false(rig.suppress_pad_home_focus, "the lobby match starts with it released")
	var pad_back: InputEventJoypadButton = InputEventJoypadButton.new()
	pad_back.button_index = JOY_BUTTON_BACK
	pad_back.pressed = true
	assert_true(pad_back.is_action_pressed(&"camera_snap_home"), "fixture: Back is camera_snap_home")
	rig.tuning = rig.tuning.duplicate() as CameraTuning
	rig.tuning.snap_enabled = true  # snap ships disabled; this covers the suppress flag.
	rig._unhandled_input(pad_back)
	assert_eq(rig._focus_action, &"camera_snap_home", "pad Back focuses home in the lobby match")


## The wetness the puddle shader is fed (0 when no layer or no patches exist).
func _wetness(puddles: RainPuddles) -> float:
	var patches: MultiMeshInstance3D = puddles.get_node_or_null("Patches") as MultiMeshInstance3D if puddles != null else null
	if patches == null:
		return 0.0
	var value: Variant = (patches.material_override as ShaderMaterial).get_shader_parameter(&"wetness")
	return float(value) if value != null else 0.0
