extends Node3D
## CLI adapter over the same runtime fixture the sandbox uses.
func _ready() -> void:
	var mode: String = "drop"
	var height: float = 2.0
	var interval: float = 2.0
	var tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
	var gap: float = tuning.hover_height / (tuning.cube_size - tuning.cube_margin)
	var offset: float = 0.0
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):
			mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--drop-height-cubes="):
			height = arg.trim_prefix("--drop-height-cubes=").to_float()
		elif arg.begins_with("--stack-interval-s="):
			interval = arg.trim_prefix("--stack-interval-s=").to_float()
		elif arg.begins_with("--stack-gap-cubes="):
			gap = arg.trim_prefix("--stack-gap-cubes=").to_float()
		elif arg.begins_with("--offset-cubes="):
			offset = arg.trim_prefix("--offset-cubes=").to_float()
		elif arg.begins_with("--preset="):
			tuning = load("res://config/physics_presets/" + arg.trim_prefix("--preset=") + ".tres") as PhysicsTuning
	if tuning == null:
		push_error("PHYSICS_COMPARE unknown preset")
		get_tree().quit(2)
		return
	var field: Field = Field.new()
	field.tuning = tuning
	add_child(field)
	var trial: PhysicsComparison = PhysicsComparison.new()
	trial.tuning = tuning
	add_child(trial)
	trial.finished.connect(func(result: Dictionary) -> void:
		print("PHYSICS_COMPARE result=" + JSON.stringify(result))
		get_tree().quit(1 if result.has("error") else 0)
	)
	if not trial.start(field, mode, height, interval, gap, Vector3.ZERO, offset):
		push_error("PHYSICS_COMPARE invalid mode or height/interval/gap")
		get_tree().quit(2)
