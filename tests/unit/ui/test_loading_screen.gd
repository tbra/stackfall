extends GutTest
## ("add a proper loading screen
## instead" of the idle centre-beacon camera shot between Start Match and the
## countdown). Drives ui/menus/LoadingScreen.gd's public API directly with a plain
## MatchConfig/PlayerSlot array -- the same dependency-injection shape
## tests/unit/ui/test_hud.gd's FakeMatch uses, so this needs no real Match/
## MatchLifecycle state at all.

var _screen: LoadingScreen = null
var _loopback: LoopbackSession


func before_each() -> void:
	_loopback = LoopbackSession.new(self)
	_screen = autofree(load("res://ui/menus/LoadingScreen.tscn").instantiate())
	add_child_autofree(_screen)
	# Keep the fade fast enough for a test to actually wait it out.
	_screen.tuning = LoadingScreenTuning.new()
	_screen.tuning.warmup_frames = 2
	_screen.tuning.fade_out_duration_s = 0.05
	# The runner fast-forwards frames, so the game-time stall timeout would fire before a real-time image load.
	_screen.tuning.ready_timeout_s = STALL_TIMEOUT_S


func after_each() -> void:
	await _loopback.end()


func _config(disc_step: int = MatchConfig.DISC_SIZE_STEP_DEFAULT) -> MatchConfig:
	var config: MatchConfig = MatchConfig.new()
	config.disc_size_step = disc_step
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

func _row_names() -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	for row: Dictionary in _screen._ready_rows:
		names.append((row["name"] as Label).text)
	return names


func test_show_for_match_lists_players() -> void:
	_screen.show_for_match(_config(), _slots(2))
	var names: PackedStringArray = _row_names()
	assert_eq(names.size(), 2)
	assert_true(names[0].findn("Player 1") >= 0)
	assert_true(names[1].findn("Player 2") >= 0)
	assert_true(_screen._player_list.visible, "the list shows even when no gate is armed")


func test_show_for_match_marks_bots() -> void:
	_screen.show_for_match(_config(), _slots(2, 1))
	var names: PackedStringArray = _row_names()
	assert_true(names[1].findn("Player 2 (bot)") >= 0, "expected the trailing bot slot marked: %s" % names[1])
	assert_false(names[0].findn("(bot)") >= 0, "the human slot must not be marked a bot.")


func test_fade_out_eventually_hides_the_screen() -> void:
	_screen.show_for_match(_config(), _slots(2))

	_screen.fade_out()
	assert_true(_screen.visible, "must still be visible immediately -- see fade_out()'s own DECISION doc.")

	await wait_seconds(0.3, "warmup frames + fade duration")
	assert_false(_screen.visible, "fade_out() must have hidden the screen by now.")


## The CanvasLayer neither follows the Control's visibility nor its modulate, so the
## player-visible overlay is the layer's own visibility and the Content fade alpha.
func test_overlay_is_opaque_while_up_and_gone_after_the_fade() -> void:
	_screen.show_for_match(_config(), _slots(2))
	assert_true(_screen._layer.visible, "the overlay layer is up for a gated match")
	assert_eq(_screen._content.modulate.a, 1.0, "fully opaque until the fade starts")

	_screen.fade_out()
	await wait_seconds(0.3, "warmup frames + fade duration")
	assert_false(_screen._layer.visible, "the layer hides with the screen")
	assert_eq(_screen._content.modulate.a, 0.0, "the fade ended fully transparent")


func test_a_scope_reset_clears_the_rows_of_a_hidden_overlay() -> void:
	_screen.show_for_match(_config(), _slots(3))
	assert_eq(_screen._player_list.get_child_count(), 3, "fixture: one row per slot.")
	_screen.visible = false
	Events.match_scope_reset.emit()
	assert_eq(_screen._player_list.get_child_count(), 0, "a finished match leaves no rows behind.")
	assert_eq(_screen._ready_rows.size(), 0, "nor ready-mark bookkeeping.")


func test_cancel_stops_a_pending_fade_from_later_hiding_a_new_match() -> void:
	_screen.show_for_match(_config(), _slots(2))
	_screen.fade_out()

	_screen.cancel()
	_screen.show_for_match(_config(), _slots(3))

	await wait_seconds(0.3, "the stale fade_out() coroutine should have resumed and bailed out by now.")
	assert_true(_screen.visible, "the stale fade_out() must not have hidden the new match's loading screen.")


# --- overlay ahead of the match start --------------------------

func test_show_pending_is_visible_and_pending() -> void:
	_screen.show_pending(null)
	assert_true(_screen.visible)
	assert_true(_screen.is_pending())


func test_pending_times_out_when_no_start_follows() -> void:
	_screen.tuning.pending_timeout_s = 0.05
	_screen.show_pending(null)
	await wait_seconds(0.3)
	assert_false(_screen.visible)
	assert_false(_screen.is_pending())


func test_ready_timeout_hides_a_stalled_match() -> void:
	_screen.tuning.ready_timeout_s = 0.05
	var timeout_count: Array[int] = []
	_screen.readiness_timed_out.connect(func() -> void: timeout_count.append(1))
	_screen.show_for_match(_config(), _slots(2))
	await wait_seconds(0.3)
	assert_true(_screen._timed_out)
	assert_false(_screen.visible)
	assert_eq(timeout_count.size(), 1)


func test_overlay_layer_is_above_the_hud_and_below_the_pause_menu() -> void:
	var hud: HUD = autofree(load("res://ui/hud/HUD.tscn").instantiate()) as HUD
	add_child_autofree(hud)
	assert_eq(_screen._layer.layer, _screen.tuning.overlay_canvas_layer)
	assert_gt(_screen._layer.layer, hud.layer, "a Control z_index can never beat a CanvasLayer: the overlay needs its own")
	assert_lt(_screen._layer.layer, PauseMenu.OVERLAY_LAYER)


# Game-time budget; wait_until returns as soon as the image loads. The runners use
# --fixed-fps (frames outrun the worker-thread load), so allow generous frames.
const LOAD_WAIT_S: float = 60.0
const REAL_LOAD_WAIT_MS: int = 60000
const STALL_TIMEOUT_S: float = 3600.0
const COVER_SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(3440, 1440)]
const MENU_TUNING_PATH: String = "res://config/ui/main_menu_tuning.tres"


## Wall-clock-tolerant ceiling for readiness polls (returns as soon as true).
const FLOW_TIMEOUT_S: float = 600.0


func _progress_is(overlay: LoadingScreen, expected: float) -> Callable:
	return func() -> bool: return absf(overlay._progress - expected) < 0.001


## Flow tests against the real Main (same fixture shape as
## test_match_lifecycle.gd): the overlay is up and un-started Match is still in
## LOBBY when the Start press returns; the match only starts later.
func _real_main() -> Node:
	var main: Node = (load("res://game/main/Main.tscn") as PackedScene).instantiate()
	var tiny: MapDef = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	tiny.field_radius = 20.0
	(main.get_node("Field") as Field).map_def = tiny
	add_child_autofree(main)
	# the real-time pending/ready timeouts (10 s / 20 s) are product
	# safety nets; a world build on a gate-loaded machine can outlast them and
	# cancel the overlay mid-test. These flows assert hand-off order, not timeouts.
	var overlay_tuning: LoadingScreenTuning = (main._loading_screen as LoadingScreen).tuning.duplicate() as LoadingScreenTuning # the preload is shared
	overlay_tuning.pending_timeout_s = FLOW_TIMEOUT_S
	overlay_tuning.ready_timeout_s = FLOW_TIMEOUT_S
	(main._loading_screen as LoadingScreen).tuning = overlay_tuning
	return main


func _flow_config(main: Node) -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map((main.get_node("Field") as Field).map_def)
	config.player_count = 2
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
	await wait_process_frames(overlay.tuning.stable_frames + overlay.tuning.warmup_frames + 2)
	assert_true(overlay.visible, "host waits for the first applied territory result")
	Events.territory_updated.emit(Match.raster(), null)
	await wait_until(_progress_is(overlay, 1.0), FLOW_TIMEOUT_S, "readiness completes")
	assert_almost_eq(overlay._progress, 1.0, 0.001)
	Events.match_state_changed.disconnect(on_state)
	Net.leave()
	Match.abort_match()
	Match.set_process(true)


func test_early_client_territory_completes_readiness_after_build() -> void:
	Match.set_process(false)
	Match.abort_match()
	var main: Node = _real_main()
	assert_true(await _loopback.join_net_as_client(), "fixture: the Net autoload is an accepted client")
	var overlay: LoadingScreen = main._loading_screen
	overlay.show_for_match(_flow_config(main), _slots(2))
	Events.territory_replicated.emit(null)
	assert_true(main._first_territory_ready, "late join keyframe is latched before world build")
	main._match_flow_port().call(&"_finish_loading_when_ready", main._loading_generation)
	await wait_process_frames(2)
	assert_lt(overlay._progress, overlay.tuning.complete_progress)
	main._world_built = true
	await wait_until(_progress_is(overlay, overlay.tuning.complete_progress), FLOW_TIMEOUT_S, "readiness completes")
	assert_almost_eq(overlay._progress, overlay.tuning.complete_progress, 0.001)
	assert_false(overlay._timed_out)
	overlay.cancel()
	main._world_built = false
	Net.leave()
	Match.set_process(true)


func test_client_overlay_appears_on_loading_announcement() -> void:
	Match.set_process(false)
	Match.abort_match()
	var main: Node = _real_main()
	var overlay: LoadingScreen = main._loading_screen
	assert_false(overlay.visible)
	Events.match_loading_announced.emit()
	assert_true(overlay.visible)
	assert_true(overlay.is_pending())
	assert_lt(overlay._progress, 0.1)
	Match.set_process(true)


func test_client_waits_for_replicated_territory_before_ready() -> void:
	Match.set_process(false)
	Match.abort_match()
	var main: Node = _real_main()
	assert_true(await _loopback.join_net_as_client(), "fixture: the Net autoload is an accepted client")
	var overlay: LoadingScreen = main._loading_screen
	Events.match_loading_announced.emit()
	overlay.show_for_match(_flow_config(main), _slots(2))
	main._world_built = true
	main._match_flow_port().call(&"_finish_loading_when_ready", main._loading_generation)
	await wait_process_frames(overlay.tuning.stable_frames + 2)
	assert_true(overlay.visible)
	assert_lt(overlay._progress, 1.0)
	Events.territory_replicated.emit(null)
	await wait_until(_progress_is(overlay, 1.0), FLOW_TIMEOUT_S, "readiness completes")
	assert_almost_eq(overlay._progress, 1.0, 0.001)
	overlay.cancel()
	await wait_process_frames(overlay.tuning.warmup_frames + 2)
	main._world_built = false
	Net.leave()
	Match.set_process(true)


# --- loading tips ------------------------------------------------------------

func test_tip_table_is_valid() -> void:
	var table: LoadingTipTable = load("res://config/ui/loading_tip_table.tres")
	assert_gt(table.tips.size(), 14)
	assert_lt(table.tips.size(), 26)
	for tip: String in table.tips:
		assert_lte(tip.length(), table.max_tip_length, tip)
		assert_false(tip.contains("\u2014"), tip)
		assert_false(tip.strip_edges().is_empty())


func test_tip_picker_never_repeats() -> void:
	var table: LoadingTipTable = load("res://config/ui/loading_tip_table.tres")
	var previous: int = -1
	for roll: int in range(500):
		var index: int = table.pick_index(previous, roll * 7919)
		assert_between(index, 0, table.tips.size() - 1)
		assert_ne(index, previous)
		previous = index
	assert_eq(table.pick_index(-1, 3), 3 % table.tips.size())


func test_tip_picker_edge_sizes() -> void:
	var table: LoadingTipTable = LoadingTipTable.new()
	assert_eq(table.pick_index(-1, 5), -1)
	table.tips = PackedStringArray(["only"])
	assert_eq(table.pick_index(0, 5), 0)


func test_show_for_match_shows_a_new_tip_each_load() -> void:
	_screen.show_for_match(_config(), _slots(2))
	var tip_label: Label = _screen.get_node("%TipLabel")
	assert_true(tip_label.visible)
	var first: String = tip_label.text
	assert_ne(first, "")
	_screen.cancel()
	_screen.show_for_match(_config(), _slots(2))
	assert_ne(tip_label.text, first)


func test_pending_then_load_keeps_the_same_tip() -> void:
	_screen.show_pending(_config())
	var tip_label: Label = _screen.get_node("%TipLabel")
	var first: String = tip_label.text
	_screen.show_for_match(_config(), _slots(2))
	assert_eq(tip_label.text, first)
