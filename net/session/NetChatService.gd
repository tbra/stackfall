class_name NetChatService
extends RefCounted
## Host chat service of the Net autoload: refusal chain, per-peer flood buckets,
## duplicate filter, history and fan-out. Sends go through injected Callables, so
## tests build it directly. STUB: the default bodies log and do nothing; Net does
## not call it yet.

## A line the host accepted and published (Net re-emits it on Events).
signal line_accepted(line: Dictionary)
## A history batch a client accepted (Net re-emits it on Events).
signal history_accepted(lines: Array)


class Seams extends RefCounted:
	## () -> bool : this instance is the host of a non-private session.
	var is_chat_host: Callable = Callable()
	## () -> float : seconds, monotonic.
	var now_s: Callable = Callable()
	## (peer_id: int) -> Dictionary : the roster entry, empty when unknown.
	var peer_info: Callable = Callable()
	## (peer_id: int, method: StringName, args: Array) -> void : one addressed send.
	var send_to_peer: Callable = Callable()
	## () -> Array : the peer ids a send may address.
	var targets: Callable = Callable()


func _init(_config: ChatConfig, _seams: NetChatService.Seams) -> void:
	pass


## Host: a chat line from `sender`, refused in order, else published.
func on_submit(_sender: int, _payload: Variant) -> void:
	push_error("NetChatService.on_submit: not implemented")


## Host: send the history ring to a newly seated peer.
func send_history(_peer_id: int) -> void:
	push_error("NetChatService.send_history: not implemented")


## Host: stamp, store, emit and fan out a line.
func publish(_line: Dictionary) -> void:
	push_error("NetChatService.publish: not implemented")
