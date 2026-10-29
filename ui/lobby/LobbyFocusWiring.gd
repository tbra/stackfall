class_name LobbyFocusWiring extends RefCounted
## Lobby gamepad focus chain. Stub: the filler package moves the chain assembly here.

var _built: bool = false


## `tail_stops` returns the stops after the players panel (invite, ready, start).
func _init(_root: Control, _card: LobbySettingsCard, _panel: LobbyPlayersPanel, _tail_stops: Callable, _back: Button, _options: Button) -> void:
	pass


func build() -> void:
	pass


## No-op before `build()`.
func rewire() -> void:
	pass


func is_built() -> bool:
	return _built
