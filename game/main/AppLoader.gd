class_name AppLoader
extends Node
## STUB (P7 plan section 2.1): null-object bodies, nothing wired; the filler package P7-Iload implements it.
## Background prewarm, late activation and scene loading for Main. Child of Main;
## properties are set before add_child.

signal loading_status_requested(text: String)
signal late_activated

var queue: MenuPrewarmQueue = null
var quit: DeferredQuit = null


func wants_background() -> bool:
	return false


func begin(_lobby_path: String) -> void:
	pass


## False when a close arrived during the splash.
func menu_shown(_lobby_path: String) -> bool:
	return false


func ensure_late_active() -> void:
	pass


## Coroutine in the filler.
func await_prewarmed(_paths: PackedStringArray) -> bool:
	return false


func load_scene(_path: String) -> PackedScene:
	return null


func ensure_script(_path: String) -> GDScript:
	return null


func is_late_active() -> bool:
	return false
