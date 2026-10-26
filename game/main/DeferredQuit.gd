class_name DeferredQuit
extends RefCounted
## Close-request handling used by AppLoader.

## Test seam: when valid, replaces the real quit.
var quit_callable: Callable = Callable()

var _requested: bool = false
var _done: bool = false


## Marks QuitFlag unless quit_callable is valid; quits now when not busy, else defers.
func on_close_request(busy: bool) -> void:
	if not quit_callable.is_valid():
		QuitFlag.mark()
	_requested = true
	settle(busy)


## Call when the in-flight work finishes; quits if a close was requested.
func settle(busy: bool) -> void:
	if not _requested or busy or _done:
		return
	_done = true
	if quit_callable.is_valid():
		quit_callable.call()
	else:
		Sfx.quit_tree()  # marks QuitFlag, drains audio, then quits


func is_requested() -> bool:
	return _requested


func is_done() -> bool:
	return _done
