extends GutTest
## Bontago-mp0.27: the pre-match 3-2-1. Host side: COUNTDOWN refuses
## placement and does not run the block timer; seconds come from MatchConfig
## (sandbox / 0 skip it). Client side: the HUD label renders the host's
## remaining time, "Go!" after, and the camera entry point finds the beacon.

const HUD_SCENE: PackedScene = preload("res://ui/HUD.tscn")

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef


class CountdownProvider:
	extends RefCounted
	var remaining: float = 0.0
	var match_state: int = MatchAutoload.State.COUNTDOWN

	func countdown_remaining() -> float:
		return remaining

	func state() -> int:
		return match_state


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_tiny_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _tiny_map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)


func after_each() -> void:
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _config(seconds: float = MatchConfig.COUNTDOWN_SECONDS_DEFAULT) -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.hot_seat = false
	config.block_timer = 6.0
	config.rng_seed = 31337
	config.countdown_seconds = seconds
	return config


func _home_world_position(slot_id: int) -> Vector3:
	var home: Vector2 = Match.slot(slot_id).home_position
	return _field.to_global(Vector3(home.x, 5.0, home.y))


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


func test_replicated_remaining_time_drives_a_late_joiners_count() -> void:
	Match.start_match(_config())
	Match.apply_replicated_countdown(2)
	assert_almost_eq(Match.countdown_remaining(), 2.0, 0.001)


func test_hud_label_shows_host_remaining_then_go_then_nothing() -> void:
	var hud: HUD = autofree(HUD_SCENE.instantiate())
	var provider: CountdownProvider = CountdownProvider.new()
	hud.match_provider = provider
	add_child_autofree(hud)
	hud.match_provider = provider
	var label: Label = hud.get_node("CountdownLabel") as Label
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


func test_camera_places_at_own_beacon_looking_at_centre() -> void:
	Match.start_match(_config())
	_field.place_flags(2, PackedColorArray([Color.RED, Color.BLUE]), 1)
	var rig: CameraRig = autofree(load("res://game/CameraRig.tscn").instantiate())
	add_child_autofree(rig)
	assert_true(rig.place_at_home_beacon(1))
	var beacon: Vector3 = Vector3.ZERO
	for flag: HomeFlag in _field.home_flags():
		if flag.slot_id() == 1:
			beacon = flag.global_position
	assert_eq(rig.get_target(), beacon)
	var to_centre: Vector3 = (Vector3.ZERO - beacon).normalized()
	var forward: Vector3 = -rig.get_camera().global_transform.basis.z
	forward.y = 0.0
	to_centre.y = 0.0
	assert_gt(forward.normalized().dot(to_centre.normalized()), 0.9, "camera looks toward the centre")
	assert_false(rig.place_at_home_beacon(99), "unknown slot leaves the camera alone")


func test_held_countdown_does_not_run_down_but_still_solves_territory() -> void:
	Match.start_match(_config())
	Match.set_countdown_held(true)
	_step(4.0)
	assert_eq(Match.state(), Match.State.COUNTDOWN, "a held countdown waits for the loading screen")
	assert_almost_eq(Match.countdown_remaining(), 3.0, 0.001)
	Match.set_countdown_held(false)
	_step(3.1)
	assert_eq(Match.state(), Match.State.PLAYING)
	Match.abort_match()
	Match.start_match(_config())
	assert_false(Match._lifecycle.is_countdown_held(), "a new match starts un-held")


func test_gift_slot_is_refused_during_the_countdown() -> void:
	Match.start_match(_config())
	assert_eq(Match.state(), Match.State.COUNTDOWN)
	assert_false(Match.request_use_gift_slot(0), "the host refuses a gift-slot use before PLAYING")


func test_hold_is_released_when_loading_screen_is_hidden_or_never_shown() -> void:
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	add_child_autofree(main)
	Match.start_match(_config())
	Match.set_countdown_held(true)
	main._world_built = true
	main._loading_screen.visible = false
	assert_false(main._loading_screen.visible, "the overlay is not shown")
	main._finish_loading_when_ready(main._loading_generation)
	assert_false(Match._lifecycle.is_countdown_held(), "early return frees the hold")
	_step(3.1)
	assert_eq(Match.state(), Match.State.PLAYING, "the countdown proceeds")
	Match.abort_match()
	Match.start_match(_config())
	Match.set_countdown_held(true)
	main._on_loading_readiness_timed_out()
	assert_false(Match._lifecycle.is_countdown_held(), "the ready timeout frees the hold")
	main._world_built = false
