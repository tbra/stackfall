class_name SnowPresentation
extends WeatherPresentation
## Falling snow (Bontago-22y.6): one GPUParticles3D box that follows the active
## camera, flakes falling in world space, density scaled by the ramped
## intensity. Presentation only; the colliding snow is SnowEffect/SnowCaps.
##
## DECISION (vfx/weather/SnowPresentation.gd): the Low graphics preset is read
## by its id (GraphicsPreset has no weather field and is shared by other
## packages); Low only lowers the flake count, never the colliding snow, so
## gameplay is identical on every preset.

const LOW_PRESET_ID: StringName = &"low"
const FLAKE_SHADER: Shader = preload("res://shaders/weather/snow_flake.gdshader")
## DECISION: guards the fall quantisation against a zero/negative tuned step
## (pure math, not a tunable).
const MIN_FALL_STEP_M: float = 0.1

var tuning: SnowTuning = preload("res://config/weather/snow.tres") as SnowTuning

var _particles: GPUParticles3D = null
## Bontago-1pi.11.37: GraphicsPreset.weather_density_scale, applied through amount_ratio.
var _density_scale: float = 1.0
## Bontago-mp0.19: fall distance now emitted (quantised) and its ratio to the
## tuned fall; the flake lifetime and amount scale with it so the snow starts
## at the cloud ceiling at unchanged density.
var _fall_m: float = 0.0
var _fall_ratio: float = 1.0


func _ready() -> void:
	_build()
	Settings.graphics_preset_changed.connect(_on_graphics_preset_changed)
	set_intensity(intensity)


func _exit_tree() -> void:
	if Settings.graphics_preset_changed.is_connected(_on_graphics_preset_changed):
		Settings.graphics_preset_changed.disconnect(_on_graphics_preset_changed)


func particles() -> GPUParticles3D:
	return _particles


func amount_for(preset: GraphicsPreset) -> int:
	if preset != null and preset.id == LOW_PRESET_ID:
		return maxi(tuning.flake_amount_low, 1)
	return maxi(tuning.flake_amount, 1)


func set_intensity(value: float) -> void:
	super.set_intensity(value)
	if _particles != null:
		_particles.amount_ratio = clampf(value, 0.0, 1.0) * _density_scale
		_particles.emitting = value > 0.0


func _process(_delta: float) -> void:
	var viewport: Viewport = get_viewport()
	var camera: Camera3D = viewport.get_camera_3d() if viewport != null else null
	if camera != null:
		var ceiling: WeatherCeilingTuning = CloudCeiling.TUNING
		var camera_pos: Vector3 = camera.global_position
		var bottom: float = camera_pos.y - ceiling.snow_below_camera_m
		var top: float = minf(ceiling.ceiling_y(camera_pos.y) - ceiling.spawn_below_ceiling_m, bottom + ceiling.snow_max_fall_m)
		top = maxf(top, camera_pos.y + tuning.flake_height_above_camera_m)
		global_position = Vector3(camera_pos.x, top, camera_pos.z)
		_apply_fall(top - bottom, ceiling.snow_fall_step_m)


## Resizes the flake lifetime/amount/culling box for a `fall_m` fall (rounded
## up to `step_m`); a no-op while the rounded value is unchanged.
func _apply_fall(fall_m: float, step_m: float) -> void:
	if _particles == null:
		return
	var step: float = maxf(step_m, MIN_FALL_STEP_M)
	var rounded: float = ceilf(fall_m / step) * step
	if is_equal_approx(rounded, _fall_m):
		return
	_fall_m = rounded
	var base_fall: float = tuning.flake_fall_speed * tuning.flake_lifetime_s
	_fall_ratio = maxf(rounded / maxf(base_fall, 0.001), 1.0)
	_particles.lifetime = tuning.flake_lifetime_s * _fall_ratio
	_particles.amount = int(roundf(float(amount_for(Settings.current_graphics_preset())) * _fall_ratio))
	var fall: float = tuning.flake_fall_speed * (1.0 + tuning.flake_jitter) * _particles.lifetime
	var extent: Vector3 = tuning.flake_box_half_extent
	_particles.visibility_aabb = AABB(Vector3(-extent.x, -fall - extent.y, -extent.z), Vector3(extent.x * 2.0, fall + extent.y * 2.0, extent.z * 2.0))


func _on_graphics_preset_changed(preset: GraphicsPreset) -> void:
	_density_scale = preset.weather_density_scale if preset != null else 1.0
	if _particles != null:
		var amount: int = int(roundf(float(amount_for(preset)) * _fall_ratio))
		if _particles.amount != amount:
			_particles.amount = amount
		_particles.amount_ratio = clampf(intensity, 0.0, 1.0) * _density_scale


func _build() -> void:
	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = tuning.flake_box_half_extent
	process.direction = Vector3.DOWN
	process.spread = rad_to_deg(atan(tuning.flake_drift))
	process.initial_velocity_min = tuning.flake_fall_speed * (1.0 - tuning.flake_jitter)
	process.initial_velocity_max = tuning.flake_fall_speed * (1.0 + tuning.flake_jitter)
	process.gravity = Vector3.ZERO
	process.scale_min = 1.0 - tuning.flake_jitter
	process.scale_max = 1.0 + tuning.flake_jitter
	process.turbulence_enabled = tuning.flake_drift > 0.0
	process.turbulence_noise_strength = tuning.flake_drift
	process.turbulence_influence_min = 0.0
	process.turbulence_influence_max = tuning.flake_drift

	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = FLAKE_SHADER
	material.set_shader_parameter(&"flake_color", tuning.flake_color)

	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2.ONE * tuning.flake_size_m
	quad.material = material

	_particles = GPUParticles3D.new()
	_particles.name = "Flakes"
	var build_preset: GraphicsPreset = Settings.current_graphics_preset()
	_particles.amount = amount_for(build_preset)
	_density_scale = build_preset.weather_density_scale if build_preset != null else 1.0
	_particles.lifetime = tuning.flake_lifetime_s
	_particles.local_coords = false
	_particles.process_material = process
	_particles.draw_pass_1 = quad
	_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Weather layer: the disc mirror does not reflect falling flakes (the caps
	# stay on the default layer and do mirror, like the blocks they sit on).
	_particles.layers = RainPresentation.RENDER_LAYER_BIT
	var fall: float = tuning.flake_fall_speed * (1.0 + tuning.flake_jitter) * tuning.flake_lifetime_s
	var extent: Vector3 = tuning.flake_box_half_extent
	_particles.visibility_aabb = AABB(Vector3(-extent.x, -fall - extent.y, -extent.z), Vector3(extent.x * 2.0, fall + extent.y * 2.0, extent.z * 2.0))
	add_child(_particles)
