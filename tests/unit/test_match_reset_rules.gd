extends GutTest
## Bontago-1pi.46 R2 (docs/MATCH_RESET_AUDIT.md G3, G6 + rumble): the rules and
## autoload carry-overs behind "a new match after leaving is indistinguishable from
## a freshly launched one".
##
## G3: MatchTerritory cached match A's influence circles across abort_match() and
## start_match(B), so the host's MatchNet._encode_circles() shipped A's circles to
## clients during B's loading/countdown. clear_circles() now runs from
## MatchLifecycle._reset_match_state() and at the top of _build_territory().
## G6: Sfx's tense stem (contextual music off) only cleared on a later
## goal_capture_progress. Sfx.reset_match_audio() returns it to calm.
## Rumble stops the last pad on Events.match_scope_reset.

const MatchNetScript := preload("res://net/MatchNet.gd")
const SFX_SCRIPT: GDScript = preload("res://autoload/Sfx.gd")

var _tiny_map: MapDef
var _field: Field
var _blocks_root: Node3D
var _registry: BlockRegistry
var _net: MatchNetScript

var _sfx: Node
var _audio_config: AudioConfig
var _tmp_dir: String
var _settings_cfg_path: String
var _stop_calls: Array[int] = []


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_tiny_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _tiny_map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)

	# Sfx/Rumble read the real Settings autoload; redirect it to a temp cfg for the file.
	_settings_cfg_path = OS.get_user_data_dir().path_join("test_match_reset_rules_settings_tmp.cfg")
	_delete_if_exists(_settings_cfg_path)
	Settings.set_config_path_for_test(_settings_cfg_path)
	_stop_calls = []
	Rumble.stop_vibration_fn = Callable(self, "_record_stop")
	Rumble.set_last_device_for_test(Rumble.DEVICE_NONE, &"")


func after_each() -> void:
	if _net != null and is_instance_valid(_net):
		_net.set_providers(null, null)
	_net = null
	Match.set_net_provider(null)
	Match.set_replicator(null)
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()
	Rumble.stop_vibration_fn = Callable(Rumble, "_stop_vibration_real")
	Rumble.set_last_device_for_test(Rumble.DEVICE_NONE, &"")
	Settings.set_config_path_for_test(Settings.default_config_path())
	_delete_if_exists(_settings_cfg_path)
	if _tmp_dir != "" and DirAccess.dir_exists_absolute(_tmp_dir):
		for filename: String in DirAccess.get_files_at(_tmp_dir):
			DirAccess.remove_absolute(_tmp_dir.path_join(filename))


# --- helpers ------------------------------------------------------------------

func _delete_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _record_stop(device: int) -> void:
	_stop_calls.append(device)


func _config(player_count: int = 2) -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	# Script swap first (see test_match_net.gd's _config()).
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = player_count
	config.hot_seat = false
	config.rng_seed = 4242
	return config


func _run_countdown() -> void:
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)


func _start_playing(player_count: int = 2) -> void:
	Match.start_match(_config(player_count))
	_run_countdown()
	assert_eq(Match.state(), Match.State.PLAYING, "fixture should reach PLAYING")


func _circle_count() -> int:
	return (Match.circle_render_arrays()["xs"] as PackedFloat32Array).size()


func _make_host_net() -> MatchNetScript:
	var fake: FakeNet = FakeNet.host({1: 0}, [0])
	Match.set_net_provider(fake)
	var node: MatchNetScript = MatchNetScript.new()
	node.set_process(false)
	add_child_autofree(node)
	node.set_providers(fake, Match)
	_net = node
	return node


func _decoded_circle_payload(net: MatchNetScript) -> Dictionary:
	return CircleWire.decode(
		net._encode_circles(), Match.circle_wire_xz_bound(), Match.circle_wire_radius_max()
	)


func _assert_render_arrays_empty(context: String) -> void:
	var arrays: Dictionary = Match.circle_render_arrays()
	assert_eq((arrays["xs"] as PackedFloat32Array).size(), 0, "%s: xs empty" % context)
	assert_eq((arrays["zs"] as PackedFloat32Array).size(), 0, "%s: zs empty" % context)
	assert_eq((arrays["radii"] as PackedFloat32Array).size(), 0, "%s: radii empty" % context)
	assert_eq((arrays["teams"] as PackedInt32Array).size(), 0, "%s: teams empty" % context)
	assert_false(bool(arrays["argmax_mode"]), "%s: argmax_mode back to default" % context)


# --- G3: stale influence circles -----------------------------------------------

func test_every_reset_path_drops_the_previous_matchs_circles() -> void:
	# Merged: clear_circles(), abort_match(), a direct start_match() from PLAYING
	# (no explicit abort) and _build_territory() alone (the second guard).
	for path: StringName in [&"clear_circles", &"abort_match", &"start_match_from_playing", &"build_territory"]:
		_start_playing()
		assert_gt(_circle_count(), 0, "%s: fixture: circles live in match A" % path)
		match path:
			&"clear_circles":
				Match._territory.clear_circles()
				_assert_render_arrays_empty("after clear_circles()")
				Match._territory.clear_circles()
				_assert_render_arrays_empty("clear_circles() is idempotent")
			&"abort_match":
				Match.abort_match()
				_assert_render_arrays_empty("after abort_match()")
			&"start_match_from_playing":
				Match.start_match(_config(3))
				assert_ne(Match.state(), Match.State.PLAYING)
				_assert_render_arrays_empty("B's countdown after a direct restart")
			&"build_territory":
				Match._territory._build_territory()
				_assert_render_arrays_empty("after _build_territory()")
		Match.abort_match()


func test_a_new_match_after_a_solved_one_has_no_circles_before_playing() -> void:
	_start_playing()
	assert_gt(_circle_count(), 0, "fixture: circles live in match A")

	Match.abort_match()
	Match.start_match(_config(3))

	assert_eq(Match.state(), Match.State.COUNTDOWN, "B is counting down, not yet PLAYING")
	_assert_render_arrays_empty("B's countdown")
	_run_countdown()
	assert_eq(Match.state(), Match.State.PLAYING)
	assert_gt(_circle_count(), 0, "once B is PLAYING its own home circles are solved")


func test_the_hosts_circle_payload_during_the_next_countdown_decodes_to_zero_circles() -> void:
	_start_playing()
	var net: MatchNetScript = _make_host_net()
	assert_gt((_decoded_circle_payload(net)["xs"] as PackedFloat32Array).size(), 0, "fixture: A's payload carries circles")

	Match.abort_match()
	Match.start_match(_config(3))
	assert_eq(Match.state(), Match.State.COUNTDOWN)

	var decoded: Dictionary = _decoded_circle_payload(net)
	assert_false(decoded.is_empty(), "the payload is still a valid, decodable packet")
	assert_eq((decoded["xs"] as PackedFloat32Array).size(), 0, "no stale circles replicated to clients")
	assert_eq((decoded["teams"] as PackedInt32Array).size(), 0)
	assert_eq(
		(decoded["goal_positions"] as PackedVector2Array).size(),
		(Match.circle_render_arrays()["goal_positions"] as PackedVector2Array).size(),
		"B's own goal discs are still shipped"
	)


# --- G6: tense stem carries over -------------------------------------------------

func _make_sfx(contextual: bool) -> void:
	_audio_config = load("res://config/audio_config.tres").duplicate() as AudioConfig
	_audio_config.contextual_music_enabled = contextual
	_audio_config.bundled_theme = null
	_sfx = autofree(SFX_SCRIPT.new())
	_sfx.config = _audio_config
	add_child_autofree(_sfx)
	_tmp_dir = OS.get_user_data_dir().path_join("test_match_reset_rules_tmp")
	DirAccess.make_dir_recursive_absolute(_tmp_dir)


func _write_tiny_wav(path: String) -> void:
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	wav.stereo = false
	var data: PackedByteArray = PackedByteArray()
	data.resize(2205 * 2)
	wav.data = data
	assert_eq(wav.save_to_wav(path), OK, "fixture wav should save cleanly: %s" % path)


func _install_both_stem_files() -> void:
	_audio_config.music_stem_calm_file = "calm_stem.wav"
	_audio_config.music_stem_tense_file = "tense_stem.wav"
	_write_tiny_wav(_tmp_dir.path_join(_audio_config.music_stem_calm_file))
	_write_tiny_wav(_tmp_dir.path_join(_audio_config.music_stem_tense_file))
	_sfx.set_root_dir_for_test(_tmp_dir)


func test_match_scope_reset_returns_the_tense_stem_to_calm() -> void:
	_make_sfx(false)
	_install_both_stem_files()
	assert_true(_sfx.tense_stem_available(), "fixture: both stems installed")
	Events.goal_capture_progress.emit(0, 0.9)
	assert_true(_sfx._tense_stem_is_active, "fixture: tense is up at the end of match A")
	assert_gt(_sfx.tense_stem_target_volume_db(), _sfx.calm_stem_target_volume_db(), "fixture: tense is the louder target")
	assert_not_null(_sfx._music_crossfade_tween, "fixture: the capture started a crossfade")

	Events.match_scope_reset.emit()

	assert_false(_sfx._tense_stem_is_active, "tense off after the reset")
	assert_gt(_sfx.calm_stem_target_volume_db(), _sfx.tense_stem_target_volume_db(), "calm is the louder target again")
	assert_null(_sfx._music_crossfade_tween, "the in-flight crossfade is killed")
	assert_almost_eq(_sfx._music_player.volume_db, _sfx.calm_stem_target_volume_db(), 0.001, "calm stem at its calm volume")
	assert_almost_eq(
		_sfx._tense_music_player.volume_db, _sfx.tense_stem_target_volume_db(), 0.001, "tense stem muted at its calm-state volume"
	)


func test_the_reset_is_idempotent_and_a_noop_when_already_calm() -> void:
	_make_sfx(false)
	_install_both_stem_files()
	var calm_db: float = _sfx.calm_stem_target_volume_db()
	var tense_db: float = _sfx.tense_stem_target_volume_db()

	Events.match_scope_reset.emit()
	Events.match_scope_reset.emit()

	assert_false(_sfx._tense_stem_is_active)
	assert_almost_eq(_sfx.calm_stem_target_volume_db(), calm_db, 0.001)
	assert_almost_eq(_sfx.tense_stem_target_volume_db(), tense_db, 0.001)


func test_the_reset_clears_the_tense_flag_with_no_stems_installed() -> void:
	# Shipped single-stream config: the flag flips from goal_capture_progress alone.
	_make_sfx(false)
	_sfx.set_root_dir_for_test(_tmp_dir)
	assert_false(_sfx.tense_stem_available(), "fixture: no tense stem installed")
	Events.goal_capture_progress.emit(0, 0.9)
	assert_true(_sfx._tense_stem_is_active, "fixture: the flag flips even without stems")

	Events.match_scope_reset.emit()

	assert_false(_sfx._tense_stem_is_active)


func test_the_reset_keeps_the_playlist_envelope_with_contextual_music_on() -> void:
	_make_sfx(true)
	_sfx._music_player.volume_db = -12.5
	var context: StringName = _sfx._music_context
	var state: int = _sfx._music_state

	Events.match_scope_reset.emit()

	assert_false(_sfx._tense_stem_is_active)
	assert_almost_eq(_sfx._music_player.volume_db, -12.5, 0.001, "the playlist envelope owns the volume")
	assert_eq(_sfx._music_context, context, "audit D2: music context carries across matches")
	assert_eq(_sfx._music_state, state, "audit D2: the playlist state carries across matches")


# --- Rumble ------------------------------------------------------------------------


func test_match_scope_reset_stops_the_last_pad_and_nothing_when_none_spoke() -> void:
	Events.match_scope_reset.emit()
	assert_eq(_stop_calls.size(), 0, "no pad has ever spoken: nothing to stop")

	Rumble.set_last_device_for_test(3, Settings.DEVICE_GAMEPAD)
	Events.match_scope_reset.emit()
	assert_eq(_stop_calls, [3] as Array[int], "the last-active pad is stopped")
