class_name ThrowArcPreview
extends Node3D
## M4 P2e (docs/M4_P2_PACKAGES.md P2e, spec 2.5 "Throw (specials only)"):
## a pure-presentation ballistic-arc polyline, shown only while game/
## PlayerController.gd reports is_aiming_throw() true. It samples the same
## closed-form `position(t) = origin + velocity*t + 0.5*gravity*t^2` game/
## BlockFactory.gd's own gravity_scale wiring implies (constant acceleration,
## no drag on a thrown special before it lands), stepping at a fixed dt
## (GhostTuning.throw_arc_max_time_s / throw_arc_sample_count) but stopping at
## the FIRST sample that reaches the landing surface, not a fixed sample
## count.
##
## Bontago-1en.25 (feedback/throw-arc.png, "arc leaves the screen while
## rising"): the arc used to always sample out to throw_arc_max_time_s
## regardless of where it lands, so a hard lofted throw's preview was still
## rising off the top of the screen when the line simply stopped. Landing
## height comes from the optional `field` argument sample_arc()/update_arc()
## now take (game/Field.gd, read-only here: disk_local_from_world() for "is
## this XZ still over the disc" and surface_y() for its top height, both
## already tilt-aware/flat-approximated the same way every other caller of
## those two functions is) -- the disc's own top while the sample is still
## within map_def.field_radius of the disc center, or
## GhostTuning.throw_arc_floor_below_disc_m below the disc's surface once it
## has flown past the rim (a flat "there is no ground here" backstop, itself
## togglable via throw_arc_floor_enabled). throw_arc_max_time_s stays exactly
## what it always was for a throw that never lands within that time (raised
## to 4 s, comfortably past the hang time SpecialTuning's own throw_max_speed/
## throw_loft_ratio defaults produce, so it now reads only as the safety cap
## its own doc comment always claimed rather than the normal cutoff).
##
## `field` defaults to null so every existing bare-unit-test caller (no Field
## instanced) keeps its pre-Bontago-1en.25 behaviour unchanged: sampled purely
## to the safety cap, no landing cutoff at all -- there is no ground to land
## on when nothing describes one, so this deliberately does not invent a fake
## y=0 floor for that case.
##
## sample_arc() is deliberately a pure function of its own arguments plus the
## two tuning Resources and the optional read-only `field` (no read of
## PlayerController/scene-tree state beyond that one argument) so a bare unit
## test can call it directly without instancing a PlayerController or a Match
## -- exactly the "provable without physics" bar the M4 P2 packages doc sets
## for P2a's own SpecialBehavior, applied here to this package's own pure
## math.

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


## Pure ballistic sampler -- P2e's own testable seam, extended in
## Bontago-1en.25 to cut off at ground/disc contact. `origin`/`velocity` are
## world-space; matches game/PlayerController.gd._throw_velocity_for_drag()'s
## and _request_throw()'s own launch convention (a straight-line velocity
## from a spawn point, no initial acceleration ramp). `field`, if given, is
## read-only (see this file's top doc comment); null keeps the pre-landing
## fixed-time-budget behaviour every existing bare-unit-test caller relies on.
func sample_arc(origin: Vector3, velocity: Vector3, field: Field = null) -> PackedVector3Array:
	var gravity: Vector3 = (
		Vector3.DOWN * float(ProjectSettings.get_setting("physics/3d/default_gravity")) * physics_tuning.gravity_multiplier
	)
	var sample_count: int = maxi(ghost_tuning.throw_arc_sample_count, 1)
	var dt: float = ghost_tuning.throw_arc_max_time_s / float(sample_count)
	var points: PackedVector3Array = PackedVector3Array()
	points.append(origin)
	var previous: Vector3 = origin
	for i in range(1, sample_count + 1):
		var t: float = dt * float(i)
		var point: Vector3 = origin + velocity * t + 0.5 * gravity * t * t
		var landing_y: float = _landing_height_at(point, field)
		if point.y <= landing_y:
			points.append(_landing_point(previous, point, landing_y))
			return points
		points.append(point)
		previous = point
	return points


## The world Y the arc must stop at for a candidate `point`, given the
## (read-only) `field` sample_arc() above was called with -- the disc's own
## surface_y() while `point`'s XZ is still within map_def.field_radius of the
## disc center (per field.disk_local_from_world(), so a tilted disc's own
## rotation is honoured exactly like every other caller of that function),
## GhostTuning.throw_arc_floor_below_disc_m under that surface once it has
## flown past the rim (unless throw_arc_floor_enabled is off, in which case an
## off-disc throw never "lands" and only the safety cap in sample_arc()'s own
## loop bound stops it). `field == null` (the bare-unit-test/no-active-match
## case) returns -INF: there is no ground to land on when nothing describes
## one, so this never invents a fake floor for that case either.
func _landing_height_at(point: Vector3, field: Field) -> float:
	if field == null:
		return -INF
	var local_xz: Vector2 = field.disk_local_from_world(point)
	if local_xz.length() <= field.map_definition().field_radius:
		return field.surface_y()
	if not ghost_tuning.throw_arc_floor_enabled:
		return -INF
	return field.surface_y() - ghost_tuning.throw_arc_floor_below_disc_m


## Linearly interpolates between the last sample still above the landing
## height and the first one at or below it, so the arc's own last point sits
## (within floating-point tolerance) exactly at `landing_y` instead of
## whatever overshoot the fixed dt step produced -- good enough for a
## presentation-only preview line, no physics query involved.
func _landing_point(previous: Vector3, point: Vector3, landing_y: float) -> Vector3:
	var drop: float = previous.y - point.y
	if drop <= 0.0001:
		return Vector3(point.x, landing_y, point.z)
	var f: float = clampf((previous.y - landing_y) / drop, 0.0, 1.0)
	return previous.lerp(point, f)


## Recomputes and shows the arc for the given launch. Called every frame
## PlayerController._drive_throw_visuals() decides the live drag would
## commit as a throw right now (see that function's own DECISION comment) --
## safe to call every frame, like GhostPreview.apply_validity(). `field` is
## forwarded straight to sample_arc() (Bontago-1en.25); PlayerController
## passes Match.field(), read-only, same as its own _on_placement_relocated().
func update_arc(origin: Vector3, velocity: Vector3, field: Field = null) -> void:
	_rebuild_mesh(sample_arc(origin, velocity, field))
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
	# Bontago-1en.25: a small camera-facing disc at the landing point, on
	# its own tunable (throw_arc_end_marker_enabled) since a bare polyline
	# already reads as "ends here" once it stops at the actual landing
	# height (this package's whole point) -- the marker is only an extra
	# legibility cue, not load-bearing for the acceptance tests below.
	if ghost_tuning.throw_arc_end_marker_enabled:
		_add_end_marker(points[points.size() - 1], camera)


## Bontago-1en.25's optional landing-point marker: a small flat camera-facing
## disc (same to-camera convention _rebuild_mesh's own ribbon side-offset
## uses above), drawn as a second surface on the same ImmediateMesh so
## clear_arc()'s one clear_surfaces() call still drops it along with the
## ribbon.
##
## DECISION (game/ThrowArcPreview.gd, Bontago-1en.25): no shape/ray cast
## against placed blocks along the sampled segments -- the brief's own
## "if cheap" qualifier for stopping the arc on a tower top instead of
## passing through it. sample_arc() is deliberately pure (no PhysicsServer
## query, callable with zero nodes in the tree, see this file's top doc
## comment); wiring a per-segment cast would need a live
## PhysicsDirectSpaceState3D, only available from update_arc() once this
## node is inside a real tree, which would make the two functions disagree
## about where the arc ends and cost a shape cast every frame the arc is
## visible for no gameplay effect (a thrown special's real flight path is
## still whatever BlockFactory/physics actually resolves, spec 2.5 -- this
## preview is advisory only). Left for a follow-up package; reported as
## unresolved in this package's own handoff rather than guessed at here.
func _add_end_marker(point: Vector3, camera: Camera3D) -> void:
	var radius: float = ghost_tuning.throw_arc_end_marker_radius
	if radius <= 0.0:
		return
	var normal: Vector3 = (camera.global_position - point).normalized() if camera != null else Vector3.UP
	var right: Vector3 = normal.cross(Vector3.UP)
	if right.length() <= 0.0001:
		right = normal.cross(Vector3.FORWARD)
	right = right.normalized()
	var up: Vector3 = right.cross(normal).normalized()
	var segments: int = 10
	# DECISION (game/ThrowArcPreview.gd): Godot 4's Mesh enum dropped
	# PRIMITIVE_TRIANGLE_FAN (Godot 3 had it; this build's ClassDB does not,
	# verified by the parse error a first attempt at this hit) -- PRIMITIVE_
	# TRIANGLES with the fan's triangles spelled out explicitly (center, ring
	# vertex i, ring vertex i+1) draws the identical shape.
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(segments):
		var angle_a: float = TAU * float(i) / float(segments)
		var angle_b: float = TAU * float(i + 1) / float(segments)
		_immediate_mesh.surface_set_color(ghost_tuning.throw_arc_color)
		_immediate_mesh.surface_add_vertex(point)
		_immediate_mesh.surface_set_color(ghost_tuning.throw_arc_color)
		_immediate_mesh.surface_add_vertex(point + (right * cos(angle_a) + up * sin(angle_a)) * radius)
		_immediate_mesh.surface_set_color(ghost_tuning.throw_arc_color)
		_immediate_mesh.surface_add_vertex(point + (right * cos(angle_b) + up * sin(angle_b)) * radius)
	_immediate_mesh.surface_end()
