class_name OptionsOverlay extends RefCounted
## Cached options menu with focus trap and restore. Stub: the filler package moves the shared block here.


## First open instantiates under `parent`; later opens present the cached menu.
func open(_parent: Node, _trap_root: Node, _on_closed: Callable) -> void:
	pass


func is_open() -> bool:
	return false


## Dismisses and restores focus; the caller's `on_closed` is not called.
func close() -> void:
	pass
