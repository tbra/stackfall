extends GutTest
## Bontago-1pi.52 (scope widened by the owner: "before it, every refusal was
## broadcast to all peers -- check if other sounds and effects have the same
## issue"). The audit of every feedback trigger (see the bead's comment) found
## these PERSONAL reactions that still reached the wrong machine or seat:
##
##   - Rumble's "your next block arrived" tick, "you were eliminated" pulse and
##     win/lose pulse tested Net.is_local_slot() alone, which is true for EVERY
##     slot offline, bots included: a solo game against bots buzzed the pad for
##     each bot's feed, elimination and (as the first local seat) win/loss;
##   - Sfx's gift-claim chime looped the same way, so a bot's claim chimed for
##     the human;
##   - the host broadcast Events.placement_relocated (a cursor/camera jump that
##     belongs to the owning seat) to every client, and a client applied
##     whatever slot and point arrived unchecked.
##
## WORLD reactions (impacts, drop thuds, specials, weather, goal capture,
## eliminations' breakage) stay on every machine and are not touched here.
##
## Same fixtures as tests/unit/test_refusal_feedback_local.gd: the real Match
## through MatchNet with a faked Net, a fresh Sfx on a temp folder, the real
## Rumble with its vibration seam swapped for a recorder. The Sfx/Rumble hooks
## are invoked directly (their Events connections are one line each) so no
## other autoload's reaction to the same signal runs.

const MatchNetScript := preload("res://net/MatchNet.gd")
const SFX_SCRIPT: GDScript = preload("res://autoload/Sfx.gd")

const HOST_PEER: int = 1
const REMOTE_PEER: int = 2
const HOST_SLOT: int = 0
const REMOTE_SLOT: int = 1
const GAMEPAD_DEVICE: int = 0
const GIFT_ID: int = 7
const SOME_SPECIAL: StringName = &"bomb"
const RELOCATED_POINT: Vector2 = Vector2(3.0, -2.0)

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


func before_each() -> void:
	_settings_cfg_path = OS.get_user_data_dir().path_join("test_personal_feedback_settings_tmp.cfg")
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
	_audio_config.bundled_theme_path = ""
	_sfx = autofree(SFX_SCRIPT.new())
	_sfx.config = _audio_config
	add_child_autofree(_sfx)
	_tmp_dir = OS.get_user_data_dir().path_join("test_personal_feedback_tmp")
	DirAccess.make_dir_recursive_absolute(_tmp_dir)
	_write_tiny_wav(_tmp_dir.path_join(_audio_config.gift_claimed_file))
	_sfx.set_root_dir_for_test(_tmp_dir)

	_rumble_calls = []
	Rumble.start_vibration_fn = Callable(self, "_record_rumble")
	Rumble.set_last_device_for_test(GAMEPAD_DEVICE, Settings.DEVICE_GAMEPAD)


func after_each() -> void:
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


## A client instance whose own seat is `local_slot_id`.
func _make_client_net(local_slot_id: int) -> MatchNetScript:
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


## Runs `config` to PLAYING. `keep_start_feedback` leaves whatever the match
## start itself made the pad do in _rumble_calls (the first block of every slot
## is issued at that moment), otherwise it is cleared.
func _start_playing(player_count: int = 2, ai_count: int = 0, keep_start_feedback: bool = false) -> void:
	_run_to_playing(_config(player_count, ai_count), keep_start_feedback)


func _run_to_playing(config: MatchConfig, keep_start_feedback: bool = false) -> void:
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)
	assert_eq(Match.state(), Match.State.PLAYING, "fixture should reach PLAYING")
	if not keep_start_feedback:
		_rumble_calls.clear()


# --- Rumble: "your next block arrived" tick -----------------------------------


func test_offline_match_start_ticks_the_pad_for_the_human_seat_only() -> void:
	# Offline Net.is_local_slot() is true for every slot, so a bot's first block
	# used to buzz the human's pad as well.
	_start_playing(2, 1, true)
	assert_true(Match.slot(1).is_bot, "fixture: slot 1 is the bot")

	assert_eq(_rumble_calls.size(), 1, "one tick: the human's own first block, not the bot's")


func test_a_bots_next_block_never_ticks_the_pad_offline() -> void:
	_start_playing(2, 1)

	Rumble._on_feed_block_issued(1, &"", &"")

	assert_eq(_rumble_calls.size(), 0, "offline bot feed")

	Rumble._on_feed_block_issued(HOST_SLOT, &"", &"")

	assert_eq(_rumble_calls.size(), 1, "the human's own feed still ticks")


func test_a_hosts_pad_ticks_for_its_own_seat_and_not_for_a_remote_clients() -> void:
	_make_host_net()
	_start_playing()

	Rumble._on_feed_block_issued(REMOTE_SLOT, &"", &"")
	assert_eq(_rumble_calls.size(), 0, "host, remote client's next block")

	Rumble._on_feed_block_issued(HOST_SLOT, &"", &"")
	assert_eq(_rumble_calls.size(), 1, "host, its own next block")


func test_a_clients_pad_ticks_for_its_own_seat_and_not_for_the_hosts() -> void:
	_make_client_net(REMOTE_SLOT)

	Rumble._on_feed_block_issued(HOST_SLOT, &"", &"")
	assert_eq(_rumble_calls.size(), 0, "client, host's next block")

	Rumble._on_feed_block_issued(REMOTE_SLOT, &"", &"")
	assert_eq(_rumble_calls.size(), 1, "client, its own next block")


# --- Rumble: elimination ------------------------------------------------------


func test_a_bots_elimination_never_buzzes_the_human_pad_offline() -> void:
	_start_playing(2, 1)

	Rumble._on_player_eliminated(1, 1)

	assert_eq(_rumble_calls.size(), 0, "offline bot elimination")

	Rumble._on_player_eliminated(HOST_SLOT, 0)

	assert_eq(_rumble_calls.size(), 1, "the human's own elimination still buzzes")


func test_an_elimination_buzzes_only_the_eliminated_players_own_machine() -> void:
	_make_host_net()
	_start_playing()

	Rumble._on_player_eliminated(REMOTE_SLOT, REMOTE_SLOT)
	assert_eq(_rumble_calls.size(), 0, "host, remote client eliminated")

	Rumble._on_player_eliminated(HOST_SLOT, HOST_SLOT)
	assert_eq(_rumble_calls.size(), 1, "host, itself eliminated")


# --- Rumble: match end --------------------------------------------------------


func test_the_match_end_pulse_is_the_local_humans_not_a_bot_seats() -> void:
	# Bots are always the last seats, so the first local seat is a human in a
	# real match; flipping the flag puts a bot first to prove the loop skips it.
	_start_playing(3, 0)
	Match.slot(0).is_bot = true

	Rumble._on_match_won(1)

	assert_eq(_rumble_calls.size(), 1, "the first local HUMAN seat (slot 1) gets the pulse")
	assert_almost_eq(float(_rumble_calls[0]["weak"]), Rumble.config.match_won_weak_magnitude, 0.0001, "slot 1 is on the winning team")


func test_a_match_with_only_bot_seats_never_buzzes_a_pad() -> void:
	_start_playing(2, 0)
	Match.slot(0).is_bot = true
	Match.slot(1).is_bot = true

	Rumble._on_match_won(0)

	assert_eq(_rumble_calls.size(), 0, "no human seat on this machine: nothing to buzz")


func test_a_host_wins_or_loses_on_its_own_seat_only() -> void:
	_make_host_net()
	_start_playing()

	Rumble._on_match_won(REMOTE_SLOT)

	assert_eq(_rumble_calls.size(), 1)
	assert_almost_eq(float(_rumble_calls[0]["weak"]), Rumble.config.match_lost_weak_magnitude, 0.0001, "the remote's win is the host's loss")


# --- Sfx: gift claimed --------------------------------------------------------


func test_a_bots_gift_claim_never_chimes_for_the_human_offline() -> void:
	_start_playing(2, 1)
	assert_true(Match.slot(1).is_bot, "fixture: slot 1 is the bot")

	_sfx._on_gift_claimed(GIFT_ID, 1, SOME_SPECIAL)

	assert_false(_any_sfx_playing(), "offline bot claim (every team-of-one is on its own team)")

	_sfx._on_gift_claimed(GIFT_ID, HOST_SLOT, SOME_SPECIAL)

	assert_true(_any_sfx_playing(), "the human's own claim still chimes")


func test_a_remote_clients_claim_does_not_chime_for_an_opposing_host() -> void:
	_make_host_net()
	_start_playing()

	_sfx._on_gift_claimed(GIFT_ID, REMOTE_SLOT, SOME_SPECIAL)

	assert_false(_any_sfx_playing(), "host, an opponent's claim")

	_sfx._on_gift_claimed(GIFT_ID, HOST_SLOT, SOME_SPECIAL)

	assert_true(_any_sfx_playing(), "host, its own claim")


func test_a_teammates_claim_still_chimes_team_wide() -> void:
	# Bontago-keo.17 owner decision "b": a claim is a team notification, so a
	# teammate hears it. Slots 0 and 2 are one team, 1 and 3 the other.
	_make_host_net()
	var config: MatchConfig = _config(4, 0)
	config.team_mode = MatchConfig.TeamMode.TEAMS_2
	_run_to_playing(config)

	_sfx._on_gift_claimed(GIFT_ID, 1, SOME_SPECIAL)
	assert_false(_any_sfx_playing(), "host (team 0), the other team's claim")

	_sfx._on_gift_claimed(GIFT_ID, 2, SOME_SPECIAL)
	assert_true(_any_sfx_playing(), "host (team 0), its teammate's claim")


# --- MatchNet: placement_relocated goes to the owning seat only ---------------


func test_a_remote_clients_relocation_goes_to_that_peer_alone() -> void:
	var net: MatchNetScript = _make_host_net()
	_start_playing()

	Events.placement_relocated.emit(REMOTE_SLOT, RELOCATED_POINT)

	assert_eq(int(net.replicated_event_counts.get(MatchNetScript.EVENT_PLACEMENT_RELOCATED, 0)), 0, "never broadcast to every peer")
	assert_eq(int(net.relocate_replies_by_peer.get(REMOTE_PEER, 0)), 1, "the owner is told exactly once")
	assert_eq(net.relocate_replies_by_peer.size(), 1, "and nobody else is addressed")
	assert_eq(net.last_relocate_reply, [REMOTE_PEER, REMOTE_SLOT, RELOCATED_POINT])


func test_the_hosts_own_and_a_bots_relocation_are_never_sent_anywhere() -> void:
	var net: MatchNetScript = _make_host_net()
	_start_playing(3, 1)
	assert_true(Match.slot(2).is_bot, "fixture: slot 2 is the bot")

	Events.placement_relocated.emit(HOST_SLOT, RELOCATED_POINT)
	Events.placement_relocated.emit(2, RELOCATED_POINT)

	assert_eq(int(net.replicated_event_counts.get(MatchNetScript.EVENT_PLACEMENT_RELOCATED, 0)), 0, "nothing broadcast")
	assert_eq(net.relocate_replies_by_peer.size(), 0, "the host's seat reacts to the local emit; a bot has no peer")


func test_no_relocation_is_addressed_to_a_peer_that_already_left() -> void:
	var net: MatchNetScript = _make_host_net()
	_start_playing()
	_fake_net.slots_by_peer.erase(REMOTE_PEER)

	Events.placement_relocated.emit(REMOTE_SLOT, RELOCATED_POINT)

	assert_eq(net.relocate_replies_by_peer.size(), 0, "a vacated seat is nobody's to notify")


func test_a_client_applies_its_own_relocation() -> void:
	var net: MatchNetScript = _make_client_net(REMOTE_SLOT)
	watch_signals(Events)

	net.net_match_event(MatchNetScript.EVENT_PLACEMENT_RELOCATED, [REMOTE_SLOT, RELOCATED_POINT])

	assert_signal_emitted_with_parameters(Events, "placement_relocated", [REMOTE_SLOT, RELOCATED_POINT])


func test_a_client_ignores_a_relocation_for_someone_elses_seat() -> void:
	var net: MatchNetScript = _make_client_net(REMOTE_SLOT)
	watch_signals(Events)

	# What an older build's host broadcast for the host's own auto-drop looks like.
	net.net_match_event(MatchNetScript.EVENT_PLACEMENT_RELOCATED, [HOST_SLOT, RELOCATED_POINT])

	assert_signal_not_emitted(Events, "placement_relocated")


func test_a_client_drops_a_malformed_relocation_payload() -> void:
	var net: MatchNetScript = _make_client_net(REMOTE_SLOT)
	watch_signals(Events)
	var payloads: Array = [
		[],
		[REMOTE_SLOT],
		["1", RELOCATED_POINT],
		[REMOTE_SLOT, "x"],
		[REMOTE_SLOT, Vector3.ZERO],
		[-1, RELOCATED_POINT],
		[Match.slot_count(), RELOCATED_POINT],
		[REMOTE_SLOT, Vector2(INF, 0.0)],
		[REMOTE_SLOT, Vector2(0.0, NAN)],
		[REMOTE_SLOT, Vector2(1.0e9, 0.0)],
		[REMOTE_SLOT, RELOCATED_POINT, 1],
	]

	for payload: Array in payloads:
		net.net_match_event(MatchNetScript.EVENT_PLACEMENT_RELOCATED, payload)

	assert_signal_not_emitted(Events, "placement_relocated")
