class_name ForgedSenderApi
extends MultiplayerAPIExtension
## A MultiplayerAPI whose remote sender id is whatever the test sets, so a net_* handler can be
## called as if an RPC from that peer were being dispatched. Install it on a node's path with
## `ForgedSenderApi.install(tree, node, peer)`; the node must be in the tree.

var sender_id: int = 0


static func install(tree: SceneTree, node: Node, peer: int) -> ForgedSenderApi:
	var api: ForgedSenderApi = ForgedSenderApi.new()
	api.sender_id = peer
	tree.set_multiplayer(api, node.get_path())
	return api


func _get_remote_sender_id() -> int:
	return sender_id
