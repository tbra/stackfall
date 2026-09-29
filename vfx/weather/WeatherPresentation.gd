class_name WeatherPresentation
extends Node3D
## Base for a weather's client-side visuals (Bontago-22y.10). The presenter
## instances a presentation scene whose root extends this and feeds it the
## ramped intensity 0..1. Placeholders do nothing; Wind/Rain/Snow packages
## replace the scenes. Presentation only: never touches physics.

var intensity: float = 0.0


func set_intensity(value: float) -> void:
	intensity = value
	visible = value > 0.0
