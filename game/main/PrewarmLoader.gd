class_name PrewarmLoader
extends RefCounted
## STUB (P7 plan section 2.1): null-object bodies, nothing wired; the filler package P7-Iload implements it.
## Threaded and blocking resource loads behind overridable methods (tests subclass it).


func request(_path: String) -> bool:
	return false


func status(_path: String) -> ResourceLoader.ThreadLoadStatus:
	return ResourceLoader.THREAD_LOAD_INVALID_RESOURCE


func collect(_path: String) -> Resource:
	return null


func load_now(_path: String) -> Resource:
	return null


func exists(_path: String) -> bool:
	return false
