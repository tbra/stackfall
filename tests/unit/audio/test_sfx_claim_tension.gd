extends GutTest
## autoload/Sfx.gd beacon-claim tension layer: volume, duck,
## sting and reset, in both contextual_music modes. A fresh Sfx instance is
## used so the autoload is untouched; match state (live, client, hold length,
## seats) comes from an installed FakeMatchContext and the layer is driven
## through the real Events signals. Observed through the public claim_tension_*
## and claim_duck_* getters and the instance's child AudioStreamPlayers.

const SFX_SCRIPT: GDScript = preload("res://autoload/Sfx.gd")
const MINE: int = 1
const RIVAL: int = 2

## Capture-hold length the fake context reports (Sfx extrapolates a client's progress at this rate).
class HoldContext extends FakeMatchContext:
	var hold_s: float = 20.0

	func capture_hold_seconds() -> float:
		return hold_s


var _sfx: Node
var _config: AudioConfig
var _ctx: HoldContext
var _saved_context: MatchContext = null
var _saved_volumes: Array[float] = []
var _saved_mutes: Array[bool] = []


func before_each() -> void:
	_saved_volumes = [Settings.master_volume_percent(), Settings.music_volume_percent(), Settings.sfx_volume_percent()]
	_saved_mutes = [Settings.master_muted(), Settings.music_muted(), Settings.sfx_muted()]
	Settings.set_master_volume_percent(1.0)
	Settings.set_music_volume_percent(1.0)
	Settings.set_sfx_volume_percent(1.0)
	Settings.set_master_muted(false)
	Settings.set_music_muted(false)
	Settings.set_sfx_muted(false)
	_config = (load("res://config/audio/audio_config.tres") as AudioConfig).duplicate() as AudioConfig
	_config.claim_interrupt_min_interval_s = 0.0
	_saved_context = MatchContext.installed()
	# Offline Net: every seat below slot_count_value is a local human, each its own team,
	# so with two seats team MINE (1) is "mine" and team RIVAL (2) is not.
	_ctx = HoldContext.new()
	_ctx.state_value = MatchPhase.State.PLAYING
	_ctx.slot_count_value = 2
	MatchContext.install(_ctx)
	_sfx = autofree(SFX_SCRIPT.new())
	_sfx.config = _config
	add_child_autofree(_sfx)


func after_each() -> void:
	MatchContext.install(_saved_context)
	Settings.set_master_volume_percent(_saved_volumes[0])
	Settings.set_music_volume_percent(_saved_volumes[1])
	Settings.set_sfx_volume_percent(_saved_volumes[2])
	Settings.set_master_muted(_saved_mutes[0])
	Settings.set_music_muted(_saved_mutes[1])
	Settings.set_sfx_muted(_saved_mutes[2])
	DirAccess.remove_absolute(Settings.effective_path())


## Cue (sting) players currently sounding: the first max_simultaneous player children.
func _playing_stings() -> int:
	var count: int = 0
	var seen: int = 0
	for child: Node in _sfx.get_children():
		var player: AudioStreamPlayer = child as AudioStreamPlayer
		if player == null:
			continue
		if player.playing:
			count += 1
		seen += 1
		if seen >= _config.max_simultaneous:
			break
	return count


## The tension bed: the child player holding a looped stream.
func _bed_player() -> AudioStreamPlayer:
	for child: Node in _sfx.get_children():
		var player: AudioStreamPlayer = child as AudioStreamPlayer
		var wav: AudioStreamWAV = player.stream as AudioStreamWAV if player != null else null
		if wav != null and wav.loop_mode != AudioStreamWAV.LOOP_DISABLED:
			return player
	return null


func _volume_at(progress: float) -> float:
	Events.goal_capture_progress.emit(MINE, progress)
	return _sfx.claim_tension_target_volume_db()


func test_volume_and_duck_follow_progress() -> void:
	for contextual: bool in [false, true]:
		_config.contextual_music_enabled = contextual
		_sfx.reset_claim_tension()
		var silent: float = _volume_at(0.0)
		var half: float = _volume_at(0.5)
		var full: float = _volume_at(1.0)
		assert_eq(silent, SFX_SCRIPT.MUSIC_STEM_MUTE_DB, "contextual=%s" % contextual)
		assert_gt(half, silent)
		assert_gt(full, half)
		assert_almost_eq(full, _config.claim_tension_max_db, 0.001)
		assert_almost_eq(_sfx.claim_duck_target_db(), _config.claim_music_duck_db, 0.001)
		Events.goal_capture_progress.emit(MINE, 0.5)
		assert_between(_sfx.claim_duck_target_db(), _config.claim_music_duck_db, 0.0)
		assert_gt(_sfx.claim_tension_pitch_scale(), 1.0)


func test_rival_is_quieter_darker() -> void:
	Events.goal_capture_progress.emit(MINE, 0.8)
	var mine_db: float = _sfx.claim_tension_target_volume_db()
	var mine_pitch: float = _sfx.claim_tension_pitch_scale()
	Events.goal_capture_progress.emit(-1, 0.0)
	Events.goal_capture_progress.emit(RIVAL, 0.8)
	assert_lt(_sfx.claim_tension_target_volume_db(), mine_db)
	assert_lt(_sfx.claim_tension_pitch_scale(), mine_pitch)


func test_sting_once_per_break() -> void:
	Events.goal_capture_progress.emit(MINE, 0.7)
	Events.goal_capture_progress.emit(-1, 0.0)
	Events.goal_capture_progress.emit(-1, 0.0)
	await get_tree().process_frame
	assert_eq(_playing_stings(), 1, "one sting for one break")


func test_a_win_never_stings() -> void:
	# The zero reading is followed by match_won in the same call stack.
	Events.goal_capture_progress.emit(MINE, 1.0)
	Events.goal_capture_progress.emit(-1, 0.0)
	Events.match_won.emit(MINE)
	await get_tree().process_frame
	assert_eq(_playing_stings(), 0, "a win never stings")
	assert_eq(_sfx.claim_tension_level(), 0.0)


func test_rival_break_plays_a_cue() -> void:
	Events.goal_capture_progress.emit(RIVAL, 0.7)
	Events.goal_capture_progress.emit(-1, 0.0)
	await get_tree().process_frame
	assert_eq(_playing_stings(), 1)


func test_not_live_break_is_silent() -> void:
	_ctx.state_value = MatchPhase.State.COUNTDOWN
	Events.goal_capture_progress.emit(MINE, 0.7)
	Events.goal_capture_progress.emit(-1, 0.0)
	await get_tree().process_frame
	assert_eq(_playing_stings(), 0)


func test_scope_reset_clears_layer() -> void:
	Events.goal_capture_progress.emit(MINE, 0.9)
	var bed: AudioStreamPlayer = _bed_player()
	assert_not_null(bed, "a strong hold starts the looped tension bed")
	assert_true(bed.playing)
	Events.match_scope_reset.emit()
	assert_eq(_sfx.claim_tension_level(), 0.0)
	assert_eq(_sfx.claim_duck_target_db(), 0.0)
	assert_false(bed.playing)
	assert_eq(bed.volume_db, SFX_SCRIPT.MUSIC_STEM_MUTE_DB)


func test_client_extrapolates_between_sparse_updates_and_stops_on_break() -> void:
	_ctx.net_is_client_value = true
	_ctx.hold_s = 20.0
	Events.goal_capture_progress.emit(MINE, 0.1)
	var at_first: float = _sfx.claim_tension_level()
	_sfx._process(5.0)  # 0.35
	var mid: float = _sfx.claim_tension_level()
	assert_gt(mid, at_first, "keeps rising with no new packet")
	_sfx._process(5.0)  # 0.6
	var later: float = _sfx.claim_tension_level()
	assert_gt(later, mid)
	Events.goal_capture_progress.emit(MINE, 0.8)  # snaps to the received value
	assert_gt(_sfx.claim_tension_level(), later, "a real update replaces the extrapolation")
	_sfx._process(100.0)
	assert_almost_eq(_sfx.claim_tension_level(), 1.0, 0.0001, "capped at a full hold")
	Events.goal_capture_progress.emit(-1, 0.0)
	assert_eq(_sfx.claim_tension_level(), 0.0)
	_sfx._process(5.0)
	assert_eq(_sfx.claim_tension_level(), 0.0, "no extrapolation after a break")


func test_client_does_not_extrapolate_a_falling_hold() -> void:
	_ctx.net_is_client_value = true
	_ctx.hold_s = 20.0
	Events.goal_capture_progress.emit(MINE, 0.8)
	Events.goal_capture_progress.emit(MINE, 0.6)
	var before: float = _sfx.claim_tension_level()
	_sfx._process(5.0)
	assert_eq(_sfx.claim_tension_level(), before, "a fading claim never creeps upward")


func test_client_does_not_extrapolate_outside_a_live_match() -> void:
	_ctx.net_is_client_value = true
	Events.goal_capture_progress.emit(MINE, 0.5)
	_ctx.state_value = MatchPhase.State.END
	var before: float = _sfx.claim_tension_level()
	_sfx._process(5.0)
	assert_eq(_sfx.claim_tension_level(), before)


func test_host_does_not_extrapolate() -> void:
	_ctx.net_is_client_value = false
	_ctx.hold_s = 20.0
	Events.goal_capture_progress.emit(MINE, 0.3)
	var before: float = _sfx.claim_tension_level()
	_sfx._process(5.0)
	assert_eq(_sfx.claim_tension_level(), before)
