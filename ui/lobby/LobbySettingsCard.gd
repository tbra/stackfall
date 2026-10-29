class_name LobbySettingsCard extends VBoxContainer
## The lobby settings form. Stub: the filler package moves the controls, builders and handlers here.

## A user edit of any control (host only).
signal changed
## A row, section or Advanced visibility change; the lobby rewires focus.
signal layout_changed


## Everything except seat budget, roster, bot names and rng seed.
func config() -> MatchConfig:
	return null


## Wires data into the controls without emitting `changed`.
func apply(_config: MatchConfig) -> void:
	pass


## Host-only gating of every control.
func set_editable(_host: bool) -> void:
	pass


## Ordered settings focus stops, gated-off ones removed.
func focus_stops() -> Array[Control]:
	return []


func toggle_focused_advanced() -> void:
	pass


func sections() -> Array[UiSection]:
	return []
