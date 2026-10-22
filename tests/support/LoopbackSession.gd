class_name LoopbackSession
extends RefCounted
## Puts the Net autoload into a real CLIENT session without poking its state: a second,
## path-isolated Net instance hosts on a free loopback port and the autoload joins it through
## join_game(), exactly as the game does. Everything that reads the real Net (Sfx, Rumble,
## Main, LoadingScreen) then sees a genuine client seated in slot 1.
##
## The remote host's multiplayer root is a container node, and the host is that node's child
## named "Net", so its RPC path relative to its root is the same "Net" the autoload has
## relative to /root.

const _NET_SCRIPT: GDScript = preload("res://autoload/Net.gd")
const _ROOT_NAME: String = "LoopbackHostRoot"
const _HOST_NAME: String = "Net"
const _CLIENT_ROOT_PREFIX: String = "LoopbackClientRoot"
const _JOIN_WAIT_S: float = 10.0
## The first joiner of a host takes the first seat after the host's own.
const CLIENT_SLOT: int = 1

## The second Net instance the autoload joined; null until join_net_as_client().
var remote_host: Node = null

var _test: GutTest
var _remote_clients: Array[Node] = []


func _init(test: GutTest) -> void:
	_test = test


## Leaves any session on the Net autoload, hosts a private loopback session on a second Net and
## joins it from the autoload. Returns true once the autoload is seated in CLIENT_SLOT and holds
## the roster.
func join_net_as_client() -> bool:
	Net.leave()
	var root: Node = Node.new()
	root.name = _ROOT_NAME
	_test.get_tree().set_multiplayer(
		MultiplayerAPI.create_default_interface(), NodePath(String(_test.get_path()) + "/" + _ROOT_NAME))
	_test.add_child_autofree(root)
	remote_host = _NET_SCRIPT.new()
	remote_host.name = _HOST_NAME
	root.add_child(remote_host)
	var port: int = AgentProbe.free_udp_port()
	if remote_host.host_game(port, "Hostie", false) != OK:
		return false
	remote_host.set_accepting_joins(true)
	if Net.join_game("127.0.0.1", port, "Clienty") != OK:
		return false
	return await _test.wait_until(func() -> bool:
		return Net.is_client() and Net.local_slot() == CLIENT_SLOT and Net.peer_ids().size() == 2,
		_JOIN_WAIT_S)


## Joins one more path-isolated Net instance to the session the Net autoload is hosting, the way a
## second player does. Returns it once it is seated and holds the full roster, or null.
func join_remote_client(player_name: String) -> Node:
	if not Net.is_host() or Net.is_offline():
		return null
	var root_name: String = "%s%d" % [_CLIENT_ROOT_PREFIX, _remote_clients.size()]
	var root: Node = Node.new()
	root.name = root_name
	_test.get_tree().set_multiplayer(
		MultiplayerAPI.create_default_interface(), NodePath(String(_test.get_path()) + "/" + root_name))
	_test.add_child_autofree(root)
	var client: Node = _NET_SCRIPT.new()
	client.name = _HOST_NAME
	root.add_child(client)
	_remote_clients.append(client)
	Net.set_accepting_joins(true) # a private loopback host refuses remote joins until told otherwise
	var expected_peers: int = Net.peer_ids().size() + 1
	if client.join_game("127.0.0.1", Net.host_port(), player_name) != OK:
		return null
	var seated: bool = await _test.wait_until(func() -> bool:
		return client.is_client() and client.local_slot() > 0 and client.peer_ids().size() == expected_peers,
		_JOIN_WAIT_S)
	return client if seated else null


## Leaves both ends and lets the host's deferred disconnect finish before the nodes are freed.
func end() -> void:
	for client: Node in _remote_clients:
		if is_instance_valid(client):
			client.leave()
	_remote_clients.clear()
	Net.leave()
	if remote_host != null and is_instance_valid(remote_host):
		remote_host.leave()
	await _test.get_tree().process_frame
	await _test.get_tree().process_frame
