extends GutTest
## splash, loading-screen and weather-loop art must not stay
## resident after their screen/effect ends, and must load again when needed.

const LOAD_WAIT_S: float = 10.0
const SETTLE_FRAMES: int = 4


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


func test_loading_backdrop_is_released_after_clear_and_reloads() -> void:
	var backdrop: LoadingBackdrop = LoadingBackdrop.new()
	add_child_autofree(backdrop)
	var config: MatchConfig = MatchConfig.new()
	var path: String = backdrop.path_for(config)
	var was_held: bool = ResourceLoader.has_cached(path)
	backdrop.show_for(config, 0.0)
	assert_not_null(backdrop.texture)
	var ref: WeakRef = weakref(backdrop.texture)
	backdrop.finish_fade()
	backdrop.clear()
	await wait_process_frames(SETTLE_FRAMES)
	assert_null(backdrop.texture, "rect holds no plate after the match starts")
	if not was_held:
		await wait_until(func() -> bool: return ref.get_ref() == null, LOAD_WAIT_S)
		assert_null(ref.get_ref(), "plate freed")
		assert_false(ResourceLoader.has_cached(path), "plate not cached")
	backdrop.show_for(config, 0.0)
	assert_not_null(backdrop.texture, "the next loading screen shows an image again")
