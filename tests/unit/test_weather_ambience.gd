extends GutTest
## Weather ambience loops and gust whoosh (Bontago-mp0.118).

var _amb: WeatherAmbience = null


func before_each() -> void:
	_amb = WeatherAmbience.new()
	add_child_autofree(_amb)


func _gust(duration: float) -> Dictionary:
	return {"id": 1, "x": 0.0, "y": 5.0, "z": 0.0, "a": 0.0, "r": 3.0, "d": duration, "s": 1.0}


func test_each_weather_has_a_loadable_loop() -> void:
	for weather_id: StringName in [&"rain", &"snow", &"storm"]:
		Events.weather_started.emit(weather_id)
		var player: AudioStreamPlayer = _amb.bed_player(weather_id)
		assert_not_null(player, "%s bed" % weather_id)
		var stream: AudioStreamWAV = player.stream as AudioStreamWAV
		assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD)
		assert_eq(stream.loop_end, 1411200, "%s loop covers the file" % weather_id)
	assert_ne(_amb.bed_player(&"rain").stream, _amb.bed_player(&"storm").stream)


func test_fog_has_no_bed() -> void:
	Events.weather_started.emit(&"fog")
	assert_eq(_amb.bed_ids().size(), 0)


func test_intensity_maps_to_gain_and_volume() -> void:
	Events.weather_started.emit(&"rain")
	Events.weather_intensity_changed.emit(&"rain", 0.5)
	assert_almost_eq(_amb.bed_target(&"rain"), 0.5, 0.0001)
	_amb.advance(100.0)
	assert_almost_eq(_amb.bed_gain(&"rain"), 0.5, 0.0001)
	var half_db: float = _amb.bed_player(&"rain").volume_db
	Events.weather_intensity_changed.emit(&"rain", 1.0)
	_amb.advance(100.0)
	assert_gt(_amb.bed_player(&"rain").volume_db, half_db)
	assert_true(_amb.is_bed_playing(&"rain"))


func test_crossfade_completes() -> void:
	Events.weather_started.emit(&"rain")
	Events.weather_intensity_changed.emit(&"rain", 1.0)
	_amb.advance(100.0)
	Events.weather_started.emit(&"storm")
	Events.weather_intensity_changed.emit(&"storm", 1.0)
	Events.weather_stopped.emit(&"rain")
	_amb.advance(_amb.tuning.crossfade_s * 0.5)
	assert_gt(_amb.bed_gain(&"rain"), 0.0)
	assert_lt(_amb.bed_gain(&"rain"), 1.0)
	assert_gt(_amb.bed_gain(&"storm"), 0.0)
	_amb.advance(_amb.tuning.crossfade_s)
	assert_false(_amb.is_bed_playing(&"rain"))
	assert_almost_eq(_amb.bed_gain(&"storm"), 1.0, 0.0001)
	assert_true(_amb.is_bed_playing(&"storm"))


func test_match_end_fades_everything_out() -> void:
	Events.weather_started.emit(&"snow")
	Events.weather_intensity_changed.emit(&"snow", 1.0)
	_amb.advance(100.0)
	Events.match_scope_reset.emit()
	_amb.advance(100.0)
	assert_false(_amb.is_bed_playing(&"snow"))


func test_pause_ducks_volume() -> void:
	Events.weather_started.emit(&"rain")
	Events.weather_intensity_changed.emit(&"rain", 1.0)
	_amb.advance(100.0)
	var normal_db: float = _amb.bed_player(&"rain").volume_db
	Events.pause_menu_opened.emit()
	assert_almost_eq(_amb.bed_player(&"rain").volume_db, normal_db + _amb.tuning.pause_duck_db, 0.001)
	Events.pause_menu_closed.emit()
	assert_almost_eq(_amb.bed_player(&"rain").volume_db, normal_db, 0.001)


func test_gust_event_plays_whoosh_matching_duration() -> void:
	assert_eq(_amb.gust_stream_count(), 3)
	Events.breeze_gust_started.emit(_gust(0.8))
	assert_eq(_amb.gusts_played, 1)
	var short_stream: AudioStreamWAV = _amb.last_gust_stream
	Events.breeze_gust_started.emit(_gust(5.0))
	assert_eq(_amb.gusts_played, 2)
	assert_gt(_amb.last_gust_stream.get_length(), short_stream.get_length())
	assert_eq(_amb.last_gust_stream.loop_mode, AudioStreamWAV.LOOP_DISABLED)
