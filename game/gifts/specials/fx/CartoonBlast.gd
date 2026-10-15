class_name CartoonBlast
extends Node3D
## Bontago-a3z (owner: the Bomb/Rocket explosion "should be more cartoony"): a
## self-contained, visual-only blast drawn by GiftFxPresenter on every peer.
##
## Layers, all timed from one clock (GiftExplosionFxTuning):
## - a spiky star flash (shaders/gifts/cartoon_blast_flash.gdshader) that pops and fades;
## - a cluster of cel-shaded, dark-outlined fireball puffs
##   (shaders/gifts/cartoon_blast_puff.gdshader) that pop in with an overshoot, drift out
##   and up, cool from white-hot through orange to smoke, then shrink away;
## - a ground shock ring (FxRing);
## - a few dark debris chunks flung out under gravity, tumbling;
## - the original impact dust flipbook (ImpactPuff) as a ground layer.
## Sizes scale with the special's blast radius. The node frees itself at the end.
##
## DECISION: physics interpolation is off for this subtree; every transform is
## written from _process, so interpolating it would only add a frame of lag.

const PUFF_SHADER: Shader = preload("res://shaders/gifts/cartoon_blast_puff.gdshader")
const FLASH_SHADER: Shader = preload("res://shaders/gifts/cartoon_blast_flash.gdshader")
const HEAT_PARAM: StringName = &"heat"
## Shared unit meshes (radius/size 1), scaled per instance.
static var _sphere: SphereMesh = null
static var _box: BoxMesh = null

var tuning: GiftExplosionFxTuning = null
var blast_radius_m: float = 1.0
var _age_s: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _puffs: Array[MeshInstance3D] = []
var _puff_dirs: Array[Vector3] = []
var _puff_radii: PackedFloat32Array = PackedFloat32Array()
var _puff_delays: PackedFloat32Array = PackedFloat32Array()
var _puff_reach: PackedFloat32Array = PackedFloat32Array()
var _debris: Array[MeshInstance3D] = []
var _debris_velocity: Array[Vector3] = []
var _debris_axis: Array[Vector3] = []
var _flash: MeshInstance3D = null
var _flash_material: ShaderMaterial = null
var _ring: FxRing = null


func _init() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	set_process(false)


## Builds every layer for a blast of `radius_m` with `t`; call once the node is
## in the tree and placed at the blast point. `shape_seed` varies the cluster's shape.
func setup(t: GiftExplosionFxTuning, radius_m: float, shape_seed: int = 0) -> void:
	tuning = t
	blast_radius_m = maxf(radius_m, 0.0)
	_rng.seed = shape_seed
	var puff_material: ShaderMaterial = _make_puff_material()
	_build_puffs(puff_material)
	_build_debris(puff_material)
	_build_flash()
	_ring = FxRing.new()
	add_child(_ring)
	_ring.position = Vector3.UP * tuning.ring_lift_m
	_ring.setup(
		tuning.ring_color, tuning.ring_radius_per_blast_radius * blast_radius_m, tuning.ring_width_m, tuning.ring_s
	)
	if tuning.dust_enabled:
		_add_dust()
	advance(0.0)
	set_process(true)


## Moves the whole blast `delta` seconds on; false once it has finished.
func advance(delta: float) -> bool:
	if tuning == null:
		return false
	_age_s += delta
	_advance_puffs()
	_advance_debris(delta)
	_advance_flash()
	if _ring != null:
		_ring.advance(delta)
	return _age_s < tuning.duration_s


func puff_count() -> int:
	return _puffs.size()


func _process(delta: float) -> void:
	if not advance(delta):
		queue_free()


func _make_puff_material() -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = PUFF_SHADER
	material.set_shader_parameter(&"hot_color", tuning.hot_color)
	material.set_shader_parameter(&"fire_color", tuning.fire_color)
	material.set_shader_parameter(&"smoke_color", tuning.smoke_color)
	material.set_shader_parameter(&"outline_color", tuning.outline_color)
	material.set_shader_parameter(&"outline_width", tuning.outline_width)
	material.set_shader_parameter(&"hot_glow", tuning.hot_glow)
	return material


func _build_puffs(material: ShaderMaterial) -> void:
	var base_radius: float = tuning.puff_radius_per_blast_radius * blast_radius_m
	for i: int in range(maxi(tuning.puff_count, 0)):
		var flat: Vector2 = Vector2.from_angle(_rng.randf_range(0.0, TAU))
		var outward: Vector3 = Vector3(flat.x, 0.0, flat.y) * (1.0 - tuning.puff_upward_bias)
		outward += Vector3.UP * tuning.puff_upward_bias * _rng.randf()
		# The first puff stays at the centre as the cluster's core.
		var reach: float = 0.0 if i == 0 else sqrt(_rng.randf())
		_puff_dirs.append(outward.normalized() * reach)
		_puff_reach.append(reach)
		_puff_radii.append(base_radius * (1.0 + tuning.puff_radius_jitter * _rng.randf_range(-1.0, 1.0)))
		_puff_delays.append(0.0 if i == 0 else _rng.randf() * tuning.puff_stagger_s)
		var puff: MeshInstance3D = _make_mesh(_unit_sphere(), material)
		_puffs.append(puff)


func _build_debris(material: ShaderMaterial) -> void:
	for _i: int in range(maxi(tuning.debris_count, 0)):
		var flat: Vector2 = Vector2.from_angle(_rng.randf_range(0.0, TAU))
		var direction: Vector3 = Vector3(flat.x, _rng.randf_range(0.5, 2.0), flat.y).normalized()
		_debris_velocity.append(direction * tuning.debris_speed_mps * _rng.randf_range(0.5, 1.0))
		_debris_axis.append(Vector3(_rng.randf_range(-1.0, 1.0), 1.0, _rng.randf_range(-1.0, 1.0)).normalized())
		var chunk: MeshInstance3D = _make_mesh(_unit_box(), material)
		chunk.set_instance_shader_parameter(HEAT_PARAM, tuning.debris_tone)
		chunk.scale = Vector3.ONE * tuning.debris_size_m
		_debris.append(chunk)


func _build_flash() -> void:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2.ONE
	_flash_material = ShaderMaterial.new()
	_flash_material.shader = FLASH_SHADER
	_flash_material.set_shader_parameter(&"flash_color", tuning.flash_color)
	_flash_material.set_shader_parameter(&"points", float(tuning.flash_points))
	_flash = _make_mesh(quad, _flash_material)
	# The shader billboards and sizes the quad on the GPU; keep culling from hiding it.
	_flash.extra_cull_margin = tuning.flash_size_per_blast_radius * blast_radius_m


func _add_dust() -> void:
	var dust: ImpactPuff = ImpactPuff.new()
	add_child(dust)
	dust.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	dust.play(
		global_position, tuning.hard, blast_radius_m * tuning.size_per_blast_radius,
		tuning.tint, tuning.alpha, tuning.fps, tuning.frame_count
	)


func _make_mesh(mesh: Mesh, material: Material) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance


## Pop with overshoot, settle, then shrink away over the last part of the blast.
func _advance_puffs() -> void:
	var shrink: float = FxEase.shrink(_age_s, tuning.duration_s, tuning.puff_shrink_start)
	var spread: float = tuning.puff_spread_per_blast_radius * blast_radius_m
	var lift: Vector3 = Vector3.UP * tuning.puff_lift_radii * tuning.puff_radius_per_blast_radius * blast_radius_m
	for i: int in range(_puffs.size()):
		var puff: MeshInstance3D = _puffs[i]
		var local_s: float = _age_s - _puff_delays[i]
		var size: float = FxEase.pop(local_s, tuning.puff_pop_s, tuning.puff_overshoot) * shrink * _puff_radii[i]
		puff.visible = size > 0.0
		if not puff.visible:
			continue
		var travel: float = FxEase.out_quad(local_s / (tuning.puff_pop_s * 2.0)) if tuning.puff_pop_s > 0.0 else 1.0
		puff.position = lift + _puff_dirs[i] * spread * travel + Vector3.UP * tuning.puff_rise_mps * local_s
		puff.scale = Vector3.ONE * size
		var cooled_s: float = local_s + _puff_reach[i] * tuning.puff_outer_cool_lead_s
		var heat: float = 1.0 - clampf(cooled_s / tuning.puff_cool_s, 0.0, 1.0) if tuning.puff_cool_s > 0.0 else 0.0
		puff.set_instance_shader_parameter(HEAT_PARAM, heat)


func _advance_debris(delta: float) -> void:
	var fade: float = clampf(1.0 - _age_s / tuning.duration_s, 0.0, 1.0) if tuning.duration_s > 0.0 else 0.0
	for i: int in range(_debris.size()):
		var chunk: MeshInstance3D = _debris[i]
		_debris_velocity[i] += Vector3.DOWN * tuning.debris_gravity_mps2 * delta
		chunk.position += _debris_velocity[i] * delta
		chunk.visible = fade > 0.0
		if chunk.visible:
			chunk.basis = Basis(_debris_axis[i], tuning.debris_spin_rps * _age_s).scaled(
				Vector3.ONE * tuning.debris_size_m * fade
			)


func _advance_flash() -> void:
	if _flash == null:
		return
	var k: float = clampf(_age_s / tuning.flash_s, 0.0, 1.0) if tuning.flash_s > 0.0 else 1.0
	_flash.visible = k < 1.0
	var size: float = tuning.flash_size_per_blast_radius * blast_radius_m * (0.5 + 0.5 * sqrt(k))
	_flash_material.set_shader_parameter(&"size", size)
	_flash_material.set_shader_parameter(&"alpha_scale", 1.0 - k * k)


static func _unit_sphere() -> SphereMesh:
	if _sphere == null:
		_sphere = SphereMesh.new()
		_sphere.radius = 1.0
		_sphere.height = 2.0
	return _sphere


static func _unit_box() -> BoxMesh:
	if _box == null:
		_box = BoxMesh.new()
		_box.size = Vector3.ONE
	return _box
