extends GutTest
## Bontago-mp0.140: the disc looks wet while it rains. The rain presentation drives
## the overlay's shader parameters from the ramped intensity (no net traffic).

const RAIN_PATH: String = "res://config/weather/rain.tres"

var _rain: RainTuning = null
var _field: Field = null
var _overlay: TerritoryOverlay = null


func before_each() -> void:
	_rain = load(RAIN_PATH) as RainTuning
	var map_def: MapDef = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	map_def.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = map_def
	add_child_autofree(_field)
	_overlay = _field.overlay()


func _param(key: StringName) -> float:
	return float(_overlay.material().get_shader_parameter(key))


func _presentation() -> RainPresentation:
	var p: RainPresentation = RainPresentation.new()
	add_child_autofree(p)
	p.configure(_rain, 1.0)
	return p


func test_dry_without_rain() -> void:
	assert_not_null(_overlay)
	assert_almost_eq(_param(&"wet_darken"), 0.0, 0.00001)
	var dry_rough: float = _param(&"base_roughness")
	_overlay.set_wet(0.0, _rain.wet_sheen_add, _rain.wet_roughness_scale, _rain.wet_darken)
	assert_almost_eq(_param(&"wet_darken"), 0.0, 0.00001)
	assert_almost_eq(_param(&"base_roughness"), dry_rough, 0.00001)


func test_wetness_follows_rain_intensity_and_clears() -> void:
	var dry_rough: float = _param(&"base_roughness")
	var dry_sheen: float = _param(&"disk_sheen_strength")
	var p: RainPresentation = _presentation()
	p.set_intensity(0.5)
	var half: float = _param(&"wet_darken")
	assert_almost_eq(half, _rain.wet_darken * 0.5, 0.0001, "eases with intensity")
	p.set_intensity(1.0)
	assert_almost_eq(_param(&"wet_darken"), _rain.wet_darken, 0.0001, "tuned target at full rain")
	assert_gt(_param(&"wet_darken"), half)
	assert_lt(_param(&"base_roughness"), dry_rough, "shinier")
	assert_gt(_param(&"disk_sheen_strength"), dry_sheen, "more sheen")
	p.set_intensity(0.0)
	assert_almost_eq(_param(&"wet_darken"), 0.0, 0.00001)
	assert_almost_eq(_param(&"base_roughness"), dry_rough, 0.00001)
	assert_almost_eq(_param(&"disk_sheen_strength"), dry_sheen, 0.00001)
