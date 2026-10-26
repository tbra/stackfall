class_name DeferredQuit
extends RefCounted
## STUB (P7 plan section 2.1): null-object bodies, nothing wired; the filler package P7-Iload implements it.
## Close-request handling shared by AppLoader and Boot.

## Test seam: when valid, replaces the real quit.
var quit_callable: Callable = Callable()


## Marks QuitFlag unless quit_callable is valid; quits now when not busy, else defers.
func on_close_request(_busy: bool) -> void:
	pass


## Call when the in-flight work finishes; quits if a close was requested.
func settle(_busy: bool) -> void:
	pass


func is_requested() -> bool:
	return false


func is_done() -> bool:
	return false
