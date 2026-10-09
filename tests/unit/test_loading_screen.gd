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


## Bontago-1pi.124: the title is the game mode name only (no map shape or size).
func test_show_for_match_title_is_only_the_game_mode_name() -> void:
	var config: MatchConfig = _config(MatchConfig.MapVariant.ROUND, MapDef.MapSize.LARGE)
	_screen.show_for_match(config, _slots(2))
	assert_eq(_screen._map_label.text, DisplayNames.mode(MatchConfig.resolve_game_mode(config.game_mode)))
	assert_eq(_screen._map_label.text.findn("Ring"), -1, "no map shape in the title")
	assert_eq(_screen._map_label.text.findn("Large"), -1, "no map size in the title")


func test_show_for_match_lists_players() -> void:
	_screen.show_for_match(_config(), _slots(2))
	var names: PackedStringArray = _screen.player_row_names()
	assert_eq(names.size(), 2)
	assert_true(names[0].findn("Player 1") >= 0)
	assert_true(names[1].findn("Player 2") >= 0)
	assert_true(_screen._player_list.visible, "the list shows even when no gate is armed")


func test_show_for_match_marks_bots() -> void:
	_screen.show_for_match(_config(), _slots(2, 1))
	var names: PackedStringArray = _screen.player_row_names()
	assert_true(names[1].findn("Player 2 (bot)") >= 0, "expected the trailing bot slot marked: %s" % names[1])
	assert_false(names[0].findn("(bot)") >= 0, "the human slot must not be marked a bot.")


func test_show_for_match_with_no_slots_shows_no_rows() -> void:
	_screen.show_for_match(_config(), [])
	assert_eq(_screen.player_row_names().size(), 0)
	assert_false(_screen._player_list.visible)


## Bontago-1pi.63: no loading text, bar, spinner, status line, button or timer nodes.
func test_screen_has_only_map_players_and_the_ready_prompt() -> void:
	for node_name: String in ["SpinnerLabel", "StageLabel", "ProgressBar", "InfoLabel", "StatusLabel", "ReadyButton", "CapLabel", "PromptSuffix"]:
		assert_null(_screen.find_child(node_name, true, false), "%s was removed" % node_name)
	assert_eq(_screen.ready_prompt_text(), "Ready?")
	assert_false("min_display_s" in _screen.tuning, "no minimum display time")


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


# --- Bontago-1pi.46 (G10): the player rows do not outlive the overlay ---------

func test_a_scope_reset_clears_the_rows_of_a_hidden_overlay() -> void:
	_screen.show_for_match(_config(), _slots(3))
	assert_eq(_screen._player_list.get_child_count(), 3, "fixture: one row per slot.")
	_screen.visible = false
	Events.match_scope_reset.emit()
	assert_eq(_screen._player_list.get_child_count(), 0, "a finished match leaves no rows behind.")
	assert_eq(_screen._ready_rows.size(), 0, "nor ready-mark bookkeeping.")


func test_a_scope_reset_keeps_the_rows_while_the_overlay_is_up_for_the_new_match() -> void:
	# Main shows the overlay (LOADING) and then builds the world, which emits the reset.
	_screen.show_for_match(_config(), _slots(2))
	Events.match_scope_reset.emit()
	assert_eq(_screen._player_list.get_child_count(), 2, "the loading list survives the world build's reset.")


func test_cancel_clears_the_rows_too() -> void:
	_screen.show_for_match(_config(), _slots(2))
	_screen.cancel()
	assert_eq(_screen._player_list.get_child_count(), 0, "a cancelled load leaves no rows behind.")


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


# --- Bontago-1pi.32 L3: the overlay's own CanvasLayer, above the HUD ----------

func test_overlay_layer_is_above_the_hud_and_below_the_pause_menu() -> void:
	var hud: HUD = autofree(load("res://ui/HUD.tscn").instantiate()) as HUD
	add_child_autofree(hud)
	assert_eq(_screen.overlay_canvas_layer(), _screen.tuning.overlay_canvas_layer)
	assert_gt(_screen.overlay_canvas_layer(), hud.layer, "a Control z_index can never beat a CanvasLayer: the overlay needs its own")
	assert_lt(_screen.overlay_canvas_layer(), PauseMenu.OVERLAY_LAYER)


func test_overlay_layer_follows_every_visibility_change() -> void:
	assert_false(_screen.overlay_layer_visible(), "fixture: hidden until shown")
	_screen.show_for_match(_config(), _slots(2))
	assert_true(_screen.overlay_layer_visible())
	_screen.visible = false
	assert_false(_screen.overlay_layer_visible(), "a direct visible = false (Main, tests) hides the layer too")
	_screen.visible = true
	assert_true(_screen.overlay_layer_visible())
	_screen.cancel()
	assert_false(_screen.overlay_layer_visible())


func test_fade_runs_on_the_layer_content_and_the_next_show_is_opaque_again() -> void:
	_screen.show_for_match(_config(), _slots(2))
	assert_almost_eq(_screen.overlay_opacity(), 1.0, 0.001, "opaque while held: nothing behind it shows through")
	_screen.fade_out()
	await wait_seconds(0.3, "warmup frames + fade duration")
	assert_false(_screen.overlay_layer_visible())
	assert_almost_eq(_screen.overlay_opacity(), 0.0, 0.01, "the layer's content faded (the root modulate cannot reach a CanvasLayer)")
	_screen.show_for_match(_config(), _slots(2))
	assert_almost_eq(_screen.overlay_opacity(), 1.0, 0.001)
	_screen.cancel()


# --- Bontago-mp0.96: the prerendered arena backdrop ----------------------------

const PLATE_DIR: String = "res://assets/ui/loading_arena_v2"
const VARIANT_SHAPES: Array[String] = ["round"]
# Game-time budget; wait_until returns as soon as the plate loads. The runners use
# --fixed-fps (frames outrun the worker-thread load), so allow generous frames.
const LOAD_WAIT_S: float = 60.0
const COVER_SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(3440, 1440)]


func _sky_config(variant: int, mode: int, resolved: String = "") -> MatchConfig:
	var config: MatchConfig = _config(variant)
	config.sky_theme_mode = mode as MatchConfig.SkyThemeMode
	config.sky_theme_resolved = resolved
	return config


func _plate(shape: String, sky_id: String) -> String:
	return "%s/%s_%s.png" % [PLATE_DIR, shape, sky_id]


func _plate_loaded() -> bool:
	return _screen.backdrop_texture() != null


func test_every_map_variant_selects_its_own_plate() -> void:
	assert_eq(VARIANT_SHAPES.size(), MatchConfig.MapVariant.size(), "fixture: one shape per variant.")
	for variant: int in MatchConfig.MapVariant.values():
		var config: MatchConfig = _sky_config(variant, MatchConfig.SkyThemeMode.NIGHT)
		_screen.show_for_match(config, _slots(2))
		assert_eq(_screen.backdrop_path(), _plate(VARIANT_SHAPES[variant], "night"), "variant %d" % variant)
		assert_true(ResourceLoader.exists(_screen.backdrop_path()), "the chosen plate is on disk.")


func test_each_sky_theme_selects_its_plate() -> void:
	var expected: Dictionary = {
		MatchConfig.SkyThemeMode.DAY: "sunset", MatchConfig.SkyThemeMode.NIGHT: "night", MatchConfig.SkyThemeMode.DAWN: "dawn",
	}
	for mode: int in expected:
		var config: MatchConfig = _sky_config(MatchConfig.MapVariant.ROUND, mode)
		assert_eq(_screen.backdrop_path_for(config), _plate("round", expected[mode] as String), "sky mode %d" % mode)


func test_random_sky_uses_the_hosts_resolved_theme_and_waits_until_it_is_rolled() -> void:
	var unrolled: MatchConfig = _sky_config(MatchConfig.MapVariant.ROUND, MatchConfig.SkyThemeMode.RANDOM)
	assert_eq(_screen.backdrop_path_for(unrolled), "", "no plate for a sky that is not rolled yet (no wrong one to flash).")
	var rolled: MatchConfig = _sky_config(MatchConfig.MapVariant.ROUND, MatchConfig.SkyThemeMode.RANDOM, "dawn")
	assert_eq(_screen.backdrop_path_for(rolled), _plate("round", "dawn"))


func test_a_running_cycle_uses_the_plate_nearest_its_opening_phase() -> void:
	var sky_theme: SkyThemeDef = load(_screen.tuning.backdrop_cycle_theme_path) as SkyThemeDef
	assert_not_null(sky_theme)
	var config: MatchConfig = _sky_config(MatchConfig.MapVariant.ROUND, MatchConfig.SkyThemeMode.CYCLE)
	var expected: String = _screen.tuning.backdrop_theme_for_phase(sky_theme.cycle_start_phase, sky_theme)
	assert_true(MatchConfig.SKY_THEME_IDS.has(expected), "fixture: the opening phase maps to a real theme: '%s'." % expected)
	assert_eq(_screen.backdrop_path_for(config), _plate("round", expected))
	assert_eq(_screen.tuning.backdrop_theme_for_phase(sky_theme.cycle_locked_phase_sunset, sky_theme), "sunset")
	assert_eq(_screen.tuning.backdrop_theme_for_phase(sky_theme.cycle_locked_phase_night, sky_theme), "night")
	assert_eq(_screen.tuning.backdrop_theme_for_phase(sky_theme.cycle_locked_phase_dawn, sky_theme), "dawn")
	assert_eq(_screen.tuning.backdrop_theme_for_phase(0.99, sky_theme), "dawn", "the ring wraps: just before phase 1 is nearer dawn than night.")
	assert_eq(_screen.tuning.backdrop_theme_for_phase(0.5, null), "", "no theme resource, no answer.")


func test_unknown_variant_and_theme_fall_back() -> void:
	var tuning: LoadingScreenTuning = _screen.tuning
	assert_eq(tuning.backdrop_path(99, "night"), _plate("round", "night"), "an unknown variant draws the round plate.")
	assert_eq(tuning.backdrop_path(-1, "dawn"), _plate("round", "dawn"))
	assert_eq(tuning.backdrop_path(MatchConfig.MapVariant.ROUND, "eclipse"), _plate("round", "sunset"), "an unknown theme draws sunset.")
	assert_eq(tuning.backdrop_fallback_path(), _plate("round", "sunset"))
	var config: MatchConfig = _sky_config(MatchConfig.MapVariant.ROUND, MatchConfig.SkyThemeMode.NIGHT)
	config.map_variant = 99 as MatchConfig.MapVariant
	assert_eq(_screen.backdrop_path_for(config), _plate("round", "night"))


func test_a_missing_plate_falls_back_to_the_default_and_then_to_the_plain_background() -> void:
	_screen.tuning.backdrop_shape_ids = PackedStringArray(["round", "no_such_shape"])
	var config: MatchConfig = _sky_config(1, MatchConfig.SkyThemeMode.NIGHT)
	assert_eq(_screen.backdrop_path_for(config), _plate("round", "sunset"), "no art on disk: the default plate.")
	_screen.tuning.backdrop_dir = "res://assets/ui/no_such_plate_dir"
	assert_eq(_screen.backdrop_path_for(config), "", "not even a default plate: plain background, no error.")
	_screen.show_for_match(config, _slots(2))
	assert_null(_screen.backdrop_texture())
	assert_false((_screen.get_node("%Backdrop") as Control).visible)
	assert_true(_screen.visible, "the loading screen still shows.")


func test_a_pending_overlay_without_a_config_has_no_plate_until_the_match_arrives() -> void:
	_screen.show_pending(null)
	assert_eq(_screen.backdrop_path(), "")
	assert_false((_screen.get_node("%Backdrop") as Control).visible)
	_screen.show_for_match(_sky_config(MatchConfig.MapVariant.ROUND, MatchConfig.SkyThemeMode.DAY), _slots(2))
	assert_eq(_screen.backdrop_path(), _plate("round", "sunset"))
	await wait_until(_plate_loaded, LOAD_WAIT_S, "the plate loads on a worker thread")
	assert_eq(_screen.backdrop_shown_path(), _plate("round", "sunset"))


func test_the_plate_loads_threaded_and_is_shown_cover_cropped_behind_the_card() -> void:
	_screen.show_for_match(_sky_config(MatchConfig.MapVariant.ROUND, MatchConfig.SkyThemeMode.DAY), _slots(2))
	await wait_until(_plate_loaded, LOAD_WAIT_S, "the plate loads on a worker thread")
	var backdrop: TextureRect = _screen.get_node("%Backdrop") as TextureRect
	assert_true(backdrop.visible)
	assert_eq(backdrop.texture.resource_path, _plate("round", "sunset"))
	assert_eq(backdrop.expand_mode, TextureRect.EXPAND_IGNORE_SIZE)
	assert_eq(backdrop.stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_COVERED, "fills the screen, cropping rather than letterboxing.")
	assert_eq(backdrop.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	var content: Control = _screen.get_node("%Content") as Control
	var card: Control = _screen.get_node("%Card") as Control
	assert_eq(backdrop.get_parent(), content)
	assert_lt(backdrop.get_index(), card.get_parent().get_index(), "behind the card's container.")
	assert_gt(backdrop.get_index(), (_screen.get_node("%Background") as Node).get_index(), "above the opaque base colour.")
	await wait_seconds(_screen.tuning.backdrop_fade_in_s + 0.1, "the fade-in")
	assert_almost_eq(backdrop.modulate.a, 1.0, 0.01)


func test_the_backdrop_fills_the_screen_at_1280x720_and_3440x1440_and_the_card_stays_put() -> void:
	for window: Vector2i in COVER_SIZES:
		var host: SubViewport = UiScale.make_viewport(window)
		host.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child_autofree(host)
		var screen: LoadingScreen = load("res://ui/LoadingScreen.tscn").instantiate() as LoadingScreen
		host.add_child(screen)
		screen.show_for_match(_sky_config(MatchConfig.MapVariant.ROUND, MatchConfig.SkyThemeMode.NIGHT), _slots(4))
		for _i: int in range(4):
			await get_tree().process_frame
		var backdrop: Control = screen.get_node("%Backdrop") as Control
		var logical: Vector2 = Vector2(UiScale.logical_size(Vector2(window)))
		assert_eq(backdrop.get_global_rect(), Rect2(Vector2.ZERO, logical), "the plate's rect is the whole screen at %s." % window)
		for overlay_name: String in ["%Dim", "%Vignette"]:
			assert_eq((screen.get_node(overlay_name) as Control).get_global_rect(), Rect2(Vector2.ZERO, logical), "%s covers it too." % overlay_name)
		var card_rect: Rect2 = (screen.get_node("%Card") as Control).get_global_rect()
		assert_almost_eq(card_rect.get_center().x, logical.x * 0.5, 1.5, "the card stays centred at %s." % window)
		assert_almost_eq(card_rect.get_center().y, logical.y * 0.5, 1.5)
		screen.cancel()


func test_the_same_plate_is_kept_across_shows_and_a_different_one_never_flashes_the_old() -> void:
	var first: MatchConfig = _sky_config(MatchConfig.MapVariant.ROUND, MatchConfig.SkyThemeMode.NIGHT)
	_screen.show_for_match(first, _slots(2))
	await wait_until(_plate_loaded, LOAD_WAIT_S, "the night plate loads")
	var kept: Texture2D = _screen.backdrop_texture()
	_screen.show_for_match(first, _slots(2))
	assert_same(_screen.backdrop_texture(), kept, "the same plate stays (the pending overlay then the match call).")
	_screen.cancel()
	_screen.show_for_match(first, _slots(2))
	assert_same(_screen.backdrop_texture(), kept, "a rematch on the same plate has it at once, nothing to wait for.")
	assert_almost_eq((_screen.get_node("%Backdrop") as Control).modulate.a, 1.0, 0.001)
	_screen.show_for_match(_sky_config(MatchConfig.MapVariant.ROUND, MatchConfig.SkyThemeMode.DAWN), _slots(2))
	assert_ne(_screen.backdrop_texture(), kept, "the night art is dropped as soon as the dawn match is chosen.")
	assert_eq(_screen.backdrop_path(), _plate("round", "dawn"))
	await wait_until(_plate_loaded, LOAD_WAIT_S, "the dawn plate loads")
	assert_eq(_screen.backdrop_shown_path(), _plate("round", "dawn"))


func test_a_load_superseded_in_flight_never_shows_the_stale_plate() -> void:
	_screen.show_for_match(_sky_config(MatchConfig.MapVariant.ROUND, MatchConfig.SkyThemeMode.NIGHT), _slots(2))
	_screen.show_for_match(_sky_config(MatchConfig.MapVariant.ROUND, MatchConfig.SkyThemeMode.DAWN), _slots(2))
	await wait_until(_plate_loaded, LOAD_WAIT_S, "the final plate loads")
	await wait_process_frames(3)
	assert_eq(_screen.backdrop_shown_path(), _plate("round", "dawn"))
	assert_eq((_screen.get_node("%Backdrop") as TextureRect).texture.resource_path, _plate("round", "dawn"))


func test_the_backdrop_fades_with_the_overlay() -> void:
	_screen.show_for_match(_sky_config(MatchConfig.MapVariant.ROUND, MatchConfig.SkyThemeMode.DAY), _slots(2))
	await wait_until(_plate_loaded, LOAD_WAIT_S, "the plate loads")
	assert_eq((_screen.get_node("%Backdrop") as Node).get_parent(), _screen.get_node("%Content"), "the plate lives in the faded Content, so fade_out takes it too.")
	_screen.fade_out()
	await wait_seconds(0.3, "warmup frames + fade duration")
	assert_false(_screen.visible)
	assert_almost_eq(_screen.overlay_opacity(), 0.0, 0.01)


func test_dim_and_vignette_come_from_the_tuning() -> void:
	var tuning: LoadingScreenTuning = LoadingScreenTuning.new()
	tuning.backdrop_dim_color = Color(0.1, 0.2, 0.3, 0.7)
	tuning.backdrop_vignette_color = Color(0.4, 0.3, 0.2, 0.9)
	tuning.backdrop_vignette_start = 0.3
	var screen: LoadingScreen = load("res://ui/LoadingScreen.tscn").instantiate() as LoadingScreen
	screen.tuning = tuning
	add_child_autofree(screen)
	assert_eq((screen.get_node("%Dim") as ColorRect).color, tuning.backdrop_dim_color)
	var vignette: GradientTexture2D = (screen.get_node("%Vignette") as TextureRect).texture as GradientTexture2D
	assert_not_null(vignette)
	assert_eq(vignette.fill, GradientTexture2D.FILL_RADIAL)
	assert_eq(vignette.gradient.get_color(0), Color(tuning.backdrop_vignette_color, 0.0), "clear at the centre.")
	assert_eq(vignette.gradient.get_color(2), tuning.backdrop_vignette_color, "darkest at the edge.")
	assert_almost_eq(vignette.gradient.get_offset(1), 0.3, 0.0001, "the falloff starts where the tuning says.")
	assert_lt((screen.get_node("%Dim") as ColorRect).color.a, 1.0, "a dim, not a cover: the plate shows through.")


## Wall-clock-tolerant ceiling for readiness polls (returns as soon as true).
const FLOW_TIMEOUT_S: float = 600.0


func _progress_is(overlay: LoadingScreen, expected: float) -> Callable:
	return func() -> bool: return absf(overlay.progress() - expected) < 0.001


## Flow tests against the real Main (same fixture shape as
## test_match_lifecycle.gd): the overlay is up and un-started Match is still in
## LOBBY when the Start press returns; the match only starts later.
func _real_main() -> Node:
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	var tiny: MapDef = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	tiny.field_radius = 20.0
	(main.get_node("Field") as Field).map_def = tiny
	add_child_autofree(main)
	# Bontago-fca.66: the real-time pending/ready timeouts (10 s / 20 s) are product
	# safety nets; a world build on a gate-loaded machine can outlast them and
	# cancel the overlay mid-test. These flows assert hand-off order, not timeouts.
	var overlay_tuning: LoadingScreenTuning = (main._loading_screen as LoadingScreen).tuning.duplicate() as LoadingScreenTuning # the preload is shared
	overlay_tuning.pending_timeout_s = FLOW_TIMEOUT_S
	overlay_tuning.ready_timeout_s = FLOW_TIMEOUT_S
	(main._loading_screen as LoadingScreen).tuning = overlay_tuning
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
	await wait_process_frames(overlay.tuning.stable_frames + overlay.tuning.warmup_frames + 2)
	assert_true(overlay.visible, "host waits for the first applied territory result")
	Events.territory_updated.emit(Match.raster(), Match.groups())
	await wait_until(_progress_is(overlay, 1.0), FLOW_TIMEOUT_S, "readiness completes")
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
	await wait_until(_progress_is(overlay, overlay.tuning.complete_progress), FLOW_TIMEOUT_S, "readiness completes")
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
	await wait_until(_progress_is(overlay, 1.0), FLOW_TIMEOUT_S, "readiness completes")
	assert_almost_eq(overlay.progress(), 1.0, 0.001)
	overlay.cancel()
	await wait_process_frames(overlay.tuning.warmup_frames + 2)
	main._world_built = false
	Net.leave()
	Match.set_process(true)
