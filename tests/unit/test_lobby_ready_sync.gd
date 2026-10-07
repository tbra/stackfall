extends GutTest
## Bontago-1pi.89: Net's per-peer "ready" flag is the single source of truth; the Lobby's Ready
## toggle and the seat badges are views of it. Every route that changes the flag (toggle press,
## reset_ready_flags, returning from a match, a rejoin) must leave the toggle, the local seat's
## badge and the Net flag equal -- for the host and for a client, on a FakeNet and on real ENet
## sessions. Third report of the same desync (Bontago-1pi.67, 1pi.73): the toggle kept its own
## pressed state and nothing ever wrote Net's flag back into it.

const LOBBY_SCENE: PackedScene = preload("res://ui/Lobby.tscn")
const _NET_SCRIPT: GDScript = preload("res://autoload/Net.gd")

const HOST_ID: int = 1
const GUEST_ID: int = 2
const HOST_NAME: String = "Hostie"
const GUEST_NAME: String = "Guesty"
const WAIT_FRAMES: int = 400

var _host_net: Variant = null
var _client_net: Variant = null


func after_each() -> void:
	Settings.set_active_input_device_for_test(Settings.DEFAULT_ACTIVE_DEVICE)
	if _client_net != null:
		_client_net.leave()
	if _host_net != null:
		_host_net.leave()
	_client_net = null
	_host_net = null
	# Net._reject_peer()/leave() close the transport a couple of frames later.
	await get_tree().process_frame
	await get_tree().process_frame


# --- Helpers ----------------------------------------------------------------------

func _toggle(lobby: Lobby) -> CheckButton:
	return lobby.get_node("%ReadyCheck") as CheckButton


func _panel_of(lobby: Lobby) -> LobbyPlayersPanel:
	return lobby.get_node("%PlayersPanel") as LobbyPlayersPanel


## Seat name -> whether its badge reads Ready, for every drawn human row.
func _badges(lobby: Lobby) -> Dictionary:
	var badges: Dictionary = {}
	for node: Node in _panel_of(lobby)._player_rows:
		var row: LobbySeatRow = node as LobbySeatRow
		if row == null or row.is_bot or row.badge == null:
			continue
		# Bontago-1pi.106: the host's badge is a crown, so its ready state is read off the row flag.
		badges[row.display_name] = row.is_ready if row.is_host else row.badge.tooltip_text == LobbySeatRow.ready_tooltip(true)
	return badges


## "" when the toggle, every seat badge and the Net flags (as `net` reads them) all agree; else a
## sentence naming what differs. `net` is the Lobby's own provider (a FakeNet or a real Net).
func _disagreement(lobby: Lobby, net: Variant) -> String:
	var problems: PackedStringArray = PackedStringArray()
	var own: Dictionary = net.peer_info(net.local_peer_id())
	var flag: bool = bool(own.get("ready", false))
	var toggle: CheckButton = _toggle(lobby)
	if toggle.button_pressed != flag:
		problems.append("toggle is %s but the Net flag is %s" % [toggle.button_pressed, flag])
	var badges: Dictionary = _badges(lobby)
	for peer_id: int in net.peer_ids():
		var info: Dictionary = net.peer_info(peer_id)
		var player_name: String = str(info.get("name", ""))
		if not badges.has(player_name):
			problems.append("no seat row for %s" % player_name)
		elif bool(badges[player_name]) != bool(info.get("ready", false)):
			problems.append("%s's badge is %s but its Net flag is %s" % [player_name, badges[player_name], info.get("ready", false)])
	return "; ".join(problems)


## The reported symptom: the local seat's badge says Ready while the toggle is off.
func _symptom_present(lobby: Lobby, net: Variant) -> bool:
	var own: Dictionary = net.peer_info(net.local_peer_id())
	var badges: Dictionary = _badges(lobby)
	return bool(badges.get(str(own.get("name", "")), false)) and not _toggle(lobby).button_pressed


# --- FakeNet: a deterministic stand-in for every route ----------------------------

func _make_fake(is_host: bool) -> FakeNet:
	var fake: FakeNet = FakeNet.host({HOST_ID: 0, GUEST_ID: 1}, [0]) if is_host else FakeNet.client(1)
	fake.slots_by_peer = {HOST_ID: 0, GUEST_ID: 1}
	fake.local_peer_id_value = HOST_ID if is_host else GUEST_ID
	fake.names_by_peer = {HOST_ID: HOST_NAME, GUEST_ID: GUEST_NAME}
	fake.ready_by_peer = {HOST_ID: false, GUEST_ID: false}
	return fake


## A fresh Lobby seated on `provider` BEFORE _ready(), so the real entry path runs on it.
func _enter_lobby(provider: Variant) -> Lobby:
	var lobby: Lobby = LOBBY_SCENE.instantiate() as Lobby
	lobby.net_provider = provider
	add_child_autofree(lobby)
	return lobby


## What Net does after any flag change: tell the lobby the roster moved.
func _broadcast(fake: FakeNet) -> void:
	Events.net_roster_changed.emit(fake.roster_payload())


func _roles() -> Array[bool]:
	return [true, false]


func test_a_fresh_lobby_opens_off_and_agrees_for_host_and_client() -> void:
	for is_host: bool in _roles():
		var fake: FakeNet = _make_fake(is_host)
		var lobby: Lobby = _enter_lobby(fake)
		assert_false(_toggle(lobby).button_pressed, "host=%s: starts off" % is_host)
		assert_eq(_disagreement(lobby, fake), "", "host=%s: entry" % is_host)


func test_toggle_press_writes_the_net_flag_and_all_three_stay_equal() -> void:
	for is_host: bool in _roles():
		var fake: FakeNet = _make_fake(is_host)
		var lobby: Lobby = _enter_lobby(fake)
		_toggle(lobby).button_pressed = true
		assert_eq(fake.set_local_ready_calls, [true], "host=%s: the press is the one write into Net" % is_host)
		_broadcast(fake)
		assert_eq(_disagreement(lobby, fake), "", "host=%s: pressed on" % is_host)
		assert_true(_toggle(lobby).button_pressed)
		_toggle(lobby).button_pressed = false
		_broadcast(fake)
		assert_eq(_disagreement(lobby, fake), "", "host=%s: pressed off" % is_host)
		assert_eq(fake.set_local_ready_calls, [true, false], "host=%s: no echo writes from the view" % is_host)


func test_reset_ready_flags_turns_the_toggle_off_with_the_badges() -> void:
	for is_host: bool in _roles():
		var fake: FakeNet = _make_fake(is_host)
		fake.is_host_value = true  # only the host resets; a client sees the host's reset arrive
		var lobby: Lobby = _enter_lobby(fake)
		fake.is_host_value = is_host
		_toggle(lobby).button_pressed = true
		fake.set_peer_ready(HOST_ID if not is_host else GUEST_ID, true)  # the other seat readies too
		_broadcast(fake)
		assert_eq(_disagreement(lobby, fake), "", "host=%s: both ready" % is_host)
		fake.is_host_value = true
		fake.reset_ready_flags()
		fake.is_host_value = is_host
		_broadcast(fake)
		assert_false(_toggle(lobby).button_pressed, "host=%s: the reset reaches the toggle, not only the badges" % is_host)
		assert_eq(_disagreement(lobby, fake), "", "host=%s: after reset" % is_host)


func test_a_client_toggle_follows_the_hosts_view_of_it() -> void:
	# The client's flag is whatever the host's roster says: a stale press the host never
	# recorded (refused, or reset first) must not stay lit.
	var fake: FakeNet = _make_fake(false)
	var lobby: Lobby = _enter_lobby(fake)
	_toggle(lobby).button_pressed = true
	fake.ready_by_peer[GUEST_ID] = false  # the host never accepted it
	_broadcast(fake)
	assert_false(_toggle(lobby).button_pressed)
	assert_eq(_disagreement(lobby, fake), "")


func test_entering_a_lobby_with_the_flag_already_set_shows_the_toggle_on() -> void:
	for is_host: bool in _roles():
		var fake: FakeNet = _make_fake(is_host)
		fake.ready_by_peer[fake.local_peer_id_value] = true
		var lobby: Lobby = _enter_lobby(fake)
		assert_true(_toggle(lobby).button_pressed, "host=%s: the toggle shows Net's flag on entry" % is_host)
		assert_eq(_disagreement(lobby, fake), "", "host=%s: entry with flag set" % is_host)
		assert_eq(fake.set_local_ready_calls, [], "host=%s: showing the flag never writes it back" % is_host)


## A client that re-enters the lobby reads the host's cached lobby data, whose embedded roster
## was published BEFORE the match (everyone ready). Net's live roster, not that snapshot, drives
## the badges.
func test_a_stale_cached_roster_never_beats_the_live_net_flags_on_entry() -> void:
	var fake: FakeNet = _make_fake(false)
	var stale: Dictionary = MatchConfig.new().to_dict()
	stale["roster"] = [
		{"peer_id": HOST_ID, "slot_id": 0, "name": HOST_NAME, "ready": true},
		{"peer_id": GUEST_ID, "slot_id": 1, "name": GUEST_NAME, "ready": true},
	]
	fake.lobby_data_value = stale
	var lobby: Lobby = _enter_lobby(fake)
	assert_false(_toggle(lobby).button_pressed)
	assert_eq(_disagreement(lobby, fake), "", "the live flags (all off) win over the stale roster")


## The reported symptom (host row 'Ready' while its toggle is off) over every flag sequence the
## roster can announce: after each Net broadcast it must be absent, host and client.
func test_the_ready_badge_with_the_toggle_off_never_happens() -> void:
	for is_host: bool in _roles():
		var fake: FakeNet = _make_fake(is_host)
		fake.ready_by_peer[fake.local_peer_id_value] = true  # as after a match: flag set, fresh toggle
		var lobby: Lobby = _enter_lobby(fake)
		assert_false(_symptom_present(lobby, fake), "host=%s: entry with a leftover flag" % is_host)
		for flag: bool in [false, true, true, false, true, false]:
			fake.ready_by_peer[fake.local_peer_id_value] = flag
			_broadcast(fake)
			assert_false(_symptom_present(lobby, fake), "host=%s: flag %s" % [is_host, flag])
			assert_eq(_toggle(lobby).button_pressed, flag, "host=%s: toggle follows %s" % [is_host, flag])


func test_syncing_the_toggle_is_silent() -> void:
	# A view update is not a press: no ready_on/ready_off cue, no set_local_ready call.
	var fake: FakeNet = _make_fake(true)
	var lobby: Lobby = _enter_lobby(fake)
	watch_signals(Events)
	fake.ready_by_peer[HOST_ID] = true
	_broadcast(fake)
	assert_true(_toggle(lobby).button_pressed)
	assert_signal_not_emitted(Events, "lobby_ui_cue")
	assert_eq(fake.set_local_ready_calls, [])


# --- Real ENet host + client -------------------------------------------------------

func _make_net_side(node_name: String) -> Variant:
	var node: Node = _NET_SCRIPT.new()
	node.name = node_name
	var path: NodePath = NodePath(String(get_path()) + "/" + node_name)
	get_tree().set_multiplayer(MultiplayerAPI.create_default_interface(), path)
	add_child_autofree(node)
	return node


func _wait_for(condition: Callable, frames: int = WAIT_FRAMES) -> bool:
	for _i: int in range(frames):
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()


var _host_port: int = 0


func _join_client() -> void:
	assert_eq(_client_net.join_game("127.0.0.1", _host_port, GUEST_NAME), OK)
	var seated: bool = await _wait_for(func() -> bool:
		return _host_net.peer_ids().size() == 2 and _client_net.peer_ids().size() == 2
	)
	assert_true(seated, "host and client settle on a 2-peer roster")


## Polls until both lobbies agree with their own Net, then asserts it (a message names the gap).
func _expect_agreement(host_lobby: Lobby, client_lobby: Lobby, context: String) -> void:
	var settled: bool = await _wait_for(func() -> bool:
		return _disagreement(host_lobby, _host_net) == "" and _disagreement(client_lobby, _client_net) == ""
	)
	assert_true(settled, "%s: toggle, badges and Net flags agree on both sides" % context)
	assert_eq(_disagreement(host_lobby, _host_net), "", "%s: host lobby" % context)
	assert_eq(_disagreement(client_lobby, _client_net), "", "%s: client lobby" % context)
	# And the two Nets hold the same flags (the client's copy is the host's roster).
	for peer_id: int in _host_net.peer_ids():
		assert_eq(
			bool((_client_net.peer_info(peer_id) as Dictionary).get("ready", false)),
			bool((_host_net.peer_info(peer_id) as Dictionary).get("ready", false)),
			"%s: peer %d flag, client copy vs host" % [context, peer_id]
		)


func _flag_of(net: Variant, peer_id: int) -> bool:
	return bool((net.peer_info(peer_id) as Dictionary).get("ready", false))


func test_over_enet_every_route_keeps_toggle_badge_and_flag_equal() -> void:
	_host_net = _make_net_side("ReadySyncHostNet")
	_client_net = _make_net_side("ReadySyncClientNet")
	_host_port = AgentProbe.free_udp_port()
	assert_eq(_host_net.host_game(_host_port, HOST_NAME), OK)
	await _join_client()
	var client_id: int = _client_net.local_peer_id()

	var host_lobby: Lobby = _enter_lobby(_host_net)
	var client_lobby: Lobby = _enter_lobby(_client_net)
	await _expect_agreement(host_lobby, client_lobby, "entry")
	assert_false(_toggle(host_lobby).button_pressed)
	assert_false(_toggle(client_lobby).button_pressed)

	# Route 1: the host presses its toggle.
	_toggle(host_lobby).button_pressed = true
	await _expect_agreement(host_lobby, client_lobby, "host presses on")
	assert_true(_flag_of(_host_net, Net.HOST_PEER_ID))
	assert_true(_toggle(host_lobby).button_pressed)

	# Route 2: the client presses its toggle (round trip through the host).
	_toggle(client_lobby).button_pressed = true
	var accepted: bool = await _wait_for(func() -> bool: return _flag_of(_host_net, client_id))
	assert_true(accepted, "the host recorded the client's press")
	await _expect_agreement(host_lobby, client_lobby, "client presses on")
	assert_true(_toggle(client_lobby).button_pressed)
	assert_true(_host_net.all_peers_ready())

	# Route 3: the host presses off again; the client's stays.
	_toggle(host_lobby).button_pressed = false
	await _expect_agreement(host_lobby, client_lobby, "host presses off")
	assert_true(_toggle(client_lobby).button_pressed, "an unrelated peer's flip does not move my toggle")

	# Route 4: reset_ready_flags() straight on the host's Net (every flag on first).
	_toggle(host_lobby).button_pressed = true
	await _expect_agreement(host_lobby, client_lobby, "both on")
	_host_net.reset_ready_flags()
	await _expect_agreement(host_lobby, client_lobby, "after reset_ready_flags")
	assert_false(_toggle(host_lobby).button_pressed, "the host's toggle follows the reset")
	assert_false(_toggle(client_lobby).button_pressed, "the client's toggle follows the reset")
	assert_false(_host_net.all_peers_ready())

	# Route 5: return from a match. Everyone ready and the host's lobby data published with
	# those flags (the client caches that snapshot), then the match starts and ends.
	_toggle(host_lobby).button_pressed = true
	_toggle(client_lobby).button_pressed = true
	await _expect_agreement(host_lobby, client_lobby, "both on before the match")
	host_lobby._republish_roster_if_host()
	var cached: bool = await _wait_for(func() -> bool:
		var snapshot: Array = _client_net.lobby_data().get("roster", [])
		return snapshot.size() == 2 and bool((snapshot[1] as Dictionary).get("ready", false))
	)
	assert_true(cached, "the client holds a lobby snapshot with everyone ready")
	_host_net.set_match_in_progress(true)
	_host_net.set_match_in_progress(false)
	var cleared: bool = await _wait_for(func() -> bool:
		return not _flag_of(_client_net, Net.HOST_PEER_ID) and not _flag_of(_client_net, client_id)
	)
	assert_true(cleared, "returning to the lobby clears every ready flag, host and client views")
	# The fresh lobbies, client first: it enters with the stale snapshot cached.
	host_lobby.queue_free()
	client_lobby.queue_free()
	await get_tree().process_frame
	client_lobby = _enter_lobby(_client_net)
	assert_eq(_disagreement(client_lobby, _client_net), "", "client re-enters on the stale snapshot: still equal to Net")
	assert_false(_toggle(client_lobby).button_pressed)
	host_lobby = _enter_lobby(_host_net)
	await _expect_agreement(host_lobby, client_lobby, "after returning from a match")
	assert_false(_toggle(host_lobby).button_pressed)
	assert_false(_symptom_present(host_lobby, _host_net))

	# Route 6: the client rejoins. A new session peer starts not ready, whatever it was before.
	_toggle(client_lobby).button_pressed = true
	var again: bool = await _wait_for(func() -> bool: return _flag_of(_host_net, client_id))
	assert_true(again)
	client_lobby.queue_free()
	_client_net.leave()
	var gone: bool = await _wait_for(func() -> bool: return _host_net.peer_ids().size() == 1)
	assert_true(gone, "the host dropped the client's seat")
	await _join_client()
	var rejoined_id: int = _client_net.local_peer_id()
	assert_false(_flag_of(_host_net, rejoined_id), "a rejoined peer is seeded not ready")
	client_lobby = _enter_lobby(_client_net)
	await _expect_agreement(host_lobby, client_lobby, "after the client rejoined")
	assert_false(_toggle(client_lobby).button_pressed)
	assert_false(_symptom_present(client_lobby, _client_net))
