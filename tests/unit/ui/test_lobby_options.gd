extends GutTest
## the Options screen opens over the lobby and closes back to it with focus restored,
## lobby shortcuts stay silent while it is open, and lobby networking carries on underneath.

const LOBBY_SCENE: PackedScene = preload("res://ui/lobby/Lobby.tscn")
const _NET_SCRIPT: GDScript = preload("res://autoload/Net.gd")
const WAIT_TIMEOUT_MSEC: int = 15000
const SETTLE_FRAMES: int = 120

var _host_net: Variant = null
var _client_net: Variant = null


func after_each() -> void:
	if _client_net != null:
		_client_net.leave()
	if _host_net != null:
		_host_net.leave()
	_client_net = null
	_host_net = null
	await get_tree().process_frame
	await get_tree().process_frame


func _make_lobby(is_host: bool = true) -> Lobby:
	var fake: FakeNet = FakeNet.new()
	fake.is_host_value = is_host
	fake.is_offline_value = true
	var lobby: Lobby = LOBBY_SCENE.instantiate() as Lobby
	lobby.net_provider = fake
	add_child_autofree(lobby)
	return lobby


func _action(name: StringName) -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = name
	event.pressed = true
	return event


func _options_of(lobby: Lobby) -> OptionsMenu:
	for child: Node in lobby.get_children():
		if child is OptionsMenu:
			return child as OptionsMenu
	return null


func test_options_button_opens_and_close_restores_focus_to_it() -> void:
	var lobby: Lobby = _make_lobby()
	await wait_process_frames(2)
	var button: Button = lobby.find_child("OptionsButton", true, false) as Button
	button.pressed.emit()
	await wait_process_frames(2)
	assert_true(lobby._options_menu != null)
	var menu: OptionsMenu = _options_of(lobby)
	assert_not_null(menu)
	assert_eq(button.focus_mode, Control.FOCUS_NONE, "lobby controls are suspended")
	menu.closed.emit()
	await wait_process_frames(2)
	assert_false(lobby._options_menu != null)
	assert_false(menu.visible, "Options is hidden, kept for reuse")
	assert_eq(button.focus_mode, Control.FOCUS_ALL)
	assert_eq(lobby.get_viewport().gui_get_focus_owner(), button, "focus returns to the Options button")


func test_shortcut_opens_options_once() -> void:
	var lobby: Lobby = _make_lobby()
	await wait_process_frames(2)
	lobby._unhandled_input(_action(&"lobby_options"))
	assert_true(lobby._options_menu != null)
	lobby.open_options()
	var count: int = 0
	for child: Node in lobby.get_children():
		if child is OptionsMenu:
			count += 1
	assert_eq(count, 1)
	assert_true(InputMap.has_action(&"lobby_options"))
	assert_false(InputMap.action_get_events(&"lobby_options").is_empty())


func _make_net_side(node_name: String) -> Variant:
	var node: Node = _NET_SCRIPT.new()
	node.name = node_name
	var path: NodePath = NodePath(String(get_path()) + "/" + node_name)
	get_tree().set_multiplayer(MultiplayerAPI.create_default_interface(), path)
	add_child_autofree(node)
	return node


## Polls once per frame until `condition` holds or `timeout_msec` of wall-clock time passes.
## Loopback ENet delivery takes real time that frame counts do not measure (a loaded
## machine runs hundreds of frames per millisecond of OS scheduling delay), so the bound
## is a clock, not a frame budget.
func _wait_for(condition: Callable, timeout_msec: int = WAIT_TIMEOUT_MSEC) -> bool:
	var deadline: int = Time.get_ticks_msec() + timeout_msec
	while not condition.call():
		if Time.get_ticks_msec() >= deadline:
			return false
		await get_tree().process_frame
	return true


func test_enet_client_stays_connected_and_host_keeps_accepting_while_options_open() -> void:
	_host_net = _make_net_side("OptHostNet")
	_client_net = _make_net_side("OptClientNet")
	var port: int = AgentProbe.free_udp_port()
	assert_eq(_host_net.host_game(port, "Hostie"), OK)
	assert_eq(_client_net.join_game("127.0.0.1", port, "Guesty"), OK)
	var seated: bool = await _wait_for(func() -> bool:
		return _host_net.peer_ids().size() == 2 and _client_net.peer_ids().size() == 2
	)
	assert_true(seated)
	var host_lobby: Lobby = LOBBY_SCENE.instantiate() as Lobby
	host_lobby.net_provider = _host_net
	add_child_autofree(host_lobby)
	var client_lobby: Lobby = LOBBY_SCENE.instantiate() as Lobby
	client_lobby.net_provider = _client_net
	add_child_autofree(client_lobby)
	await wait_process_frames(3)
	client_lobby.open_options()
	assert_true(client_lobby._options_menu != null)
	# The host changes ready state while the client's Options is open; the client still hears it.
	_host_net.set_local_ready(true)
	var client_id: int = _client_net.local_peer_id()
	var heard: bool = await _wait_for(func() -> bool:
		return bool((_client_net.peer_info(Net.HOST_PEER_ID) as Dictionary).get("ready", false))
	)
	assert_true(heard, "client keeps receiving roster changes under Options")
	assert_eq(_client_net.peer_ids().size(), 2, "client stays connected")
	# Host opens Options too, then the client flips ready: the host still accepts it.
	host_lobby.open_options()
	_client_net.set_local_ready(true)
	var accepted: bool = await _wait_for(func() -> bool:
		return bool((_host_net.peer_info(client_id) as Dictionary).get("ready", false))
	)
	assert_true(accepted, "host accepts ready changes while its Options is open")
	# Settle a while longer: no drop.
	await wait_process_frames(SETTLE_FRAMES)
	assert_eq(_host_net.peer_ids().size(), 2)
	assert_eq(_client_net.peer_ids().size(), 2)
