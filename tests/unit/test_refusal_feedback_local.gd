extends GutTest
## Bontago-1pi.52 (owner playtest 2026-10-03, two players over direct IP: "the
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
## as tests/unit/test_remote_intent_validation.gd), a fresh Sfx instance on a
## temp folder (tests/unit/test_sfx.gd's pattern) and the real Rumble autoload
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
var _net: MatchNetScript
var _fake_net: FakeNet
var _tiny_map: MapDef
var _sfx: Node
var _audio_config: AudioConfig
var _tmp_dir: String
var _settings_cfg_path: String
var _rumble_calls: Array[Dictionary] = []
var _rejected_events: Array[int] = []
var _rejected_listener: Callable


func before_each() -> void:
	_settings_cfg_path = OS.get_user_data_dir().path_join("test_refusal_feedback_settings_tmp.cfg")
	_delete_if_exists(_settings_cfg_path)
	Settings.set_config_path_for_test(_settings_cfg_path)
	Settings.set_rumble_enabled(true)
	Settings.set_rumble_strength(1.0)

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

	_audio_config = load("res://config/audio_config.tres").duplicate() as AudioConfig
	_audio_config.contextual_music_enabled = false
	_audio_config.bundled_theme = null
	_sfx = autofree(SFX_SCRIPT.new())
	_sfx.config = _audio_config
	add_child_autofree(_sfx)
	_tmp_dir = OS.get_user_data_dir().path_join("test_refusal_feedback_tmp")
	DirAccess.make_dir_recursive_absolute(_tmp_dir)
	_write_tiny_wav(_tmp_dir.path_join(_audio_config.rejected_file))
	_sfx.set_root_dir_for_test(_tmp_dir)

	_rumble_calls = []
	Rumble.start_vibration_fn = Callable(self, "_record_rumble")
	Rumble.set_last_device_for_test(GAMEPAD_DEVICE, Settings.DEVICE_GAMEPAD)

	_rejected_events = []
	_rejected_listener = func(slot_id: int, _reason: StringName) -> void:
		_rejected_events.append(slot_id)
	Events.placement_rejected.connect(_rejected_listener)


func after_each() -> void:
	if Events.placement_rejected.is_connected(_rejected_listener):
		Events.placement_rejected.disconnect(_rejected_listener)
	if _net != null and is_instance_valid(_net):
		_net.set_providers(null, null)
	_net = null
	Net._mode = Net.Mode.OFFLINE
	Net._local_slot = 0
	Match.set_net_provider(null)
	Match.set_replicator(null)
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()
	Rumble.start_vibration_fn = Callable(Rumble, "_start_vibration_real")
	Rumble.set_last_device_for_test(Rumble.DEVICE_NONE, &"")
	for filename: String in DirAccess.get_files_at(_tmp_dir):
		DirAccess.remove_absolute(_tmp_dir.path_join(filename))
	Settings.set_config_path_for_test(Settings.default_config_path())
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


## A listen-server host (peer 1, slot 0) with one remote client (peer 2, slot 1).
func _make_host_net() -> MatchNetScript:
	var peer_slots: Dictionary = {HOST_PEER: HOST_SLOT, REMOTE_PEER: REMOTE_SLOT}
	_fake_net = FakeNet.host(peer_slots, [HOST_SLOT])
	_fake_net.slots_by_peer = peer_slots
	Match.set_net_provider(_fake_net)
	var node: MatchNetScript = MatchNetScript.new()
	node.set_process(false)
	add_child_autofree(node)
	node.set_providers(_fake_net, Match)
	_net = node
	# Sfx/Rumble read the real Net: a host drives slot 0 only.
	Net._mode = Net.Mode.HOST
	Net._local_slot = HOST_SLOT
	return node


## A client instance whose own seat is `local_slot_id`. Its MatchNet applies
## whatever the host sends through net_match_event().
func _make_client_net(local_slot_id: int) -> MatchNetScript:
	# A client mirrors a world the host built: start one as the host, then
	# swap the session (test_match_net.gd's own client fixtures do the same).
	Match.set_net_provider(FakeNet.host({}, [HOST_SLOT, REMOTE_SLOT]))
	_start_playing()
	_fake_net = FakeNet.client(local_slot_id)
	Match.set_net_provider(_fake_net)
	var node: MatchNetScript = MatchNetScript.new()
	node.set_process(false)
	add_child_autofree(node)
	node.set_providers(_fake_net, Match)
	_net = node
	Net._mode = Net.Mode.CLIENT
	Net._local_slot = local_slot_id
	return node


func _config(player_count: int = 2, ai_count: int = 0) -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = player_count
	config.ai_count = ai_count
	config.hot_seat = false
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
func _remote_refused_place(net: MatchNetScript) -> void:
	net._handle_place_intent(
		REMOTE_PEER, REMOTE_SLOT, _home_world_position(HOST_SLOT), 0, Quaternion.IDENTITY, Match.feed_seq(REMOTE_SLOT)
	)


func _assert_no_feedback_here(what: String) -> void:
	assert_false(_any_sfx_playing(), "%s: no refusal sound" % what)
	assert_eq(_rumble_calls.size(), 0, "%s: no refusal rumble" % what)


# --- host: a remote player's refusal ------------------------------------------


func test_host_hears_nothing_for_a_remote_clients_refused_placement() -> void:
	var net: MatchNetScript = _make_host_net()
	_start_playing()

	_remote_refused_place(net)

	assert_eq(int(net.reject_replies_by_peer.get(REMOTE_PEER, 0)), 1, "fixture: the host did refuse the remote's release")
	assert_eq(_rejected_events, [REMOTE_SLOT] as Array[int], "fixture: Match announced the refusal once")
	_assert_no_feedback_here("host, remote client's refusal")


func test_a_remote_refusal_goes_to_the_owning_peer_once_and_is_never_broadcast() -> void:
	var net: MatchNetScript = _make_host_net()
	_start_playing()

	_remote_refused_place(net)

	assert_eq(int(net.replicated_event_counts.get(MatchNetScript.EVENT_PLACEMENT_REJECTED, 0)), 0, "a refusal is never broadcast to every peer")
	assert_eq(int(net.reject_replies_by_peer.get(REMOTE_PEER, 0)), 1, "the owner gets exactly one reply (broadcast + targeted used to double it)")
	assert_eq(net.reject_replies_by_peer.size(), 1, "and nobody else is addressed")
	assert_eq(net.last_reject_reply[1], REMOTE_SLOT)


func test_a_remote_throw_refusal_goes_to_the_owning_peer_once_and_host_hears_nothing() -> void:
	var net: MatchNetScript = _make_host_net()
	_start_playing()
	# Queue a held special on the remote slot (test_match_throw.gd's own
	# _queue_special()) so the throw reaches the host's territory check.
	Match._gifts._ensure_capacity(REMOTE_SLOT)
	Match._gifts._held_specials[REMOTE_SLOT] = &"test_special"
	Match._feed._held_is_gift[REMOTE_SLOT] = true
	var off_disk: Vector3 = _home_world_position(REMOTE_SLOT) + Vector3(1000.0, 0.0, 1000.0)

	net._handle_throw_intent(
		REMOTE_PEER, REMOTE_SLOT, off_disk, 0, Quaternion.IDENTITY, Vector3(5.0, 0.0, 0.0), Match.feed_seq(REMOTE_SLOT)
	)

	assert_eq(_rejected_events, [REMOTE_SLOT] as Array[int], "fixture: the host refused a throw off the disk")
	assert_eq(int(net.replicated_event_counts.get(MatchNetScript.EVENT_PLACEMENT_REJECTED, 0)), 0)
	assert_eq(int(net.reject_replies_by_peer.get(REMOTE_PEER, 0)), 1)
	_assert_no_feedback_here("host, remote client's refused throw")


func test_a_throw_refused_without_a_held_special_replies_to_the_sender_once() -> void:
	var net: MatchNetScript = _make_host_net()
	_start_playing()

	net._handle_throw_intent(
		REMOTE_PEER, REMOTE_SLOT, _home_world_position(REMOTE_SLOT), 0, Quaternion.IDENTITY, Vector3.ZERO, Match.feed_seq(REMOTE_SLOT)
	)

	assert_eq(int(net.reject_replies_by_peer.get(REMOTE_PEER, 0)), 1, "Match emits nothing for NOT_A_SPECIAL, so only the tail replies")
	assert_eq(int(net.replicated_event_counts.get(MatchNetScript.EVENT_PLACEMENT_REJECTED, 0)), 0)
	_assert_no_feedback_here("host, remote client's no-special throw")


func test_a_refusal_the_host_wire_check_makes_still_reaches_only_the_sender() -> void:
	var net: MatchNetScript = _make_host_net()
	_start_playing()

	# A negative feed_seq is refused at the wire; Match never sees it, so no
	# Events.placement_rejected fires on the host at all.
	net._handle_place_intent(REMOTE_PEER, REMOTE_SLOT, _home_world_position(REMOTE_SLOT), 0, Quaternion.IDENTITY, -1)

	assert_eq(_rejected_events.size(), 0)
	assert_eq(int(net.reject_replies_by_peer.get(REMOTE_PEER, 0)), 1)
	_assert_no_feedback_here("host, wire-refused intent")


func test_no_reply_is_addressed_to_a_peer_that_already_left() -> void:
	var net: MatchNetScript = _make_host_net()
	_start_playing()
	_fake_net.slots_by_peer.erase(REMOTE_PEER)

	Match.request_place(REMOTE_SLOT, _home_world_position(HOST_SLOT), 0, Quaternion.IDENTITY, false, Match.feed_seq(REMOTE_SLOT))

	assert_eq(_rejected_events, [REMOTE_SLOT] as Array[int], "fixture: the host still refused it")
	assert_eq(net.reject_replies_by_peer.size(), 0, "a seat with no peer behind it is nobody's to notify")
	_assert_no_feedback_here("host, refusal for a vacated seat")


# --- host: its own refusal ----------------------------------------------------


func test_the_hosts_own_refusal_still_plays_sound_and_rumble_and_is_not_sent_anywhere() -> void:
	var net: MatchNetScript = _make_host_net()
	_start_playing()

	Match.request_place(HOST_SLOT, _home_world_position(REMOTE_SLOT), 0, Quaternion.IDENTITY, false, Match.feed_seq(HOST_SLOT))

	assert_eq(_rejected_events, [HOST_SLOT] as Array[int], "fixture: the host's own release was refused")
	assert_true(_any_sfx_playing(), "the host hears its own refusal")
	assert_eq(_rumble_calls.size(), 1, "the host's pad rumbles for its own refusal")
	assert_eq(net.reject_replies_by_peer.size(), 0, "nothing goes to the remote peer for the host's refusal")
	assert_eq(int(net.replicated_event_counts.get(MatchNetScript.EVENT_PLACEMENT_REJECTED, 0)), 0, "and nothing is broadcast")


# --- client -------------------------------------------------------------------


func test_a_client_gets_its_own_refusal_as_sound_and_rumble() -> void:
	var net: MatchNetScript = _make_client_net(REMOTE_SLOT)

	net.net_match_event(MatchNetScript.EVENT_PLACEMENT_REJECTED, [REMOTE_SLOT, PlacementRules.REASON_CONTESTED])

	assert_eq(_rejected_events, [REMOTE_SLOT] as Array[int], "the client's own refusal reaches its Events bus")
	assert_true(_any_sfx_playing(), "the refused client hears it")
	assert_eq(_rumble_calls.size(), 1, "and its pad rumbles")


func test_a_client_ignores_a_refusal_for_someone_elses_slot() -> void:
	var net: MatchNetScript = _make_client_net(REMOTE_SLOT)

	# What an older build's host broadcast for the host's own refusal looks like.
	net.net_match_event(MatchNetScript.EVENT_PLACEMENT_REJECTED, [HOST_SLOT, PlacementRules.REASON_CONTESTED])

	assert_eq(_rejected_events.size(), 0, "another seat's refusal never reaches this client's Events bus")
	_assert_no_feedback_here("client, host's refusal")


func test_a_client_stays_silent_even_if_another_slots_refusal_is_emitted_locally() -> void:
	_make_client_net(REMOTE_SLOT)

	Events.placement_rejected.emit(HOST_SLOT, PlacementRules.REASON_CONTESTED)

	_assert_no_feedback_here("client, foreign slot on the local bus")


func test_a_client_drops_a_malformed_refusal_payload() -> void:
	var net: MatchNetScript = _make_client_net(REMOTE_SLOT)
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


# --- bots and hot-seat --------------------------------------------------------


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


func test_every_hot_seat_human_hears_their_own_refusal() -> void:
	# Offline hot-seat: one machine, several local humans.
	_start_playing(2, 0)

	Match.request_place(REMOTE_SLOT, _home_world_position(HOST_SLOT), 0, Quaternion.IDENTITY, false, Match.feed_seq(REMOTE_SLOT))

	assert_eq(_rejected_events, [REMOTE_SLOT] as Array[int])
	assert_true(_any_sfx_playing(), "hot-seat player 2's refusal sounds on the shared machine")
	assert_eq(_rumble_calls.size(), 1)


func test_a_bot_seat_on_a_host_is_never_sent_a_reply() -> void:
	var net: MatchNetScript = _make_host_net()
	_start_playing(3, 1)
	assert_true(Match.slot(2).is_bot, "fixture: slot 2 is the bot")

	Match.request_place(2, _home_world_position(HOST_SLOT), 0, Quaternion.IDENTITY, false, Match.feed_seq(2))

	assert_eq(_rejected_events, [2] as Array[int], "fixture: the bot's release was refused")
	assert_eq(net.reject_replies_by_peer.size(), 0, "a bot has no peer to tell")
	_assert_no_feedback_here("host, bot refusal")
