extends GutTest
## Bontago-1pi.11.63: splash, loading-screen and weather-loop art must not stay
## resident after their screen/effect ends, and must load again when needed.

const LOAD_WAIT_S: float = 60.0
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


func test_loading_backdrop_is_released_after_fade_and_reloads() -> void:
	var screen: LoadingScreen = load("res://ui/LoadingScreen.tscn").instantiate() as LoadingScreen
	add_child_autofree(screen)
	screen.tuning = LoadingScreenTuning.new()
	screen.tuning.warmup_frames = 1
	screen.tuning.fade_out_duration_s = 0.02
	var config: MatchConfig = MatchConfig.new()
	var was_held: bool = ResourceLoader.has_cached(screen.backdrop_path_for(config))
	screen.show_for_match(config, _slots())
	await wait_until(func() -> bool: return screen.backdrop_texture() != null, LOAD_WAIT_S, "plate loads")
	var path: String = screen.backdrop_shown_path()
	var ref: WeakRef = weakref(screen.backdrop_texture())
	assert_false(path.is_empty())
	screen.fade_out()
	await wait_until(func() -> bool: return not screen.visible, LOAD_WAIT_S, "fade finishes")
	await wait_process_frames(SETTLE_FRAMES)
	assert_null(screen.backdrop_texture(), "rect holds no plate after the match starts")
	if not was_held:
		await wait_until(func() -> bool: return ref.get_ref() == null, LOAD_WAIT_S)
		assert_null(ref.get_ref(), "plate freed")
		assert_false(ResourceLoader.has_cached(path), "plate not cached")
	screen.show_for_match(config, _slots())
	await wait_until(func() -> bool: return screen.backdrop_texture() != null, LOAD_WAIT_S, "plate loads again")
	assert_false(screen.backdrop_shown_path().is_empty(), "the next loading screen shows an image again (a fresh random pick)")


func test_weather_bed_is_released_after_fade_and_reloads() -> void:
	var amb: WeatherAmbience = WeatherAmbience.new()
	add_child_autofree(amb)
	Events.weather_started.emit(&"snow")
	Events.weather_intensity_changed.emit(&"snow", 1.0)
	amb.advance(100.0)
	var pl: WeakRef = weakref(amb.bed_player(&"snow"))
	Events.weather_stopped.emit(&"snow")
	amb.advance(100.0)
	await wait_until(func() -> bool: return pl.get_ref() == null, LOAD_WAIT_S)
	assert_eq(amb.bed_ids().size(), 0, "faded bed dropped")
	assert_null(pl.get_ref(), "player freed")
	# DECISION: the AudioServer may keep the stopped playback (and so the stream)
	# alive for a few mix cycles; the bed and player no longer reference it.
	Events.weather_started.emit(&"snow")
	assert_not_null(amb.bed_player(&"snow"), "bed rebuilt on demand")


## Bontago-6cw: a plate fetched from the loader thread is released a few frames later, so the
## RenderingServer commands queued by the worker (create/initialize) run before the free.
func test_release_later_holds_the_texture_until_frames_pass() -> void:
	var texture: ImageTexture = ImageTexture.create_from_image(Image.create(2, 2, false, Image.FORMAT_RGBA8))
	var ref: WeakRef = weakref(texture)
	LoadingScreen.release_later(texture)
	texture = null
	assert_not_null(ref.get_ref(), "still held right after the release request")
	await wait_process_frames(LoadingScreen.TEXTURE_RELEASE_FRAMES + 2)
	assert_null(ref.get_ref(), "freed once the hold frames passed")
	LoadingScreen.release_later(null)
