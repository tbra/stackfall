extends GutTest
## SkyEnvironmentWriter: a frame writes the expected fields, an identical frame writes none, a
## sun-dim-only change writes only light_energy, apply_preset owns glow / volumetric fog / deck.

const PRESET_PATHS: Array[String] = [
	"res://config/graphics/presets/low.tres",
	"res://config/graphics/presets/medium.tres",
	"res://config/graphics/presets/high.tres",
]
const DIMMED_ENERGY: float = 0.25
const BASE_BACKGROUND_ENERGY: float = 1.5

var _environment: Environment
var _light: DirectionalLight3D
var _writer: SkyEnvironmentWriter


func before_each() -> void:
	_environment = Environment.new()
	_environment.background_energy_multiplier = BASE_BACKGROUND_ENERGY
	_light = DirectionalLight3D.new()
	add_child_autofree(_light)
	_writer = SkyEnvironmentWriter.new()
	_writer.bind(_environment, _light)


func after_each() -> void:
	WeatherFogShader.reset_to_launch(get_tree())


func _frame() -> SkyFrame:
	var frame: SkyFrame = SkyFrame.new()
	frame.fog_light_color = Color(0.4, 0.5, 0.6, 1.0)
	frame.fog_density = 0.01
	frame.ambient_light_energy = 0.7
	frame.background_energy_scale = 0.5
	frame.light_energy = 1.2
	frame.light_color = Color(1.0, 0.9, 0.8, 1.0)
	frame.sun_direction = Vector3(0.5, 0.6, 0.1).normalized()
	frame.haze_strength = 0.3
	frame.haze_begin = 50.0
	frame.haze_end = 400.0
	return frame


func test_first_frame_writes_fields_and_values_land() -> void:
	var frame: SkyFrame = _frame()
	_writer.apply(frame, get_tree())
	assert_true(_writer.last_written.has(&"fog_density"))
	assert_true(_writer.last_written.has(&"light_energy"))
	assert_almost_eq(_environment.fog_density, 0.01, 0.0001)
	assert_almost_eq(_environment.ambient_light_energy, 0.7, 0.0001)
	assert_almost_eq(_environment.background_energy_multiplier, BASE_BACKGROUND_ENERGY * 0.5, 0.0001)
	assert_almost_eq(_light.light_energy, 1.2, 0.0001)
	assert_true(_environment.fog_enabled)
	assert_almost_eq(WeatherFogShader.ambient_strength, 0.3, 0.0001)


func test_identical_frame_writes_nothing() -> void:
	var frame: SkyFrame = _frame()
	_writer.apply(frame, get_tree())
	_environment.fog_density = 0.5  # a foreign write survives: an identical frame rewrites nothing
	_writer.apply(frame, get_tree())
	assert_eq(_writer.last_written.size(), 0)
	assert_almost_eq(_environment.fog_density, 0.5, 0.0001)


func test_sun_dim_only_change_writes_only_light_energy() -> void:
	var frame: SkyFrame = _frame()
	_writer.apply(frame, get_tree())
	frame.light_energy = DIMMED_ENERGY
	_writer.apply(frame, get_tree())
	assert_eq(_writer.last_written, [&"light_energy"] as Array[StringName])
	assert_almost_eq(_light.light_energy, DIMMED_ENERGY, 0.0001)


func test_haze_pushed_only_when_its_inputs_change() -> void:
	var frame: SkyFrame = _frame()
	_writer.apply(frame, get_tree())
	WeatherFogShader.ambient_strength = 0.9  # a foreign write survives an unneeded push
	_writer.apply(frame, get_tree())
	assert_almost_eq(WeatherFogShader.ambient_strength, 0.9, 0.0001, "unchanged inputs: no push")
	frame.haze_end = 500.0
	_writer.apply(frame, get_tree())
	assert_almost_eq(WeatherFogShader.ambient_strength, 0.3, 0.0001, "changed input: pushed")
	assert_almost_eq(WeatherFogShader.ambient_end_m, 500.0, 0.0001)


func test_depth_fog_mode_and_restore_to_captured_base() -> void:
	_environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	_environment.fog_depth_begin = 7.0
	_environment.fog_depth_end = 70.0
	_environment.fog_depth_curve = 2.0
	_writer.bind(_environment, _light)
	var frame: SkyFrame = _frame()
	frame.fog_depth_mode = true
	frame.fog_depth_begin = 10.0
	frame.fog_depth_end = 100.0
	_writer.apply(frame, get_tree())
	assert_eq(_environment.fog_mode, Environment.FOG_MODE_DEPTH)
	assert_almost_eq(_environment.fog_depth_end, 100.0, 0.0001)
	assert_almost_eq(_environment.fog_density, 0.01, 0.0001, "set_fog_mode resets density; rewritten")
	frame.fog_depth_mode = false
	_writer.apply(frame, get_tree())
	assert_eq(_environment.fog_mode, Environment.FOG_MODE_EXPONENTIAL)
	assert_almost_eq(_environment.fog_depth_begin, 7.0, 0.0001)
	assert_almost_eq(_environment.fog_depth_curve, 2.0, 0.0001)
	assert_almost_eq(_environment.fog_density, 0.01, 0.0001)


func test_light_follows_sun_basis_then_fixed_rotation() -> void:
	var frame: SkyFrame = _frame()
	_writer.apply(frame, get_tree())
	var forward: Vector3 = -_light.global_basis.z
	assert_true(forward.is_equal_approx(-frame.sun_direction), "light looks along -sun")
	frame.light_uses_sun_basis = false
	frame.light_rotation_deg = Vector3(-30.0, 45.0, 0.0)
	_writer.apply(frame, get_tree())
	assert_true(_light.rotation_degrees.is_equal_approx(frame.light_rotation_deg))


func test_deck_spawn_sync_and_material_follow_frame() -> void:
	var parent: Node3D = Node3D.new()
	add_child_autofree(parent)
	var def: SkyCycleDef = SkyCycleDef.new()
	var deck: FogVolume = _writer.spawn_deck(parent, def)
	assert_eq(deck.get_parent(), parent)
	assert_eq(deck.size, def.cloud_deck_size_m)
	def.cloud_deck_height_m = -10.0
	_writer.sync_deck(def)
	assert_almost_eq(deck.position.y, -10.0, 0.0001)
	var frame: SkyFrame = _frame()
	frame.deck_density = 0.4
	frame.deck_albedo = Color(0.2, 0.3, 0.4, 1.0)
	_writer.apply(frame, get_tree())
	var fog_material: FogMaterial = deck.material as FogMaterial
	assert_almost_eq(fog_material.density, 0.4, 0.0001)
	assert_eq(fog_material.albedo, frame.deck_albedo)


func test_apply_preset_matches_each_preset() -> void:
	var parent: Node3D = Node3D.new()
	add_child_autofree(parent)
	var deck: FogVolume = _writer.spawn_deck(parent, SkyCycleDef.new())
	for path: String in PRESET_PATHS:
		var preset: GraphicsPreset = load(path) as GraphicsPreset
		_writer.apply_preset(preset)
		assert_eq(_environment.glow_enabled, preset.glow_enabled, path)
		assert_eq(_environment.volumetric_fog_enabled, preset.volumetric_fog_enabled, path)
		assert_eq(deck.visible, preset.volumetric_fog_enabled, path)


func test_apply_preset_before_spawn_sets_deck_visibility_and_null_is_noop() -> void:
	var low: GraphicsPreset = load(PRESET_PATHS[0]) as GraphicsPreset
	_writer.apply_preset(low)
	var parent: Node3D = Node3D.new()
	add_child_autofree(parent)
	var deck: FogVolume = _writer.spawn_deck(parent, SkyCycleDef.new())
	assert_eq(deck.visible, low.volumetric_fog_enabled)
	_writer.apply_preset(null)
	assert_eq(_writer.last_written.size(), 0)
