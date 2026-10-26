extends GutTest
## (scope widened by the owner: "before it, every refusal was
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
## Same fixtures as tests/unit/ui/test_refusal_feedback_local.gd: the real Match
## through MatchNet with a faked Net, the real Sfx autoload read through its cue players
## (SfxChildren), the real Rumble with its vibration seam swapped for a recorder. Sfx hears
## Events.gift_claimed as in the game; the Rumble hooks are invoked directly.

const MatchNetScript := preload("res://net/MatchNet.gd")

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
var _fake_net: FakeNet
var _tiny_map: MapDef
var _rumble_enabled_before: bool
var _rumble_strength_before: float
var _rumble_calls: Array[Dictionary] = []

var _loopback: LoopbackSession


func before_each() -> void:
	_loopback = LoopbackSession.new(self)
	_rumble_enabled_before = Settings.rumble_enabled()
	_rumble_strength_before = Settings.rumble_strength()
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

	SfxChildren.stop_all()

	_rumble_calls = []
	Rumble.start_vibration_fn = Callable(self, "_record_rumble")
	var press: InputEventJoypadButton = InputEventJoypadButton.new()
	press.device = GAMEPAD_DEVICE
	Rumble._input(press)


func after_each() -> void:
	await _loopback.end()
	Match._net_provider = null
	Match.set_replicator(null)
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()
	Rumble.start_vibration_fn = Callable(Rumble, "_start_vibration_real")
	Rumble._last_device_id = Rumble.DEVICE_NONE
	Rumble._last_family = &""
	SfxChildren.stop_all()
	Settings.set_rumble_enabled(_rumble_enabled_before)
	Settings.set_rumble_strength(_rumble_strength_before)


func _record_rumble(device: int, weak_magnitude: float, strong_magnitude: float, duration_s: float) -> void:
	_rumble_calls.append({
		"device": device, "weak": weak_magnitude, "strong": strong_magnitude, "duration": duration_s
	})


func _any_sfx_playing() -> bool:
	return SfxChildren.any_playing()


## A listen-server host (peer 1, slot 0) with one remote client (peer 2, slot 1).
func _make_host_net() -> MatchNetScript:
	var peer_slots: Dictionary = {HOST_PEER: HOST_SLOT, REMOTE_PEER: REMOTE_SLOT}
	_fake_net = FakeNet.host(peer_slots, [HOST_SLOT])
	_fake_net.slots_by_peer = peer_slots
	Match._net_provider = _fake_net
	var node: MatchNetScript = MatchNetScript.new()
	node.set_process(false)
	add_child_autofree(node)
	assert_true(node.bind_ports(FakeSessionPort.new(_fake_net), MatchHostPort.new(Match), MatchReplicaPort.new(Match)))
	# Sfx/Rumble read the real Net: a host drives slot 0 only.
	assert_eq(Net.host_game(AgentProbe.free_udp_port(), "", false), OK)
	assert_eq(Net.local_slot(), HOST_SLOT)
	return node


## A client instance whose own seat is `local_slot_id`.
func _make_client_net(local_slot_id: int) -> MatchNetScript:
	# A real client of a loopback host: the first joiner always takes REMOTE_SLOT.
	assert_eq(local_slot_id, REMOTE_SLOT)
	assert_true(await _loopback.join_net_as_client(), "fixture: the Net autoload is a seated client")
	Match._net_provider = FakeNet.host({}, [HOST_SLOT, REMOTE_SLOT])
	_start_playing()
	_fake_net = FakeNet.client(local_slot_id)
	Match._net_provider = _fake_net
	var node: MatchNetScript = MatchNetScript.new()
	node.set_process(false)
	add_child_autofree(node)
	assert_true(node.bind_ports(FakeSessionPort.new(_fake_net), MatchHostPort.new(Match), MatchReplicaPort.new(Match)))
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


func test_a_hosts_pad_ticks_for_its_own_seat_and_not_for_a_remote_clients() -> void:
	_make_host_net()
	_start_playing()

	Rumble._on_feed_block_issued(REMOTE_SLOT, &"", &"")
	assert_eq(_rumble_calls.size(), 0, "host, remote client's next block")

	Rumble._on_feed_block_issued(HOST_SLOT, &"", &"")
	assert_eq(_rumble_calls.size(), 1, "host, its own next block")


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


func test_a_bots_gift_claim_never_chimes_for_the_human_offline() -> void:
	_start_playing(2, 1)
	assert_true(Match.slot(1).is_bot, "fixture: slot 1 is the bot")

	Events.gift_claimed.emit(GIFT_ID, 1, SOME_SPECIAL)

	assert_false(_any_sfx_playing(), "offline bot claim (every team-of-one is on its own team)")

	Events.gift_claimed.emit(GIFT_ID, HOST_SLOT, SOME_SPECIAL)

	assert_true(_any_sfx_playing(), "the human's own claim still chimes")


func test_a_teammates_claim_still_chimes_team_wide() -> void:
	# "b": a claim is a team notification, so a
	# teammate hears it. Slots 0 and 2 are one team, 1 and 3 the other.
	_make_host_net()
	var config: MatchConfig = _config(4, 0)
	config.team_mode = MatchConfig.TeamMode.TEAMS_2
	_run_to_playing(config)

	Events.gift_claimed.emit(GIFT_ID, 1, SOME_SPECIAL)
	assert_false(_any_sfx_playing(), "host (team 0), the other team's claim")

	Events.gift_claimed.emit(GIFT_ID, 2, SOME_SPECIAL)
	assert_true(_any_sfx_playing(), "host (team 0), its teammate's claim")


# --- MatchNet: placement_relocated goes to the owning seat only ---------------


func test_a_remote_clients_relocation_goes_to_that_peer_alone() -> void:
	var sent: Array[Array] = []
	var broadcasts: Array[Array] = []
	var seams: MatchIntentGateway.Seams = MatchIntentGateway.Seams.new()
	seams.can_send = func() -> bool: return true
	seams.send_to_host = func(_method: StringName, _args: Array) -> void: pass
	seams.send_to_peer = func(peer_id: int, method: StringName, args: Array) -> bool:
		sent.append([peer_id, method, args])
		return true
	seams.broadcast = func(method: StringName, args: Array) -> void: broadcasts.append([method, args])
	var peer_slots: Dictionary = {HOST_PEER: HOST_SLOT, REMOTE_PEER: REMOTE_SLOT}
	var host_net: FakeNet = FakeNet.host(peer_slots, [HOST_SLOT])
	host_net.slots_by_peer = peer_slots
	var mirror: MatchEventMirror = MatchEventMirror.new(seams)
	mirror.bind_ports(
		FakeSessionPort.new(host_net),
		MatchHostPort.new(Match)
	)

	mirror.on_placement_relocated(REMOTE_SLOT, RELOCATED_POINT)

	assert_eq(broadcasts.size(), 0, "never broadcast to every peer")
	assert_eq(sent.size(), 1, "the owner is told exactly once and nobody else is addressed")
	assert_eq(sent[0][0], REMOTE_PEER)
	var client: MatchNetScript = await _make_client_net(REMOTE_SLOT)
	watch_signals(Events)
	client.net_match_event(sent[0][2][0], sent[0][2][1])
	assert_signal_emitted_with_parameters(Events, "placement_relocated", [REMOTE_SLOT, RELOCATED_POINT])


func test_a_client_drops_a_malformed_relocation_payload() -> void:
	var net: MatchNetScript = await _make_client_net(REMOTE_SLOT)
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
		net.net_match_event(MatchWireEvents.PLACEMENT_RELOCATED, payload)

	assert_signal_not_emitted(Events, "placement_relocated")
