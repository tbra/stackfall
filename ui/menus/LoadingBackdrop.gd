class_name LoadingBackdrop extends TextureRect
## Loading-screen backdrop plate. Stub: the filler package moves the loader here.


func show_for(_config: MatchConfig, _fade_in_s: float) -> void:
	pass


func path_for(_config: MatchConfig) -> String:
	return ""


func finish_fade() -> void:
	pass


func clear() -> void:
	pass


static func threaded_texture_loads_safe() -> bool:
	return false


static func release_later(_resource: Resource) -> void:
	pass
