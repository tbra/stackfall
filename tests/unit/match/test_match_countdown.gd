extends "res://tests/unit/match/match_world_test.gd"
## Bontago-mp0.27: the pre-match 3-2-1. Host side: COUNTDOWN refuses
## placement and does not run the block timer; seconds come from MatchConfig
## (sandbox / 0 skip it). Client side: the HUD label renders the host's
## remaining time, "Go!" after, and the camera entry point finds the beacon.

const HUD_SCENE: PackedScene = preload("res://ui/hud/HUD.tscn")

class CountdownProvider:
	extends RefCounted
	var remaining: float = 0.0
	var match_state: int = MatchAutoload.State.COUNTDOWN

	func countdown_remaining() -> float:
		return remaining

	func state() -> int:
		return match_state


func _config(seconds: float = MatchConfig.COUNTDOWN_SECONDS_DEFAULT) -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.hot_seat = false
	config.block_timer = 6.0
	config.rng_seed = 31337
	config.countdown_seconds = seconds
	return config


func _step(seconds: float) -> void:
	var ticks: int = int(round(seconds * Engine.physics_ticks_per_second))
	for _i: int in range(ticks):
		Match._process(1.0 / Engine.physics_ticks_per_second)


func test_countdown_rejects_placement_and_holds_the_block_timer() -> void:
	Match.start_match(_config())
	assert_eq(Match.state(), Match.State.COUNTDOWN)
	assert_almost_eq(Match.countdown_remaining(), 3.0, 0.001)
	var seq_before: int = Match.feed_seq(0)
	var reason: StringName = Match.request_place(0, _home_world_position(0), 0, Quaternion.IDENTITY, false)
	assert_eq(reason, PlacementRules.REASON_NO_BLOCK, "intents during the countdown are refused")
	assert_eq(_blocks_root.get_child_count(), 0)
	var left_before: float = Match.feed_time_left(0)
	_step(2.0)
	assert_eq(Match.state(), Match.State.COUNTDOWN)
	assert_almost_eq(Match.feed_time_left(0), left_before, 0.001, "block timer does not run in COUNTDOWN")
	assert_eq(Match.feed_seq(0), seq_before)
	_step(1.1)
	assert_eq(Match.state(), Match.State.PLAYING)
	var after: StringName = Match.request_place(0, _home_world_position(0), 0, Quaternion.IDENTITY, false)
	assert_eq(after, PlacementRules.REASON_OK)


func test_zero_seconds_and_sandbox_skip_the_countdown() -> void:
	var cfg: MatchConfig = _config(0.0)
	assert_eq(cfg.effective_countdown_seconds(), 0.0)
	var sandbox_cfg: MatchConfig = _config()
	sandbox_cfg.sandbox = true
	assert_eq(sandbox_cfg.effective_countdown_seconds(), 0.0, "sandbox skips the countdown")
	assert_eq(_config().effective_countdown_seconds(), Match.COUNTDOWN_SECONDS)
	Match.start_match(cfg)
	assert_eq(Match.countdown_remaining(), 0.0)
	_step(0.05)
	assert_eq(Match.state(), Match.State.PLAYING, "a zero countdown reaches PLAYING on the first tick")


func test_hud_label_shows_host_remaining_then_go_then_nothing() -> void:
	var hud: HUD = autofree(HUD_SCENE.instantiate())
	var provider: CountdownProvider = CountdownProvider.new()
	hud.match_provider = provider
	add_child_autofree(hud)
	hud.match_provider = provider
	var label: Label = hud.find_child("CountdownLabel", true, false) as Label
	assert_false(label.visible)
	provider.remaining = 2.4
	hud._process(0.016)
	assert_true(label.visible)
	assert_eq(label.text, "3")
	provider.remaining = 1.0
	hud._process(0.016)
	assert_eq(label.text, "1")
	provider.remaining = 0.0
	provider.match_state = MatchAutoload.State.PLAYING
	hud._process(0.016)
	assert_eq(label.text, hud.hud_visual_tuning.countdown_go_text)
	assert_true(label.visible)
	hud._process(hud.hud_visual_tuning.countdown_go_hold_s + 0.1)
	assert_false(label.visible, "after the countdown nothing remains")

