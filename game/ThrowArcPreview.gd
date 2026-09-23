class_name ThrowArcPreview
extends Node3D
## M4 P2e (docs/M4_P2_PACKAGES.md P2e, spec 2.5 "Throw (specials only)"):
## a pure-presentation ballistic-arc polyline, shown only while game/
## PlayerController.gd reports is_aiming_throw() true. No physics query, no
## collision/landing detection -- it just samples the same closed-form
## `position(t) = origin + velocity*t + 0.5*gravity*t^2` game/BlockFactory.gd's
## own gravity_scale wiring implies (constant acceleration, no drag on a
## thrown special before it lands) out to a fixed time budget
## (GhostTuning.throw_arc_max_time_s) and draws it as a ribbon.
##
## sample_arc() is deliberately a pure function of its own arguments plus the
## two tuning Resources (no read of PlayerController/scene-tree state) so a
## bare unit test can call it directly without instancing a PlayerController
## or a Match -- exactly the "provable without physics" bar the M4 P2
## packages doc sets for P2a's own SpecialBehavior, applied here to this
## package's own pure math.

@export var physics_tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
@export var ghost_tuning: GhostTuning = preload("res://config/ghost_tuning.tres")

var _mesh_instance: MeshInstance3D
var _immediate_mesh: ImmediateMesh
var _material: StandardMaterial3D
## For tests/current_points(): the world-space centreline points the ribbon
## last drew, cleared to empty by clear_arc().
var _last_points: PackedVector3Array = PackedVector3Array()


func _ready() -> void:
	_immediate_mesh = ImmediateMesh.new()
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _immediate_mesh
	_mesh_instance.material_override = _material
	# DECISION (game/ThrowArcPreview.gd): top_level, like GhostPreview's own
	# _projection_mesh -- update_arc() below always writes world-space
	# vertices (the origin it's given is already global), so this node's own
	# transform must never compose on top of them.
	_mesh_instance.top_level = true
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_instance)
	visible = false


## Pure ballistic sampler -- P2e's own testable seam. `origin`/`velocity` are
## world-space; matches game/PlayerController.gd._throw_velocity_for_drag()'s
## and _request_throw()'s own launch convention (a straight-line velocity
## from a spawn point, no initial acceleration ramp).
func sample_arc(origin: Vector3, velocity: Vector3) -> PackedVector3Array:
	var gravity: Vector3 = (
		Vector3.DOWN * float(ProjectSettings.get_setting("physics/3d/default_gravity")) * physics_tuning.gravity_multiplier
	)
	var sample_count: int = maxi(ghost_tuning.throw_arc_sample_count, 1)
	var points: PackedVector3Array = PackedVector3Array()
	for i in range(sample_count + 1):
		var t: float = ghost_tuning.throw_arc_max_time_s * float(i) / float(sample_count)
		points.append(origin + velocity * t + 0.5 * gravity * t * t)
	return points


## Recomputes and shows the arc for the given launch. Called every frame
## PlayerController._drive_throw_visuals() decides the live drag would
## commit as a throw right now (see that function's own DECISION comment) --
## safe to call every frame, like GhostPreview.apply_validity().
func update_arc(origin: Vector3, velocity: Vector3) -> void:
	_rebuild_mesh(sample_arc(origin, velocity))
	visible = true


## Hides the arc and drops its geometry. Called every frame the live drag
## would NOT commit as a throw (negligible drag, or not aiming at all).
func clear_arc() -> void:
	visible = false
	_last_points = PackedVector3Array()
	if _immediate_mesh != null:
		_immediate_mesh.clear_surfaces()


## For tests: the world-space sample points the ribbon currently follows
## (the centreline, not the ribbon's own left/right edges); empty after
## clear_arc()/before the first update_arc().
func current_points() -> PackedVector3Array:
	return _last_points


func _rebuild_mesh(points: PackedVector3Array) -> void:
	_last_points = points
	_immediate_mesh.clear_surfaces()
	if points.size() < 2:
		return
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() and get_viewport() != null else null
	var half_width: float = ghost_tuning.throw_arc_width * 0.5
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in range(points.size()):
		var point: Vector3 = points[i]
		var dir: Vector3
		if i == 0:
			dir = points[1] - points[0]
		elif i == points.size() - 1:
			dir = points[i] - points[i - 1]
		else:
			dir = points[i + 1] - points[i - 1]
		if dir.length() <= 0.0001:
			dir = Vector3.FORWARD
		dir = dir.normalized()
		# DECISION (game/ThrowArcPreview.gd): the ribbon's side offset faces
		# the active camera per-vertex (rather than a fixed world axis, or the
		# whole-mesh BILLBOARD_ENABLED material mode) so the line reads at a
		# consistent on-screen width from any orbit angle without distorting
		# the polyline's own 3D depth the way a single flat billboard sprite
		# would.
		var to_camera: Vector3 = (camera.global_position - point).normalized() if camera != null else Vector3.UP
		var side: Vector3 = dir.cross(to_camera)
		if side.length() <= 0.0001:
			side = dir.cross(Vector3.UP)
		side = side.normalized() * half_width
		_immediate_mesh.surface_set_color(ghost_tuning.throw_arc_color)
		_immediate_mesh.surface_add_vertex(point + side)
		_immediate_mesh.surface_set_color(ghost_tuning.throw_arc_color)
		_immediate_mesh.surface_add_vertex(point - side)
	_immediate_mesh.surface_end()
