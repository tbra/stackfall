class_name WeatherPresentation
extends Node3D
## Base for a weather's client-side visuals. The presenter
## instances a presentation scene whose root extends this and feeds it the
## ramped intensity 0..1. Placeholders do nothing; Storm/Rain/Snow packages
## replace the scenes. Presentation only: never touches physics.

var intensity: float = 0.0
## Returns the live Array[Skybox]; set by WeatherPresenter before add_child, so
## a presentation never searches the tree for the sky it drives.
var skybox_source: Callable = Callable()


func skyboxes() -> Array[Skybox]:
	var found: Array[Skybox] = []
	if skybox_source.is_valid():
		found = skybox_source.call()
	return found


func set_intensity(value: float) -> void:
	intensity = value
	visible = value > 0.0
