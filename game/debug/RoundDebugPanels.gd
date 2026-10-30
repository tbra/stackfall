class_name RoundDebugPanels
extends Node
## F2 pose, F3 net and F9 bot-cost panels of one match. MainMatchFlow adds it with the world and frees it with the world.
## Interface stub: builds nothing until it is filled in.

## The camera the pose panel reads; set before add_child.
var camera: Camera3D = null
## The field the pose panel reads; set before add_child.
var field: Field = null
## Match state the panels read; injected by the builder.
var match_context: MatchContext = null
## Debug tuning; DebugMode.config() is the default once built.
var config: DebugConfig = null


func _ready() -> void:
	pass
