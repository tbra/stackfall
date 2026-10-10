class_name UiSection
extends VBoxContainer
## STUB (Bontago-1pi.159.4 C1a): the typed public API of the design system's Section (header,
## summary, collapsible Advanced body), from ui/lobby/LobbySection.gd. Built in C2.
## TODO(C2): header + caret + summary, accept ChipToggle grids.

@export var title: String = ""
@export var summary: String = ""
var advanced_open: bool = false


func set_advanced_open(_open: bool) -> void:
	pass  # TODO(C2)
