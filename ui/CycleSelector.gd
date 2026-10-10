class_name CycleSelector
extends UiDropdown
## The click-to-cycle control behind every short option list on a menu screen (Bontago-1pi.94).
## Bontago-1pi.159.7: now a thin compatibility layer over [UiDropdown] in CYCLE mode. The whole
## behaviour (items, select(), item_selected / cycled signals, auto_advance, list_tooltip, right
## click = previous, swallowed held ui_accept) lives in the component, so every caller keeps its
## class_name, API, stored int and wire format. What the layer keeps from the old control is the
## look and sizing: no chevron, no block styling and no row-item contract, because the screens
## (ui/Lobby.gd, ui/lobby/LobbySeatRow.gd, ui/GraphicsSettingsTab.gd, ui/OptionsMenu.gd) still
## size and style it themselves. Deleted by the Lobby / Options migrations (1pi.159.2 / 159.3),
## which use UiDropdown directly.


func _initial_mode() -> UiDropdown.Mode:
	return UiDropdown.Mode.CYCLE


func _initial_chevron() -> bool:
	return false


func _apply_row_contract() -> void:
	pass  # DECISION: legacy sizing stays caller-driven until the screen migrates to UiDropdown.


func _restyle() -> void:
	pass  # DECISION: legacy look stays theme + the caller's pill styling.
