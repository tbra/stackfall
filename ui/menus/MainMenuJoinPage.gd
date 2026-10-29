class_name MainMenuJoinPage extends VBoxContainer
## Main menu join page. Stub: the filler package moves the page here.

signal join_requested(address: String, port: int)
signal steam_join_requested(lobby_id: int)
signal back_requested


## Starts or stops LAN discovery and the Steam refresh countdown.
func set_active(_on: bool) -> void:
	pass
