class_name StreamLibrary
extends RefCounted
## STUB (P7 plan section 2.2): null-object bodies, nothing wired; the filler package P7-Ilib implements it.
## Cached audio stream loading from one directory: file IO, no scene tree.


func _init(_root_dir: String) -> void:
	pass


func available() -> bool:
	return false


## Cached; null (and a one-shot warning in the filler) when missing.
func stream(_filename: String) -> AudioStream:
	return null


func has_file(_filename: String) -> bool:
	return false


func release() -> void:
	pass
