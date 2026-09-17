extends Node3D
## M1 physics sandbox: a static disk, an orbit camera, and a player
## controller holding a ghost-preview block fed from the M1 placeholder
## random feed. No territory rules yet (M2) — every placement is valid.


func _ready() -> void:
	print(_boot_line())


## One-line report of the settings M0 is required to get right (spec 3.1, 3.5).
func _boot_line() -> String:
	var version: String = str(Engine.get_version_info().get("string", "unknown"))
	var physics_engine: String = str(ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	var ticks: int = Engine.physics_ticks_per_second
	var interpolated: bool = bool(ProjectSettings.get_setting("physics/common/physics_interpolation", false))
	var renderer: String = str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"))
	return "Stackfall boot | godot %s | renderer %s | physics %s | %d Hz | interpolation %s" % [
		version, renderer, physics_engine, ticks, interpolated,
	]
