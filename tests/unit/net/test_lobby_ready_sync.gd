extends GutTest
## Net's per-peer "ready" flag is the single source of truth; the Lobby's Ready
## toggle and the seat badges are views of it. Every route that changes the flag (toggle press,
## returning from a match, a rejoin) must leave the toggle, the local seat's
## badge and the Net flag equal -- for the host and for a client, on a FakeNet and on real ENet
## sessions. Third report of the same desync: the toggle kept its own
## pressed state and nothing ever wrote Net's flag back into it.

const LOBBY_SCENE: PackedScene = preload("res://ui/lobby/Lobby.tscn")
const HOST_ID: int = 1
const GUEST_ID: int = 2
const HOST_NAME: String = "Hostie"
const GUEST_NAME: String = "Guesty"
var _host_net: Variant = null
var _client_net: Variant = null


func after_each() -> void:
	Settings._input(InputEventKey.new())
	if _client_net != null:
		_client_net.leave()
	if _host_net != null:
		_host_net.leave()
	_client_net = null
	_host_net = null
	# A refused handshake and leave() close the transport a couple of frames later.
	await get_tree().process_frame
	await get_tree().process_frame


# --- Helpers ----------------------------------------------------------------------

func _toggle(lobby: Lobby) -> CheckButton:
	return lobby.find_child("ReadyCheck", true, false) as CheckButton


func _panel_of(lobby: Lobby) -> LobbyPlayersPanel:
	return lobby.find_child("PlayersPanel", true, false) as LobbyPlayersPanel


## Seat name -> whether its badge reads Ready, for every drawn human row.
func _badges(lobby: Lobby) -> Dictionary:
	var badges: Dictionary = {}
	for row: LobbySeatRow in LobbyProbe.seat_rows(lobby):
		if row.is_bot or row.badge == null:
			continue
		# the host's badge is a crown, so its ready state is read off the row flag.
		badges[row.display_name] = row.is_ready if row.is_host else (row.badge as Control).get_accessibility_name() == LobbySeatRow.ready_tooltip(true)
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


# --- Real ENet host + client -------------------------------------------------------
