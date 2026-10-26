class_name StreamLibrary
extends RefCounted
## Cached audio stream loading from one directory: file IO, no scene tree.
## Names are matched case-insensitively against lower-case files; a miss is never cached.

var _root_dir: String
var _streams_by_name: Dictionary = {}
var _warned_missing: Dictionary = {}


func _init(root_dir: String) -> void:
	_root_dir = root_dir


func root_dir() -> String:
	return _root_dir


func available() -> bool:
	return DirAccess.dir_exists_absolute(_root_dir)


## Cached; null (and a one-shot print per name) when missing or not a .wav/.mp3.
func stream(filename: String) -> AudioStream:
	var key: String = filename.to_lower()
	if _streams_by_name.has(key):
		return _streams_by_name[key]
	var full_path: String = _root_dir.path_join(key)
	if not FileAccess.file_exists(full_path):
		if not _warned_missing.has(key):
			_warned_missing[key] = true
			print("StreamLibrary: expected file missing: %s" % full_path)
		return null
	var loaded: AudioStream = null
	if key.ends_with(".wav"):
		loaded = AudioStreamWAV.load_from_file(full_path)
	elif key.ends_with(".mp3"):
		loaded = AudioStreamMP3.load_from_file(full_path)
	if loaded != null:
		_streams_by_name[key] = loaded
	return loaded


func has_file(filename: String) -> bool:
	return FileAccess.file_exists(_root_dir.path_join(filename.to_lower()))


func release() -> void:
	_streams_by_name.clear()
