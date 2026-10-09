extends GutTest
## Bontago-mp0.116: impact sample selection by strength tier x surface, variant
## rotation, and that every shipped variation wav loads headless.

const SFX_SCRIPT: GDScript = preload("res://autoload/Sfx.gd")

var _sfx: Node
var _config: AudioConfig


func before_each() -> void:
	_config = (load("res://config/audio_config.tres") as AudioConfig).duplicate() as AudioConfig
	_config.contextual_music_enabled = false
	_config.bundled_theme = null
	_config.bundled_theme_path = ""
	_sfx = autofree(SFX_SCRIPT.new())
	_sfx.config = _config
	add_child_autofree(_sfx)
	_sfx.set_root_dir_for_test(ProjectSettings.globalize_path("res://assets/effects"))


func _speed_for_t(t: float) -> float:
	return _config.impact_speed_min + t * (_config.impact_speed_loud - _config.impact_speed_min)


func _last_stream() -> AudioStream:
	var index: int = (_sfx._next_sfx_player_index - 1 + _sfx._sfx_players.size()) % _sfx._sfx_players.size()
	return (_sfx._sfx_players[index] as AudioStreamPlayer).stream


func _expect_set(speed: float, surface: StringName, tier: StringName) -> void:
	_sfx._play_impact(speed, surface)
	var stream: AudioStream = _last_stream()
	var matched: bool = false
	for file: String in _config.impact_variation_for(surface, tier):
		if _sfx._load_stream(file) == stream:
			matched = true
	assert_true(matched, "%s/%s at %.2f m/s must use the %s_%s set" % [surface, tier, speed, surface, tier])


func test_tier_thresholds() -> void:
	assert_eq(_config.impact_tier(_speed_for_t(0.0)), AudioConfig.TIER_SOFT)
	assert_eq(_config.impact_tier(_speed_for_t(0.32)), AudioConfig.TIER_SOFT)
	assert_eq(_config.impact_tier(_speed_for_t(0.35)), AudioConfig.TIER_MEDIUM)
	assert_eq(_config.impact_tier(_speed_for_t(0.66)), AudioConfig.TIER_MEDIUM)
	assert_eq(_config.impact_tier(_speed_for_t(0.70)), AudioConfig.TIER_HARD)
	assert_eq(_config.impact_tier(_speed_for_t(5.0)), AudioConfig.TIER_HARD)


func test_strength_and_surface_pick_matching_sample_set() -> void:
	for surface: StringName in [AudioConfig.SURFACE_BLOCK, AudioConfig.SURFACE_DISC]:
		_expect_set(_speed_for_t(0.1), surface, AudioConfig.TIER_SOFT)
		_expect_set(_speed_for_t(0.5), surface, AudioConfig.TIER_MEDIUM)
		_expect_set(_speed_for_t(0.9), surface, AudioConfig.TIER_HARD)


func test_variants_rotate_without_immediate_repeat() -> void:
	var speed: float = _speed_for_t(0.5)
	var seen: Dictionary = {}
	var previous: AudioStream = null
	for _i: int in range(24):
		_sfx._play_impact(speed, AudioConfig.SURFACE_BLOCK)
		var stream: AudioStream = _last_stream()
		assert_ne(stream, previous, "same variant twice in a row")
		previous = stream
		seen[stream] = true
	assert_eq(seen.size(), 2, "both variants should be used")


func test_below_min_is_silent_and_position_entry_plays() -> void:
	_sfx._on_block_impacted_at(_config.impact_speed_min * 0.5, Vector3.ZERO)
	for player: AudioStreamPlayer in _sfx._sfx_players:
		assert_false(player.playing)
	_sfx._on_block_impacted_at(_config.impact_speed_loud, Vector3.ZERO)
	assert_not_null(_last_stream(), "no bodies in the empty world -> disc set plays")
	assert_eq(_sfx._classify_surface(Vector3.ZERO), AudioConfig.SURFACE_DISC)


func test_events_signal_reaches_sfx_for_host_and_client_path() -> void:
	# MatchNet._emit_impact (client) and Block (host) both emit this exact pair.
	var real: Node = get_tree().root.get_node("Sfx")
	var before: int = real._next_sfx_player_index
	Events.block_impacted_at.emit(_config.impact_speed_loud, Vector3.ZERO)
	assert_ne(real._next_sfx_player_index, before, "autoload Sfx must react to block_impacted_at")


func test_every_variation_wav_loads() -> void:
	for key: StringName in _config.impact_variation_files:
		for file: String in _config.impact_variation_files[key]:
			assert_not_null(_sfx._load_stream(_config.impact_variation_dir.path_join(file)), file)


## Bontago-bth.3: the cached/pooled pick must play exactly what the original
## per-call lookup did (stream, volume) for a recorded, seeded impact sequence.
func _reference_pick(rng: RandomNumberGenerator, last: Dictionary, speed: float, surface: StringName) -> AudioStream:
	var tier: StringName = _config.impact_tier(speed)
	var files: Array[String] = _config.impact_variation_for(surface, tier)
	var key: String = "%s_%s" % [surface, tier]
	var index: int = 0
	if files.size() > 1:
		var previous: int = int(last.get(key, -1))
		index = rng.randi_range(0, files.size() - 2)
		if previous >= 0 and index >= previous:
			index += 1
		last[key] = index
	return _sfx._load_stream(files[index])


func test_recorded_impact_sequence_matches_reference() -> void:
	_sfx._rng.seed = 4242
	var ref_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	ref_rng.seed = 4242
	var ref_last: Dictionary = {}
	var driver: RandomNumberGenerator = RandomNumberGenerator.new()
	driver.seed = 7
	for i: int in range(200):
		var speed: float = driver.randf_range(_config.impact_speed_min, _config.impact_speed_loud * 1.5)
		var surface: StringName = AudioConfig.SURFACE_BLOCK if driver.randf() < 0.5 else AudioConfig.SURFACE_DISC
		var expected: AudioStream = _reference_pick(ref_rng, ref_last, speed, surface)
		_sfx._play_impact(speed, surface)
		assert_eq(_last_stream(), expected, "impact %d stream" % i)
		var player: AudioStreamPlayer = _sfx._sfx_players[(_sfx._next_sfx_player_index - 1 + _sfx._sfx_players.size()) % _sfx._sfx_players.size()]
		var expected_db: float = _config.sfx_volume_db + _config.impact_volume_db(speed) + Settings.master_volume_db() + Settings.sfx_volume_db()
		assert_almost_eq(player.volume_db, expected_db, 0.0001, "impact %d volume" % i)
