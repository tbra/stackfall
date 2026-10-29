extends GutTest
## LoadingBackdrop: one random plate per loading screen, shown through `texture`,
## kept across the fade and a repeat show, dropped by clear(), loaded on the main thread headless.

const FADE_IN_S: float = 0.2
const FRAMES: int = 6


func _backdrop() -> LoadingBackdrop:
	var backdrop: LoadingBackdrop = LoadingBackdrop.new()
	add_child_autofree(backdrop)
	return backdrop


func test_path_for_without_config_is_empty() -> void:
	assert_eq(_backdrop().path_for(null), "")


func test_path_for_config_names_an_existing_plate() -> void:
	var path: String = _backdrop().path_for(MatchConfig.new())
	assert_false(path.is_empty())
	assert_true(ResourceLoader.exists(path), "the plate exists on disk")


func test_path_for_is_one_pick_per_screen() -> void:
	var backdrop: LoadingBackdrop = _backdrop()
	var config: MatchConfig = MatchConfig.new()
	var first: String = backdrop.path_for(config)
	for _i: int in 20:
		assert_eq(backdrop.path_for(config), first)


func test_show_for_headless_loads_the_picked_plate_at_once() -> void:
	var backdrop: LoadingBackdrop = _backdrop()
	var config: MatchConfig = MatchConfig.new()
	backdrop.show_for(config, 0.0)
	assert_not_null(backdrop.texture, "loaded on the main thread: no wait")
	assert_eq(backdrop.texture.resource_path, backdrop.path_for(config))


func test_show_for_without_config_shows_nothing() -> void:
	var backdrop: LoadingBackdrop = _backdrop()
	backdrop.show_for(null, FADE_IN_S)
	assert_null(backdrop.texture)


func test_shown_plate_does_not_change_across_the_fade() -> void:
	var backdrop: LoadingBackdrop = _backdrop()
	var config: MatchConfig = MatchConfig.new()
	backdrop.show_for(config, FADE_IN_S)
	var path: String = backdrop.texture.resource_path
	await wait_process_frames(FRAMES)
	assert_eq(backdrop.texture.resource_path, path, "while fading in")
	backdrop.finish_fade()
	assert_eq(backdrop.texture.resource_path, path, "after the fade finishes")
	assert_eq(backdrop.path_for(config), path)


func test_same_plate_is_not_reloaded() -> void:
	var backdrop: LoadingBackdrop = _backdrop()
	var config: MatchConfig = MatchConfig.new()
	backdrop.show_for(config, FADE_IN_S)
	var texture: Texture2D = backdrop.texture
	backdrop.show_for(config, FADE_IN_S)
	await wait_process_frames(FRAMES)
	assert_same(backdrop.texture, texture)


func test_clear_drops_the_plate_and_a_later_show_loads_it_again() -> void:
	var backdrop: LoadingBackdrop = _backdrop()
	var config: MatchConfig = MatchConfig.new()
	backdrop.show_for(config, 0.0)
	backdrop.clear()
	assert_null(backdrop.texture)
	backdrop.show_for(config, 0.0)
	assert_not_null(backdrop.texture)


func test_clear_with_nothing_shown_is_harmless() -> void:
	var backdrop: LoadingBackdrop = _backdrop()
	backdrop.clear()
	backdrop.finish_fade()
	assert_null(backdrop.texture)


func test_threaded_loads_are_unsafe_only_under_the_headless_display() -> void:
	assert_eq(LoadingBackdrop.threaded_texture_loads_safe(), DisplayServer.get_name() != "headless")


func test_release_later_accepts_null_and_a_resource() -> void:
	await LoadingBackdrop.release_later(null)
	await LoadingBackdrop.release_later(Resource.new())
	pass_test("both calls returned")
