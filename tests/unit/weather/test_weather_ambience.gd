extends GutTest
## Weather ambience loops and gust whoosh.

var _amb: WeatherAmbience = null
var _defs: Dictionary = {}


func before_each() -> void:
	_amb = WeatherAmbience.new()
	add_child_autofree(_amb)
	_defs.clear()
	for def: WeatherTuning in WeatherTuning.load_all():
		_defs[def.id] = def


## The bed's looping player (null once it faded out and was released).
func _bed(weather_id: StringName) -> AudioStreamPlayer:
	return _amb.get_node_or_null("Bed_" + String(weather_id)) as AudioStreamPlayer


func _is_playing(weather_id: StringName) -> bool:
	var player: AudioStreamPlayer = _bed(weather_id)
	return player != null and player.playing


## The linear bed gain, read back from what is audible: the player's volume less the bed's own
## level and the Master + Weather mix.
func _gain(weather_id: StringName) -> float:
	var player: AudioStreamPlayer = _bed(weather_id)
	if player == null:
		return 0.0
	var base_db: float = (_defs[weather_id] as WeatherTuning).ambience_volume_db
	return db_to_linear(player.volume_db - base_db - Settings.master_volume_db() - Settings.weather_volume_db())


func _gust_player(index: int) -> AudioStreamPlayer:
	return _amb.get_node("Gust%d" % index) as AudioStreamPlayer


func _gust(duration: float) -> Dictionary:
	return {"id": 1, "x": 0.0, "y": 5.0, "z": 0.0, "a": 0.0, "r": 3.0, "d": duration, "s": 1.0}


func test_intensity_maps_to_gain_and_volume() -> void:
	Events.weather_started.emit(&"rain")
	Events.weather_intensity_changed.emit(&"rain", 0.5)
	_amb.advance(100.0)
	assert_almost_eq(_gain(&"rain"), 0.5, 0.0001)
	var half_db: float = _bed(&"rain").volume_db
	Events.weather_intensity_changed.emit(&"rain", 1.0)
	_amb.advance(100.0)
	assert_gt(_bed(&"rain").volume_db, half_db)
	assert_true(_is_playing(&"rain"))


func test_crossfade_completes() -> void:
	Events.weather_started.emit(&"rain")
	Events.weather_intensity_changed.emit(&"rain", 1.0)
	_amb.advance(100.0)
	Events.weather_started.emit(&"storm")
	Events.weather_intensity_changed.emit(&"storm", 1.0)
	Events.weather_stopped.emit(&"rain")
	_amb.advance(_amb.tuning.crossfade_s * 0.5)
	assert_gt(_gain(&"rain"), 0.0)
	assert_lt(_gain(&"rain"), 1.0)
	assert_gt(_gain(&"storm"), 0.0)
	_amb.advance(_amb.tuning.crossfade_s)
	assert_false(_is_playing(&"rain"))
	assert_almost_eq(_gain(&"storm"), 1.0, 0.0001)
	assert_true(_is_playing(&"storm"))


func test_match_end_fades_everything_out() -> void:
	Events.weather_started.emit(&"snow")
	Events.weather_intensity_changed.emit(&"snow", 1.0)
	_amb.advance(100.0)
	Events.match_scope_reset.emit()
	_amb.advance(100.0)
	assert_false(_is_playing(&"snow"))


func test_pause_ducks_volume() -> void:
	Events.weather_started.emit(&"rain")
	Events.weather_intensity_changed.emit(&"rain", 1.0)
	_amb.advance(100.0)
	var normal_db: float = _bed(&"rain").volume_db
	Events.pause_menu_opened.emit()
	assert_almost_eq(_bed(&"rain").volume_db, normal_db + _amb.tuning.pause_duck_db, 0.001)
	Events.pause_menu_closed.emit()
	assert_almost_eq(_bed(&"rain").volume_db, normal_db, 0.001)


func test_gust_event_plays_whoosh_matching_duration() -> void:
	Events.breeze_gust_started.emit(_gust(0.8))
	assert_true(_gust_player(0).playing)
	var short_stream: AudioStreamWAV = _gust_player(0).stream as AudioStreamWAV
	Events.breeze_gust_started.emit(_gust(5.0))
	assert_true(_gust_player(1).playing)
	var long_stream: AudioStreamWAV = _gust_player(1).stream as AudioStreamWAV
	assert_gt(long_stream.get_length(), short_stream.get_length())
	assert_eq(long_stream.loop_mode, AudioStreamWAV.LOOP_DISABLED)


## loops and gust whoosh follow Master + Weather only, not SFX.
func test_weather_volume_follows_weather_channel_only() -> void:
	var saved_weather: float = Settings.weather_volume_percent()
	var saved_sfx: float = Settings.sfx_volume_percent()
	Events.weather_started.emit(&"rain")
	Events.weather_intensity_changed.emit(&"rain", 1.0)
	_amb.advance(100.0)
	var base_db: float = _bed(&"rain").volume_db
	Settings.set_sfx_volume_percent(0.1)
	assert_almost_eq(_bed(&"rain").volume_db, base_db, 0.001, "SFX slider must not move the bed")
	Settings.set_sfx_volume_percent(saved_sfx)
	Settings.set_weather_volume_percent(0.5)
	assert_almost_eq(_bed(&"rain").volume_db, base_db + linear_to_db(0.5) - linear_to_db(saved_weather), 0.001, "Weather slider moves the bed")
	Events.breeze_gust_started.emit(_gust(0.8))
	assert_almost_eq(_gust_player(0).volume_db, _amb.tuning.gust_volume_db + Settings.master_volume_db() + Settings.weather_volume_db(), 0.001)
	Settings.set_weather_volume_percent(saved_weather)

