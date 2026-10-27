extends GutTest
## Modes program parity recipe. Every mode builds its world
## through one pipeline; this compares each mode's world against the reference lobby match with
## MatchFingerprint. The floor test proves the recipe itself is deterministic (two fresh launches
## of the reference are equal); the mode tests allow only the delta-table differences listed in KNOWN_GAPS
## and fail on any other line.

const MAIN_SCENE: PackedScene = preload("res://game/main/Main.tscn")
const SEED: int = 777
const TINY_FIELD_RADIUS: float = 20.0
const CHECK_COUNTDOWN_S: float = 0.5
const CHECK_PLAYING_S: float = 1.0
const WATCH_BOTS: int = 2
const CHECKPOINTS: PackedStringArray = ["menu", "countdown", "playing"]

## "<label substring>|<key prefix>" -> the delta-table row (plan section 3) that makes
## the difference intentional. Mode worlds differ from the reference only by these.
const GAP_SEATS: String = "seat roster: the mode seats humans only, no bot (delta table: ai_count = 0 / player_count per mode), so bot nodes, listeners, HUD names and the local-player extras differ"
const GAP_OFFLINE: String = "mode worlds run offline without a host session (no cursors, no host net mode): the spec main menu puts Sandbox and Tutorial under Play Offline"
const GAP_SANDBOX: String = "sandbox extras: Sandbox node, relaxed rules, no loading screen (delta table: sandbox skips the loading screen)"
const GAP_TUTORIAL: String = "tutorial extras: Tutorial node, single seat and flag, timer pinned at its maximum, pause menu suppressed (delta table: the tutorial pins the block timer at its maximum)"
const GAP_PRESET: String = "preset world: gift demo seeds blocks and four seats (delta table: sandbox_preset extra)"
const GAP_SPECTATOR: String = "no local seat: the spectator camera and SpectatorController replace the player's (delta table, watch bots)"
const GAP_HEADLESS: String = "headless bots: no local seat, HUD or camera follow, Timer for --seconds (delta table)"
const GAP_PAD_FOCUS: String = "sandbox suppresses the gamepad home focus (delta table: sandbox extra)"
const KNOWN_GAPS: Dictionary = {
	"|net.cursors": GAP_OFFLINE,
	"|wiring.events.": GAP_SEATS,
	"|wiring.main_children": GAP_SEATS,
	"|wiring.node.BotController": GAP_SEATS,
	"|ui.bot_controllers": GAP_SEATS,
	"|ui.hud_texts": GAP_SEATS,
	"sandbox|camera.suppress_pad_home_focus": GAP_PAD_FOCUS,
	"sandbox|net.": GAP_OFFLINE,
	"sandbox|rules.feed_timer_enabled": GAP_SANDBOX,
	"sandbox|rules.slot_timers": GAP_SANDBOX,
	"sandbox|rules.stats": GAP_SANDBOX,
	"sandbox|ui.loading_visible": GAP_SANDBOX,
	"sandbox|ui.main_sandbox": GAP_SANDBOX,
	"sandbox|wiring.node.LoadingScreen": GAP_SANDBOX,
	"sandbox|wiring.node.Sandbox": GAP_SANDBOX,
	"tutorial|field.": GAP_TUTORIAL,
	"tutorial|net.": GAP_OFFLINE,
	"tutorial|rules.": GAP_TUTORIAL,
	"tutorial|ui.main_tutorial": GAP_TUTORIAL,
	"tutorial|ui.pause_suppressed": GAP_TUTORIAL,
	"tutorial|wiring.node.Field": GAP_TUTORIAL,
	"tutorial|wiring.node.LoadingScreen": GAP_TUTORIAL,
	"tutorial|wiring.node.LocalPlayer": GAP_TUTORIAL,
	"tutorial|wiring.node.Tutorial": GAP_TUTORIAL,
	"gift demo|camera.suppress_pad_home_focus": GAP_PAD_FOCUS,
	"gift demo|field.": GAP_PRESET,
	"gift demo|globals.": GAP_PRESET,
	"gift demo|net.": GAP_OFFLINE,
	"gift demo|rules.": GAP_PRESET,
	"gift demo|ui.loading_visible": GAP_SANDBOX,
	"gift demo|ui.main_sandbox": GAP_SANDBOX,
	"gift demo|wiring.node.Field": GAP_PRESET,
	"gift demo|wiring.node.LoadingScreen": GAP_SANDBOX,
	"gift demo|wiring.node.LocalPlayer": GAP_PRESET,
	"gift demo|wiring.node.Node3D": GAP_PRESET,
	"gift demo|wiring.node.Sandbox": GAP_SANDBOX,
	"watch bots|camera.": GAP_SPECTATOR,
	"watch bots|ui.main_local_player": GAP_SPECTATOR,
	"watch bots|wiring.node.LocalPlayer": GAP_SPECTATOR,
	"watch bots|wiring.node.SpectatorController": GAP_SPECTATOR,
	"headless bots|camera.": GAP_HEADLESS,
	"headless bots|ui.main_local_player": GAP_HEADLESS,
	"headless bots|wiring.node.LocalPlayer": GAP_HEADLESS,
	"headless bots|wiring.node.Timer": GAP_HEADLESS,
}

var _mains: Array[Node] = []
var _map: MapDef


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	SnapshotSync.end_match()
	# A vibration leaked by an earlier script in the shard must not reach the capture.
	Rumble.stop_all()
	Input.stop_joy_vibration(MatchFingerprint.RUMBLE_PROBE_DEVICE)
	Match._lifecycle._host_bot_names = PackedStringArray()
	assert_true(Net.is_offline(), "fixture: the real Net must start offline")
	Engine.time_scale = 1.0
	_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_map.field_radius = TINY_FIELD_RADIUS


func after_each() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	DebugMode.clear_override_for_test()
	Net.leave()
	Match.abort_match()
	SnapshotSync.end_match()
	for main: Node in _mains:
		if is_instance_valid(main):
			main.queue_free()
	_mains.clear()
	Match.set_process(true)
	Sfx.reset_match_audio()
	await get_tree().process_frame
	await get_tree().process_frame


# --- helpers --------------------------------------------------------------------------

func _new_main() -> Node:
	var main: Node = MAIN_SCENE.instantiate()
	(main.get_node("Field") as Field).map_def = _map
	add_child(main)
	_mains.append(main)
	assert_not_null(main.get("_main_menu"), "fixture: Main boots to the main menu")
	return main


## Menu entries build their config from Main.match_config: pin the seed, the tiny map and the
## reference's Day sky and dry weather, so only mode differences show.
func _seed_main_config(main: Node) -> void:
	var config: MatchConfig = (main.get("match_config") as MatchConfig).duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_map)
	config.rng_seed = SEED
	config.weather_mode = MatchConfig.WeatherMode.OFF
	config.sky_theme_mode = MatchConfig.SkyThemeMode.DAY
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


func _reference_config() -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_map)
	config.player_count = 2
	config.ai_count = 1
	config.rng_seed = SEED
	config.weather_mode = MatchConfig.WeatherMode.OFF
	config.sky_theme_mode = MatchConfig.SkyThemeMode.DAY
	return config


func _run_seconds(seconds: float) -> void:
	var step: float = 1.0 / Engine.physics_ticks_per_second
	for _i: int in range(int(ceil(seconds * Engine.physics_ticks_per_second))):
		Match._process(step)
		Match.weather().tick(step)


## The reference lobby match: menu, COUNTDOWN + 0.5 s, PLAYING + 1 s.
func _reference_lobby_match() -> Dictionary:
	var main: Node = _new_main()
	var out: Dictionary = {"menu": MatchFingerprint.capture(main)}
	_host()
	assert_true(Net.is_host(), "fixture: hosting")
	Match.start_match(_reference_config())
	await _settle()
	_run_seconds(CHECK_COUNTDOWN_S)
	assert_eq(Match.state(), Match.State.COUNTDOWN, "fixture: still counting down")
	out["countdown"] = MatchFingerprint.capture(main)
	_run_seconds(Match.COUNTDOWN_SECONDS + CHECK_PLAYING_S)
	await _settle()
	assert_eq(Match.state(), Match.State.PLAYING, "fixture: playing")
	out["playing"] = MatchFingerprint.capture(main)
	Net.leave()
	await _free_main(main)
	Match.abort_match()
	return out


## A mode world, captured after the same play time as the reference's capture: the ticks run
## until the mode is PLAYING (a mode that skips the countdown is there at once), then the
## reference's countdown-plus-playing seconds, so round clocks and slot timers line up.
func _capture_mode_playing(main: Node) -> Dictionary:
	await _settle()
	var step: float = 1.0 / Engine.physics_ticks_per_second
	var guard: int = int(ceil((Match.COUNTDOWN_SECONDS + CHECK_PLAYING_S) * Engine.physics_ticks_per_second))
	while Match.state() != Match.State.PLAYING and guard > 0:
		_run_seconds(step)
		guard -= 1
	assert_eq(Match.state(), Match.State.PLAYING, "fixture: the mode reaches PLAYING")
	# The reference spends one tick of its capture entering PLAYING, so the mode runs one fewer.
	_run_seconds((CHECK_COUNTDOWN_S + CHECK_PLAYING_S) - step / 2.0 - step)
	await _settle()
	return MatchFingerprint.capture(main)


func _assert_same(reference: Dictionary, other: Dictionary, label: String) -> void:
	var found: PackedStringArray = MatchFingerprint.diff(reference, other)
	var real: PackedStringArray = PackedStringArray()
	for line: String in found:
		var intentional: bool = false
		for entry: Variant in KNOWN_GAPS.keys():
			var parts: PackedStringArray = String(entry).split("|")
			if (parts[0] == "" or label.contains(parts[0])) and line.begins_with(parts[1]):
				intentional = true
				break
		if not intentional:
			real.append(line)
	assert_eq(real.size(), 0, "%s: differs from the reference in %d key(s) the delta table does not allow:
  %s" % [label, real.size(), "
  ".join(real)])


func _assert_mode_matches_reference(label: String, mode_playing: Dictionary) -> void:
	var reference: Dictionary = await _reference_lobby_match()
	_assert_same(reference["playing"] as Dictionary, mode_playing, label)


# --- floor ----------------------------------------------------------------------------

func test_floor_two_fresh_reference_matches_are_equal() -> void:
	var first: Dictionary = await _reference_lobby_match()
	var second: Dictionary = await _reference_lobby_match()
	for checkpoint: String in CHECKPOINTS:
		assert_true(first.has(checkpoint) and second.has(checkpoint), "fixture: %s captured twice" % checkpoint)
		var found: PackedStringArray = MatchFingerprint.diff(first[checkpoint] as Dictionary, second[checkpoint] as Dictionary)
		assert_eq(found.size(), 0, "the recipe is nondeterministic @ %s:\n  %s" % [checkpoint, "\n  ".join(found)])


# --- baseline: each mode against the reference --------------------------------------

func test_sandbox_world_against_the_reference() -> void:
	var main: Node = _new_main()
	_seed_main_config(main)
	await main.start_sandbox_from_menu()
	var mode: Dictionary = await _capture_mode_playing(main)
	await _free_main(main)
	Match.abort_match()
	await _assert_mode_matches_reference("sandbox", mode)


func test_tutorial_world_against_the_reference() -> void:
	var main: Node = _new_main()
	_seed_main_config(main)
	await main.start_tutorial_from_menu()
	var mode: Dictionary = await _capture_mode_playing(main)
	await _free_main(main)
	Match.abort_match()
	await _assert_mode_matches_reference("tutorial", mode)


func test_gift_demo_world_against_the_reference() -> void:
	var main: Node = _new_main()
	_seed_main_config(main)
	await main.start_gift_demo_from_menu()
	var mode: Dictionary = await _capture_mode_playing(main)
	await _free_main(main)
	Match.abort_match()
	await _assert_mode_matches_reference("gift demo", mode)


func test_watch_bots_world_against_the_reference() -> void:
	DebugMode.set_override_for_test(true)
	var main: Node = _new_main()
	_seed_main_config(main)
	var options: WatchBotsOptions = WatchBotsOptions.defaults()
	options.bots = WATCH_BOTS
	options.weather = false
	await main.start_watch_bots(options)
	var mode: Dictionary = await _capture_mode_playing(main)
	Net.leave()
	await _free_main(main)
	Match.abort_match()
	await _assert_mode_matches_reference("watch bots", mode)


func test_headless_bots_world_against_the_reference() -> void:
	var main: Node = _new_main()
	_seed_main_config(main)
	_host()
	main._start_headless_bot_match_with_args(PackedStringArray(["--bots=%d" % WATCH_BOTS]))
	var mode: Dictionary = await _capture_mode_playing(main)
	Net.leave()
	await _free_main(main)
	Match.abort_match()
	await _assert_mode_matches_reference("headless bots", mode)
