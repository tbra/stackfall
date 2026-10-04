class_name DiskShapeMesh
extends RefCounted
## Builds the visible slab mesh for a map whose shape is not a plain circle or
## ellipse (RING, TWIN, CROSS; Bontago-1pi.60). TerritoryOverlay used to draw
## one CylinderMesh for every shape, so those maps looked like the default disc
## while the collider and rules used the real cell shape. This builds the same
## cells Field's collision trimesh uses: one top quad per in-shape cell at
## y = +height / 2 and a wall, `height` deep, on every side facing outside the
## shape, centred on y = 0 like a CylinderMesh of that height.

const NEIGHBOUR_DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]


## True when MapDef's shape needs this mesh rather than a (possibly z-scaled) cylinder.
static func needs_cell_mesh(map_def: MapDef) -> bool:
	return map_def.map_shape != MapDef.MapShape.ROUND and map_def.map_shape != MapDef.MapShape.OVAL


static func build(map_def: MapDef, height: float) -> ArrayMesh:
	var grid: CellGrid = CellGrid.new(map_def.field_radius, map_def.cell_size, map_def.shape_test())
	var inside: PackedByteArray = PackedByteArray()
	inside.resize(grid.cell_count())
	for cell: int in grid.in_disk_cells():
		inside[cell] = 1
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var half: float = height * 0.5
	for cell: int in grid.in_disk_cells():
		var c: Vector2i = grid.cell_coords(cell)
		var x0: float = float(c.x) * grid.cell_size - grid.half_extent
		var z0: float = float(c.y) * grid.cell_size - grid.half_extent
		var x1: float = x0 + grid.cell_size
		var z1: float = z0 + grid.cell_size
		# Top face, normal +Y (counter-clockwise seen from above is front in Godot).
		_tri(verts, normals, Vector3(x0, half, z0), Vector3(x0, half, z1), Vector3(x1, half, z1), Vector3.UP)
		_tri(verts, normals, Vector3(x0, half, z0), Vector3(x1, half, z1), Vector3(x1, half, z0), Vector3.UP)
		for dir: Vector2i in NEIGHBOUR_DIRS:
			var n: Vector2i = c + dir
			if grid.in_bounds(n.x, n.y) and inside[grid.cell_index(n.x, n.y)] == 1:
				continue
			var a: Vector3
			var b: Vector3
			var out: Vector3 = Vector3(float(dir.x), 0.0, float(dir.y))
			if dir.x != 0:
				var x: float = x1 if dir.x > 0 else x0
				a = Vector3(x, half, z0)
				b = Vector3(x, half, z1)
			else:
				var z: float = z1 if dir.y > 0 else z0
				a = Vector3(x0, half, z)
				b = Vector3(x1, half, z)
			var down: Vector3 = Vector3(0.0, -height, 0.0)
			# Winding is fixed up by _tri() against `out`.
			_tri(verts, normals, a, b, b + down, out)
			_tri(verts, normals, a, b + down, a + down, out)
	var mesh: ArrayMesh = ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Appends one triangle wound so its front face (clockwise in Godot) looks along `front`.
static func _tri(
	verts: PackedVector3Array, normals: PackedVector3Array,
	p0: Vector3, p1: Vector3, p2: Vector3, front: Vector3
) -> void:
	var facing: Vector3 = (p1 - p0).cross(p2 - p0)
	if facing.dot(front) > 0.0:
		verts.append_array(PackedVector3Array([p0, p2, p1]))
	else:
		verts.append_array(PackedVector3Array([p0, p1, p2]))
	for _i: int in range(3):
		normals.append(front)
