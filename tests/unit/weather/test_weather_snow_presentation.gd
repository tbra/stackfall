extends GutTest
## Snow presentation (Bontago-mp0.97, owner playtest: "snow particle effects
## is too subtle"): the falling flakes take their visibility numbers from
## config/weather/snow.tres, the flake shader gets them, the Low preset still
## draws fewer, and the flakes thin out and stop early in the ramp-out so the
## melt that follows is seen with the snowfall over.

const SHARE_TOLERANCE: float = 0.001

var _snow: SnowPresentation = null
var _tuning: SnowTuning = null


func before_each() -> void:
	_snow = (load("res://game/weather/snow_presentation.tscn") as PackedScene).instantiate() as SnowPresentation
	_tuning = _snow.tuning
	add_child_autofree(_snow)
	_snow.set_process(false)
	_snow._on_graphics_preset_changed(_preset(&"high", 1.0))


func _preset(id: StringName, density_scale: float) -> GraphicsPreset:
	var preset: GraphicsPreset = GraphicsPreset.new()
	preset.id = id
	preset.weather_density_scale = density_scale
	return preset


func test_flakes_follow_the_intensity_while_building_up() -> void:
	_snow.set_intensity(0.0)
	assert_false(_snow.particles().emitting)
	_snow.set_intensity(0.5)
	assert_almost_eq(_snow.particles().amount_ratio, 0.5, SHARE_TOLERANCE)
	assert_true(_snow.particles().emitting)
	_snow.set_intensity(1.0)
	assert_almost_eq(_snow.particles().amount_ratio, 1.0, SHARE_TOLERANCE)


func test_flakes_thin_out_and_stop_early_in_the_ramp_out() -> void:
	_snow.set_intensity(1.0)
	var stop: float = _tuning.flake_stop_intensity
	assert_gt(stop, 0.0)
	# Falling: the same intensity has fewer flakes than it did while building up.
	_snow.set_intensity(0.75)
	var falling: float = _snow.particles().amount_ratio
	assert_lt(falling, 0.75, "ramp-out thins the flakes faster than the intensity")
	_snow.set_intensity(stop + 0.01)
	assert_lt(_snow.particles().amount_ratio, 0.05)
	assert_true(_snow.particles().emitting)
	_snow.set_intensity(stop)
	assert_eq(_snow.particles().amount_ratio, 0.0, "snowfall is over while the intensity is still above zero")
	assert_false(_snow.particles().emitting)
	_snow.set_intensity(stop * 0.5)
	assert_false(_snow.particles().emitting, "and stays over for the rest of the melt")
	assert_true(_snow.visible, "the presentation node itself lives on until the weather stops")


func test_low_preset_and_governor_scale_apply_on_top() -> void:
	_snow.set_intensity(1.0)
	_snow._on_graphics_preset_changed(_preset(&"low", 0.5))
	assert_almost_eq(_snow.particles().amount_ratio, 0.5, SHARE_TOLERANCE, "the governor scale multiplies the density")
	var expected: int = int(roundf(float(_tuning.flake_amount_low) * _snow._fall_ratio))
	assert_eq(_snow.particles().amount, expected, "Low draws the Low flake count")
