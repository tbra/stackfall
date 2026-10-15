class_name FreezeBurst
extends Node3D
## Bontago-a3z (owner: "freeze activating could use some nice effect"): the Freeze
## gift's activation burst, drawn by GiftFxPresenter on every peer from the replicated
## special_triggered. Visual only; the freeze itself is FreezeEffect (host) and the
## per-block frost overlay (Block.set_frozen_visual).
##
## Layers (FreezeFxTuning): a snowflake flash, a cluster of cel-shaded ice shards that
## burst out of the trigger point leaning outward, pop with an overshoot and shrink
## away, and a frost ring with a faint fill that grows to the freeze radius, so the
## area the gift covers reads at a glance. The node frees itself at the end.

const PUFF_SHADER: Shader = preload("res://shaders/gifts/cartoon_blast_puff.gdshader")
const FLASH_SHADER: Shader = preload("res://shaders/gifts/cartoon_blast_flash.gdshader")
const HEAT_PARAM: StringName = &"heat"
## The spike mesh is unit height, centred; this lifts its base onto the node origin.
const SHARD_BASE_OFFSET: Vector3 = Vector3(0.0, 0.5, 0.0)
const SPIKE_SIDES: int = 6
static var _spike: CylinderMesh = null

var tuning: FreezeFxTuning = null
var _age_s: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _shards: Array[MeshInstance3D] = []
var _shard_bases: Array[Vector3] = []
var _shard_tilts: Array[Basis] = []
var _shard_sizes: Array[Vector3] = []
var _shard_delays: PackedFloat32Array = PackedFloat32Array()
var _flash: MeshInstance3D = null
var _flash_material: ShaderMaterial = null
var _ring: FxRing = null


func _init() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	set_process(false)


## Builds the burst for a freeze of `radius_m`; call once placed at the trigger point.
func setup(t: FreezeFxTuning, radius_m: float, shape_seed: int = 0) -> void:
	tuning = t
	_rng.seed = shape_seed
	_build_shards()
	_build_flash()
	_ring = FxRing.new()
	add_child(_ring)
	_ring.position = Vector3.UP * tuning.ring_lift_m
	_ring.setup(tuning.ring_color, radius_m, tuning.ring_width_m, tuning.ring_s, tuning.ring_fill)
	advance(0.0)
	set_process(true)


## Moves the burst `delta` seconds on; false once it has finished.
func advance(delta: float) -> bool:
	if tuning == null:
		return false
	_age_s += delta
	_advance_shards()
	_advance_flash()
	if _ring != null:
		_ring.advance(delta)
	return _age_s < tuning.duration_s


func shard_count() -> int:
	return _shards.size()


func _process(delta: float) -> void:
	if not advance(delta):
		queue_free()


func _build_shards() -> void:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = PUFF_SHADER
	material.set_shader_parameter(&"hot_color", tuning.ice_light)
	material.set_shader_parameter(&"fire_color", tuning.ice_mid)
	material.set_shader_parameter(&"smoke_color", tuning.ice_shadow)
	material.set_shader_parameter(&"outline_color", tuning.ice_outline)
	material.set_shader_parameter(&"outline_width", tuning.ice_outline_width)
	material.set_shader_parameter(&"hot_glow", tuning.ice_glow)
	var count: int = maxi(tuning.shard_count, 0)
	for i: int in range(count):
		# Even spacing plus jitter, so the burst reads as a ring of spikes, not a clump.
		var angle: float = TAU * (float(i) + _rng.randf()) / float(maxi(count, 1))
		var flat: Vector2 = Vector2.from_angle(angle)
		var outward: Vector3 = Vector3(flat.x, 0.0, flat.y)
		var distance: float = _rng.randf_range(tuning.shard_min_distance_m, tuning.shard_max_distance_m)
		_shard_bases.append(outward * distance)
		_shard_tilts.append(Basis(Vector3.UP.cross(outward).normalized(), deg_to_rad(tuning.shard_lean_deg)))
		var height: float = tuning.shard_height_m * (1.0 + tuning.shard_height_jitter * _rng.randf_range(-1.0, 1.0))
		_shard_sizes.append(Vector3(tuning.shard_width_m, height, tuning.shard_width_m))
		_shard_delays.append(_rng.randf() * tuning.shard_stagger_s)
		var shard: MeshInstance3D = MeshInstance3D.new()
		shard.mesh = _unit_spike()
		shard.material_override = material
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shard.set_instance_shader_parameter(
			HEAT_PARAM, _rng.randf_range(tuning.shard_tone_min, tuning.shard_tone_max)
		)
		shard.visible = false
		add_child(shard)
		_shards.append(shard)


func _build_flash() -> void:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2.ONE
	_flash_material = ShaderMaterial.new()
	_flash_material.shader = FLASH_SHADER
	_flash_material.set_shader_parameter(&"flash_color", tuning.flash_color)
	_flash_material.set_shader_parameter(&"points", float(tuning.flash_points))
	_flash = MeshInstance3D.new()
	_flash.mesh = quad
	_flash.material_override = _flash_material
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.extra_cull_margin = tuning.flash_size_m
	add_child(_flash)


func _advance_shards() -> void:
	var shrink: float = FxEase.shrink(_age_s, tuning.duration_s, tuning.shard_shrink_start)
	for i: int in range(_shards.size()):
		var size: float = FxEase.pop(_age_s - _shard_delays[i], tuning.shard_pop_s, tuning.shard_overshoot) * shrink
		var shard: MeshInstance3D = _shards[i]
		shard.visible = size > 0.0
		if not shard.visible:
			continue
		var shaped: Basis = _shard_tilts[i] * Basis.from_scale(_shard_sizes[i] * size)
		shard.transform = Transform3D(shaped, _shard_bases[i] + shaped * SHARD_BASE_OFFSET)


func _advance_flash() -> void:
	var k: float = clampf(_age_s / tuning.flash_s, 0.0, 1.0) if tuning.flash_s > 0.0 else 1.0
	_flash.visible = k < 1.0
	_flash_material.set_shader_parameter(&"size", tuning.flash_size_m * (0.5 + 0.5 * sqrt(k)))
	_flash_material.set_shader_parameter(&"alpha_scale", 1.0 - k * k)


## A six-sided spike: unit height, base radius 0.5, centred on its origin.
static func _unit_spike() -> CylinderMesh:
	if _spike == null:
		_spike = CylinderMesh.new()
		_spike.top_radius = 0.0
		_spike.bottom_radius = 0.5
		_spike.height = 1.0
		_spike.radial_segments = SPIKE_SIDES
		_spike.rings = 1
	return _spike
