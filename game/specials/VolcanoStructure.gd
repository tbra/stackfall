class_name VolcanoStructure
extends Node3D
## The Volcano's standalone world object (Bontago-1pi.85.14; plan section 3, owner
## answer 1pi.85.4 (a)). A child of the Field, so it rides the tilting disc.
##
## Host (physics = true): carries an AnimatableBody3D with a convex cone hull that
## grows over rise_s, pushes blocks in its footprint outward while it rises (bounded
## scan, push_max_bodies per tick) and, once risen, spawns 1-3 owner-coloured
## blocks of random shape (GiftShapePicker, shared weights) per burst through BlockSpawner (not counted as placements, stops at the
## cap). Client (physics = false): the same placeholder cone visual and clock, no
## collision body and no spawning. The node frees itself after rise_s +
## eruption_duration_s of simulation time, or as soon as the match is no longer live.
##
## DECISION: the collider rises by scaling a full-height hull in Y (built once in
## _ready, then only CollisionShape3D.scale.y changes per rise tick) rather than
## translating a full cone up through the disc, so blocks are never squeezed against
## the floor. The apex is the same as rebuilding the hull at each height.
##
## DECISION: the collider sits on Field.BEACON_COLLISION_LAYER (mask 0), the beacon
## precedent: blocks collide with it, placement queries do not see it.

## The hull never degenerates to a flat plane at the start of the rise.
const MIN_HEIGHT_FRACTION: float = 0.02

## Seed mixing for the host's deterministic eruption stream (slot and spawn counter).
const SLOT_SEED_MIX: int = 2654435761
const SEQ_SEED_MIX: int = 40503

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
var _fx: VolcanoEruptionFx = null
var _fx_stopped: bool = false
## Count of host structures spawned this session; mixed into the eruption seed.
static var _spawn_seq: int = 0
var _body: AnimatableBody3D = null
var _collision: CollisionShape3D = null
## Pivot holding the visual (model or fallback cone); scaled in Y during the rise.
var _visual: Node3D = null
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
	if physics:
		# Host-deterministic eruption stream: match seed, owner slot and spawn counter.
		_spawn_seq += 1
		var base_seed: int = int(Match.config.rng_seed) if Match.config != null else 0
		structure._rng.seed = base_seed ^ ((owner_slot + 1) * SLOT_SEED_MIX) ^ (_spawn_seq * SEQ_SEED_MIX)
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
	_visual = Node3D.new()
	add_child(_visual)
	if not _build_model_visual():
		_build_cone_visual()
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
	_build_particles()
	_apply_height(current_height())


## Cosmetic eruption particles on host and client (client-side visual; no net traffic).
func _build_particles() -> void:
	if _effect.particles == null:
		return
	_fx = VolcanoEruptionFx.new()
	_fx.position = Vector3(0.0, _effect.height_m, 0.0)
	add_child(_fx)
	_fx.setup(_effect.particles, Settings.current_graphics_preset())


func eruption_fx() -> VolcanoEruptionFx:
	return _fx


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
	return MatchAutoload.is_live(Match.state())


## One simulation step; public so tests drive it without the physics loop.
func tick(delta: float) -> void:
	if _effect == null or (bind_to_match and not _match_is_live()):
		_stop_fx()
		queue_free()
		return
	var was_rising: bool = is_rising()
	_age += delta
	if is_expired():
		_stop_fx()
		queue_free()
		return
	if was_rising:
		_apply_height(current_height())
		if _physics:
			_push_footprint()
	if not is_rising():
		_erupt(delta)


func _apply_height(height: float) -> void:
	if _visual != null:
		var fraction: float = maxf(height, 0.0) / maxf(_effect.height_m, HEIGHT_EPSILON)
		# The visual's base stays on y = 0: it grows upward from the structure origin.
		_visual.scale = Vector3(1.0, maxf(fraction, MIN_HEIGHT_FRACTION), 1.0)
	if _collision != null:
		if _collision.shape == null:
			_collision.shape = _build_hull(_effect.height_m)
		var hull_fraction: float = maxf(height, _effect.height_m * MIN_HEIGHT_FRACTION) / maxf(_effect.height_m, HEIGHT_EPSILON)
		_collision.scale = Vector3(1.0, hull_fraction, 1.0)


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


## Fallback visual: the procedural cone, centred on its origin so it is lifted by half
## its height to keep the base on y = 0.
func _build_cone_visual() -> void:
	var cone: MeshInstance3D = MeshInstance3D.new()
	cone.mesh = _build_cone_mesh()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = _effect.cone_color
	cone.material_override = material
	cone.position = Vector3(0.0, _effect.height_m * 0.5, 0.0)
	_visual.add_child(cone)


## Instances the effect's model scene, scaled non-uniformly so its measured footprint is
## base_radius_m * 2 and its height height_m, base centre on the pivot origin. False
## (nothing added) when there is no usable scene.
func _build_model_visual() -> bool:
	if _effect.model_scene == null:
		return false
	var model: Node3D = _effect.model_scene.instantiate() as Node3D
	if model == null:
		return false
	var bounds: AABB = _model_bounds(model, Transform3D.IDENTITY)
	if bounds.size.x <= HEIGHT_EPSILON or bounds.size.y <= HEIGHT_EPSILON or bounds.size.z <= HEIGHT_EPSILON:
		model.free()
		return false
	var model_scale: Vector3 = Vector3(
		_effect.base_radius_m * 2.0 / bounds.size.x,
		_effect.height_m / bounds.size.y,
		_effect.base_radius_m * 2.0 / bounds.size.z
	)
	var base_centre: Vector3 = bounds.position + Vector3(bounds.size.x * 0.5, 0.0, bounds.size.z * 0.5)
	model.scale = model_scale
	model.position = -base_centre * model_scale
	_visual.add_child(model)
	return true


## Union AABB of every mesh below `node`, in the model root's space.
static func _model_bounds(node: Node, to_root: Transform3D) -> AABB:
	var result: AABB = AABB()
	var found: bool = false
	var node_3d: Node3D = node as Node3D
	var current: Transform3D = to_root * node_3d.transform if node_3d != null else to_root
	var mesh_instance: MeshInstance3D = node as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh != null:
		result = current * mesh_instance.mesh.get_aabb()
		found = true
	for child: Node in node.get_children():
		var child_bounds: AABB = _model_bounds(child, current)
		if child_bounds.size == Vector3.ZERO:
			continue
		result = child_bounds if not found else result.merge(child_bounds)
		found = true
	return result


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


func _stop_fx() -> void:
	if _fx != null and not _fx_stopped:
		_fx_stopped = true
		_fx.stop()


## Counts the next burst down and fires it. The host spawns the blocks; host and client both
## emit the cosmetic embers (a client's own clock, so its bursts are not frame-locked to the
## host's shots). Stops quietly at the block cap.
func _erupt(delta: float) -> void:
	if _fx != null and not _fx_stopped:
		_fx.set_plume_active(true)
	_next_burst_s -= delta
	if _next_burst_s > 0.0:
		return
	_next_burst_s = _rng.randf_range(
		_effect.eruption_interval_min_s, maxf(_effect.eruption_interval_min_s, _effect.eruption_interval_max_s)
	)
	if _fx != null:
		_fx.burst()
	if not _physics:
		return
	var count: int = _rng.randi_range(_effect.min_blocks_per_burst, maxi(_effect.min_blocks_per_burst, _effect.max_blocks_per_burst))
	var phase: float = _rng.randf_range(0.0, TAU)
	for i: int in range(count):
		var spread: Vector3 = Vector3.ZERO
		if count > 1:
			var angle: float = phase + TAU * float(i) / float(count)
			spread = Vector3(cos(angle), 0.0, sin(angle)) * _effect.burst_spread_m
		var origin: Vector3 = apex_world() + global_basis.y * _effect.spawn_clearance_m + spread
		var shape: BlockShape = _effect.block_shape
		if _effect.shape_weights != null:
			shape = GiftShapePicker.pick(_rng, _effect.shape_weights)
		var spawned: Block = BlockSpawner.spawn(
			shape, origin, Basis.IDENTITY, _owner_slot, _launch_velocity(), _effect.block_cap
		)
		if spawned == null:
			return


func _launch_velocity() -> Vector3:
	var azimuth: float = _rng.randf_range(0.0, TAU)
	var polar: float = deg_to_rad(_rng.randf_range(0.0, _effect.cone_angle_deg))
	var local_direction: Vector3 = Vector3(sin(polar) * cos(azimuth), cos(polar), sin(polar) * sin(azimuth))
	return global_basis * local_direction * _effect.launch_speed_mps
