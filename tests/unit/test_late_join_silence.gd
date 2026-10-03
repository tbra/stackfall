extends GutTest
## Bontago-1pi.56: a client joining mid-match must hear the world being rebuilt
## as silence. The host's world replay restores state through the same Events a
## live match emits (block_placed per body, player_eliminated per dead slot,
## gift_flight_spawned per falling crate), and Sfx used to answer every one with
## its drop / breakage / gift sound, so the joiner heard the match history in one
## burst. net/MatchNet.gd now marks the replay (the net_match_start that carries
## the replay id, up to the matching net_replay_end) with
## Events.world_replay_changed, and Sfx mutes its one-shot feedback in that span.
##
## The fixture follows tests/unit/test_late_join.gd: host world on the real Match,
## the replay captured through MatchNet's seam, then Match turns client and the
## captured messages are applied in order -- the calls the RPC layer makes. A fresh
## Sfx instance (not the autoload) is created after the host-side setup, pointed at
## a temp folder of tiny wavs, so what it plays is exactly what the replay caused.

const MatchNetScript := preload("res://net/MatchNet.gd")
const SFX_SCRIPT: GDScript = preload("res://autoload/Sfx.gd")

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _nets: Array[MatchNetScript] = []
var _sfx: Node
var _audio: AudioConfig
var _sound_dir: String
var _settings_cfg_path: String


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_nets.clear()
	_sfx = null


func after_each() -> void:
	for net: MatchNetScript in _nets:
		if net != null and is_instance_valid(net):
			net.set_providers(null, null)
	_nets.clear()
	Match.set_net_provider(null)
	Match.set_replicator(null)
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()
	if _sound_dir != "":
		for filename: String in DirAccess.get_files_at(_sound_dir):
			DirAccess.remove_absolute(_sound_dir.path_join(filename))
		_sound_dir = ""
	if _settings_cfg_path != "":
		Settings.set_config_path_for_test(Settings.default_config_path())
		if FileAccess.file_exists(_settings_cfg_path):
			DirAccess.remove_absolute(_settings_cfg_path)
		_settings_cfg_path = ""
	await get_tree().process_frame


# --- Fixtures -----------------------------------------------------------------

func _build_world() -> void:
	var map: MapDef = load("res://config/maps/round_small.tres") as MapDef
	_field = Field.new()
	_field.map_def = map
	add_child_autofree(_field)
	_blocks_root = Node3D.new()
	add_child_autofree(_blocks_root)
	_registry = BlockRegistry.new()
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)


func _make_net(session: FakeNet) -> MatchNetScript:
	Match.set_net_provider(session)
	var node: MatchNetScript = MatchNetScript.new()
	node.set_process(false)
	add_child_autofree(node)
	node.set_providers(session, Match)
	_nets.append(node)
	return node


func _config(player_count: int) -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.map_variant = MatchConfig.MapVariant.ROUND
	config.map_size = MapDef.MapSize.SMALL
	config.player_count = player_count
	config.ai_count = 0
	config.team_mode = MatchConfig.TeamMode.OFF
	config.hot_seat = false
	config.block_timer = 6.0
	config.rng_seed = 4242
	config.game_mode = MatchConfig.GameMode.ELIMINATION
	config.round_timer_minutes = 5
	config.allow_mid_match_join = true
	return config


func _start_playing(config: MatchConfig) -> void:
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)
	assert_eq(Match.state(), Match.State.PLAYING, "fixture should reach PLAYING")


func _home(slot_id: int) -> Vector3:
	var home: Vector2 = Match.slot(slot_id).home_position
	return _field.to_global(Vector3(home.x, 0.0, home.y))


func _write_tiny_wav(path: String) -> void:
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	wav.stereo = false
	var data: PackedByteArray = PackedByteArray()
	data.resize(2205 * 2)
	wav.data = data
	assert_eq(wav.save_to_wav(path), OK, "fixture wav should save: %s" % path)


## A fresh Sfx with the drop, breakage and gift cues installed.
func _make_sfx() -> void:
	_settings_cfg_path = OS.get_user_data_dir().path_join("test_late_join_silence_settings.cfg")
	Settings.set_config_path_for_test(_settings_cfg_path)
	_audio = load("res://config/audio_config.tres").duplicate() as AudioConfig
	_audio.contextual_music_enabled = false
	_audio.bundled_theme = null
	_sfx = SFX_SCRIPT.new()
	_sfx.config = _audio
	add_child_autofree(_sfx)
	_sound_dir = OS.get_user_data_dir().path_join("test_late_join_silence_sfx")
	DirAccess.make_dir_recursive_absolute(_sound_dir)
	for filename: String in [_audio.drop_file, _audio.breakage_file, _audio.gift_spawn_file]:
		_write_tiny_wav(_sound_dir.path_join(filename))
	_sfx.set_root_dir_for_test(_sound_dir)


func _any_player_playing() -> bool:
	for player: AudioStreamPlayer in _sfx._sfx_players:
		if player.playing:
			return true
	return false


func _stop_all_players() -> void:
	for player: AudioStreamPlayer in _sfx._sfx_players:
		player.stop()


## The host side of a mid-match join: a world with bodies, an eliminated slot and a
## crate still falling, then the joiner's replay captured exactly as it goes on the
## wire (the end marker is deferred to the end of the frame). Leaves Match built and
## running on the host side; call _become_client() before applying the capture.
func _capture_host_replay(joiner_peer: int = 3, joiner_slot: int = 3) -> Array[Array]:
	_build_world()
	var host_session: FakeNet = FakeNet.host({1: 0, 2: 1}, [0])
	var host_net: MatchNetScript = _make_net(host_session)
	_start_playing(_config(4))
	assert_eq(host_net.submit_place(0, _home(0), 0, Quaternion.IDENTITY, false, Match.feed_seq(0)), PlacementRules.REASON_OK)
	host_net._handle_place_intent(2, 1, _home(1), 0, Quaternion.IDENTITY, Match.feed_seq(1))
	for _i: int in range(30):
		Match._process(1.0 / 60.0)
	Match._territory.flush_pending()
	assert_eq(Match.registry().all_blocks().size(), 2, "fixture placed two bodies")
	Match._lifecycle._eliminate_slot(2)
	Match._lifecycle._check_last_team_standing()
	assert_eq(Match.state(), Match.State.PLAYING, "three teams remain, the match runs on")
	Match._gifts._spawn_crate_at(Vector2(2.0, 1.0))
	assert_eq(Match.gift_states().size(), 1, "one crate is in flight")
	host_session.slots_by_peer[joiner_peer] = joiner_slot
	host_net.capture_replay = true
	host_net._on_net_peer_joined(joiner_peer, joiner_slot, "Latey")
	await get_tree().process_frame
	var capture: Array[Array] = host_net.replay_capture.duplicate()
	host_net.queue_free()
	await get_tree().process_frame
	return capture


func _become_client(slot_id: int) -> MatchNetScript:
	var client_net: MatchNetScript = _make_net(FakeNet.client(slot_id))
	client_net._on_net_mode_changed(Net.Mode.CLIENT)
	return client_net


func _apply(client_net: MatchNetScript, message: Array) -> void:
	client_net.callv(StringName(message[1]), message[2] as Array)


# --- The replay is silent --------------------------------------------------------

func test_the_replay_rebuilds_the_world_without_a_single_sound() -> void:
	var capture: Array[Array] = await _capture_host_replay()
	var client_net: MatchNetScript = _become_client(3)
	_make_sfx()

	# Positive control: the very handlers the replay triggers do sound when the
	# silence is not on, so the silence below is not a fixture artefact.
	_sfx._on_block_placed(null, &"cube")
	assert_true(_any_player_playing(), "a live drop sounds")
	_stop_all_players()
	_sfx._on_player_eliminated(1, 1)
	assert_true(_any_player_playing(), "a live elimination sounds")
	_stop_all_players()
	assert_eq(int(_sfx._last_gift_spawn_msec), -1, "the gift jingle has not played yet")

	watch_signals(Events)
	_apply(client_net, capture[0])
	assert_eq(StringName(capture[0][1]), &"net_match_start")
	assert_true(client_net.is_replaying_world(), "the replay's opening message turns the silence on")
	assert_true(_sfx._world_replay_silent, "Sfx heard it")
	for index: int in range(1, capture.size()):
		_apply(client_net, capture[index])
		assert_false(_any_player_playing(), "message %d (%s) made a sound" % [index, capture[index][1]])

	# The world was still restored through the same events a live match emits.
	assert_eq(get_signal_emit_count(Events, "block_placed"), 2, "both bodies rebuilt through block_placed")
	assert_gte(get_signal_emit_count(Events, "player_eliminated"), 1, "the dead slot replayed")
	assert_eq(get_signal_emit_count(Events, "gift_flight_spawned"), 1, "the falling crate replayed")
	assert_eq(Match.registry().all_blocks().size(), 2, "both bodies exist on the joiner")
	assert_false(Match.slot(2).home_flag_alive, "the eliminated slot is out on the joiner")
	assert_eq(int(_sfx._last_gift_spawn_msec), -1, "the gift jingle never played")

	# The silence is exactly the replay: on at the start, off at net_replay_end.
	assert_false(client_net.is_replaying_world(), "net_replay_end lifted it")
	assert_false(_sfx._world_replay_silent)
	assert_eq(get_signal_emit_count(Events, "world_replay_changed"), 2)
	assert_eq(get_signal_parameters(Events, "world_replay_changed", 0), [true])
	assert_eq(get_signal_parameters(Events, "world_replay_changed", 1), [false])
	assert_eq(client_net.last_replay_acknowledged, int((capture[capture.size() - 1][2] as Array)[0]))


func test_live_events_after_the_replay_still_sound() -> void:
	var capture: Array[Array] = await _capture_host_replay()
	var client_net: MatchNetScript = _become_client(3)
	_make_sfx()
	for message: Array in capture:
		_apply(client_net, message)
	assert_false(_any_player_playing(), "the replay itself was silent")
	assert_false(client_net.is_replaying_world())

	# A body the host places after the joiner's replay ended: the drop sounds.
	client_net.net_block_spawned(900, &"cube", 1, Vector3(1.0, 6.0, 1.0), Quaternion.IDENTITY)
	assert_not_null(Match.registry().block_for_net_id(900), "the live spawn is applied")
	assert_true(_any_player_playing(), "a live drop after the join sounds")
	_stop_all_players()

	# A live elimination: the breakage sounds.
	client_net.net_match_event(MatchNetScript.EVENT_PLAYER_ELIMINATED, [1, 1])
	assert_true(_any_player_playing(), "a live elimination after the join sounds")
	_stop_all_players()

	# A live crate flight: the jingle sounds.
	client_net.net_match_event(MatchNetScript.EVENT_GIFT_FLIGHT, [77, Vector3(3.0, 18.0, 1.0), Vector3(3.0, 0.0, 1.0)])
	assert_true(_any_player_playing(), "a live gift flight after the join sounds")


# --- The marker ----------------------------------------------------------------------

func test_the_replay_names_itself_in_its_opening_message() -> void:
	var capture: Array[Array] = await _capture_host_replay()
	var start_args: Array = capture[0][2]
	assert_eq(start_args.size(), 3, "net_match_start carries the replay id")
	var end_id: int = int((capture[capture.size() - 1][2] as Array)[0])
	assert_gt(end_id, 0)
	assert_eq(int(start_args[2]), end_id, "the id that opens the replay is the one that closes it")


func test_a_plain_match_start_is_not_a_replay() -> void:
	_build_world()
	var client_net: MatchNetScript = _make_net(FakeNet.client(1))
	client_net._on_net_mode_changed(Net.Mode.CLIENT)
	watch_signals(Events)
	client_net.net_match_start(_config(2).to_dict(), [])
	assert_false(client_net.is_replaying_world(), "the lobby's match start does not mute anything")
	assert_signal_not_emitted(Events, "world_replay_changed")


func test_the_host_never_mutes_itself() -> void:
	_build_world()
	var host_net: MatchNetScript = _make_net(FakeNet.host({1: 0}, [0]))
	watch_signals(Events)
	host_net.net_match_start(_config(2).to_dict(), [], 5)
	assert_false(host_net.is_replaying_world(), "a replay id is only ever honoured by a client")
	assert_signal_not_emitted(Events, "world_replay_changed")


# --- A replay that never completes must not mute the match -------------------------

func test_leaving_the_session_mid_replay_lifts_the_silence() -> void:
	var capture: Array[Array] = await _capture_host_replay()
	var client_net: MatchNetScript = _become_client(3)
	_make_sfx()
	_apply(client_net, capture[0])
	assert_true(_sfx._world_replay_silent)
	watch_signals(Events)
	client_net._on_net_mode_changed(Net.Mode.OFFLINE)
	assert_false(client_net.is_replaying_world())
	assert_false(_sfx._world_replay_silent, "Sfx hears the end too")
	assert_eq(get_signal_parameters(Events, "world_replay_changed", 0), [false])


func test_a_new_match_start_lifts_a_replay_that_never_ended() -> void:
	var capture: Array[Array] = await _capture_host_replay()
	var client_net: MatchNetScript = _become_client(3)
	_make_sfx()
	_apply(client_net, capture[0])
	assert_true(client_net.is_replaying_world())
	client_net.net_match_start(_config(2).to_dict(), [])
	assert_false(client_net.is_replaying_world(), "the broadcast restart is a full sync of its own")
	assert_false(_sfx._world_replay_silent)


func test_a_replay_that_outlives_the_ack_timeout_stops_muting() -> void:
	var capture: Array[Array] = await _capture_host_replay()
	var client_net: MatchNetScript = _become_client(3)
	_make_sfx()
	_apply(client_net, capture[0])
	client_net._tick_world_replay_expiry()
	assert_true(client_net.is_replaying_world(), "still inside the timeout")
	client_net._replaying_since_ms -= int(client_net.config.replay_ack_timeout * 1000.0) + 1
	client_net._tick_world_replay_expiry()
	assert_false(client_net.is_replaying_world(), "the host would have dropped this peer by now")
	assert_false(_sfx._world_replay_silent)


func test_only_the_matching_replay_end_lifts_the_silence() -> void:
	var capture: Array[Array] = await _capture_host_replay()
	var client_net: MatchNetScript = _become_client(3)
	_apply(client_net, capture[0])
	var replay_id: int = int((capture[0][2] as Array)[2])
	client_net.net_replay_end(replay_id + 1)
	assert_true(client_net.is_replaying_world(), "another replay's end does not end this one")
	client_net.net_replay_end(replay_id)
	assert_false(client_net.is_replaying_world())


# --- Impacts are not part of the replay -----------------------------------------

func test_impacts_are_not_replayed_to_the_joiner() -> void:
	_build_world()
	var host_session: FakeNet = FakeNet.host({1: 0, 2: 1}, [0])
	var host_net: MatchNetScript = _make_net(host_session)
	_start_playing(_config(4))
	host_net.capture_impacts = true
	host_net.collect_impact(6.0, Vector3(1.0, 2.0, 1.0), Time.get_ticks_msec())
	host_session.slots_by_peer[3] = 3
	host_net.capture_replay = true
	host_net._on_net_peer_joined(3, 3, "Latey")
	await get_tree().process_frame
	var capture: Array[Array] = host_net.replay_capture.duplicate()
	for message: Array in capture:
		assert_ne(StringName(message[1]), &"net_block_impacts", "no impact batch rides in the replay")
	host_net.queue_free()
	await get_tree().process_frame

	var client_net: MatchNetScript = _become_client(3)
	watch_signals(Events)
	for message: Array in capture:
		_apply(client_net, message)
	assert_signal_not_emitted(Events, "block_impacted", "the joiner hears no old thud")
	assert_signal_not_emitted(Events, "block_impacted_at")
	assert_eq(client_net.pending_impact_count(), 0, "and has none queued")
