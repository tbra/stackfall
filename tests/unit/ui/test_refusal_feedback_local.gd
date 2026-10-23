extends GutTest
## (two players over direct IP: "the
## host could hear my block rejected sound"). A placement refusal is decided on
## the host and replicated as Events.placement_rejected; its feedback (sound,
## rumble, HUD toast, ghost flash) belongs only to the refused player's own
## machine:
##
##   - the host must not hear/feel a remote client's refusal;
##   - a client must not hear/feel the host's refusal, nor another client's;
##   - the owning client still gets its own refusal, exactly once (it used to
##     get a broadcast copy AND the targeted reply);
##   - a bot's refusal gives nobody feedback.
##
## These drive the real Match through MatchNet with a faked Net (the same shape
## as tests/unit/net/test_remote_intent_validation.gd), a fresh Sfx instance on a
## temp folder (tests/unit/audio/test_sfx.gd's pattern) and the real Rumble autoload
## with its vibration seam swapped for a recorder. Net's own mode is poked
## directly (test_sfx.gd's gift_claimed tests' convention) because Sfx and
## Rumble read the real Net autoload's is_local_slot().

const MatchNetScript := preload("res://net/MatchNet.gd")
const SFX_SCRIPT: GDScript = preload("res://autoload/Sfx.gd")

const HOST_PEER: int = 1
const REMOTE_PEER: int = 2
const HOST_SLOT: int = 0
const REMOTE_SLOT: int = 1
const GAMEPAD_DEVICE: int = 0

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _fake_net: FakeNet
var _tiny_map: MapDef
var _sfx: Node
var _audio_config: AudioConfig
var _tmp_dir: String
var _settings_cfg_path: String
var _rumble_calls: Array[Dictionary] = []
var _rejected_events: Array[int] = []
## What the host's intent door sent out through its Seams: [peer_id, method, args] per addressed send.
var _replies: Array[Array] = []
var _broadcasts: int = 0
var _rejected_listener: Callable

var _loopback: LoopbackSession


func before_each() -> void:
	_loopback = LoopbackSession.new(self)
	_settings_cfg_path = OS.get_user_data_dir().path_join("test_refusal_feedback_settings_tmp.cfg")
	_delete_if_exists(_settings_cfg_path)
	Settings.set_config_path_for_test(_settings_cfg_path)
	Settings.set_rumble_enabled(true)
	Settings.set_rumble_strength(1.0)

	Match.set_process(false)
	Match.abort_match()
	_tiny_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _tiny_map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)

	_audio_config = load("res://config/audio/audio_config.tres").duplicate() as AudioConfig
	_audio_config.contextual_music_enabled = false
	_audio_config.bundled_theme = null
	_audio_config.bundled_theme_path = ""
	_sfx = autofree(SFX_SCRIPT.new())
	_sfx.config = _audio_config
	add_child_autofree(_sfx)
	_tmp_dir = OS.get_user_data_dir().path_join("test_refusal_feedback_tmp")
	DirAccess.make_dir_recursive_absolute(_tmp_dir)
	_write_tiny_wav(_tmp_dir.path_join(_audio_config.rejected_file))
	_sfx.set_root_dir_for_test(_tmp_dir)

	_rumble_calls = []
	Rumble.start_vibration_fn = Callable(self, "_record_rumble")
	var press: InputEventJoypadButton = InputEventJoypadButton.new()
	press.device = GAMEPAD_DEVICE
	Rumble._input(press)

	_rejected_events = []
	_rejected_listener = func(slot_id: int, _reason: StringName) -> void:
		_rejected_events.append(slot_id)
	Events.placement_rejected.connect(_rejected_listener)


func after_each() -> void:
	if Events.placement_rejected.is_connected(_rejected_listener):
		Events.placement_rejected.disconnect(_rejected_listener)
	await _loopback.end()
	Match._net_provider = null
	Match.set_replicator(null)
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()
	Rumble.start_vibration_fn = Callable(Rumble, "_start_vibration_real")
	Rumble._last_device_id = Rumble.DEVICE_NONE
	Rumble._last_family = &""
	for filename: String in DirAccess.get_files_at(_tmp_dir):
		DirAccess.remove_absolute(_tmp_dir.path_join(filename))
	Settings.set_config_path_for_test(Settings.REAL_CONFIG_PATH)
	_delete_if_exists(_settings_cfg_path)


func _delete_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _record_rumble(device: int, weak_magnitude: float, strong_magnitude: float, duration_s: float) -> void:
	_rumble_calls.append({
		"device": device, "weak": weak_magnitude, "strong": strong_magnitude, "duration": duration_s
	})


func _write_tiny_wav(path: String) -> void:
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	wav.stereo = false
	var data: PackedByteArray = PackedByteArray()
	data.resize(2205 * 2)
	wav.data = data
	assert_eq(wav.save_to_wav(path), OK, "fixture wav should save cleanly: %s" % path)


func _any_sfx_playing() -> bool:
	for player: AudioStreamPlayer in _sfx._sfx_players:
		if player.playing:
			return true
	return false


## The host's intent door for a listen-server host (peer 1, slot 0) with one remote client (peer 2,
## slot 1), bound to the real Match with spy Seams: every reply it addresses lands in _replies.
func _make_host_gateway() -> MatchIntentGateway:
	var peer_slots: Dictionary = {HOST_PEER: HOST_SLOT, REMOTE_PEER: REMOTE_SLOT}
	_fake_net = FakeNet.host(peer_slots, [HOST_SLOT])
	_fake_net.slots_by_peer = peer_slots
	Match._net_provider = _fake_net
	_replies = []
	_broadcasts = 0
	var seams: MatchIntentGateway.Seams = MatchIntentGateway.Seams.new()
	seams.can_send = func() -> bool: return true
	seams.send_to_host = func(_method: StringName, _args: Array) -> void: pass
	seams.send_to_peer = func(peer_id: int, method: StringName, args: Array) -> bool:
		_replies.append([peer_id, method, args])
		return true
	seams.broadcast = func(_method: StringName, _args: Array) -> void: _broadcasts += 1
	seams.now_s = func() -> float: return 0.0
	seams.is_replay_pending = func(_peer_id: int) -> bool: return false
	seams.store_cursor = func(_slot_id: int, _origin: Vector3, _orientation_index: int, _free_quat: Quaternion) -> void: pass
	var gateway: MatchIntentGateway = MatchIntentGateway.new(_fake_net, Match, preload("res://config/net/net_config.tres"), NetCounters.new(), seams)
	assert_true(gateway.is_valid(), "fixture: the gateway bound the faked session and the real Match")
	# Sfx/Rumble read the real Net: a host drives slot 0 only.
	assert_eq(Net.host_game(AgentProbe.free_udp_port(), "", false), OK)
	assert_eq(Net.local_slot(), HOST_SLOT)
	return gateway


## What the owning client does with the one reply the host addressed to it: its own MatchNet applies
## the event, and the refusal reaches that client's Events bus.
func _deliver_reply_to_remote_client() -> void:
	assert_eq(_replies.size(), 1, "fixture: exactly one reply was addressed")
	var reply: Array = _replies[0]
	_rejected_events.clear()
	_fake_net = FakeNet.client(REMOTE_SLOT)
	Match._net_provider = _fake_net
	var client: MatchNetScript = MatchNetScript.new()
	client.set_process(false)
	add_child_autofree(client)
	assert_true(client.bind_ports(SessionPort.new(_fake_net), MatchHostPort.new(Match), MatchReplicaPort.new(Match)))
	client.net_match_event(reply[2][0], reply[2][1])


## A client instance whose own seat is `local_slot_id`. Its MatchNet applies
## whatever the host sends through net_match_event().
func _make_client_net(local_slot_id: int) -> MatchNetScript:
	# A real client of a loopback host: the first joiner always takes REMOTE_SLOT.
	assert_eq(local_slot_id, REMOTE_SLOT)
	assert_true(await _loopback.join_net_as_client(), "fixture: the Net autoload is a seated client")
	# A client mirrors a world the host built: start one as the host, then
	# swap the session (test_match_net.gd's own client fixtures do the same).
	Match._net_provider = FakeNet.host({}, [HOST_SLOT, REMOTE_SLOT])
	_start_playing()
	_fake_net = FakeNet.client(local_slot_id)
	Match._net_provider = _fake_net
	var node: MatchNetScript = MatchNetScript.new()
	node.set_process(false)
	add_child_autofree(node)
	assert_true(node.bind_ports(SessionPort.new(_fake_net), MatchHostPort.new(Match), MatchReplicaPort.new(Match)))
	return node


func _config(player_count: int = 2, ai_count: int = 0) -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = player_count
	config.ai_count = ai_count
	config.block_timer = 6.0
	config.rng_seed = 4242
	return config


func _start_playing(player_count: int = 2, ai_count: int = 0) -> void:
	Match.start_match(_config(player_count, ai_count))
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)
	assert_eq(Match.state(), Match.State.PLAYING, "fixture should reach PLAYING")
	# Match start already rumbled/ticked for the first issued blocks.
	_rumble_calls.clear()
	_rejected_events.clear()


func _home_world_position(slot_id: int) -> Vector3:
	var home: Vector2 = Match.slot(slot_id).home_position
	return _field.to_global(Vector3(home.x, 0.0, home.y))


## The remote client (peer 2) releases its block on the host's own home flag:
## enemy territory, so the host refuses it.
func _remote_refused_place(gateway: MatchIntentGateway) -> void:
	gateway.handle_place(
		REMOTE_PEER, REMOTE_SLOT, _home_world_position(HOST_SLOT), 0, Quaternion.IDENTITY, Match.feed_seq(REMOTE_SLOT)
	)


func _assert_no_feedback_here(what: String) -> void:
	assert_false(_any_sfx_playing(), "%s: no refusal sound" % what)
	assert_eq(_rumble_calls.size(), 0, "%s: no refusal rumble" % what)


# --- host: a remote player's refusal ------------------------------------------


func test_host_hears_nothing_for_a_remote_clients_refused_placement() -> void:
	var gateway: MatchIntentGateway = _make_host_gateway()
	_start_playing()

	_remote_refused_place(gateway)

	assert_eq(_replies.size(), 1, "fixture: the host did refuse the remote's release")
	assert_eq(_replies[0][0], REMOTE_PEER, "fixture: and told the remote")
	assert_eq(_rejected_events, [REMOTE_SLOT] as Array[int], "fixture: Match announced the refusal once")
	_assert_no_feedback_here("host, remote client's refusal")


func test_a_remote_refusal_goes_to_the_owning_peer_once_and_is_never_broadcast() -> void:
	var gateway: MatchIntentGateway = _make_host_gateway()
	_start_playing()

	_remote_refused_place(gateway)

	assert_eq(_broadcasts, 0, "a refusal is never broadcast to every peer")
	assert_eq(_replies.size(), 1, "the owner gets exactly one reply (broadcast + targeted used to double it) and nobody else is addressed")
	assert_eq(_replies[0][0], REMOTE_PEER)
	assert_eq(_replies[0][1], &"net_match_event")
	assert_eq(_replies[0][2][1][0], REMOTE_SLOT)
	_deliver_reply_to_remote_client()
	assert_eq(_rejected_events, [REMOTE_SLOT] as Array[int], "the owning client's own bus announces the refusal")


func test_a_remote_throw_refusal_goes_to_the_owning_peer_once_and_host_hears_nothing() -> void:
	var gateway: MatchIntentGateway = _make_host_gateway()
	_start_playing()
	# Queue a held special on the remote slot (test_match_throw.gd's own
	# _queue_special()) so the throw reaches the host's territory check.
	Match._gifts._ensure_capacity(REMOTE_SLOT)
	Match._gifts._held_specials[REMOTE_SLOT] = &"test_special"
	Match._feed._held_is_gift[REMOTE_SLOT] = true
	var off_disk: Vector3 = _home_world_position(REMOTE_SLOT) + Vector3(1000.0, 0.0, 1000.0)

	gateway.handle_throw(
		REMOTE_PEER, REMOTE_SLOT, off_disk, 0, Quaternion.IDENTITY, Vector3(0.0, -0.5, -1.0).normalized(), Match.feed_seq(REMOTE_SLOT)
	)

	assert_eq(_rejected_events, [REMOTE_SLOT] as Array[int], "fixture: the host refused a throw off the disk")
	assert_eq(_broadcasts, 0)
	assert_eq(_replies.size(), 1)
	assert_eq(_replies[0][0], REMOTE_PEER)
	_assert_no_feedback_here("host, remote client's refused throw")
	_deliver_reply_to_remote_client()
	assert_eq(_rejected_events, [REMOTE_SLOT] as Array[int], "the owning client hears its refused throw")


func test_the_hosts_own_refusal_still_plays_sound_and_rumble_and_is_not_sent_anywhere() -> void:
	_make_host_gateway()
	_start_playing()

	Match.request_place(HOST_SLOT, _home_world_position(REMOTE_SLOT), 0, Quaternion.IDENTITY, false, Match.feed_seq(HOST_SLOT))

	assert_eq(_rejected_events, [HOST_SLOT] as Array[int], "fixture: the host's own release was refused")
	assert_true(_any_sfx_playing(), "the host hears its own refusal")
	assert_eq(_rumble_calls.size(), 1, "the host's pad rumbles for its own refusal")
	assert_eq(_replies.size(), 0, "nothing goes to the remote peer for the host's refusal")
	assert_eq(_broadcasts, 0, "and nothing is broadcast")


# --- client -------------------------------------------------------------------


func test_a_client_ignores_a_refusal_for_someone_elses_slot() -> void:
	var net: MatchNetScript = await _make_client_net(REMOTE_SLOT)

	# What an older build's host broadcast for the host's own refusal looks like.
	net.net_match_event(MatchNetScript.EVENT_PLACEMENT_REJECTED, [HOST_SLOT, PlacementRules.REASON_CONTESTED])

	assert_eq(_rejected_events.size(), 0, "another seat's refusal never reaches this client's Events bus")
	_assert_no_feedback_here("client, host's refusal")


func test_a_client_drops_a_malformed_refusal_payload() -> void:
	var net: MatchNetScript = await _make_client_net(REMOTE_SLOT)
	var payloads: Array = [
		[],
		[REMOTE_SLOT],
		["1", PlacementRules.REASON_CONTESTED],
		[REMOTE_SLOT, 7],
		[-1, PlacementRules.REASON_CONTESTED],
		[Match.slot_count(), PlacementRules.REASON_CONTESTED],
		[REMOTE_SLOT, "x".repeat(MatchNetScript.REJECT_REASON_MAX_LENGTH + 1)],
	]

	for payload: Array in payloads:
		net.net_match_event(MatchNetScript.EVENT_PLACEMENT_REJECTED, payload)

	assert_eq(_rejected_events.size(), 0, "no malformed refusal may reach the client's feedback")
	_assert_no_feedback_here("client, malformed refusals")


# --- bots and single-PC play --------------------------------------------------


func test_a_bots_refusal_gives_no_feedback_but_a_local_humans_does() -> void:
	# Offline: Net.is_local_slot() is true for every slot, so only the bot flag
	# keeps a bot's refused release (slot 1 here) silent.
	_start_playing(2, 1)
	assert_true(Match.slot(1).is_bot, "fixture: slot 1 is the bot")

	Match.request_place(1, _home_world_position(HOST_SLOT), 0, Quaternion.IDENTITY, false, Match.feed_seq(1))

	assert_eq(_rejected_events, [1] as Array[int], "fixture: the bot's release was refused")
	_assert_no_feedback_here("bot refusal")

	Match.request_place(HOST_SLOT, _home_world_position(1), 0, Quaternion.IDENTITY, false, Match.feed_seq(HOST_SLOT))

	assert_eq(_rejected_events, [1, HOST_SLOT] as Array[int], "fixture: the human's release was refused too")
	assert_true(_any_sfx_playing(), "the local human still hears their own refusal")
	assert_eq(_rumble_calls.size(), 1)
