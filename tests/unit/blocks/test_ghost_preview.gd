extends GutTest
## GhostPreview must apply the orientation-index + free-quaternion rotation
## correctly and never drift on reset (spec 1.7, 2.5 — M1 acceptance).


func _make_ghost() -> GhostPreview:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))
	return ghost


## Footprint quad bookkeeping read off the ghost's own child nodes.
func _footprint_quad_count(ghost: GhostPreview) -> int:
	return GhostParts.footprint_quads(ghost).size()


## The footprint quad's own outline, in ghost-local XZ (its mesh vertices, back out of world space).
func _footprint_polygon_local(ghost: GhostPreview) -> PackedVector2Array:
	var local: PackedVector2Array = PackedVector2Array()
	var quads: Array[MeshInstance3D] = GhostParts.footprint_quads(ghost)
	if quads.is_empty():
		return local
	for point: Vector2 in GhostParts.quad_points_world(quads[0]):
		local.append(Vector2(point.x - ghost.global_position.x, point.y - ghost.global_position.z))
	return local


## Whether the projection prism mesh is currently built (a collapsed prism has a footprint quad but no mesh).
func _has_projection_mesh(ghost: GhostPreview) -> bool:
	return GhostParts.has_prism_mesh(ghost)


## Every world-space vertex of the projection prism mesh.
func _prism_vertices(ghost: GhostPreview) -> PackedVector3Array:
	return GhostParts.prism_vertices(ghost)


## The silhouette outline loops (ghost-local XZ) the prism walls are built from.
func _outline_loops(ghost: GhostPreview) -> Array[PackedVector2Array]:
	return GhostParts.silhouette(ghost).loops


# --- rotated-bottom pivot -----------------------------

## The lowest world-space Y any corner of the ghost's own shape visual
## reaches -- the thing a player actually sees clip into the disk or float
## above the cursor if the pivot math is wrong. Each mesh's local box corners
## have to go through `ghost.basis` (not just a Y-translation) to land in
## world space correctly once the ghost itself is rotated -- a MeshInstance3D
## child's own `.position` is local to the (unrotated) ShapeVisual/ghost
## frame, and its rotation comes entirely from the ghost node's own basis.
func _visual_world_bottom_y(ghost: GhostPreview) -> float:
	var visual: Node3D = null
	for child: Node in ghost.get_children():
		if child.name == "ShapeVisual":
			visual = child as Node3D
			break
	assert_not_null(visual, "fixture: the ghost should have a shape visual once a shape is set.")
	var min_world_y: float = INF
	for mesh_child: Node in visual.get_children():
		var mesh_instance: MeshInstance3D = mesh_child as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var local_aabb: AABB = mesh_instance.mesh.get_aabb()
		for corner_index: int in range(8):
			var corner_local: Vector3 = local_aabb.position + Vector3(
				local_aabb.size.x * float(corner_index & 1),
				local_aabb.size.y * float((corner_index >> 1) & 1),
				local_aabb.size.z * float((corner_index >> 2) & 1)
			)
			var world_corner: Vector3 = ghost.global_position + ghost.basis * (mesh_instance.position + corner_local)
			min_world_y = minf(min_world_y, world_corner.y)
	return min_world_y


## Requirement "the preview starts from the bottom
## of the ghost block which looks a bit weird when it's angled": the mirror
## image of _visual_world_bottom_y() above -- the highest world-space Y any
## corner of the ghost's own shape visual reaches, used to check the
## projection prism's own new top-of-column cap.
func _visual_world_top_y(ghost: GhostPreview) -> float:
	var visual: Node3D = null
	for child: Node in ghost.get_children():
		if child.name == "ShapeVisual":
			visual = child as Node3D
			break
	assert_not_null(visual, "fixture: the ghost should have a shape visual once a shape is set.")
	var max_world_y: float = -INF
	for mesh_child: Node in visual.get_children():
		var mesh_instance: MeshInstance3D = mesh_child as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var local_aabb: AABB = mesh_instance.mesh.get_aabb()
		for corner_index: int in range(8):
			var corner_local: Vector3 = local_aabb.position + Vector3(
				local_aabb.size.x * float(corner_index & 1),
				local_aabb.size.y * float((corner_index >> 1) & 1),
				local_aabb.size.z * float((corner_index >> 2) & 1)
			)
			var world_corner: Vector3 = ghost.global_position + ghost.basis * (mesh_instance.position + corner_local)
			max_world_y = maxf(max_world_y, world_corner.y)
	return max_world_y


func test_update_placement_puts_an_unrotated_shapes_visual_bottom_at_the_reported_height() -> void:
	var ghost: GhostPreview = _make_ghost()

	ghost.update_placement(Vector3(2.0, 5.0, -3.0), Vector3.UP)

	assert_almost_eq(ghost.global_position.x, 2.0, 0.001)
	assert_almost_eq(ghost.global_position.z, -3.0, 0.001)
	var expected_bottom: float = 5.0 + ghost.tuning.hover_height
	assert_almost_eq(
		_visual_world_bottom_y(ghost), expected_bottom, ghost.tuning.cube_margin * 0.5 + 0.001,
		"the ghost's own bottom face should sit at the reported disk height plus hover_height."
	)


## The regression this item exists to fix: pillar is 3 cells tall unrotated,
## so tipping it 90 degrees onto its side used to leave its old bottom-centre
## pivot -- now off to one side of the tipped shape, not underneath it --
## sitting at the cursor height while the actual lowest point hung well
## below it (or floated above, depending on direction).
func test_update_placement_keeps_a_rotated_talls_shapes_visual_bottom_at_the_reported_height() -> void:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/pillar.tres"))
	ghost.set_orientation_index(BlockOrientations.step_pitch_fwd(0))

	ghost.update_placement(Vector3(0.0, 4.0, 0.0), Vector3.UP)

	var expected_bottom: float = 4.0 + ghost.tuning.hover_height
	assert_almost_eq(
		_visual_world_bottom_y(ghost), expected_bottom, ghost.tuning.cube_margin * 0.5 + 0.001,
		"after a 90-degree pitch, the pillar's own rotated lowest point must sit at the reported height."
	)


# --- footprint projection: the whole rotated shape's silhouette ------------
# The footprint is always the whole rotated shape's own silhouette -- one
# polygon, not one per bottom cell -- so a case that used to expect one quad per
# distinct column expects exactly 1.

func _flat_l_shape() -> BlockShape:
	var shape: BlockShape = BlockShape.new()
	shape.id = &"test_flat_l"
	shape.cells = [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1)]
	return shape


func _bbox_of(points: PackedVector2Array) -> Rect2:
	var min_pt: Vector2 = points[0]
	var max_pt: Vector2 = points[0]
	for point: Vector2 in points:
		min_pt = Vector2(minf(min_pt.x, point.x), minf(min_pt.y, point.y))
		max_pt = Vector2(maxf(max_pt.x, point.x), maxf(max_pt.y, point.y))
	return Rect2(min_pt, max_pt - min_pt)


func _polygon_area(points: PackedVector2Array) -> float:
	var area: float = 0.0
	var n: int = points.size()
	for i: int in range(n):
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	return absf(area) * 0.5


## The regression this pins: before every footprint quad was a
## fixed axis-aligned unit square whose *position* (not shape) tracked the
## rotated shape (docs/rotation-issue.png: a rotated block with unrotated,
## overlapping footprint squares). At a 90-degree yaw a square's own bounding
## box happens to look the same either way, so this checks 45 degrees too,
## where a truly rotated shape's footprint becomes a diamond -- a bug that
## left the bounding box at the original axis-aligned size would be caught by
## the 45-degree case's larger, non-axis-aligned bounding box.
##
## updated for the whole-shape hull contract -- there is now
## exactly one footprint polygon (index 0) covering every cell's own rotated
## corners together, not one polygon per cell, so the expected points below
## are gathered across all of the L-shape's 3 cells before taking their own
## convex hull (the same primitive the implementation calls, but the corner
## *rotation* math is still independently hand-expanded, which is the part
## 's regression was actually in).
func test_footprint_polygon_matches_the_whole_rotated_shapes_projected_corners() -> void:
	var shape: BlockShape = _flat_l_shape()
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(shape)

	# The footprint follows the rendered shell, so the corners use the visual cube_size box.
	var half_size: float = ghost.tuning.cube_size * 0.5
	var pivot: Vector3 = shape.bottom_center()
	var corner_signs: Array[Vector3] = [
		Vector3(-1.0, -1.0, -1.0), Vector3(1.0, -1.0, -1.0), Vector3(-1.0, 1.0, -1.0), Vector3(1.0, 1.0, -1.0),
		Vector3(-1.0, -1.0, 1.0), Vector3(1.0, -1.0, 1.0), Vector3(-1.0, 1.0, 1.0), Vector3(1.0, 1.0, 1.0),
	]

	for angle: float in [PI * 0.5, PI * 0.25]:
		ghost.free_quaternion = Quaternion(Vector3.UP, angle)
		ghost.set_orientation_index(0)
		ghost.update_placement(Vector3.ZERO, Vector3.UP)

		var expected_points: PackedVector2Array = PackedVector2Array()
		for cell: Vector3i in shape.cells:
			var local_center: Vector3 = (Vector3(cell) - pivot) * ghost.tuning.cube_size
			for corner_sign: Vector3 in corner_signs:
				var corner: Vector3 = local_center + corner_sign * half_size
				# Basis(Vector3.UP, angle) * corner, hand-expanded (matches
				# CameraRig/PlayerController's own forward = (sin, 0, cos)
				# convention: yaw increasing rotates +Z toward +X).
				var x: float = corner.x * cos(angle) + corner.z * sin(angle)
				var z: float = -corner.x * sin(angle) + corner.z * cos(angle)
				expected_points.append(Vector2(x, z))
		var expected_hull: PackedVector2Array = Geometry2D.convex_hull(expected_points)
		var expected_bbox: Rect2 = _bbox_of(expected_hull)
		var expected_area: float = float(shape.cells.size()) * ghost.tuning.cube_size * ghost.tuning.cube_size

		assert_eq(_footprint_quad_count(ghost), 1, "the whole L-shape must still show exactly one footprint polygon.")
		var actual_polygon: PackedVector2Array = _footprint_polygon_local(ghost)
		var actual_bbox: Rect2 = _bbox_of(actual_polygon)
		assert_true(
			actual_bbox.position.is_equal_approx(expected_bbox.position),
			"bbox origin wrong at angle %.3f: got %s expected %s" % [angle, actual_bbox.position, expected_bbox.position]
		)
		assert_true(
			actual_bbox.size.is_equal_approx(expected_bbox.size),
			"bbox size wrong at angle %.3f: got %s expected %s" % [angle, actual_bbox.size, expected_bbox.size]
		)
		var silhouette_area: float = 0.0
		for loop: PackedVector2Array in _outline_loops(ghost):
			silhouette_area += _polygon_area(loop)
		assert_almost_eq(
			silhouette_area, expected_area, 0.001,
			"a rigid rotation must preserve the whole shape's own footprint area exactly, at any angle."
		)


# --- the whole-shape projection prism -------------------------

func _footprint_test_map() -> MapDef:
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_ghost_preview_footprint_disk"
	map_def.field_radius = 12.0
	map_def.cell_size = 1.0
	map_def.disk_height = 1.0
	map_def.territory_res = 16
	return map_def


## The owner's own repro ("I took a screenshot where I'm hovering a tilted
## ghost block on top of a dropped block and you can see that the middle
## section of the ghost block shows up on top of the dropped block and the
## other sections land on the disc"): a tilted bar3 held above a real placed
## pillar must show exactly one footprint polygon, landed on the bare disc
## (never the pillar's own top face -- the old per-cell raycast against the
## unfiltered world happily landed there), plus a projection prism reaching
## from that same disc height up to the held shape's own current highest
## point (the column now caps at the shape's top, not its
## bottom, so a pitched/yawed ghost sits fully inside it).
func test_pitched_bar3_over_a_placed_block_gets_one_disc_footprint_and_a_matching_prism() -> void:
	var field: Field = autofree(Field.new())
	field.map_def = _footprint_test_map()
	add_child_autofree(field)

	var tuning: PhysicsTuning = load("res://config/physics/physics_tuning.tres")
	var block: Block = BlockFactory.build(load("res://config/blocks/pillar.tres"), tuning)
	field.get_parent().add_child(block)
	autofree(block)
	block.global_position = Vector3(0.0, 5.0, 0.0)
	await wait_physics_frames(90)
	block.sleeping = true

	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/bar3.tres"))
	# A partial pitch (not a 90-degree step, which for an X-extending bar
	# pitched about X is a geometric no-op -- see game/player/PlayerController.gd's
	# own test_moving_horizontally_into_a_placed_block_stops_short_of_it_at_a_
	# pitched_rotation for the same choice), same as the owner's own
	# rotate-drag gesture.
	ghost.apply_free_rotation_delta(0.0, deg_to_rad(20.0), Vector3.RIGHT)

	# The disk-only probe (item 5) reports the bare disk
	# surface at the field's own origin regardless of the pillar sitting
	# there -- same surface_point PlayerController's own probe would report.
	var disk_surface_point: Vector3 = Vector3.ZERO
	ghost.update_placement(disk_surface_point, Vector3.UP)

	assert_eq(_footprint_quad_count(ghost), 1, "one whole-shape footprint, not one per cell.")
	assert_almost_eq(
		GhostParts.footprint_quads(ghost)[0].global_position.y, disk_surface_point.y + ghost.ghost_tuning.footprint_offset, 0.01,
		"the footprint must land on the bare disc, never the placed pillar's own top face."
	)

	assert_true(_has_projection_mesh(ghost), "a real gap between the shape and the disc must show a projection prism.")


# --- projection walls: no dark seams or overlapping stepped columns -----------
# A tilted 4-long bar and a T-piece used to show vertical seams inside the
# translucent prism.
# Attempt 3 walls the *merged rendered mesh's* own silhouette (game/
# GhostPreview.gd's _shape_silhouette_loops(), Geometry2D.merge_polygons over
# every triangle of the shape's own real visual shell) instead of the earlier
# per-column hulls, so no interior wall is left to double-blend. Attempt 4
# restores the per-column hull rule on top of that: the prism is the shaft
# *under* the shape -- every wall's top follows the shape's own underside along
# the outline (sloped for a tilted shape, stepped where an overhang begins),
# never the whole shape's top. The tests below check the built mesh itself
# (_prism_vertices()).

## The same 8 corner signs _CORNER_SIGNS declares (game/player/GhostPreview.gd),
## independently re-declared here so the per-cell expectations below are a real
## check of the implementation, not its own self-consistency.
const _TEST_CORNER_SIGNS: Array[Vector3] = [
	Vector3(-1.0, -1.0, -1.0), Vector3(1.0, -1.0, -1.0), Vector3(-1.0, 1.0, -1.0), Vector3(1.0, 1.0, -1.0),
	Vector3(-1.0, -1.0, 1.0), Vector3(1.0, -1.0, 1.0), Vector3(-1.0, 1.0, 1.0), Vector3(1.0, 1.0, 1.0),
]
## How far the independent underside probe below nudges its sample point off
## the wall line toward the shape (it must not land exactly on the outline,
## which every neighbouring triangle touches) -- deliberately different from
## GhostPreview's own inset so the two are not trivially the same computation.
const _TEST_PROBE_NUDGE: float = 0.004
## Allowed mismatch between a wall's top edge and the independently probed
## underside: the nudge times the steepest face slope a 30-degree roll makes
## (tan 60 ~ 1.73) plus float slack.
const _TEST_UNDERSIDE_TOLERANCE: float = 0.015


## One rotated `cell`'s own lowest world-space Y (its own underside), from the
## visual cube_size box and the shape's bottom_center() pivot.
func _expected_cell_min_y(ghost: GhostPreview, cell: Vector3i) -> float:
	var half_size: float = ghost.tuning.cube_size * 0.5
	var pivot: Vector3 = ghost.get_shape().bottom_center()
	var local_center: Vector3 = (Vector3(cell) - pivot) * ghost.tuning.cube_size
	var min_y: float = INF
	for corner_sign: Vector3 in _TEST_CORNER_SIGNS:
		var rotated: Vector3 = ghost.basis * (local_center + corner_sign * half_size)
		min_y = minf(min_y, rotated.y)
	return ghost.global_position.y + min_y


## Every world-space triangle of the ghost's own rendered shell, read straight
## off the ShapeVisual meshes (not through any GhostPreview helper).
func _world_shell_triangles(ghost: GhostPreview) -> Array[PackedVector3Array]:
	var triangles: Array[PackedVector3Array] = []
	for child: Node in ghost.get_children():
		if child.name != "ShapeVisual":
			continue
		for mesh_child: Node in child.get_children():
			var mesh_instance: MeshInstance3D = mesh_child as MeshInstance3D
			if mesh_instance == null or mesh_instance.mesh == null:
				continue
			for surface: int in range(mesh_instance.mesh.get_surface_count()):
				var arrays: Array = mesh_instance.mesh.surface_get_arrays(surface)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				for i: int in range(0, indices.size(), 3):
					var triangle: PackedVector3Array = PackedVector3Array()
					for k: int in range(3):
						triangle.append(ghost.global_position + ghost.basis * (mesh_instance.position + verts[indices[i + k]]))
					triangles.append(triangle)
	return triangles


## The lowest point of the shell straight above/below world XZ `point`
## (INF if no triangle covers it) -- a closed shell's lowest surface there is
## its underside. Own barycentric math, skipping edge-on (vertical) triangles.
func _probe_underside_y(triangles: Array[PackedVector3Array], point: Vector2) -> float:
	var lowest: float = INF
	for triangle: PackedVector3Array in triangles:
		var p0: Vector2 = Vector2(triangle[0].x, triangle[0].z)
		var e1: Vector2 = Vector2(triangle[1].x, triangle[1].z) - p0
		var e2: Vector2 = Vector2(triangle[2].x, triangle[2].z) - p0
		var denominator: float = e1.x * e2.y - e2.x * e1.y
		if absf(denominator) < 1e-8:
			continue
		var d: Vector2 = point - p0
		var w1: float = (d.x * e2.y - e2.x * d.y) / denominator
		var w2: float = (e1.x * d.y - d.x * e1.y) / denominator
		if w1 < 0.0 or w2 < 0.0 or w1 + w2 > 1.0:
			continue
		lowest = minf(lowest, triangle[0].y + w1 * (triangle[1].y - triangle[0].y) + w2 * (triangle[2].y - triangle[0].y))
	return lowest


## Every prism wall's top edge must sit on the shape's own underside: sampled
## at 3 interior points per wall, nudged toward whichever side the shell
## covers, and compared against the independently probed underside. Must fail
## against attempt 3 (every wall capped at the whole shape's own top).
func _assert_wall_tops_follow_the_underside(ghost: GhostPreview) -> void:
	var triangles: Array[PackedVector3Array] = _world_shell_triangles(ghost)
	var vertices: PackedVector3Array = _prism_vertices(ghost)
	assert_false(vertices.is_empty(), "fixture: a real gap between the shape and the disc must show prism geometry.")
	for wall_index: int in range(vertices.size() / 4):
		var top_a: Vector3 = vertices[wall_index * 4]
		var top_b: Vector3 = vertices[wall_index * 4 + 1]
		var a: Vector2 = Vector2(top_a.x, top_a.z)
		var b: Vector2 = Vector2(top_b.x, top_b.z)
		if a.distance_to(b) < 0.01:
			continue
		var direction: Vector2 = (b - a).normalized()
		var side_normal: Vector2 = Vector2(-direction.y, direction.x)
		for t: float in [0.25, 0.5, 0.75]:
			var point: Vector2 = a.lerp(b, t)
			var wall_top: float = lerpf(top_a.y, top_b.y, t)
			var underside: float = _probe_underside_y(triangles, point + side_normal * _TEST_PROBE_NUDGE)
			if underside == INF:
				underside = _probe_underside_y(triangles, point - side_normal * _TEST_PROBE_NUDGE)
			assert_true(underside != INF, "wall at (%.3f, %.3f) has no shape over it at all." % [point.x, point.y])
			assert_almost_eq(
				wall_top, underside, _TEST_UNDERSIDE_TOLERANCE,
				"wall top at (%.3f, %.3f) must follow the shape's own underside there." % [point.x, point.y]
			)


## No two prism walls may overlap along the same stretch of ground-plane line
## -- the exact seam symptom the owner's own screenshots show (two walls
## Z-fighting/double-blending). Reconstructs each wall quad from the flat
## vertex list (GhostPreview always appends exactly 4 vertices per wall, in
## (a_top, b_top, b_bottom, a_bottom) order) and checks every pair of collinear
## walls for a shared interior span, not just identical endpoints (walls are
## split into pieces now, so a duplicate need not share both ends).
func _assert_no_duplicate_wall_edges(vertices: PackedVector3Array) -> void:
	assert_eq(vertices.size() % 4, 0, "fixture: GhostPreview always appends exactly 4 vertices per wall.")
	var wall_count: int = vertices.size() / 4
	for i: int in range(wall_count):
		var a: Vector2 = Vector2(vertices[i * 4].x, vertices[i * 4].z)
		var b: Vector2 = Vector2(vertices[i * 4 + 1].x, vertices[i * 4 + 1].z)
		var length: float = a.distance_to(b)
		if length < 0.001:
			continue
		var direction: Vector2 = (b - a) / length
		for j: int in range(i + 1, wall_count):
			var c: Vector2 = Vector2(vertices[j * 4].x, vertices[j * 4].z)
			var d: Vector2 = Vector2(vertices[j * 4 + 1].x, vertices[j * 4 + 1].z)
			# Collinear with wall i?
			if absf(direction.cross(c - a)) > 0.001 or absf(direction.cross(d - a)) > 0.001:
				continue
			var t_c: float = direction.dot(c - a)
			var t_d: float = direction.dot(d - a)
			var overlap: float = minf(length, maxf(t_c, t_d)) - maxf(0.0, minf(t_c, t_d))
			assert_true(
				overlap <= 0.001,
				"walls %d and %d overlap by %.3f m along the same line -- coincident walls double-blend into a visible seam." % [i, j, overlap]
			)


## Every prism wall must lie on one of the merged silhouette's own outline
## edges (no interior wall left over from a per-cell/per-column approximation,
## the seam bug's own root cause), and -- with the whole shape clear of the
## ground -- together they must cover the outline's whole perimeter exactly.
func _assert_walls_tile_the_outline(ghost: GhostPreview) -> void:
	var edges: Array[PackedVector2Array] = []
	var perimeter: float = 0.0
	for loop_index: int in range(_outline_loops(ghost).size()):
		var loop: PackedVector2Array = PackedVector2Array()
		for local_point: Vector2 in _outline_loops(ghost)[loop_index]:
			loop.append(Vector2(ghost.global_position.x + local_point.x, ghost.global_position.z + local_point.y))
		for i: int in range(loop.size()):
			var edge: PackedVector2Array = PackedVector2Array([loop[i], loop[(i + 1) % loop.size()]])
			edges.append(edge)
			perimeter += edge[0].distance_to(edge[1])
	var vertices: PackedVector3Array = _prism_vertices(ghost)
	var wall_length: float = 0.0
	for wall_index: int in range(vertices.size() / 4):
		var a: Vector2 = Vector2(vertices[wall_index * 4].x, vertices[wall_index * 4].z)
		var b: Vector2 = Vector2(vertices[wall_index * 4 + 1].x, vertices[wall_index * 4 + 1].z)
		wall_length += a.distance_to(b)
		var on_edge: bool = false
		for edge: PackedVector2Array in edges:
			var closest_a: Vector2 = Geometry2D.get_closest_point_to_segment(a, edge[0], edge[1])
			var closest_b: Vector2 = Geometry2D.get_closest_point_to_segment(b, edge[0], edge[1])
			if closest_a.distance_to(a) < 0.001 and closest_b.distance_to(b) < 0.001:
				on_edge = true
				break
		assert_true(on_edge, "wall (%.3f, %.3f)->(%.3f, %.3f) is not on the silhouette outline." % [a.x, a.y, b.x, b.y])
	assert_almost_eq(wall_length, perimeter, 0.01, "the walls must cover the whole silhouette perimeter, once.")


func _max_wall_vertex_y(ghost: GhostPreview) -> float:
	var highest: float = -INF
	for vertex: Vector3 in _prism_vertices(ghost):
		highest = maxf(highest, vertex.y)
	return highest


func _held_ghost(shape_path: String, roll_degrees: float) -> GhostPreview:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load(shape_path))
	if roll_degrees != 0.0:
		ghost.apply_free_rotation_delta(0.0, deg_to_rad(roll_degrees), Vector3.RIGHT)
	ghost.update_placement(Vector3.ZERO, Vector3.UP)
	return ghost


## 's own "single cube unchanged" case: the shaft's top is the
## cube's own underside, never its top (the earlier whole-shape cap attempt
## reverted to). Must fail against attempt 3.
func test_single_cube_projection_walls_cap_at_its_own_underside_not_the_shapes_own_top() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.update_placement(Vector3.ZERO, Vector3.UP)

	assert_true(_has_projection_mesh(ghost), "fixture: hover_height alone leaves a real gap under the cube.")
	assert_almost_eq(
		_max_wall_vertex_y(ghost), _visual_world_bottom_y(ghost), 0.001,
		"the walls' own top must be the cube's own underside, not its top."
	)
	assert_true(
		_max_wall_vertex_y(ghost) < _visual_world_top_y(ghost) - 0.001,
		"the walls must stop below the cube's own top, not enclose the whole solid body."
	)
	_assert_walls_tile_the_outline(ghost)


## The literal S4 repro, restored: config/blocks/S4.tres has
## cells (1,0,0)/(2,0,0) in a bottom row and (0,1,0)/(1,1,0) directly above,
## offset one column left. No wall vertex may rise above the lower cells' own
## top (a full cube_size below the shape's own top), the x=0 end (under the
## overhanging (0,1,0)) must reach exactly that overhang's underside, and the
## x=2 end must stop at (2,0,0)'s own underside. Must fail against attempt 3
## (every wall capped at the whole shape's own top).
func test_s4_at_identity_rotation_never_projects_above_the_lower_cells_own_top() -> void:
	var ghost: GhostPreview = _held_ghost("res://config/blocks/S4.tres", 0.0)

	var lower_cell_underside_y: float = _expected_cell_min_y(ghost, Vector3i(2, 0, 0))
	var overhang_underside_y: float = _expected_cell_min_y(ghost, Vector3i(0, 1, 0))
	var lower_cell_top_y: float = lower_cell_underside_y + ghost.tuning.cube_size
	assert_almost_eq(overhang_underside_y, lower_cell_top_y, 0.001, "fixture: the overhang sits on the lower row's top level.")

	var vertices: PackedVector3Array = _prism_vertices(ghost)
	assert_false(vertices.is_empty(), "fixture: a real gap between the shape and the disc must show prism geometry.")
	var min_x: float = INF
	var max_x: float = -INF
	for vertex: Vector3 in vertices:
		min_x = minf(min_x, vertex.x)
		max_x = maxf(max_x, vertex.x)
		assert_true(
			vertex.y <= lower_cell_top_y + 0.01,
			"no prism vertex may sit above the lower cells' own top (%.3f); got %.3f at (%.3f, %.3f)"
				% [lower_cell_top_y, vertex.y, vertex.x, vertex.z]
		)
	for wall_index: int in range(vertices.size() / 4):
		for k: int in range(2):
			var top: Vector3 = vertices[wall_index * 4 + k]
			if absf(top.x - min_x) < 0.001:
				assert_almost_eq(top.y, overhang_underside_y, 0.001, "the overhang's own end wall reaches its underside.")
			elif absf(top.x - max_x) < 0.001:
				assert_almost_eq(top.y, lower_cell_underside_y, 0.001, "(2,0,0)'s end wall stops at its own underside.")
	_assert_no_duplicate_wall_edges(vertices)


## The owner's own literal repro shape/gesture: a 1x4 bar rolled 30 degrees
## about its own long axis (screenshot_20260924_204137.png) sends every one of
## its 4 cells to a distinct, overlapping rotated footprint -- exactly the case
## The per-column model could not merge or dedupe. One outer loop, no
## overlapping walls, and every wall top on the bar's own sloped underside.
func test_tilted_bar_silhouette_stays_a_single_outer_loop_with_no_overlapping_walls() -> void:
	var ghost: GhostPreview = _held_ghost("res://config/blocks/bar4.tres", 30.0)

	assert_eq(
		_outline_loops(ghost).size(), 1,
		"a rolled bar's 4 cells project to overlapping quads, but the true rendered silhouette is one outer loop."
	)
	_assert_walls_tile_the_outline(ghost)
	_assert_no_duplicate_wall_edges(_prism_vertices(ghost))
	_assert_wall_tops_follow_the_underside(ghost)
	assert_true(
		_max_wall_vertex_y(ghost) < _visual_world_top_y(ghost) - 0.01,
		"the rolled bar's shaft must stay under the bar, never reach its own top."
	)
