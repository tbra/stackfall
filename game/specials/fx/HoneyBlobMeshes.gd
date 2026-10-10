class_name HoneyBlobMeshes
## Generated (never hand-modelled) meshes for the blob honey looks (Bontago-lv2): a subdivided
## cube shell per block cell for JELLY and small flattened
## spheres for BEADS. Cells are given as block-local centres (the CollisionShape3D offsets).
## CUSTOM0 on shell/bounds meshes = (cell centre xyz, bitmask of occupied neighbour cells).

const CELL_SIZE_M: float = 1.0
const FACE_COUNT: int = 6
const AXIS_COUNT: int = 3
const CORNERS_PER_AXIS: int = 4
const CELL_MATCH_EPS_SQ: float = 0.01
const BEAD_RINGS: int = 5
const BEAD_SEGMENTS: int = 8
const CUBE_EDGES: int = 12
const EDGE_INSET: float = 0.96
const SEED_PRIME_A: int = 73856093
const SEED_PRIME_B: int = 19349663
const SEED_PRIME_C: int = 83492791
const SEED_SCALE: float = 100.0


## Face index -> unit normal: +x, -x, +y, -y, +z, -z. Bit `i` of the neighbour mask = a cell at +normal[i].
static func face_normal(face: int) -> Vector3:
	var axis: int = face >> 1
	var sign_value: float = 1.0 if face % 2 == 0 else -1.0
	var n: Vector3 = Vector3.ZERO
	n[axis] = sign_value
	return n


static func neighbour_mask(centres: Array[Vector3], centre: Vector3) -> int:
	var mask: int = 0
	for face: int in range(FACE_COUNT):
		var probe: Vector3 = centre + face_normal(face) * CELL_SIZE_M
		for other: Vector3 in centres:
			if other.distance_squared_to(probe) < CELL_MATCH_EPS_SQ:
				mask |= 1 << face
				break
	return mask


## Subdivided cube shell for every cell; faces shared with a neighbouring cell are skipped.
static func shell(centres: Array[Vector3], subdivisions: int, half: float) -> ArrayMesh:
	return _boxes(centres, maxi(subdivisions, 1), half)


static func _boxes(centres: Array[Vector3], subdivisions: int, half: float) -> ArrayMesh:
	var positions: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var custom: PackedFloat32Array = PackedFloat32Array()
	var indices: PackedInt32Array = PackedInt32Array()
	for centre: Vector3 in centres:
		var mask: int = neighbour_mask(centres, centre)
		for face: int in range(FACE_COUNT):
			if mask & (1 << face) != 0:
				continue
			_append_face(positions, normals, custom, indices, centre, mask, face, subdivisions, half)
	return _array_mesh(positions, normals, custom, indices)


static func _append_face(positions: PackedVector3Array, normals: PackedVector3Array, custom: PackedFloat32Array, indices: PackedInt32Array, centre: Vector3, mask: int, face: int, subdivisions: int, half: float) -> void:
	var axis: int = face >> 1
	var positive: bool = face % 2 == 0
	var u_axis: int = (axis + 1) % AXIS_COUNT
	var v_axis: int = (axis + 2) % AXIS_COUNT
	var normal: Vector3 = face_normal(face)
	var base: int = positions.size()
	for j: int in range(subdivisions + 1):
		for i: int in range(subdivisions + 1):
			var local: Vector3 = Vector3.ZERO
			local[axis] = half if positive else -half
			local[u_axis] = (float(i) / float(subdivisions) * 2.0 - 1.0) * half
			local[v_axis] = (float(j) / float(subdivisions) * 2.0 - 1.0) * half
			positions.append(centre + local)
			normals.append(normal)
			custom.append_array(PackedFloat32Array([centre.x, centre.y, centre.z, float(mask)]))
	var row: int = subdivisions + 1
	for j: int in range(subdivisions):
		for i: int in range(subdivisions):
			var p00: int = base + j * row + i
			var p10: int = p00 + 1
			var p01: int = p00 + row
			var p11: int = p01 + 1
			# Godot front faces are clockwise seen from outside.
			if positive:
				indices.append_array(PackedInt32Array([p00, p11, p10, p00, p01, p11]))
			else:
				indices.append_array(PackedInt32Array([p00, p10, p11, p00, p11, p01]))


## Flattened glossy beads scattered along each cell's 12 edges (where glue squeezes out), seeded
## from the cell position so every peer builds the same beads.
static func beads(centres: Array[Vector3], per_cell: int, min_radius: float, max_radius: float, flatten: float) -> ArrayMesh:
	var positions: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var half_cell: float = CELL_SIZE_M * 0.5
	for centre: Vector3 in centres:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = _seed_for(centre)
		for _b: int in range(per_cell):
			var edge: int = rng.randi() % CUBE_EDGES
			var t: float = rng.randf_range(-1.0, 1.0)
			var radius: float = rng.randf_range(min_radius, max_radius)
			var offset: Vector3 = _edge_point(edge, t) * half_cell * EDGE_INSET
			_append_bead(positions, normals, indices, centre + offset, radius, flatten)
	return _array_mesh(positions, normals, PackedFloat32Array(), indices)


## Point on cube edge `edge` (0..11) at parameter t in [-1, 1], in units of the half-cell.
static func _edge_point(edge: int, t: float) -> Vector3:
	var axis: int = edge >> 2
	var corner: int = edge % CORNERS_PER_AXIS
	var u_axis: int = (axis + 1) % AXIS_COUNT
	var v_axis: int = (axis + 2) % AXIS_COUNT
	var point: Vector3 = Vector3.ZERO
	point[axis] = t
	point[u_axis] = 1.0 if corner & 1 != 0 else -1.0
	point[v_axis] = 1.0 if corner & 2 != 0 else -1.0
	return point


static func _seed_for(centre: Vector3) -> int:
	var scaled: Vector3i = Vector3i((centre * SEED_SCALE).round())
	return scaled.x * SEED_PRIME_A ^ scaled.y * SEED_PRIME_B ^ scaled.z * SEED_PRIME_C


static func _append_bead(positions: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array, centre: Vector3, radius: float, flatten: float) -> void:
	var base: int = positions.size()
	for ring: int in range(BEAD_RINGS + 1):
		var theta: float = PI * float(ring) / float(BEAD_RINGS)
		for seg: int in range(BEAD_SEGMENTS + 1):
			var phi: float = TAU * float(seg) / float(BEAD_SEGMENTS)
			var dir: Vector3 = Vector3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi))
			positions.append(centre + Vector3(dir.x, dir.y * flatten, dir.z) * radius)
			normals.append(dir)
	var row: int = BEAD_SEGMENTS + 1
	for ring: int in range(BEAD_RINGS):
		for seg: int in range(BEAD_SEGMENTS):
			var a: int = base + ring * row + seg
			var b: int = a + row
			indices.append_array(PackedInt32Array([a, b, a + 1, a + 1, b, b + 1]))


static func _array_mesh(positions: PackedVector3Array, normals: PackedVector3Array, custom: PackedFloat32Array, indices: PackedInt32Array) -> ArrayMesh:
	var mesh: ArrayMesh = ArrayMesh.new()
	if positions.is_empty():
		return mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var flags: int = 0
	if not custom.is_empty():
		arrays[Mesh.ARRAY_CUSTOM0] = custom
		flags = Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	return mesh
