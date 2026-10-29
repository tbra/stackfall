class_name DebugTools
extends Node
## Debug-mode tool composition: sampler, F1 overlay, F2 pose overlay, F9 bot-cost overlay, CSV logger and (by flag) soak monitor and fuzzer. Main adds one instance when DebugMode.is_enabled().
## Interface stub: builds nothing until it is filled in.

## Debug tuning; DebugMode.config() is the default once built.
var config: DebugConfig = null
## The camera the pose overlay reads; set before add_child.
var camera: Camera3D = null
## The field the pose overlay reads; set before add_child.
var field: Field = null
## Build the soak monitor (the "soak" command-line flag).
var soak_enabled: bool = false
## Build the soak intent fuzzer (the "soak-fuzz" command-line flag).
var soak_fuzz_enabled: bool = false


func _ready() -> void:
	pass
