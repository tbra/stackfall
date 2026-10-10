class_name UiField
extends VBoxContainer
## STUB (Bontago-1pi.159.4 C1a): the typed public API of the design system's Field (dust label above
## a sunken LineEdit, placeholder token). Built in C2.
## TODO(C2): label + LineEdit styling, row item METER-style fill.

@warning_ignore("unused_signal")
signal text_changed(new_text: String)
@warning_ignore("unused_signal")
signal text_submitted(new_text: String)

@export var label_text: String = ""
@export var placeholder: String = ""
@export var text: String = ""
