extends GutTest
## splash, loading-screen and weather-loop art must not stay
## resident after their screen/effect ends, and must load again when needed.

const LOAD_WAIT_S: float = 10.0
const REAL_LOAD_WAIT_MS: int = 60000
const SETTLE_FRAMES: int = 4


func _slots() -> Array[PlayerSlot]:
	var slots: Array[PlayerSlot] = []
	slots.append(PlayerSlot.new(0, 0, "Player 1", Color.WHITE))
	return slots


## The shared GUT process (earlier scripts, autoload prefetch) may already hold a
## resource; release assertions only apply to paths this test brought in itself.
func _preheld(paths: Array[String]) -> Dictionary:
	var held: Dictionary = {}
	for path: String in paths:
		held[path] = ResourceLoader.has_cached(path)
	return held


func test_splash_art_is_released_after_finish() -> void:
	var held: Dictionary = _preheld([SplashScreen.IMAGE_PATH, SplashScreen.WORDMARK_PATH, SplashScreen.PIECES_PATH])
	var splash: SplashScreen = SplashScreen.new()
	add_child(splash)
	var plate: WeakRef = weakref(load(SplashScreen.IMAGE_PATH))
	var wordmark: WeakRef = weakref(load(SplashScreen.WORDMARK_PATH))
	assert_not_null(plate.get_ref(), "art is resident while the splash is up")
	splash.finish()
	await wait_process_frames(SETTLE_FRAMES)
	if not held[SplashScreen.IMAGE_PATH]:
		await wait_until(func() -> bool: return plate.get_ref() == null, LOAD_WAIT_S)
		assert_null(plate.get_ref(), "splash plate freed after the splash")
		assert_false(ResourceLoader.has_cached(SplashScreen.IMAGE_PATH))
	if not held[SplashScreen.WORDMARK_PATH]:
		await wait_until(func() -> bool: return wordmark.get_ref() == null, LOAD_WAIT_S)
		assert_null(wordmark.get_ref(), "wordmark freed after the splash")
	if not held[SplashScreen.PIECES_PATH]:
		assert_false(ResourceLoader.has_cached(SplashScreen.PIECES_PATH))
	assert_true(load(SplashScreen.IMAGE_PATH) is Texture2D, "loads again on demand")


## The 4K backdrop decodes on a worker thread in real time (the runner fast-forwards frames), so wait
## on the wall clock, not game time.
func _wait_real(condition: Callable) -> void:
	var start_ms: int = Time.get_ticks_msec()
	while not condition.call() and Time.get_ticks_msec() - start_ms < REAL_LOAD_WAIT_MS:
		await get_tree().process_frame


func test_loading_backdrop_is_released_after_fade_and_reloads() -> void:
	var screen: LoadingScreen = load("res://ui/menus/LoadingScreen.tscn").instantiate() as LoadingScreen
	add_child_autofree(screen)
	screen.tuning = LoadingScreenTuning.new()
	screen.tuning.warmup_frames = 1
	screen.tuning.fade_out_duration_s = 0.02
	screen.tuning.ready_timeout_s = 3600.0  # frames are fast-forwarded; the image loads in real time
	var config: MatchConfig = MatchConfig.new()
	var was_held: bool = ResourceLoader.has_cached(screen.backdrop_path_for(config))
	screen.show_for_match(config, _slots())
	await _wait_real(func() -> bool: return screen._backdrop.texture != null)
	var path: String = screen._backdrop_shown_path
	var ref: WeakRef = weakref(screen._backdrop.texture)
	assert_false(path.is_empty())
	screen.fade_out()
	await wait_until(func() -> bool: return not screen.visible, LOAD_WAIT_S, "fade finishes")
	await wait_process_frames(SETTLE_FRAMES)
	assert_null(screen._backdrop.texture, "rect holds no plate after the match starts")
	if not was_held:
		await wait_until(func() -> bool: return ref.get_ref() == null, LOAD_WAIT_S)
		assert_null(ref.get_ref(), "plate freed")
		assert_false(ResourceLoader.has_cached(path), "plate not cached")
	screen.show_for_match(config, _slots())
	await _wait_real(func() -> bool: return screen._backdrop.texture != null)
	assert_false(screen._backdrop_shown_path.is_empty(), "the next loading screen shows an image again (a fresh random pick)")
