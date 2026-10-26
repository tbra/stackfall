class_name GhostParts
extends RefCounted
## Reads a GhostPreview's presentation through its child nodes, by node class and public name: the
## shape visual, the gift visual, the footprint quads, the projection prism and the block decal.
## Tests use it instead of the ghost's private fields.


## The block shell node (BlockFactory.build_visual_only names it), or null with no shape.
static func shape_visual(ghost: GhostPreview) -> Node3D:
	return ghost.get_node_or_null("ShapeVisual") as Node3D


## The held-gift model, or null when the plain block is shown.
static func gift_visual(ghost: GhostPreview) -> Node3D:
	return ghost.get_node_or_null(NodePath(GhostPreview.GIFT_VISUAL_NAME)) as Node3D


## Every live footprint quad: a top-level MeshInstance3D whose material does not blend additively.
static func footprint_quads(ghost: GhostPreview) -> Array[MeshInstance3D]:
	var quads: Array[MeshInstance3D] = []
	for child: Node in ghost.get_children():
		var mesh_instance: MeshInstance3D = child as MeshInstance3D
		if mesh_instance != null and mesh_instance.top_level and not mesh_instance.is_queued_for_deletion() \
				and not _is_additive(mesh_instance):
			quads.append(mesh_instance)
	return quads


## The light-shaft prism node: the top-level MeshInstance3D with an additive material.
static func prism(ghost: GhostPreview) -> MeshInstance3D:
	for child: Node in ghost.get_children():
		var mesh_instance: MeshInstance3D = child as MeshInstance3D
		if mesh_instance != null and mesh_instance.top_level and _is_additive(mesh_instance):
			return mesh_instance
	return null


## The block projection decal child.
static func decal(ghost: GhostPreview) -> Decal:
	for child: Node in ghost.get_children():
		var found: Decal = child as Decal
		if found != null:
			return found
	return null


## Whether a prism mesh is currently built (a collapsed prism keeps its node but has no mesh).
static func has_prism_mesh(ghost: GhostPreview) -> bool:
	var node: MeshInstance3D = prism(ghost)
	return node != null and node.mesh != null


## Every world-space vertex of the prism mesh, four per wall in (a_top, b_top, b_bottom, a_bottom) order.
static func prism_vertices(ghost: GhostPreview) -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	if not has_prism_mesh(ghost):
		return result
	var node: MeshInstance3D = prism(ghost)
	var mesh: ArrayMesh = node.mesh as ArrayMesh
	var offset: Vector3 = node.global_position
	for surface: int in range(mesh.get_surface_count()):
		var verts: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for v: Vector3 in verts:
			result.append(Vector3(v.x + offset.x, v.y, v.z + offset.z))
	return result


## World-space XZ of every vertex of a footprint quad's mesh.
static func quad_points_world(quad: MeshInstance3D) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	var mesh: ArrayMesh = quad.mesh as ArrayMesh
	if mesh == null:
		return result
	for surface: int in range(mesh.get_surface_count()):
		var verts: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for v: Vector3 in verts:
			result.append(Vector2(v.x + quad.global_position.x, v.z + quad.global_position.z))
	return result


## GhostSilhouette result for the ghost's own block meshes at its current rotation, in ghost-local XZ.
static func silhouette(ghost: GhostPreview) -> GhostSilhouette.Result:
	var meshes: Array[Mesh] = []
	var offsets: PackedVector3Array = PackedVector3Array()
	var visual: Node3D = shape_visual(ghost)
	if visual != null:
		for child: Node in visual.get_children():
			var mesh_instance: MeshInstance3D = child as MeshInstance3D
			if mesh_instance != null and mesh_instance.mesh != null:
				meshes.append(mesh_instance.mesh)
				offsets.append(mesh_instance.position)
	return GhostSilhouette.build(meshes, offsets, ghost.basis)


static func _is_additive(mesh_instance: MeshInstance3D) -> bool:
	var material: StandardMaterial3D = mesh_instance.material_override as StandardMaterial3D
	return material != null and material.blend_mode == BaseMaterial3D.BLEND_MODE_ADD
