class_name PrewarmLoader
extends RefCounted
## Threaded and blocking resource loads behind overridable methods (tests subclass it).


## True when the threaded request was queued.
func request(path: String) -> bool:
	return ResourceLoader.load_threaded_request(path) == OK


func status(path: String) -> ResourceLoader.ThreadLoadStatus:
	return ResourceLoader.load_threaded_get_status(path)


## Blocks until the threaded request finishes.
func collect(path: String) -> Resource:
	return ResourceLoader.load_threaded_get(path)


func load_now(path: String) -> Resource:
	return load(path)


func exists(path: String) -> bool:
	return ResourceLoader.exists(path)
