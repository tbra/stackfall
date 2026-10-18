class_name BalloonRig
extends Node3D
## The Propeller gift party balloon, built from primitives and cel-shaded like the other
## gift models (GiftModelTable.TOON_SHADER plus the gift ink outline): a team-colour
## latex balloon with a knot and a highlight, a string and a clip ring at the drop point.
## The origin is the clip on the disc surface.
##
## PropellerStand poses it every tick (`pose`): the balloon inflates at the clip, rises on
## its string and sways. At the end of the blow the stand hands it to the Field and calls
## `begin_pop`: the body vanishes into confetti shards, the knotted rag falls down the
## string to the clip, and the rig frees itself (it advances from _process).
##
## Visual-only; every peer builds it from the replicated trigger and its own clock.
##
## DECISION: physics interpolation is off for this subtree; every transform is written
## from code, so interpolating it would only add a frame of lag.

## Fraction of the confetti life over which a shard shrinks away at the end.
const SHARD_FADE_FRACTION: float = 0.3
## Seconds the finished rig lingers after the last effect before it frees itself.
const FREE_LINGER_S: float = 0.2
## Floor for the balloon scale before the body is hidden, and a divide-by-zero guard.
const MIN_SCALE: float = 0.001
## A shard thickness and width as fractions of its edge size.
const SHARD_THICKNESS: float = 0.08
const SHARD_WIDTH: float = 0.6
## Sway phase ratio between the two axes, so the balloon traces a loop.
const SWAY_AXIS_RATIO: float = 0.83
## Upward bias of a confetti shard launch direction.
const SHARD_UP_BIAS: float = 0.45
## Fastest spin (rad/s) per axis of a confetti shard.
const SHARD_SPIN_MAX: float = 12.0
## The rag is a flattened sphere.
const RAG_FLATTEN: float = 0.45
## Highlight stretch (x, y, z) so it reads as a glossy streak.
const SHINE_STRETCH: Vector3 = Vector3(1.0, 1.6, 0.5)
## Lowest downward component of a confetti launch direction before the up bias.
const SHARD_DOWN_LIMIT: float = -0.3
## String and balloon tessellation.
const STRING_SEGMENTS: int = 6
const SPHERE_SEGMENTS: int = 24
const SPHERE_RINGS: int = 12
## Clip ring tessellation.
const CLIP_RINGS: int = 16
const CLIP_RING_SEGMENTS: int = 8

var tuning: BalloonFxTuning = null
var team_color: Color = Color.WHITE

var _body: Node3D = null
var _knot: MeshInstance3D = null
var _string: MeshInstance3D = null
var _pivot: Node3D = null
var _popped: bool = false
var _pop_age_s: float = 0.0
var _pop_origin: Vector3 = Vector3.ZERO
var _shards: Array[MeshInstance3D] = []
var _shard_velocity: Array[Vector3] = []
var _shard_spin: Array[Vector3] = []
var _knot_position: Vector3 = Vector3.ZERO
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	set_process(false)


## Builds the parts. Call once, before the node is posed.
func setup(t: BalloonFxTuning, color: Color, shape_seed: int = 0) -> void:
	tuning = t
	team_color = color
	_rng.seed = shape_seed
	_build_clip()
	_build_string()
	_build_balloon()
	pose(0.0, 0.0, 0.0, 0.0)


## Poses the balloon. `height_m` is the knot height above the clip, `inflate` runs 0..1
## (0 = nothing, 1 = full size, overshooting in between), `rise_fraction` (0..1) scales the
## sway, `time_s` is the stand clock.
func pose(height_m: float, inflate: float, rise_fraction: float, time_s: float) -> void:
	if tuning == null or _popped:
		return
	var sway: float = deg_to_rad(tuning.sway_deg) * clampf(rise_fraction, 0.0, 1.0)
	var phase: float = TAU * tuning.sway_hz * time_s
	var dir: Vector3 = Vector3(sin(sway * sin(phase)), 1.0, sin(sway * cos(phase * SWAY_AXIS_RATIO))).normalized()
	_knot_position = Vector3.UP * _clip_top() + dir * maxf(height_m, 0.0)
	_pivot.position = _knot_position
	_pivot.basis = Basis(Quaternion(Vector3.UP, dir))
	var s: float = _inflate_scale(inflate)
	_body.visible = s > MIN_SCALE
	_body.scale = Vector3.ONE * maxf(s, MIN_SCALE)
	_knot.visible = _body.visible
	_place_string(_knot_position)


## Scale for an inflate progress 0..1: ease-in plus an overshoot that settles to 1.
func _inflate_scale(inflate: float) -> float:
	var t: float = clampf(inflate, 0.0, 1.0)
	return smoothstep(0.0, 1.0, t) * (1.0 + tuning.inflate_overshoot * sin(PI * t))


## POP: confetti out of the body, the rag falls down the string. Idempotent.
func begin_pop() -> void:
	if _popped or tuning == null:
		return
	_popped = true
	_pop_age_s = 0.0
	_pop_origin = _knot_position + (_pivot.basis * Vector3.UP) * tuning.balloon_radius_m * tuning.balloon_height_ratio
	_body.visible = false
	_knot.visible = true
	_spawn_shards()
	set_process(true)


## One pop-phase step (public so tests drive it without the main loop).
func advance(delta: float) -> void:
	if not _popped:
		return
	_pop_age_s += delta
	var life: float = maxf(tuning.confetti_life_s, MIN_SCALE)
	for i: int in range(_shards.size()):
		var shard: MeshInstance3D = _shards[i]
		var age: float = minf(_pop_age_s, life)
		var gravity: Vector3 = Vector3.DOWN * (0.5 * tuning.confetti_gravity_mps2 * age * age)
		shard.position = _pop_origin + _shard_velocity[i] * age + gravity
		shard.rotation += _shard_spin[i] * delta
		var fade: float = clampf((life - _pop_age_s) / (life * SHARD_FADE_FRACTION), 0.0, 1.0)
		shard.visible = fade > 0.0
		shard.scale = Vector3.ONE * maxf(fade, MIN_SCALE)
	var fall: float = clampf(_pop_age_s / maxf(tuning.rag_fall_s, MIN_SCALE), 0.0, 1.0)
	var rag_at: Vector3 = _knot_position.lerp(Vector3.UP * _clip_top(), fall * fall)
	_pivot.position = rag_at
	_place_string(rag_at)
	if _pop_age_s >= maxf(life, tuning.rag_fall_s) + FREE_LINGER_S:
		queue_free()


func _process(delta: float) -> void:
	advance(delta)


func _clip_top() -> float:
	return tuning.clip_thickness_m * 2.0


func _build_clip() -> void:
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = maxf(tuning.clip_radius_m - tuning.clip_thickness_m, MIN_SCALE)
	torus.outer_radius = tuning.clip_radius_m + tuning.clip_thickness_m
	torus.rings = CLIP_RINGS
	torus.ring_segments = CLIP_RING_SEGMENTS
	var clip: MeshInstance3D = _mesh_instance(torus, _toon(tuning.clip_color))
	clip.position = Vector3.UP * tuning.clip_thickness_m
	add_child(clip)


func _build_string() -> void:
	var cylinder: CylinderMesh = CylinderMesh.new()
	cylinder.top_radius = tuning.string_width_m * 0.5
	cylinder.bottom_radius = tuning.string_width_m * 0.5
	cylinder.height = 1.0
	cylinder.radial_segments = STRING_SEGMENTS
	cylinder.rings = 1
	_string = _mesh_instance(cylinder, _toon(tuning.string_color))
	add_child(_string)


func _build_balloon() -> void:
	_pivot = Node3D.new()
	_pivot.name = &"Pivot"
	add_child(_pivot)
	var radius: float = tuning.balloon_radius_m
	var stretch: Vector3 = Vector3(1.0, tuning.balloon_height_ratio, 1.0)
	_knot = _mesh_instance(_sphere(tuning.knot_radius_m), _toon(team_color))
	_pivot.add_child(_knot)
	_body = Node3D.new()
	_body.name = &"Body"
	_pivot.add_child(_body)
	var latex: MeshInstance3D = _mesh_instance(_sphere(radius), _toon(team_color))
	latex.scale = stretch
	latex.position = Vector3.UP * radius * tuning.balloon_height_ratio
	_body.add_child(latex)
	var shine_material: StandardMaterial3D = StandardMaterial3D.new()
	shine_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shine_material.albedo_color = tuning.highlight_color
	var shine: MeshInstance3D = _mesh_instance(_sphere(radius * tuning.highlight_size), shine_material)
	shine.scale = SHINE_STRETCH
	shine.position = latex.position + tuning.highlight_offset.normalized() * radius * stretch
	_body.add_child(shine)


## Places the string between the clip and `top`.
func _place_string(top: Vector3) -> void:
	var from: Vector3 = Vector3.UP * _clip_top()
	var span: Vector3 = top - from
	var length: float = span.length()
	_string.visible = length > MIN_SCALE
	if not _string.visible:
		return
	_string.basis = Basis(Quaternion(Vector3.UP, span / length)).scaled(Vector3(1.0, length, 1.0))
	_string.position = from + span * 0.5


func _spawn_shards() -> void:
	var team_material: StandardMaterial3D = _flat(team_color)
	var white_material: StandardMaterial3D = _flat(tuning.confetti_white)
	var yellow_material: StandardMaterial3D = _flat(tuning.confetti_yellow)
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(tuning.confetti_size_m, tuning.confetti_size_m * SHARD_THICKNESS, tuning.confetti_size_m * SHARD_WIDTH)
	for i: int in range(maxi(tuning.confetti_count, 0)):
		var material: StandardMaterial3D = null
		if float(i) < float(tuning.confetti_count) * tuning.confetti_team_share:
			material = team_material
		else:
			material = white_material if i % 2 == 0 else yellow_material
		var shard: MeshInstance3D = _mesh_instance(box, material)
		add_child(shard)
		shard.position = _pop_origin
		var out: Vector3 = Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(SHARD_DOWN_LIMIT, 1.0) + SHARD_UP_BIAS, _rng.randf_range(-1.0, 1.0))
		_shard_velocity.append(out.normalized() * tuning.confetti_speed_mps * _rng.randf_range(0.5, 1.0))
		_shard_spin.append(Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * SHARD_SPIN_MAX)
		shard.rotation = Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU)
		_shards.append(shard)
	# The rag: the knot with a flattened empty balloon hanging off it.
	var rag_radius: float = tuning.balloon_radius_m * tuning.rag_size
	var rag: MeshInstance3D = _mesh_instance(_sphere(rag_radius), _toon(team_color))
	rag.scale = Vector3(1.0, RAG_FLATTEN, 1.0)
	rag.position = Vector3.UP * rag_radius * RAG_FLATTEN
	rag.name = &"Rag"
	_pivot.add_child(rag)


func _sphere(radius: float) -> SphereMesh:
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = SPHERE_SEGMENTS
	mesh.rings = SPHERE_RINGS
	return mesh


func _mesh_instance(mesh: Mesh, material: Material) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


func _toon(color: Color) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = GiftModelTable.TOON_SHADER
	material.set_shader_parameter(&"albedo_color", color)
	material.next_pass = GiftModelTable.OUTLINE_MATERIAL
	return material


func _flat(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	return material
