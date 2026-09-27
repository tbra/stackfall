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
