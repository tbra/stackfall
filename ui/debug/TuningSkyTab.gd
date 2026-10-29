class_name TuningSkyTab
extends RefCounted
## The F4 panel's Sky tab model: sky resources, time-of-day state and live apply. Stub: returns
## empty values and does nothing until it is filled in.

const TIME_RUNNING: String = "running"
const TIME_CUSTOM: String = "custom"
const TIME_OF_DAY_CHOICES: PackedStringArray = [TIME_RUNNING, TIME_CUSTOM]
const TIME_OF_DAY_DEFAULT_CUSTOM_PHASE: float = 0.25
const TIME_OF_DAY_PHASE_EPSILON: float = 0.001

var time_choice: String = TIME_RUNNING


func _init(_cycle: SkyCycleDef, _overlay: SkyOverlayDef, _skybox_config: SkyboxConfig, _tree: SceneTree) -> void:
	pass


func resources() -> Array[Resource]:
	return []


func owns(_resource: Resource) -> bool:
	return false


func section_tag(_resource: Resource) -> String:
	return ""


func shipped_counterpart(_resource: Resource) -> Resource:
	return null


func has_running_cycle() -> bool:
	return false


func displayed_phase() -> float:
	return 0.0


func apply_time_of_day(_choice: String) -> bool:
	return false


func apply_custom_time_of_day(_phase: float) -> void:
	pass


## True when the edit was the tab's own.
func on_field_changed(_resource: Resource, _prop: String) -> bool:
	return false


func reset() -> void:
	pass
