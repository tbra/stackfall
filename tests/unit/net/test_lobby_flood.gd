extends GutTest
## NetLobbyIntents: the host's set-ready, loading-ready and seat-preference intents,
## each behind its flood bucket. The unit cases build the class directly over a real
## NetRoster and PeerFloodGate with a synthetic clock and a recording seam; the ENet
## cases drive two real Net instances and watch what the client receives.

const _NET_SCRIPT: GDScript = preload("res://autoload/Net.gd")
const HOST_ID: int = 1
const PLAYER: int = 2
const OTHER: int = 3
const SPECTATOR: int = 4
const STRANGER: int = 99
const BUILD: String = "test-build"
const FLOOD_CALLS: int = 60
const HONEST_CALLS: int = 20
const LONG_IDLE_S: float = 10000.0
const WAIT_MSEC: int = 8000
const SETTLE_MSEC: int = 400
const START_CLOCK_S: float = 100.0

var _config: NetConfig
var _roster: NetRoster
var _flood: PeerFloodGate
var _intents: NetLobbyIntents
var _clock: float = START_CLOCK_S
var _is_host: bool = true
var _broadcasts: int = 0
var _loading: Array[int] = []
var _prefs: Array = []

var _host: Variant
var _client: Variant
var _roster_marks: Array = []


func before_each() -> void:
	_clock = START_CLOCK_S
	_is_host = true
	_broadcasts = 0
	_loading.clear()
	_prefs.clear()
	_config = (load("res://config/net/net_config.tres") as NetConfig).duplicate() as NetConfig
	_config.sanitize()
	_roster = NetRoster.new(_config)
	_roster.add_host("Hostie", BUILD, true)
	_roster.accept(PLAYER, BUILD, "Ann", 1)
	_roster.accept(OTHER, BUILD, "Bob", 2)
	_roster.accept(SPECTATOR, BUILD, "Spec", -1)
	_flood = PeerFloodGate.new(FloodLimits.from_config(_config))
	var seams: NetLobbyIntents.Seams = NetLobbyIntents.Seams.new()
	seams.now_s = func() -> float: return _clock
	seams.is_host = func() -> bool: return _is_host
	seams.broadcast_roster = func() -> void: _broadcasts += 1
	seams.loading_ready = func(peer_id: int) -> void: _loading.append(peer_id)
	seams.seat_pref = func(peer_id: int, color_index: int, team_pick: int) -> void: _prefs.append([peer_id, color_index, team_pick])
	_intents = NetLobbyIntents.new(_roster, _config, _flood, seams)


func after_each() -> void:
	if _client != null:
		_client.leave()
	if _host != null:
		_host.leave()
	_client = null
	_host = null
	if Events.net_roster_changed.is_connected(_on_roster_changed):
		Events.net_roster_changed.disconnect(_on_roster_changed)
	await get_tree().process_frame
	await get_tree().process_frame


func _ready_flag(peer_id: int) -> bool:
	return bool(_roster.peer_info(peer_id).get(LobbySeats.FIELD_READY, false))


## Seconds that refill exactly one token of a bucket refilling `per_s` tokens a second.
static func _one_token_s(per_s: float) -> float:
	return 1.0 / per_s


# --- Set ready ---------------------------------------------------------------------

func test_honest_ready_toggling_at_the_refill_rate_is_never_clipped() -> void:
	var step: float = _one_token_s(_config.flood_set_ready_refill_per_s)
	var want: bool = false
	for i: int in HONEST_CALLS:
		want = not want
		_clock += step
		_intents.on_set_ready(PLAYER, want)
		assert_eq(_ready_flag(PLAYER), want, "toggle %d lands" % i)
	assert_eq(_broadcasts, HONEST_CALLS, "one roster broadcast per accepted call")


func test_a_set_ready_flood_yields_at_most_a_burst_of_roster_broadcasts() -> void:
	for i: int in FLOOD_CALLS:
		_intents.on_set_ready(PLAYER, i % 2 == 0)
	assert_eq(_broadcasts, _config.flood_set_ready_burst, "exactly the burst, then silence")
	_clock += _one_token_s(_config.flood_set_ready_refill_per_s)
	for i: int in FLOOD_CALLS:
		_intents.on_set_ready(PLAYER, true)
	assert_eq(_broadcasts, _config.flood_set_ready_burst + 1, "one refilled token buys one more")


func test_the_flag_follows_the_last_accepted_call_not_the_dropped_ones() -> void:
	for i: int in _config.flood_set_ready_burst:
		_intents.on_set_ready(PLAYER, false)
	_intents.on_set_ready(PLAYER, true)
	assert_false(_ready_flag(PLAYER), "a dropped call changes nothing")


func test_every_accepted_call_broadcasts_even_when_the_flag_did_not_change() -> void:
	_intents.on_set_ready(PLAYER, true)
	_intents.on_set_ready(PLAYER, true)
	assert_eq(_broadcasts, 2, "the roster stays synchronous and ordered, no coalescing")


func test_a_long_idle_refills_to_the_burst_and_no_further() -> void:
	for i: int in FLOOD_CALLS:
		_intents.on_set_ready(PLAYER, true)
	_broadcasts = 0
	_clock += LONG_IDLE_S
	for i: int in FLOOD_CALLS:
		_intents.on_set_ready(PLAYER, true)
	assert_eq(_broadcasts, _config.flood_set_ready_burst)


func test_each_peer_has_its_own_set_ready_bucket() -> void:
	for i: int in FLOOD_CALLS:
		_intents.on_set_ready(PLAYER, true)
	_broadcasts = 0
	_intents.on_set_ready(OTHER, true)
	assert_eq(_broadcasts, 1, "another peer is unaffected by the flooder")
	assert_true(_ready_flag(OTHER))


func test_set_ready_from_a_spectator_a_stranger_or_a_client_instance_is_refused() -> void:
	_intents.on_set_ready(SPECTATOR, true)
	_intents.on_set_ready(STRANGER, true)
	assert_false(_ready_flag(SPECTATOR), "a spectator holds no seat")
	assert_eq(_broadcasts, 0)
	_is_host = false
	_intents.on_set_ready(PLAYER, true)
	assert_false(_ready_flag(PLAYER), "only the host acts on it")
	assert_eq(_broadcasts, 0)


func test_set_ready_mid_match_is_refused_and_works_again_in_the_lobby() -> void:
	_roster.set_match_phase(true)
	for i: int in FLOOD_CALLS:
		_intents.on_set_ready(PLAYER, true)
	assert_false(_ready_flag(PLAYER), "no ready toggles while a match runs")
	assert_eq(_broadcasts, 0)
	_roster.set_match_phase(false)
	for i: int in FLOOD_CALLS:
		_intents.on_set_ready(PLAYER, true)
	assert_eq(_broadcasts, _config.flood_set_ready_burst, "refused calls did not spend the bucket")
	assert_true(_ready_flag(PLAYER))


# --- Loading ready -----------------------------------------------------------------

func test_honest_loading_ready_reports_at_the_refill_rate_all_reach_the_gate() -> void:
	var step: float = _one_token_s(_config.flood_loading_ready_refill_per_s)
	for i: int in HONEST_CALLS:
		_clock += step
		_intents.on_loading_ready(PLAYER)
	assert_eq(_loading.size(), HONEST_CALLS)
	assert_true(_loading.all(func(peer_id: int) -> bool: return peer_id == PLAYER))


func test_a_loading_ready_flood_reaches_the_gate_only_up_to_the_burst() -> void:
	for i: int in FLOOD_CALLS:
		_intents.on_loading_ready(PLAYER)
	assert_eq(_loading.size(), _config.flood_loading_ready_burst)
	_intents.on_loading_ready(OTHER)
	assert_eq(_loading, _flood_expected(_config.flood_loading_ready_burst, PLAYER, OTHER), "another peer has its own bucket")
	assert_eq(_broadcasts, 0, "loading-ready never broadcasts the roster")


func _flood_expected(count: int, first: int, last: int) -> Array[int]:
	var out: Array[int] = []
	for i: int in count:
		out.append(first)
	out.append(last)
	return out


func test_loading_ready_from_a_spectator_a_stranger_or_a_client_instance_is_refused() -> void:
	_intents.on_loading_ready(SPECTATOR)
	_intents.on_loading_ready(STRANGER)
	assert_true(_loading.is_empty())
	_is_host = false
	_intents.on_loading_ready(PLAYER)
	assert_true(_loading.is_empty())


func test_loading_ready_is_accepted_while_a_match_is_starting() -> void:
	_roster.set_match_phase(true)
	_intents.on_loading_ready(PLAYER)
	assert_eq(_loading, [PLAYER] as Array[int], "the loading screen runs inside the match phase")


func test_a_loading_ready_flood_does_not_spend_the_set_ready_bucket() -> void:
	for i: int in FLOOD_CALLS:
		_intents.on_loading_ready(PLAYER)
	_intents.on_set_ready(PLAYER, true)
	assert_eq(_broadcasts, 1)


# --- Seat preferences --------------------------------------------------------------

func _pref_events() -> Array:
	return _prefs[0] as Array


func _pref_count() -> int:
	return _prefs.size()


func test_a_seated_peers_in_range_seat_pref_reaches_the_lobby_with_its_own_id() -> void:
	watch_signals(Events)
	_intents.on_seat_pref(PLAYER, 3, 2)
	assert_eq(_pref_count(), 1)
	if _pref_count() == 1:
		assert_eq(_pref_events(), [PLAYER, 3, 2])


func test_seat_pref_from_a_peer_without_a_seat_or_a_client_instance_is_refused() -> void:
	watch_signals(Events)
	_intents.on_seat_pref(STRANGER, 1, 1)
	_intents.on_seat_pref(SPECTATOR, 1, 1)
	_roster.remove(PLAYER, false)
	_intents.on_seat_pref(PLAYER, 1, 1)
	_is_host = false
	_intents.on_seat_pref(OTHER, 1, 1)
	assert_eq(_pref_count(), 0)


func test_seat_pref_values_out_of_range_are_refused_not_clamped() -> void:
	watch_signals(Events)
	var bad_colors: Array[int] = [-2, LobbySeats.palette_size(), 9, 1000000, 2147483647, -2147483648]
	for bad: int in bad_colors:
		_clock += LONG_IDLE_S
		_intents.on_seat_pref(PLAYER, bad, -1)
	var bad_teams: Array[int] = [-2, MatchConfig.TEAM_PICK_MAX + 1, 99, 2147483647, -2147483648]
	for bad: int in bad_teams:
		_clock += LONG_IDLE_S
		_intents.on_seat_pref(PLAYER, -1, bad)
	_clock += LONG_IDLE_S
	_intents.on_seat_pref(PLAYER, 1, 99)
	_clock += LONG_IDLE_S
	_intents.on_seat_pref(PLAYER, 99, 1)
	_clock += LONG_IDLE_S
	_intents.on_seat_pref(PLAYER, -1, -1)
	assert_eq(_pref_count(), 0)


func test_seat_pref_with_wrong_variant_types_is_refused() -> void:
	watch_signals(Events)
	for bad: Variant in [1.0, "1", null, true, [1], {"a": 1}, &"x", Vector2.ONE]:
		_clock += LONG_IDLE_S
		_intents.on_seat_pref(PLAYER, bad, -1)
		_clock += LONG_IDLE_S
		_intents.on_seat_pref(PLAYER, -1, bad)
	assert_eq(_pref_count(), 0)


func test_seat_pref_is_refused_mid_match_and_resumes_in_the_lobby() -> void:
	watch_signals(Events)
	_roster.set_match_phase(true)
	_intents.on_seat_pref(PLAYER, 1, 1)
	assert_eq(_pref_count(), 0)
	_roster.set_match_phase(false)
	_intents.on_seat_pref(PLAYER, 1, 1)
	assert_eq(_pref_count(), 1)


func test_seat_pref_flood_is_rate_limited_per_peer_and_refills() -> void:
	watch_signals(Events)
	var burst: int = _config.seat_pref_burst
	for i: int in burst:
		_intents.on_seat_pref(PLAYER, i % LobbySeats.palette_size(), -1)
	for i: int in FLOOD_CALLS:
		_intents.on_seat_pref(PLAYER, 1, 1)
	assert_eq(_pref_count(), burst, "exactly the burst got through")
	_intents.on_seat_pref(OTHER, 1, 1)
	assert_eq(_pref_count(), burst + 1, "another peer has its own bucket")
	_clock += _one_token_s(_config.seat_pref_refill_per_s) * 0.5
	_intents.on_seat_pref(PLAYER, 1, 1)
	assert_eq(_pref_count(), burst + 1, "half a token buys nothing")
	_clock += _one_token_s(_config.seat_pref_refill_per_s) * 0.5
	_intents.on_seat_pref(PLAYER, 1, 1)
	assert_eq(_pref_count(), burst + 2, "a whole token buys one request")
	_intents.on_seat_pref(PLAYER, 1, 1)
	assert_eq(_pref_count(), burst + 2, "and no more than that")
	_clock += LONG_IDLE_S
	for i: int in FLOOD_CALLS:
		_intents.on_seat_pref(PLAYER, 1, 1)
	assert_eq(_pref_count(), burst + 2 + burst, "a long pause refills to the burst, no further")


# --- Two real Net instances ----------------------------------------------------------

func _make_side(node_name: String) -> Variant:
	var node: Node = _NET_SCRIPT.new()
	node.name = node_name
	var path: NodePath = NodePath(String(get_path()) + "/" + node_name)
	get_tree().set_multiplayer(MultiplayerAPI.create_default_interface(), path)
	add_child_autofree(node)
	return node


func _wait_msec(condition: Callable, msec: int = WAIT_MSEC) -> bool:
	var deadline_msec: int = Time.get_ticks_msec() + msec
	while Time.get_ticks_msec() < deadline_msec:
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()


func _settle() -> void:
	var deadline_msec: int = Time.get_ticks_msec() + SETTLE_MSEC
	while Time.get_ticks_msec() < deadline_msec:
		await get_tree().process_frame


func _on_roster_changed(_entries: Array[Dictionary]) -> void:
	var mine: int = _client.local_peer_id()
	var info: Dictionary = _client.peer_info(mine)
	_roster_marks.append({
		"size": _client.peer_ids().size(),
		"accepted": _client.net_roster.joined_accepted,
		"ready": bool(info.get(LobbySeats.FIELD_READY, false)),
	})


func _connect_pair() -> bool:
	_host = _make_side("HostNet")
	_client = _make_side("ClientNet")
	_roster_marks.clear()
	Events.net_roster_changed.connect(_on_roster_changed)
	var port: int = AgentProbe.free_udp_port()
	assert_eq(_host.host_game(port, "Hostie"), OK)
	assert_eq(_client.join_game("127.0.0.1", port, "Clienty"), OK)
	return await _wait_msec(func() -> bool:
		return _host.peer_ids().size() == 2 and _client.local_slot() == 1)


func test_over_enet_the_client_hears_join_accepted_before_the_first_roster() -> void:
	var seated: bool = await _connect_pair()
	assert_true(seated, "client seated")
	await _settle()
	var with_both: Array = _roster_marks.filter(func(mark: Dictionary) -> bool: return int(mark["size"]) == 2)
	assert_false(with_both.is_empty(), "the client received a roster naming both peers")
	for mark: Dictionary in with_both:
		assert_true(bool(mark["accepted"]), "the roster never arrives before join_accepted")


func test_over_enet_a_set_ready_flood_costs_at_most_a_burst_of_roster_updates() -> void:
	assert_true(await _connect_pair())
	await _settle()
	var baseline: int = _roster_marks.size()
	var burst: int = _host.config.flood_set_ready_burst
	for i: int in FLOOD_CALLS:
		_client._rpc_set_ready.rpc_id(HOST_ID, i % 2 == 0)
	await _settle()
	var updates: int = _roster_marks.size() - baseline
	# Each host broadcast is seen once locally (host emit) and once by the client.
	# The +1 allows the token the wall clock refills while the test runs.
	assert_gte(updates, 2, "the first calls got through")
	assert_lte(updates, 2 * (burst + 1), "at most a burst of roster broadcasts")


func test_over_enet_every_accepted_ready_toggle_reaches_the_client_in_order() -> void:
	assert_true(await _connect_pair())
	await _settle()
	var seen: Array[bool] = []
	var record: Callable = func(_entries: Array[Dictionary]) -> void:
		var flag: bool = bool(_client.peer_info(_client.local_peer_id()).get(LobbySeats.FIELD_READY, false))
		var previous: bool = seen.back() if not seen.is_empty() else false
		if flag != previous:
			seen.append(flag)
	Events.net_roster_changed.connect(record)
	_client._rpc_set_ready.rpc_id(HOST_ID, true)
	_client._rpc_set_ready.rpc_id(HOST_ID, false)
	_client._rpc_set_ready.rpc_id(HOST_ID, true)
	await _settle()
	Events.net_roster_changed.disconnect(record)
	assert_eq(seen, [true, false, true] as Array[bool], "no coalescing: each toggle is its own update")
	assert_true(bool(_host.peer_info(_client.local_peer_id())[LobbySeats.FIELD_READY]))
