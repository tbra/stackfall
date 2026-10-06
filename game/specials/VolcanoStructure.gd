class_name VolcanoStructure
extends Node3D
## The Volcano's standalone world object (Bontago-1pi.85.14; plan section 3, owner
## answer 1pi.85.4 (a)). A child of the Field, so it rides the tilting disc.
##
## Host (physics = true): carries an AnimatableBody3D with a convex cone hull that
## grows over rise_s, pushes blocks in its footprint outward while it rises (bounded
## scan, push_max_bodies per tick) and, once risen, spawns 1-3 owner-coloured cube
## blocks per burst through BlockSpawner (not counted as placements, stops at the
## cap). Client (physics = false): the same placeholder cone visual and clock, no
## collision body and no spawning. The node frees itself after rise_s +
## eruption_duration_s of simulation time, or as soon as the match is no longer live.
##
## DECISION: the collider rises by growing the hull's apex from a flat disc to
## height_m (the hull is rebuilt each tick of the rise, ~120 ticks) rather than
## translating a full cone up through the disc, so blocks are never squeezed against
## the floor.
##
## DECISION: the collider sits on Field.BEACON_COLLISION_LAYER (mask 0), the beacon
## precedent: blocks collide with it, placement queries do not see it.

## The hull never degenerates to a flat plane at the start of the rise.
const MIN_HEIGHT_FRACTION: float = 0.02

## Fewest base-ring segments a convex hull / cone mesh needs, and the divide-by-zero guard.
const MIN_RING_SEGMENTS: int = 3
const HEIGHT_EPSILON: float = 0.0001

var _effect: VolcanoEffect = null
var _owner_slot: int = -1
var _physics: bool = false
var _exclude: Array[RID] = []
var _age: float = 0.0
var _next_burst_s: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _body: AnimatableBody3D = null
var _collision: CollisionShape3D = null
var _mesh: MeshInstance3D = null
## Set when spawned into a match world: the structure frees itself once the match is
## no longer live (ended or restarted).
var bind_to_match: bool = false


## Host spawn: parents the structure under the Field at `world_position`. Returns it,
## or null when there is no field, the effect is missing, or the point is off the disc.
static func spawn_host(effect: VolcanoEffect, world_position: Vector3, owner_slot: int, exclude: RID = RID()) -> VolcanoStructure:
	return _spawn(effect, world_position, owner_slot, true, exclude)


## Client visual: the same cone without a physics body. Null on the host (its own
## structure already draws it) or when there is nothing to attach to. The caller
## (GiftFxPresenter) passes the def's effect.
static func build_client_visual(effect: VolcanoEffect, world_position: Vector3, owner_slot: int) -> VolcanoStructure:
	if Match._is_host():
		return null
	return _spawn(effect, world_position, owner_slot, false, RID())


static func _spawn(effect: VolcanoEffect, world_position: Vector3, owner_slot: int, physics: bool, exclude: RID) -> VolcanoStructure:
	var field: Field = Match.field()
	if effect == null or field == null or not world_position.is_finite() or not field.is_inside_tree():
		return null
	var local: Vector2 = field.disk_local_from_world(world_position)
	if local.length() > field.map_def.field_radius:
		return null
	var structure: VolcanoStructure = VolcanoStructure.new()
	structure.configure(effect, owner_slot, physics, exclude)
	structure.bind_to_match = true
	field.add_child(structure)
	structure.global_position = world_position
	return structure


func configure(effect: VolcanoEffect, owner_slot: int, physics: bool, exclude: RID = RID()) -> void:
	_effect = effect
	_owner_slot = owner_slot
	_physics = physics
	_exclude = []
	if exclude.is_valid():
		_exclude.append(exclude)
	_rng.randomize()
	_next_burst_s = 0.0


func _ready() -> void:
	if _effect == null:
		return
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _build_cone_mesh()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = _effect.cone_color
	_mesh.material_override = material
	add_child(_mesh)
	if _physics:
		_body = AnimatableBody3D.new()
		_body.collision_layer = Field.BEACON_COLLISION_LAYER
		_body.collision_mask = 0
		var field: Field = get_parent() as Field
		_body.sync_to_physics = field != null and field.sync_to_physics
		var physics_material: PhysicsMaterial = PhysicsMaterial.new()
		physics_material.friction = _effect.surface_friction
		_body.physics_material_override = physics_material
		_collision = CollisionShape3D.new()
		_body.add_child(_collision)
		add_child(_body)
	_apply_height(current_height())


func age() -> float:
	return _age


func has_body() -> bool:
	return _body != null


func body() -> AnimatableBody3D:
	return _body


## Current cone height: 0 -> height_m over rise_s, then constant.
func current_height() -> float:
	if _effect == null:
		return 0.0
	if _effect.rise_s <= 0.0:
		return _effect.height_m
	return _effect.height_m * clampf(_age / _effect.rise_s, 0.0, 1.0)


func is_rising() -> bool:
	return _effect != null and _age < _effect.rise_s


func is_expired() -> bool:
	return _effect == null or _age >= _effect.rise_s + _effect.eruption_duration_s


## World position of the cone's apex.
func apex_world() -> Vector3:
	return global_position + global_basis.y * current_height()


func _physics_process(delta: float) -> void:
	tick(delta)


func _match_is_live() -> bool:
	var current: Match.State = Match.state()
	return current == Match.State.PLAYING or current == Match.State.SUDDEN_DEATH


## One simulation step; public so tests drive it without the physics loop.
func tick(delta: float) -> void:
	if _effect == null or (bind_to_match and not _match_is_live()):
		queue_free()
		return
	var was_rising: bool = is_rising()
	_age += delta
	if is_expired():
		queue_free()
		return
	if was_rising:
		_apply_height(current_height())
		if _physics:
			_push_footprint()
	if _physics and not is_rising():
		_erupt(delta)


func _apply_height(height: float) -> void:
	if _mesh != null:
		var fraction: float = maxf(height, 0.0) / maxf(_effect.height_m, HEIGHT_EPSILON)
		_mesh.scale = Vector3(1.0, maxf(fraction, MIN_HEIGHT_FRACTION), 1.0)
		# The cylinder mesh is centred on its origin: lift it so its base stays on y = 0.
		_mesh.position = Vector3(0.0, height * 0.5, 0.0)
	if _collision != null:
		_collision.shape = _build_hull(maxf(height, _effect.height_m * MIN_HEIGHT_FRACTION))


func _build_hull(height: float) -> ConvexPolygonShape3D:
	var points: PackedVector3Array = PackedVector3Array()
	var segments: int = maxi(_effect.ring_segments, MIN_RING_SEGMENTS)
	for i: int in range(segments):
		var angle: float = TAU * float(i) / float(segments)
		points.append(Vector3(cos(angle) * _effect.base_radius_m, 0.0, sin(angle) * _effect.base_radius_m))
	points.append(Vector3(0.0, height, 0.0))
	var shape: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
	shape.points = points
	return shape


func _build_cone_mesh() -> CylinderMesh:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = _effect.base_radius_m
	mesh.height = _effect.height_m
	mesh.radial_segments = maxi(_effect.ring_segments, MIN_RING_SEGMENTS)
	mesh.rings = 1
	return mesh


## Gives every block inside the footprint (plus margin) an outward speed up to
## push_speed_mps. Bounded: at most push_max_bodies bodies per tick.
func _push_footprint() -> void:
	var world: World3D = get_world_3d()
	if world == null:
		return
	var reach: float = _effect.base_radius_m + _effect.push_margin_m
	var up: Vector3 = global_basis.y
	var bodies: Array[RigidBody3D] = ExplosionFx.query_bodies(
		world.direct_space_state, global_position + up * current_height() * 0.5,
		reach + current_height(), _exclude
	)
	var pushed: int = 0
	for rigid: RigidBody3D in bodies:
		if pushed >= _effect.push_max_bodies:
			break
		if not (rigid is Block):
			continue
		var offset: Vector3 = rigid.global_position - global_position
		var flat: Vector3 = offset - up * offset.dot(up)
		if flat.length() > reach:
			continue
		var direction: Vector3 = flat.normalized() if flat.length() > ExplosionFx.EPSILON else Vector3.RIGHT
		var outward_speed: float = rigid.linear_velocity.dot(direction)
		if outward_speed >= _effect.push_speed_mps:
			continue
		SpecialPhysics.wake_and_impulse(rigid, direction * (_effect.push_speed_mps - outward_speed) * rigid.mass)
		pushed += 1


## Counts the next burst down and spawns it; stops quietly at the block cap.
func _erupt(delta: float) -> void:
	_next_burst_s -= delta
	if _next_burst_s > 0.0:
		return
	_next_burst_s = _rng.randf_range(
		_effect.eruption_interval_min_s, maxf(_effect.eruption_interval_min_s, _effect.eruption_interval_max_s)
	)
	var count: int = _rng.randi_range(_effect.min_blocks_per_burst, maxi(_effect.min_blocks_per_burst, _effect.max_blocks_per_burst))
	var phase: float = _rng.randf_range(0.0, TAU)
	for i: int in range(count):
		var spread: Vector3 = Vector3.ZERO
		if count > 1:
			var angle: float = phase + TAU * float(i) / float(count)
			spread = Vector3(cos(angle), 0.0, sin(angle)) * _effect.burst_spread_m
		var origin: Vector3 = apex_world() + global_basis.y * _effect.spawn_clearance_m + spread
		var spawned: Block = BlockSpawner.spawn(
			_effect.block_shape, origin, Basis.IDENTITY, _owner_slot, _launch_velocity(), _effect.block_cap
		)
		if spawned == null:
			return


func _launch_velocity() -> Vector3:
	var azimuth: float = _rng.randf_range(0.0, TAU)
	var polar: float = deg_to_rad(_rng.randf_range(0.0, _effect.cone_angle_deg))
	var local_direction: Vector3 = Vector3(sin(polar) * cos(azimuth), cos(polar), sin(polar) * sin(azimuth))
	return global_basis * local_direction * _effect.launch_speed_mps
