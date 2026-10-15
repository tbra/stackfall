class_name HoneyBlobMeshes
## Generated (never hand-modelled) jelly mesh: a subdivided cube shell per block cell.
## Cells are given as block-local centres (the CollisionShape3D offsets).
## CUSTOM0 on the shell mesh = (cell centre xyz, bitmask of occupied neighbour cells).

const CELL_SIZE_M: float = 1.0
const FACE_COUNT: int = 6
const AXIS_COUNT: int = 3
const CELL_MATCH_EPS_SQ: float = 0.01


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
