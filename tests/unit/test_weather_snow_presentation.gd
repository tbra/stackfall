extends GutTest
## Snow presentation (Bontago-mp0.97, owner playtest: "snow particle effects
## is too subtle"): the falling flakes take their visibility numbers from
## config/weather/snow.tres, the flake shader gets them, the Low preset still
## draws fewer, and the flakes thin out and stop early in the ramp-out so the
## melt that follows is seen with the snowfall over.

const SHADER_PATH: String = "res://shaders/weather/snow_flake.gdshader"
const SHARE_TOLERANCE: float = 0.001

var _snow: SnowPresentation = null
var _tuning: SnowTuning = null


func before_each() -> void:
	_snow = (load("res://vfx/weather/snow_presentation.tscn") as PackedScene).instantiate() as SnowPresentation
	_tuning = _snow.tuning
	add_child_autofree(_snow)
	_snow.set_process(false)
	_snow._on_graphics_preset_changed(_preset(&"high", 1.0))


func _preset(id: StringName, density_scale: float) -> GraphicsPreset:
	var preset: GraphicsPreset = GraphicsPreset.new()
	preset.id = id
	preset.weather_density_scale = density_scale
	return preset


func _flake_material() -> ShaderMaterial:
	return (_snow.particles().draw_pass_1 as QuadMesh).material as ShaderMaterial


func test_flakes_use_the_raised_config_values() -> void:
	assert_eq(_snow.amount_for(_preset(&"high", 1.0)), _tuning.flake_amount)
	assert_eq(_snow.amount_for(_preset(&"low", 1.0)), _tuning.flake_amount_low, "Low keeps the thinner set")
	assert_lt(_tuning.flake_amount_low, _tuning.flake_amount)
	assert_gt(_tuning.flake_amount, 1600, "denser than before the playtest")
	assert_gt(_tuning.flake_size_m, 0.1, "bigger than before the playtest")
	assert_true(_tuning.flake_prefill, "the column is full the moment snowfall starts")
	assert_gt(_tuning.flake_sim_fps, 0)
	var quad: QuadMesh = _snow.particles().draw_pass_1 as QuadMesh
	assert_eq(quad.size, Vector2.ONE * _tuning.flake_size_m, "the quad is the configured flake size")
	assert_eq(_snow.particles().lifetime, _tuning.flake_lifetime_s, "lifetime untouched until the ceiling fall is applied")


func test_flake_shader_gets_the_visibility_numbers() -> void:
	var material: ShaderMaterial = _flake_material()
	assert_eq(material.shader.resource_path, SHADER_PATH)
	assert_eq(material.get_shader_parameter(&"flake_color"), _tuning.flake_color)
	assert_eq(material.get_shader_parameter(&"edge_color"), _tuning.flake_edge_color)
	assert_eq(float(material.get_shader_parameter(&"edge_start")), _tuning.flake_edge_start)
	assert_eq(float(material.get_shader_parameter(&"flake_size")), _tuning.flake_size_m)
	assert_eq(float(material.get_shader_parameter(&"min_angle")), _tuning.flake_min_angle)
	assert_eq(float(material.get_shader_parameter(&"max_angle")), _tuning.flake_max_angle)
	assert_gt(float(material.get_shader_parameter(&"min_angle")), 0.0, "far flakes keep a minimum on-screen size")
	for uniform: String in ["flake_color", "edge_color", "edge_start", "flake_size", "min_angle", "max_angle"]:
		var names: Array[StringName] = []
		for entry: Dictionary in material.shader.get_shader_uniform_list():
			names.append(StringName(String(entry["name"])))
		assert_true(names.has(StringName(uniform)), "the flake shader declares %s" % uniform)


func test_flake_column_is_packed_near_the_view_not_up_to_the_clouds() -> void:
	var ceiling: WeatherCeilingTuning = CloudCeiling.TUNING
	var camera_y: float = 10.0
	var bottom: float = camera_y - _tuning.flake_below_camera_m
	var top: float = _snow.column_top(camera_y, ceiling)
	assert_almost_eq(top - bottom, _tuning.flake_max_column_m, 0.001, "the column is capped at flake_max_column_m")
	assert_lt(top - bottom, ceiling.snow_max_fall_m, "shorter than the ceiling fall, so the flakes are denser")
	assert_gte(top, camera_y + _tuning.flake_height_above_camera_m, "never starts level with the camera")
	var high_camera: float = _snow.column_top(200.0, ceiling)
	assert_almost_eq(high_camera - (200.0 - _tuning.flake_below_camera_m), _tuning.flake_max_column_m, 0.001)
	assert_gt(_tuning.flake_below_camera_m, ceiling.snow_below_camera_m, "flakes fall past the camera, down to the disc")


## Playtest capture: the dense flakes sat in one corner of the view and the far
## half was empty, because the box was centred on the camera while the camera
## looks across the play area. The box is centred ahead of the camera.
func test_flake_box_is_centred_ahead_of_the_camera_across_the_play_area() -> void:
	var camera_pos: Vector3 = Vector3(3.0, 20.0, 40.0)
	var look: Vector3 = Vector3(0.0, -20.0, -40.0).normalized()
	var centre: Vector3 = _snow.box_centre(camera_pos, look)
	assert_gt(_tuning.flake_forward_shift_m, 0.0)
	assert_almost_eq(centre.y, camera_pos.y, 0.0001, "ground-plane shift only")
	var shift: Vector3 = Vector3(centre.x - camera_pos.x, 0.0, centre.z - camera_pos.z)
	assert_almost_eq(shift.length(), _tuning.flake_forward_shift_m, 0.001, "moved flake_forward_shift_m")
	assert_lt(shift.z, 0.0, "towards where the camera looks")
	assert_almost_eq(shift.normalized().dot(Vector3(look.x, 0.0, look.z).normalized()), 1.0, 0.0001)
	# The view across the disc is covered: the box reaches well past the camera.
	var reach: float = _tuning.flake_forward_shift_m + _tuning.flake_box_half_extent.z
	assert_gt(reach, 25.0, "flakes in the far part of the view")
	assert_lt(_tuning.flake_forward_shift_m, _tuning.flake_box_half_extent.z, "the camera itself is still inside the box")
	# Straight down (or up): no horizontal direction, so no shift.
	assert_eq(_snow.box_centre(camera_pos, Vector3.DOWN), camera_pos)
	assert_eq(_snow.box_centre(camera_pos, Vector3.UP), camera_pos)


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
