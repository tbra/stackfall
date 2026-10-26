extends GutTest
## MusicPlaylist: contextual track scheduler (core/audio/MusicPlaylist.gd), driven the way Sfx drives
## it: set_context, advance(), then track_started() once Sfx has started the chosen track.
## A fresh playlist starts when a context is set that differs from the one it already holds, so
## every test begins with `_begin(context)` using a context other than the constructor's default.

const GAP_MIN_S: float = 30.0
const GAP_MAX_S: float = 75.0
const FADE_IN_S: float = 4.0
const FADE_OUT_S: float = 5.0
const INITIAL_DELAY_S: float = 2.0
const NO_POSITION: float = -1.0
const TRACK_S: float = 20.0
const GAMEPLAY_TRACKS: int = 3

var _config: AudioConfig
var _rng: RandomNumberGenerator


func before_each() -> void:
	_config = AudioConfig.new()
	_config.menu_playlist = [_track()]
	_config.lobby_playlist = [_track()]
	_config.gameplay_playlist = [_track(), _track(), _track()]
	_config.music_fade_in_seconds = FADE_IN_S
	_config.music_fade_out_seconds = FADE_OUT_S
	_config.music_gap_min_seconds = GAP_MIN_S
	_config.music_gap_max_seconds = GAP_MAX_S
	_config.music_initial_delay_seconds = INITIAL_DELAY_S
	_rng = RandomNumberGenerator.new()
	_rng.seed = 11


func _track() -> AudioStreamWAV:
	return AudioStreamWAV.new()


func _begin(context: StringName = &"gameplay") -> MusicPlaylist:
	var playlist: MusicPlaylist = MusicPlaylist.new(_config, _rng)
	playlist.set_context(context)
	return playlist


## Runs the initial delay and starts the chosen track like Sfx does; returns the track index.
func _play_first(playlist: MusicPlaylist) -> int:
	var step: MusicPlaylist.Step = playlist.advance(INITIAL_DELAY_S, NO_POSITION, TRACK_S)
	assert_eq(step, MusicPlaylist.Step.START_TRACK, "delay elapsed")
	var index: int = playlist.next_track()
	playlist.track_started(index)
	return index


func test_context_set_while_stopped_waits_the_initial_delay() -> void:
	var playlist: MusicPlaylist = _begin(&"lobby")
	assert_eq(playlist.context(), &"lobby")
	assert_eq(playlist.phase(), MusicPlaylist.Phase.WAITING)
	assert_eq(playlist.advance(INITIAL_DELAY_S - 0.5, NO_POSITION, TRACK_S), MusicPlaylist.Step.NONE, "silent during the delay")
	assert_eq(playlist.advance(0.5, NO_POSITION, TRACK_S), MusicPlaylist.Step.START_TRACK)


func test_unknown_context_is_ignored() -> void:
	var playlist: MusicPlaylist = _begin(&"lobby")
	playlist.set_context(&"credits")
	assert_eq(playlist.context(), &"lobby")
	assert_eq(playlist.phase(), MusicPlaylist.Phase.WAITING)


func test_context_change_while_waiting_restarts_the_delay() -> void:
	var playlist: MusicPlaylist = _begin(&"gameplay")
	playlist.advance(1.5, NO_POSITION, TRACK_S)
	playlist.set_context(&"lobby")
	assert_eq(playlist.context(), &"lobby")
	assert_eq(playlist.advance(1.5, NO_POSITION, TRACK_S), MusicPlaylist.Step.NONE, "delay restarted")
	assert_eq(playlist.advance(0.5, NO_POSITION, TRACK_S), MusicPlaylist.Step.START_TRACK)


func test_next_track_picks_an_index_of_the_current_context() -> void:
	var playlist: MusicPlaylist = _begin(&"gameplay")
	assert_between(playlist.next_track(), 0, GAMEPLAY_TRACKS - 1)
	playlist.set_context(&"lobby")
	assert_eq(playlist.next_track(), 0, "lobby holds one track")


func test_next_track_is_minus_one_for_an_empty_playlist() -> void:
	_config.gameplay_playlist = []
	var playlist: MusicPlaylist = _begin(&"gameplay")
	assert_eq(playlist.next_track(), -1)
	assert_ne(playlist.advance(GAP_MAX_S, NO_POSITION, TRACK_S), MusicPlaylist.Step.START_TRACK, "nothing to start")


func test_next_track_never_repeats_the_one_just_played() -> void:
	var playlist: MusicPlaylist = _begin(&"gameplay")
	var last: int = _play_first(playlist)
	for _i: int in range(60):
		playlist.track_finished()
		assert_eq(playlist.advance(GAP_MAX_S, NO_POSITION, TRACK_S), MusicPlaylist.Step.START_TRACK)
		var index: int = playlist.next_track()
		assert_between(index, 0, GAMEPLAY_TRACKS - 1)
		assert_ne(index, last, "no immediate repeat")
		playlist.track_started(index)
		last = index


func test_single_track_playlist_may_repeat() -> void:
	var playlist: MusicPlaylist = _begin(&"lobby")
	assert_eq(_play_first(playlist), 0)
	playlist.track_finished()
	playlist.advance(GAP_MAX_S, NO_POSITION, TRACK_S)
	assert_eq(playlist.next_track(), 0, "the only track is allowed again")


func test_no_repeat_memory_is_per_context() -> void:
	var playlist: MusicPlaylist = _begin(&"gameplay")
	var gameplay_last: int = _play_first(playlist)
	playlist.set_context(&"lobby")
	playlist.advance(FADE_OUT_S, NO_POSITION, TRACK_S)
	playlist.advance(INITIAL_DELAY_S, NO_POSITION, TRACK_S)
	playlist.track_started(playlist.next_track())
	playlist.set_context(&"gameplay")
	playlist.advance(FADE_OUT_S, NO_POSITION, TRACK_S)
	playlist.advance(INITIAL_DELAY_S, NO_POSITION, TRACK_S)
	assert_ne(playlist.next_track(), gameplay_last, "returning to gameplay still avoids its last track")


func test_track_fades_in_then_out_without_looping() -> void:
	var playlist: MusicPlaylist = _begin(&"lobby")
	_play_first(playlist)
	assert_eq(playlist.phase(), MusicPlaylist.Phase.PLAYING)
	assert_eq(playlist.envelope(), 0.0, "starts silent")
	playlist.advance(2.0, NO_POSITION, TRACK_S)
	assert_almost_eq(playlist.envelope(), 0.5, 0.001)
	playlist.advance(2.0, NO_POSITION, TRACK_S)
	assert_almost_eq(playlist.envelope(), 1.0, 0.001, "full after the fade-in")
	playlist.advance(14.0, NO_POSITION, TRACK_S)
	assert_almost_eq(playlist.envelope(), 0.4, 0.001, "last seconds fade out (remaining 2 of 5)")
	assert_eq(playlist.phase(), MusicPlaylist.Phase.PLAYING)


func test_playback_position_overrides_the_accumulated_delta() -> void:
	var playlist: MusicPlaylist = _begin(&"lobby")
	_play_first(playlist)
	playlist.advance(0.01, 19.0, TRACK_S)
	assert_almost_eq(playlist.envelope(), 0.2, 0.001, "one second left of a five second fade")
	playlist.advance(0.01, 2.0, TRACK_S)
	assert_almost_eq(playlist.envelope(), 0.5, 0.001, "position, not elapsed time, drives the fade-in")


func test_zero_fade_in_is_full_volume_at_once() -> void:
	_config.music_fade_in_seconds = 0.0
	var playlist: MusicPlaylist = _begin(&"lobby")
	_play_first(playlist)
	playlist.advance(0.0, NO_POSITION, TRACK_S)
	assert_almost_eq(playlist.envelope(), 1.0, 0.001)


func test_finished_track_draws_a_gap_inside_the_configured_range() -> void:
	for rng_seed: int in [1, 2, 3, 4, 5, 6, 7, 8]:
		_rng.seed = rng_seed
		var playlist: MusicPlaylist = _begin(&"gameplay")
		_play_first(playlist)
		playlist.track_finished()
		assert_eq(playlist.phase(), MusicPlaylist.Phase.WAITING)
		assert_eq(playlist.envelope(), 0.0)
		var waited: float = 0.0
		var step: MusicPlaylist.Step = MusicPlaylist.Step.NONE
		while step != MusicPlaylist.Step.START_TRACK and waited < GAP_MAX_S + 5.0:
			step = playlist.advance(1.0, NO_POSITION, TRACK_S)
			waited += 1.0
		assert_eq(step, MusicPlaylist.Step.START_TRACK, "seed %d starts the next track" % rng_seed)
		assert_gte(waited, GAP_MIN_S, "gap at least the minimum (seed %d)" % rng_seed)
		assert_lte(waited, GAP_MAX_S + 1.0, "gap at most the maximum (seed %d)" % rng_seed)


func test_gap_draw_is_driven_by_the_rng() -> void:
	var distinct: Dictionary = {}
	for rng_seed: int in [1, 2, 3, 4, 5, 6]:
		_rng.seed = rng_seed
		var playlist: MusicPlaylist = _begin(&"gameplay")
		_play_first(playlist)
		playlist.track_finished()
		var waited: float = 0.0
		while playlist.advance(0.25, NO_POSITION, TRACK_S) != MusicPlaylist.Step.START_TRACK and waited < GAP_MAX_S + 5.0:
			waited += 0.25
		distinct[waited] = true
	assert_gt(distinct.size(), 1, "different seeds draw different gaps")


func test_equal_gap_bounds_give_a_fixed_gap() -> void:
	_config.music_gap_min_seconds = 10.0
	_config.music_gap_max_seconds = 10.0
	var playlist: MusicPlaylist = _begin(&"gameplay")
	_play_first(playlist)
	playlist.track_finished()
	assert_eq(playlist.advance(9.5, NO_POSITION, TRACK_S), MusicPlaylist.Step.NONE)
	assert_eq(playlist.advance(0.5, NO_POSITION, TRACK_S), MusicPlaylist.Step.START_TRACK)


func test_context_switch_while_playing_enters_switching_and_fades_the_current_track() -> void:
	var playlist: MusicPlaylist = _begin(&"lobby")
	_play_first(playlist)
	playlist.advance(FADE_IN_S, NO_POSITION, TRACK_S)
	playlist.set_context(&"menu")
	assert_eq(playlist.phase(), MusicPlaylist.Phase.SWITCHING)
	assert_eq(playlist.context(), &"menu")
	assert_eq(playlist.advance(2.5, NO_POSITION, TRACK_S), MusicPlaylist.Step.NONE)
	assert_almost_eq(playlist.envelope(), 0.5, 0.001, "half faded out")
	assert_eq(playlist.advance(2.5, NO_POSITION, TRACK_S), MusicPlaylist.Step.STOP_PLAYER, "fade complete: Sfx stops its player")
	assert_eq(playlist.phase(), MusicPlaylist.Phase.WAITING)
	assert_almost_eq(playlist.envelope(), 0.0, 0.001)


func test_switch_fade_starts_from_the_envelope_it_interrupted() -> void:
	var playlist: MusicPlaylist = _begin(&"lobby")
	_play_first(playlist)
	playlist.advance(2.0, NO_POSITION, TRACK_S)
	assert_almost_eq(playlist.envelope(), 0.5, 0.001)
	playlist.set_context(&"menu")
	playlist.advance(2.5, NO_POSITION, TRACK_S)
	assert_almost_eq(playlist.envelope(), 0.25, 0.001, "0.5 faded by half")


func test_rapid_switches_keep_the_fade_and_latest_context_wins() -> void:
	var playlist: MusicPlaylist = _begin(&"lobby")
	_play_first(playlist)
	playlist.advance(FADE_IN_S, NO_POSITION, TRACK_S)
	playlist.set_context(&"menu")
	playlist.advance(2.5, NO_POSITION, TRACK_S)
	playlist.set_context(&"gameplay")
	playlist.set_context(&"menu")
	assert_eq(playlist.phase(), MusicPlaylist.Phase.SWITCHING)
	assert_almost_eq(playlist.envelope(), 0.5, 0.001, "switching again does not restart the fade")
	assert_eq(playlist.advance(2.5, NO_POSITION, TRACK_S), MusicPlaylist.Step.STOP_PLAYER)
	assert_eq(playlist.context(), &"menu")
	assert_eq(playlist.advance(INITIAL_DELAY_S, NO_POSITION, TRACK_S), MusicPlaylist.Step.START_TRACK)
	assert_eq(playlist.next_track(), 0, "the latest context's playlist is used")


func test_same_context_while_playing_does_not_switch() -> void:
	var playlist: MusicPlaylist = _begin(&"lobby")
	_play_first(playlist)
	playlist.set_context(&"lobby")
	assert_eq(playlist.phase(), MusicPlaylist.Phase.PLAYING)


func test_finishing_during_a_switch_waits_the_short_initial_delay() -> void:
	var playlist: MusicPlaylist = _begin(&"lobby")
	_play_first(playlist)
	playlist.set_context(&"menu")
	playlist.track_finished()
	assert_eq(playlist.phase(), MusicPlaylist.Phase.WAITING)
	assert_eq(playlist.advance(INITIAL_DELAY_S, NO_POSITION, TRACK_S), MusicPlaylist.Step.START_TRACK, "no long gap after a context change")


func test_release_stops_the_playlist() -> void:
	var playlist: MusicPlaylist = _begin(&"lobby")
	_play_first(playlist)
	playlist.release()
	assert_eq(playlist.phase(), MusicPlaylist.Phase.STOPPED)
	assert_eq(playlist.advance(GAP_MAX_S, NO_POSITION, TRACK_S), MusicPlaylist.Step.NONE)
