extends GutTest
## autoload/Sfx.gd + config/audio/AudioConfig.gd: audio loaded at runtime from a folder on disk,
## never through Godot's import pipeline. The real Sfx autoload is driven through the Events the
## game emits and observed through its AudioStreamPlayer children, so these tests depend on the
## shipped effect files; file loading over a temp folder is covered by test_stream_library.gd.

var _config: AudioConfig
var _master_percent_before: float
var _stem_config_before: Dictionary = {}


func before_each() -> void:
	# Sfx reads the real Settings autoload (master_volume_db()); the test changes the
	# master volume through the public setter and restores it in after_each.
	_master_percent_before = Settings.master_volume_percent()
	_config = Sfx.config
	_stem_config_before = {}
	SfxChildren.stop_all()


func after_each() -> void:
	SfxChildren.stop_all()
	Sfx.stop_special_loops()
	Events.world_replay_changed.emit(false)
	_restore_stems()
	# The gift-claimed tests below host a real private loopback session; Net is a
	# singleton that outlives this one test file, so it must always come back OFFLINE.
	Net.leave()
	Settings.set_master_volume_percent(_master_percent_before)


## A cue-pool player playing right now (the first max_simultaneous Sfx children; ui, music and
## claim players come after it), or null.
func _first_cue_playing() -> AudioStreamPlayer:
	var seen: int = 0
	for child: Node in Sfx.get_children():
		var player: AudioStreamPlayer = child as AudioStreamPlayer
		if player == null:
			continue
		if player.playing:
			return player
		seen += 1
		if seen >= _config.max_simultaneous:
			break
	return null


## Sfx rate limits read the wall clock (Time.get_ticks_msec), so wait on it rather than on frame time.
func _wait_wall(seconds: float) -> void:
	var from_msec: int = Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - from_msec) / 1000.0 < seconds:
		await get_tree().process_frame


func test_play_returns_false_for_unknown_event() -> void:
	assert_false(Sfx.play(&"not_a_real_event"))


## Effects were inaudible next to the music; the bundled wavs are normalised, these guard the
## playback side.
const BUNDLED_CUE_EVENTS: Array[StringName] = [
	AudioConfig.EVENT_THUD, AudioConfig.EVENT_REJECTED, AudioConfig.EVENT_CLICK,
	AudioConfig.EVENT_START_GAME, AudioConfig.EVENT_HOVER, AudioConfig.EVENT_DROP,
	AudioConfig.EVENT_BOUNCE, AudioConfig.EVENT_CREAK, AudioConfig.EVENT_ROCKET,
	AudioConfig.EVENT_BOMB, AudioConfig.EVENT_VOLCANO, AudioConfig.EVENT_QUAKE,
	AudioConfig.EVENT_PROPELLER, AudioConfig.EVENT_BREAKAGE, AudioConfig.EVENT_GIFT_CLAIMED,
	AudioConfig.EVENT_GIFT_SPAWNED,
]
func test_every_bundled_cue_resolves_to_a_stream() -> void:
	for event: StringName in BUNDLED_CUE_EVENTS:
		for filename: String in _config.files_for_event(event):
			assert_true(Sfx.preview_file(filename), "cue %s file %s should load from assets/audio/sfx" % [event, filename])
			SfxChildren.stop_all()


func test_impact_below_speed_min_does_not_play() -> void:
	Events.block_impacted_at.emit(_config.impact_speed_min * 0.5, Vector3.ZERO)
	assert_false(SfxChildren.any_playing())


func test_impact_at_or_above_speed_min_plays() -> void:
	Events.block_impacted_at.emit(_config.impact_speed_loud, Vector3.ZERO)
	assert_true(SfxChildren.any_playing())


func test_gift_flight_start_plays_spawn_jingle() -> void:
	# The jingle is rate limited; let any earlier test's jingle age out first.
	await _wait_wall(_config.gift_spawn_min_interval_s)
	Events.gift_flight_spawned.emit(7, Vector3.UP * 18.0, Vector3.ZERO)
	assert_true(SfxChildren.any_playing(), "A new gift flight must cue the spawn chime")


const SPECIALS_DIR: String = "res://config/gifts/specials"


func test_every_shipped_special_has_a_cue_that_loads() -> void:
	var checked: int = 0
	for file: String in DirAccess.get_files_at(SPECIALS_DIR):
		if not file.ends_with(".tres"):
			continue
		var def: SpecialDef = load(SPECIALS_DIR.path_join(file)) as SpecialDef
		if def == null:
			continue
		# A one-shot on its trigger, a loop for a timed window, or (the bean) a hop sound.
		var filename: String = _config.special_cue_files.get(def.id, "")
		if filename.is_empty():
			filename = _config.special_loop_files.get(def.id, "")
		if filename.is_empty() and def.id == &"jumping_bean":
			filename = _config.bean_hop_file
		assert_false(filename.is_empty(), "special %s needs a sound" % def.id)
		assert_true(Sfx.preview_file(filename), "special %s cue %s should load from assets/audio/sfx" % [def.id, filename])
		SfxChildren.stop_all()
		checked += 1
	assert_gt(checked, 0, "fixture: at least one SpecialDef found")
	for file: String in [_config.glue_hit_file, _config.drop_file]:
		assert_true(Sfx.preview_file(file), "%s should load from assets/audio/sfx" % file)
		SfxChildren.stop_all()


## Looping players Sfx has added beside its fixed pools (a timed special's bed).
func _looping_players() -> int:
	var count: int = 0
	for child: Node in Sfx.get_children():
		var player: AudioStreamPlayer = child as AudioStreamPlayer
		if player == null or not player.playing:
			continue
		var wav: AudioStreamWAV = player.stream as AudioStreamWAV
		if wav != null and wav.loop_mode == AudioStreamWAV.LOOP_FORWARD:
			count += 1
	return count


func test_special_consumed_loops_for_the_window_and_trigger_fades_it() -> void:
	var before: int = _looping_players()
	Events.special_consumed.emit(0, &"earthquake")
	assert_eq(_looping_players(), before + 1, "the rumble starts when the gift is used and loops")
	Events.special_triggered.emit(-1, &"earthquake", Vector3.ZERO, 0)
	await _wait_wall(_config.special_loop_fade_out_s + 0.3)
	assert_eq(_looping_players(), before, "the window's end fades it out and frees it")


func test_special_triggered_plays_its_cue() -> void:
	await _wait_wall(_config.special_cue_min_interval_s)
	Events.special_triggered.emit(5, &"bomb", Vector3.ZERO, 0)
	assert_true(SfxChildren.any_playing(), "a triggered special must sound")


func test_special_triggered_with_an_unknown_id_is_silent() -> void:
	Events.special_triggered.emit(5, &"not_a_special", Vector3.ZERO, 0)
	assert_false(SfxChildren.any_playing())


func test_special_triggered_is_silent_during_a_world_replay() -> void:
	await _wait_wall(_config.special_cue_min_interval_s)
	Events.world_replay_changed.emit(true)
	Events.special_triggered.emit(5, &"bomb", Vector3.ZERO, 0)
	assert_false(SfxChildren.any_playing(), "a late joiner's replay is state, not news")
	Events.world_replay_changed.emit(false)
	await _wait_wall(_config.special_cue_min_interval_s)
	Events.special_triggered.emit(5, &"bomb", Vector3.ZERO, 0)
	assert_true(SfxChildren.any_playing(), "positive control: the same trigger sounds once the replay ends")


func test_gift_claimed_for_the_local_slot_plays_the_claim_sound() -> void:
	# Net defaults to OFFLINE, where is_local_slot() is true for every slot
	# (offline: one human drives all of them) -- no setup needed.
	assert_true(Net.is_offline(), "fixture: Net starts OFFLINE")

	Events.gift_claimed.emit(1, 0, &"anvil")

	assert_true(SfxChildren.any_playing(), "the claiming slot's own claim must play a sound")


func test_gift_claimed_for_a_non_local_slot_plays_nothing() -> void:
	# A hosting Net drives slot 0 only, so slot 1 is somebody else's seat.
	assert_eq(Net.host_game(AgentProbe.free_udp_port(), "", false), OK)
	assert_false(Net.is_local_slot(1), "fixture: slot 1 is not this instance's seat")

	Events.gift_claimed.emit(1, 1, &"anvil")

	assert_false(SfxChildren.any_playing(), "another slot's claim must not play a sound here")


func test_master_volume_db_offsets_play_volume_db() -> void:
	assert_true(Sfx.play(AudioConfig.EVENT_THUD))
	var playing: AudioStreamPlayer = _first_cue_playing()
	assert_not_null(playing)
	if playing == null:
		return
	var baseline_db: float = playing.volume_db
	SfxChildren.stop_all()

	Settings.set_master_volume_percent(0.5)
	assert_true(Sfx.play(AudioConfig.EVENT_THUD))
	playing = _first_cue_playing()
	assert_not_null(playing)
	if playing == null:
		return

	assert_almost_eq(playing.volume_db - baseline_db, linear_to_db(0.5), 0.0001)


# --- Adaptive music crossfade ------------

## Turns the stems on through the public settings signal: contextual music off, no bundled
## theme, and two shipped wavs standing in for the calm and tense stem files.
func _install_both_stem_files() -> void:
	_stem_config_before = {
		"contextual": _config.contextual_music_enabled,
		"theme": _config.bundled_theme,
		"theme_path": _config.bundled_theme_path,
		"calm": _config.music_stem_calm_file,
		"tense": _config.music_stem_tense_file,
	}
	_config.contextual_music_enabled = false
	_config.bundled_theme = null
	_config.bundled_theme_path = ""
	_config.music_stem_calm_file = _config.thud_files[0]
	_config.music_stem_tense_file = _config.thud_files[1]
	Settings.audio_settings_changed.emit()


func _restore_stems() -> void:
	if _stem_config_before.is_empty():
		return
	Sfx.reset_match_audio()
	_config.contextual_music_enabled = _stem_config_before["contextual"]
	_config.bundled_theme = _stem_config_before["theme"]
	_config.bundled_theme_path = _stem_config_before["theme_path"]
	_config.music_stem_calm_file = _stem_config_before["calm"]
	_config.music_stem_tense_file = _stem_config_before["tense"]
	_stem_config_before = {}
	Settings.audio_settings_changed.emit()


func test_goal_capture_progress_crossfades_toward_tense_when_stems_available() -> void:
	_install_both_stem_files()

	Events.goal_capture_progress.emit(0, 0.9)

	assert_gt(
		Sfx.tense_stem_target_volume_db(),
		Sfx.calm_stem_target_volume_db(),
		"progress above the tense threshold should target the tense stem louder than the calm one",
	)
