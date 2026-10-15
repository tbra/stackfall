class_name VolcanoEruptionFx
extends Node3D
## Cosmetic eruption particles of a VolcanoStructure (Bontago-1pi.85.30): a one-shot ember burst per
## block shot plus a light continuous plume, both GPUParticles3D, unshaded flat-colour low-poly embers
## that cool from lava orange to dark red and fade (matches the game's cel look). No net traffic: the
## structure drives it from its own replicated clock. Counts are bounded by
## VolcanoParticleTuning.max_particles, the graphics preset (particle_budget_scale, Low's
## low_preset_scale) and nothing emits until the structure erupts.

const EMBER_SPHERE_SEGMENTS: int = 6
const EMBER_SPHERE_RINGS: int = 3
## Visibility box half extent as a multiple of the speed-based travel distance.
const BOUNDS_MARGIN: float = 1.5
const ALPHA_START_FRACTION: float = 0.6
## Slowest ember as a share of the emitter speed.
const MIN_SPEED_FRACTION: float = 0.6

var _tuning: VolcanoParticleTuning = null
var _burst: GPUParticles3D = null
var _plume: GPUParticles3D = null
var _burst_amount: int = 0
var _plume_amount: int = 0


## Total live-particle budget for `tuning` under `preset` (null preset = full).
static func budget_for(tuning: VolcanoParticleTuning, preset: GraphicsPreset) -> int:
	if tuning == null:
		return 0
	var scale: float = 1.0
	if preset != null:
		scale = clampf(preset.particle_budget_scale, 0.0, 1.0)
		if not preset.ambient_life_enabled:
			scale *= tuning.low_preset_scale
	return maxi(int(floor(float(tuning.max_particles) * scale)), 0)


## Builds both emitters; counts are the tuning's, scaled down together to fit the budget.
func setup(tuning: VolcanoParticleTuning, preset: GraphicsPreset) -> void:
	_tuning = tuning
	if tuning == null:
		return
	var budget: int = budget_for(tuning, preset)
	var plume_wanted: int = int(ceil(tuning.ember_rate_per_s * tuning.lifetime_s))
	var wanted: int = maxi(tuning.burst_count + plume_wanted, 1)
	var fit: float = minf(1.0, float(budget) / float(wanted))
	_burst_amount = int(floor(float(tuning.burst_count) * fit))
	_plume_amount = int(floor(float(plume_wanted) * fit))
	if _burst_amount > 0:
		_burst = _make_emitter(_burst_amount, tuning.speed_mps, true)
		add_child(_burst)
	if _plume_amount > 0:
		_plume = _make_emitter(_plume_amount, tuning.speed_mps * tuning.plume_speed_ratio, false)
		add_child(_plume)


## Total particle slots the node can have alive at once.
func particle_count() -> int:
	return _burst_amount + _plume_amount


func has_burst_emitter() -> bool:
	return _burst != null


func has_plume_emitter() -> bool:
	return _plume != null


## True while any emitter is emitting.
func is_emitting() -> bool:
	return (_burst != null and _burst.emitting) or (_plume != null and _plume.emitting)


## One ember burst (one block shot).
func burst() -> void:
	if _burst == null:
		return
	_burst.restart()
	_burst.emitting = true


func set_plume_active(active: bool) -> void:
	if _plume != null:
		_plume.emitting = active


## Stops everything (end of the eruption); live embers finish their lifetime.
func stop() -> void:
	set_plume_active(false)
	if _burst != null:
		_burst.emitting = false


func _make_emitter(amount: int, speed: float, one_shot: bool) -> GPUParticles3D:
	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = _tuning.lifetime_s
	particles.one_shot = one_shot
	particles.explosiveness = 1.0 if one_shot else 0.0
	particles.emitting = false
	particles.local_coords = false
	particles.fixed_fps = 0
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var reach: float = speed * _tuning.lifetime_s * BOUNDS_MARGIN
	particles.visibility_aabb = AABB(Vector3(-reach, -reach, -reach), Vector3(reach, reach, reach) * 2.0)
	var process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = _tuning.spread_deg
	process.initial_velocity_min = speed * MIN_SPEED_FRACTION
	process.initial_velocity_max = speed
	process.gravity = Vector3(0.0, -_tuning.gravity_mps2, 0.0)
	process.scale_min = _tuning.size_min_m
	process.scale_max = _tuning.size_max_m
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, ALPHA_START_FRACTION, 1.0])
	gradient.colors = PackedColorArray([
		_tuning.color,
		_tuning.cool_color,
		Color(_tuning.cool_color, 0.0),
	])
	var ramp: GradientTexture1D = GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	particles.process_material = process
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = EMBER_SPHERE_SEGMENTS
	mesh.rings = EMBER_SPHERE_RINGS
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = material
	particles.draw_pass_1 = mesh
	return particles
