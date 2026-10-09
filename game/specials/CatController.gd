class_name CatController
extends RigidBody3D
## One transient cat body, outside BlockRegistry and the ordinary shape roster.
## Only the host simulates collisions. Clients display host poses without a body.

var activation_id: int = 0
var owner_slot: int = -1
var target: Vector3 = Vector3.ZERO
var time_left: float = 0.0
var speed_mps: float = 9.0
var target_range_m: float = 25.0
var radius_m: float = 0.8
var push_impulse: float = 12.0
var _host_body: bool = true
var _origin: Vector3 = Vector3.ZERO
var _last_valid_position: Vector3 = Vector3.ZERO
var _laser: MeshInstance3D = null


func configure(id: int, slot_id: int, position: Vector3, duration: float,
		speed: float, range_m: float, radius: float, impulse: float, host_body: bool) -> void:
	activation_id = id
	owner_slot = slot_id
	_origin = position
	_last_valid_position = position
	target = position
	time_left = duration
	speed_mps = speed
	target_range_m = range_m
	radius_m = radius
	push_impulse = impulse
	_host_body = host_body
	gravity_scale = 0.0
	lock_rotation = true
	# Approximate configured horizontal contact impulse as momentum at chase speed.
	mass = maxf(1.0, impulse / maxf(speed, 0.1))
	collision_layer = 1 if host_body else 0
	collision_mask = 1 if host_body else 0
	freeze = not host_body
	if not host_body:
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC


func _ready() -> void:
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = radius_m
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.shape = shape
	add_child(collider)
	# Bontago-mp0.119: the cat_v1 GLB (tail-sway loop) replaces the primitive
	# cat; the primitive build stays as the fallback if the table lacks it.
	var cat_visual: Node3D = GiftModelTable.shared().build_gift_visual(&"cat", true)
	if cat_visual != null:
		cat_visual.name = &"CatModel"
		add_child(cat_visual)
	else:
		_build_primitive_cat()
	_laser = MeshInstance3D.new()
	_laser.top_level = true
	var dot: SphereMesh = SphereMesh.new()
	dot.radius = 0.23
	dot.height = 0.46
	_laser.mesh = dot
	var glow: StandardMaterial3D = StandardMaterial3D.new()
	glow.albedo_color = Color.RED
	glow.emission_enabled = true
	glow.emission = Color.RED
	glow.emission_energy_multiplier = 3.0
	_laser.material_override = glow
	add_child(_laser)
	global_position = _origin
	_update_laser()


func _build_primitive_cat() -> void:
	var coat: StandardMaterial3D = StandardMaterial3D.new()
	coat.albedo_color = Color(0.95, 0.55, 0.16)
	var inner_ear: StandardMaterial3D = StandardMaterial3D.new()
	inner_ear.albedo_color = Color(0.95, 0.46, 0.48)
	var eye: StandardMaterial3D = StandardMaterial3D.new()
	eye.albedo_color = Color(0.08, 0.12, 0.09)
	_add_sphere("Body", Vector3.ZERO, Vector3(1.25, 0.72, 0.75), radius_m, coat)
	_add_sphere("Head", Vector3(0.0, radius_m * 0.48, -radius_m * 0.72),
		Vector3(0.72, 0.7, 0.68), radius_m, coat)
	for side: float in [-1.0, 1.0]:
		var ear: CylinderMesh = CylinderMesh.new()
		ear.top_radius = 0.0
		ear.bottom_radius = radius_m * 0.22
		ear.height = radius_m * 0.48
		_add_mesh("Ear", ear,
			Vector3(side * radius_m * 0.32, radius_m * 1.06, -radius_m * 0.8), inner_ear)
		_add_sphere("Eye", Vector3(side * radius_m * 0.27, radius_m * 0.56,
			-radius_m * 1.24), Vector3.ONE * 0.09, radius_m, eye)
	var tail: CylinderMesh = CylinderMesh.new()
	tail.top_radius = radius_m * 0.09
	tail.bottom_radius = radius_m * 0.13
	tail.height = radius_m * 1.1
	var tail_node: MeshInstance3D = _add_mesh("Tail", tail,
		Vector3(0.0, radius_m * 0.65, radius_m * 0.9), coat)
	tail_node.rotation.x = -0.5


func _add_mesh(part_name: StringName, mesh: Mesh, offset: Vector3,
		material: Material) -> MeshInstance3D:
	var part: MeshInstance3D = MeshInstance3D.new()
	part.name = part_name
	part.mesh = mesh
	part.position = offset
	part.material_override = material
	add_child(part)
	return part


func _add_sphere(part_name: StringName, offset: Vector3, proportions: Vector3,
		radius: float, material: Material) -> void:
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	var part: MeshInstance3D = _add_mesh(part_name, sphere, offset, material)
	part.scale = proportions


func set_target(point: Vector3) -> bool:
	if not point.is_finite():
		return false
	var difference: Vector2 = Vector2(point.x - _origin.x, point.z - _origin.z)
	if difference.length() > target_range_m:
		difference = difference.normalized() * target_range_m
	var desired: Vector3 = Vector3(_origin.x + difference.x, _origin.y, _origin.z + difference.y)
	var field: FieldBody = MatchContext.current().field()
	if field != null:
		# Stop at the first missing bit of ground, including ring holes and
		# gaps between the twin islands, instead of driving a floating cat away.
		var from: Vector2 = field.disk_local_from_world(_origin)
		var to: Vector2 = field.disk_local_from_world(desired)
		var last_solid: Vector2 = from
		for step: int in range(1, 65):
			var candidate: Vector2 = from.lerp(to, float(step) / 64.0)
			if not field.map_def.shape_contains(candidate):
				break
			last_solid = candidate
		target = field.world_from_disk_local(last_solid, radius_m)
	else:
		target = desired
	_update_laser()
	return true


func _physics_process(delta: float) -> void:
	if not _host_body:
		return
	var ctx: MatchContext = MatchContext.current()
	if not MatchPhase.is_live(ctx.state()):
		ctx.end_cat(activation_id)
		return
	time_left -= delta
	if time_left <= 0.0:
		ctx.end_cat(activation_id)
		return
	var field: FieldBody = ctx.field()
	if field != null and not field.map_def.shape_contains(field.disk_local_from_world(global_position)):
		global_position = _last_valid_position
		linear_velocity = Vector3.ZERO
	else:
		_last_valid_position = global_position
	var horizontal: Vector3 = target - global_position
	horizontal.y = 0.0
	var desired: Vector3 = horizontal.normalized() * speed_mps if horizontal.length() > radius_m else Vector3.ZERO
	# DECISION: a horizontal velocity target drives a real rigid body; the Jolt
	# contact solver gives stacks the impulse, while the cap limits workload.
	linear_velocity = Vector3(desired.x, 0.0, desired.z)
	_face_velocity(linear_velocity)
	_update_laser()


func apply_snapshot(position: Vector3, velocity: Vector3, point: Vector3, remaining: float) -> void:
	if _host_body or not position.is_finite() or not velocity.is_finite() or not point.is_finite():
		return
	global_position = position
	linear_velocity = velocity
	_face_velocity(velocity)
	target = point
	time_left = remaining
	_update_laser()


func _face_velocity(velocity: Vector3) -> void:
	if Vector2(velocity.x, velocity.z).length_squared() > 0.01:
		rotation.y = atan2(-velocity.x, -velocity.z)


func _update_laser() -> void:
	if _laser != null:
		_laser.global_position = target + Vector3.UP * 0.2
