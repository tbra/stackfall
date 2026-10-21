extends GutTest
## Modes program parity recipe. Every mode builds its world
## through one pipeline; this compares each mode's world against the reference lobby match with
## MatchFingerprint. The floor test proves the recipe itself is deterministic (two fresh launches
## of the reference are equal); the baseline tests list today's differences per mode in KNOWN_GAPS
## and fail on any other line. Each batch that closes a gap deletes its entries.

const MAIN_SCENE: PackedScene = preload("res://game/main/Main.tscn")
const SEED: int = 777
const TINY_FIELD_RADIUS: float = 20.0
const CHECK_COUNTDOWN_S: float = 0.5
const CHECK_PLAYING_S: float = 1.0
const WATCH_BOTS: int = 2
const CHECKPOINTS: PackedStringArray = ["menu", "countdown", "playing"]

## "<label substring>|<key prefix>" -> delta-table reason or the package that closes it.
## Same pending mechanism as test_match_reset_fingerprint.gd.
const GAP_CLOCK: String = "capture clock offset: modes skip or shorten the lobby countdown, so timers differ at the same capture; not a rule difference (V1 aligns the clocks)"
const GAP_OFFLINE: String = "mode worlds run offline without a host session (no cursors, no SnapshotSync); closes at F2a/F2b (single pipeline, SnapshotSync.begin_match)"
const GAP_STABLE: String = "StableBlockManager is built only by the lobby match path; closes at F2 (resting blocks freeze everywhere)"
const GAP_LOCAL: String = "local-player and bot extras differ per mode (delta table section 3); HotSeat becomes LocalPlayer at R1"
const GAP_WIRING: String = "event listener counts follow the per-mode wiring (closes with the single pipeline at F2a/F2b)"
const GAP_SANDBOX: String = "sandbox extras: Sandbox node, relaxed rules, no loading screen or countdown (delta table; owner decision di0.15.2=b)"
const GAP_TUTORIAL: String = "tutorial extras: Tutorial node, single seat and flag, debug overlay, suppressed pause menu (delta table)"
const GAP_PRESET: String = "preset world: gift demo seeds blocks and four seats (delta table: sandbox_preset extra)"
const GAP_SPECTATOR: String = "no local seat: the spectator camera and SpectatorController replace the player's (delta table, watch bots)"
const GAP_HEADLESS: String = "headless bots: no local seat or camera follow, Timer for --seconds (delta table)"
const GAP_PAD_FOCUS: String = "sandbox suppresses the gamepad home focus (delta table: sandbox extra)"
const KNOWN_GAPS: Dictionary = {
	"|net.cursors": GAP_OFFLINE,
	"|rules.slot_timers": GAP_CLOCK,
	"|rules.stats": GAP_CLOCK,
	"|ui.bot_controllers": GAP_LOCAL,
	"|ui.hud_texts": GAP_LOCAL,
	"|ui.main_hot_seat": GAP_LOCAL,
	"|wiring.main_children": GAP_LOCAL,
	"|wiring.events.": GAP_WIRING,
	"|wiring.node.BotController": GAP_LOCAL,
	"|wiring.node.HotSeat": GAP_LOCAL,
	"sandbox|camera.suppress_pad_home_focus": GAP_PAD_FOCUS,
	"sandbox|globals.stable_manager": GAP_STABLE,
	"sandbox|net.": GAP_OFFLINE,
	"sandbox|rules.feed_timer_enabled": GAP_SANDBOX,
	"sandbox|ui.loading_visible": GAP_SANDBOX,
	"sandbox|ui.main_remote_cursors": GAP_OFFLINE,
	"sandbox|ui.main_sandbox": GAP_SANDBOX,
	"sandbox|ui.main_stable_block_manager": GAP_STABLE,
	"sandbox|wiring.node.LoadingScreen": GAP_SANDBOX,
	"sandbox|wiring.node.RemoteCursors": GAP_OFFLINE,
	"sandbox|wiring.node.Sandbox": GAP_SANDBOX,
	"sandbox|wiring.node.StableBlockManager": GAP_STABLE,
	"tutorial|field.": GAP_TUTORIAL,
	"tutorial|globals.stable_manager": GAP_STABLE,
	"tutorial|net.": GAP_OFFLINE,
	"tutorial|rules.": GAP_TUTORIAL,
	"tutorial|ui.main_debug_overlay": GAP_TUTORIAL,
	"tutorial|ui.main_remote_cursors": GAP_OFFLINE,
	"tutorial|ui.main_stable_block_manager": GAP_STABLE,
	"tutorial|ui.main_tutorial": GAP_TUTORIAL,
	"tutorial|ui.pause_suppressed": GAP_TUTORIAL,
	"tutorial|wiring.node.Field": GAP_TUTORIAL,
	"tutorial|wiring.node.LoadingScreen": GAP_SANDBOX,
	"tutorial|wiring.node.NetDebugOverlay": GAP_TUTORIAL,
	"tutorial|wiring.node.RemoteCursors": GAP_OFFLINE,
	"tutorial|wiring.node.StableBlockManager": GAP_STABLE,
	"tutorial|wiring.node.Tutorial": GAP_TUTORIAL,
	"gift demo|camera.suppress_pad_home_focus": GAP_PAD_FOCUS,
	"gift demo|field.": GAP_PRESET,
	"gift demo|globals.": GAP_PRESET,
	"gift demo|net.": GAP_OFFLINE,
	"gift demo|rules.": GAP_PRESET,
	"gift demo|ui.loading_visible": GAP_SANDBOX,
	"gift demo|ui.main_remote_cursors": GAP_OFFLINE,
	"gift demo|ui.main_sandbox": GAP_SANDBOX,
	"gift demo|ui.main_stable_block_manager": GAP_STABLE,
	"gift demo|wiring.node.Field": GAP_PRESET,
	"gift demo|wiring.node.LoadingScreen": GAP_SANDBOX,
	"gift demo|wiring.node.Node3D": GAP_PRESET,
	"gift demo|wiring.node.RemoteCursors": GAP_OFFLINE,
	"gift demo|wiring.node.Sandbox": GAP_SANDBOX,
	"gift demo|wiring.node.StableBlockManager": GAP_STABLE,
	"watch bots|camera.": GAP_SPECTATOR,
	"watch bots|wiring.node.SpectatorController": GAP_SPECTATOR,
	"headless bots|camera.": GAP_HEADLESS,
	"headless bots|wiring.node.Timer": GAP_HEADLESS,
}

var _mains: Array[Node] = []
var _map: MapDef


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	SnapshotSync.end_match()
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
	Sfx._tense_stem_is_active = false
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
	main._on_lobby_start_requested(_reference_config())
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


## A mode world, captured where the mode is playing (modes that skip the countdown are already
## there; the others run it out first) and one second later.
func _capture_mode_playing(main: Node) -> Dictionary:
	await _settle()
	if Match.state() == Match.State.COUNTDOWN:
		_run_seconds(Match.COUNTDOWN_SECONDS)
	_run_seconds(CHECK_PLAYING_S)
	await _settle()
	return MatchFingerprint.capture(main)


func _assert_same(reference: Dictionary, other: Dictionary, label: String) -> void:
	var found: PackedStringArray = MatchFingerprint.diff(reference, other)
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
	assert_eq(real.size(), 0, "%s: differs from the reference in %d key(s):\n  %s" % [label, real.size(), "\n  ".join(real)])
	if not known.is_empty():
		pending("%s: known gap(s): %s" % [label, "; ".join(known)])


## The first match of a process initialises weather statics (the cloud ceiling's pushed
## overcast/storm start at a -1 "never pushed" sentinel, the fog shader at its scene default), so a
## capture taken before any match differs from every later one. Recorded captures follow one
## unrecorded reference match.
func _warm_up() -> void:
	await _reference_lobby_match()


func _assert_mode_matches_reference(label: String, mode_playing: Dictionary) -> void:
	await _warm_up()
	var reference: Dictionary = await _reference_lobby_match()
	_assert_same(reference["playing"] as Dictionary, mode_playing, label)


# --- floor ----------------------------------------------------------------------------

func test_floor_two_fresh_reference_matches_are_equal() -> void:
	await _warm_up()
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
