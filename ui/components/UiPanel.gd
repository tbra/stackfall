class_name UiPanel
extends PanelContainer
## STUB (Bontago-1pi.159.4 C1a): the typed public API of the design system's Panel (disc-800 plate,
## heading with a flare bullet, a content column). Built in C2 together with the UiTitleRow helper.
## TODO(C2): plate from MenuStyleFactory.make_plate, heading, bullet.

@export var heading: String = ""
## Where screens add the panel's rows.
var content: VBoxContainer = null
