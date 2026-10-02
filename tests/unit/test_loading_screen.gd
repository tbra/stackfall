extends GutTest
## Bontago-1pi.8 (owner playtest 2026-09-27: "add a proper loading screen
## instead" of the idle centre-beacon camera shot between Start Match and the
## countdown). Drives ui/LoadingScreen.gd's public API directly with a plain
## MatchConfig/PlayerSlot array -- the same dependency-injection shape
## tests/unit/test_hud.gd's FakeMatch uses, so this needs no real Match/
## MatchLifecycle state at all.

var _screen: LoadingScreen = null


func before_each() -> void:
	_screen = autofree(load("res://ui/LoadingScreen.tscn").instantiate())
	add_child_autofree(_screen)
	# Keep the fade fast enough for a test to actually wait it out.
	_screen.tuning = LoadingScreenTuning.new()
	_screen.tuning.warmup_frames = 2
	_screen.tuning.fade_out_duration_s = 0.05
	_screen.tuning.spinner_interval_s = 0.05


func _config(variant: int = MatchConfig.MapVariant.ROUND, size: int = MapDef.MapSize.MEDIUM) -> MatchConfig:
	var config: MatchConfig = MatchConfig.new()
	config.map_variant = variant
	config.map_size = size
	return config


func _slots(count: int, bot_from: int = -1) -> Array[PlayerSlot]:
	var slots: Array[PlayerSlot] = []
	for i: int in range(count):
		var slot_item: PlayerSlot = PlayerSlot.new(i, i, "Player %d" % (i + 1), Color.WHITE)
		if bot_from >= 0 and i >= bot_from:
			slot_item.is_bot = true
		slots.append(slot_item)
	return slots


# --- show_for_match(): visibility + labels -----------------------------------

func test_show_for_match_becomes_visible() -> void:
	assert_false(_screen.visible, "fixture: hidden until shown.")
	_screen.show_for_match(_config(), _slots(2))
	assert_true(_screen.visible)
	assert_almost_eq(_screen.modulate.a, 1.0, 0.001)


func test_show_for_match_sets_the_map_label() -> void:
	_screen.show_for_match(_config(MatchConfig.MapVariant.RING, MapDef.MapSize.LARGE), _slots(2))
	assert_true(_screen._map_label.text.findn("Ring") >= 0, "expected the map shape in the label: %s" % _screen._map_label.text)
	assert_true(_screen._map_label.text.findn("Large") >= 0, "expected the map size in the label: %s" % _screen._map_label.text)


func test_show_for_match_lists_players() -> void:
	_screen.show_for_match(_config(), _slots(2))
	assert_true(_screen._info_label.text.findn("Player 1") >= 0)
	assert_true(_screen._info_label.text.findn("Player 2") >= 0)


func test_show_for_match_marks_bots() -> void:
	_screen.show_for_match(_config(), _slots(2, 1))
	assert_true(_screen._info_label.text.findn("Player 2 (bot)") >= 0, "expected the trailing bot slot marked: %s" % _screen._info_label.text)
	assert_false(_screen._info_label.text.findn("Player 1 (bot)") >= 0, "the human slot must not be marked a bot.")


func test_show_for_match_with_no_slots_shows_a_placeholder() -> void:
	_screen.show_for_match(_config(), [])
	assert_eq(_screen._info_label.text, "Get ready...")


# --- fade_out(): held frames, then a fade, then hidden -----------------------

func test_fade_out_eventually_hides_the_screen() -> void:
	_screen.show_for_match(_config(), _slots(2))

	_screen.fade_out()
	assert_true(_screen.visible, "must still be visible immediately -- see fade_out()'s own DECISION doc.")

	await wait_seconds(0.3, "warmup frames + fade duration")
	assert_false(_screen.visible, "fade_out() must have hidden the screen by now.")


func test_fade_out_is_a_noop_when_already_hidden() -> void:
	assert_false(_screen.visible, "fixture: never shown.")
	_screen.fade_out()
	await wait_seconds(0.3, "even if this somehow started a coroutine, nothing should show.")
	assert_false(_screen.visible)


# --- cancel(): the abort-mid-load safety net ---------------------------------

func test_cancel_hides_immediately() -> void:
	_screen.show_for_match(_config(), _slots(2))
	assert_true(_screen.visible, "fixture: shown.")

	_screen.cancel()

	assert_false(_screen.visible)
	assert_almost_eq(_screen.modulate.a, 1.0, 0.001, "cancel() resets opacity too, so a later show_for_match() is never left half-transparent.")


func test_cancel_stops_a_pending_fade_from_later_hiding_a_new_match() -> void:
	_screen.show_for_match(_config(), _slots(2))
	_screen.fade_out()

	_screen.cancel()
	_screen.show_for_match(_config(), _slots(3))

	await wait_seconds(0.3, "the stale fade_out() coroutine should have resumed and bailed out by now.")
	assert_true(_screen.visible, "the stale fade_out() must not have hidden the new match's loading screen.")


# --- Bontago-t8x.4: overlay ahead of the match start --------------------------

func test_show_pending_is_visible_and_pending() -> void:
	_screen.show_pending(null)
	assert_true(_screen.visible)
	assert_true(_screen.is_pending())


func test_show_for_match_clears_pending() -> void:
	_screen.show_pending(null)
	_screen.show_for_match(_config(), _slots(2))
	assert_false(_screen.is_pending())


func test_pending_times_out_when_no_start_follows() -> void:
	_screen.tuning.pending_timeout_s = 0.05
	_screen.show_pending(null)
	await wait_seconds(0.3)
	assert_false(_screen.visible)
	assert_false(_screen.is_pending())


func test_progress_stages_are_clamped_and_visible() -> void:
	_screen.show_pending(null)
	assert_gt(_screen.progress(), 0.0)
	_screen.set_stage("Solving territory", 0.7)
	assert_eq(_screen._stage_label.text, "Solving territory")
	assert_almost_eq(_screen.progress(), 0.7, 0.001)
	_screen.set_stage("Ready", 2.0)
	assert_almost_eq(_screen.progress(), 1.0, 0.001)


func test_ready_timeout_hides_a_stalled_match() -> void:
	_screen.tuning.ready_timeout_s = 0.05
	var timeout_count: Array[int] = []
	_screen.readiness_timed_out.connect(func() -> void: timeout_count.append(1))
	_screen.show_for_match(_config(), _slots(2))
	await wait_seconds(0.3)
	assert_true(_screen.timed_out())
	assert_false(_screen.visible)
	assert_eq(timeout_count.size(), 1)


func test_overlay_draws_above_siblings_and_ignores_mouse() -> void:
	assert_eq(_screen.z_index, _screen.tuning.overlay_z_index)
	assert_eq(_screen.mouse_filter, Control.MOUSE_FILTER_IGNORE)


## Flow tests against the real Main (same fixture shape as
## test_match_lifecycle.gd): the overlay is up and un-started Match is still in
## LOBBY when the Start press returns; the match only starts later.
func _real_main() -> Node:
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	var tiny: MapDef = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	tiny.field_radius = 20.0
	(main.get_node("Field") as Field).map_def = tiny
	add_child_autofree(main)
	return main


func _flow_config(main: Node) -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map((main.get_node("Field") as Field).map_def)
	config.player_count = 2
	config.hot_seat = false
	config.rng_seed = 777
	return config


func test_host_start_shows_overlay_before_the_match_starts() -> void:
	Match.set_process(false)
	Match.abort_match()
	var main: Node = _real_main()
	assert_eq(Net.host_game(47990, "Hostie"), OK)
	var states: Array[int] = []
	var on_state: Callable = func(_from: int, to: int) -> void: states.append(to)
	Events.match_state_changed.connect(on_state)
	main._on_lobby_start_pressed(_flow_config(main))
	var overlay: LoadingScreen = main._loading_screen
	assert_true(overlay.visible, "overlay up the moment Start returns")
	assert_true(overlay.is_pending())
	assert_eq(Match.state(), Match.State.LOBBY, "world build has not started yet")
	assert_true(states.is_empty())
	await wait_process_frames(overlay.tuning.pre_start_frames + 5)
	assert_true(states.has(Match.State.LOADING), "match handed off after the pre-roll")
	assert_false(overlay.is_pending())
	assert_true(overlay.visible, "overlay stays up through the build until fade_out")
	assert_eq(overlay._stage_label.text, "Solving territory")
	await wait_process_frames(overlay.tuning.stable_frames + overlay.tuning.warmup_frames + 2)
	assert_true(overlay.visible, "host waits for the first applied territory result")
	Events.territory_updated.emit(Match.raster(), Match.groups())
	await wait_process_frames(overlay.tuning.stable_frames + 2)
	assert_almost_eq(overlay.progress(), 1.0, 0.001)
	Events.match_state_changed.disconnect(on_state)
	Net.leave()
	Match.abort_match()
	Match.set_process(true)


func test_early_client_territory_completes_readiness_after_build() -> void:
	Match.set_process(false)
	Match.abort_match()
	var main: Node = _real_main()
	Net._mode = Net.Mode.CLIENT
	Net._joined_accepted = true
	var overlay: LoadingScreen = main._loading_screen
	overlay.show_for_match(_flow_config(main), _slots(2))
	Events.territory_replicated.emit(null)
	assert_true(main._first_territory_ready, "late join keyframe is latched before world build")
	main._finish_loading_when_ready(main._loading_generation)
	await wait_process_frames(2)
	assert_lt(overlay.progress(), overlay.tuning.complete_progress)
	main._world_built = true
	await wait_process_frames(overlay.tuning.stable_frames + 2)
	assert_almost_eq(overlay.progress(), overlay.tuning.complete_progress, 0.001)
	assert_false(overlay.timed_out())
	overlay.cancel()
	main._world_built = false
	Net.leave()
	Match.set_process(true)


func test_material_warmup_uses_private_world_and_is_freed() -> void:
	_screen.show_for_match(_config(), _slots(2))
	_screen.warm_common_materials()
	assert_true(_screen._warm_viewport.own_world_3d)
	assert_ne(_screen._warm_viewport.world_3d, get_viewport().world_3d)
	_screen.cancel()
	assert_null(_screen._warm_viewport)
	await wait_process_frames(2)


func test_client_overlay_appears_on_loading_announcement() -> void:
	Match.set_process(false)
	Match.abort_match()
	var main: Node = _real_main()
	var overlay: LoadingScreen = main._loading_screen
	assert_false(overlay.visible)
	Events.match_loading_announced.emit()
	assert_true(overlay.visible)
	assert_true(overlay.is_pending())
	assert_lt(overlay.progress(), 0.1)
	Match.set_process(true)


func test_client_waits_for_replicated_territory_before_ready() -> void:
	Match.set_process(false)
	Match.abort_match()
	var main: Node = _real_main()
	Net._mode = Net.Mode.CLIENT
	Net._joined_accepted = true
	var overlay: LoadingScreen = main._loading_screen
	Events.match_loading_announced.emit()
	overlay.show_for_match(_flow_config(main), _slots(2))
	main._world_built = true
	main._finish_loading_when_ready(main._loading_generation)
	await wait_process_frames(overlay.tuning.stable_frames + 2)
	assert_true(overlay.visible)
	assert_lt(overlay.progress(), 1.0)
	Events.territory_replicated.emit(null)
	await wait_process_frames(overlay.tuning.stable_frames + 2)
	assert_almost_eq(overlay.progress(), 1.0, 0.001)
	overlay.cancel()
	await wait_process_frames(overlay.tuning.warmup_frames + 2)
	main._world_built = false
	Net.leave()
	Match.set_process(true)
