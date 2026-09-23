class_name BlockMeshBuilder
extends RefCounted
## Pure geometry (spec 3.2 "core/ has no scene-tree dependence"): turns a
## BlockShape's integer cell offsets into a single ArrayMesh with every
## interior face removed, so a multi-cube shape reads as one solid piece
## instead of a visible seam grid (Bontago-xtq.3, owner feel report "our
## blocks are made up of many smaller blocks, is that necessary? the original
## just has solid shapes"). ArrayMesh is a rendering Resource, not a scene
## node, so building/caching it here has no scene-tree dependency; only the
## MeshInstance3D that displays it (game/BlockFactory.gd) lives in game/.

## The 6 axis-aligned directions a cell can neighbour another cell along.
const _FACE_DIRECTIONS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

## Per-face tangent basis (u, v) with u x v == the face's own outward normal.
## _append_face() below appends corners in the order
## (center - u - v, +u - v, +u + v, -u + v) but indexes its 2 triangles as
## (0, 2, 1) and (0, 3, 2) -- clockwise as seen from outside the cube, which
## is Godot's actual front-face convention (verified empirically against
## BoxMesh's own winding by tests/unit/test_block_mesh_builder.gd,
## Bontago-xtq.5: a prior version of this comment claimed counter-clockwise
## was the convention and the triangle indices were wound accordingly, which
## put every face backwards -- every placed/ghost block rendered inside-out,
## only hidden on the ghost by its culling-off material) -- for all 6
## directions.
const _FACE_TANGENTS: Dictionary = {
	Vector3i(1, 0, 0): [Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, 1.0)],
	Vector3i(-1, 0, 0): [Vector3(0.0, 0.0, 1.0), Vector3(0.0, 1.0, 0.0)],
	Vector3i(0, 1, 0): [Vector3(0.0, 0.0, 1.0), Vector3(1.0, 0.0, 0.0)],
	Vector3i(0, -1, 0): [Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0)],
	Vector3i(0, 0, 1): [Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0)],
	Vector3i(0, 0, -1): [Vector3(0.0, 1.0, 0.0), Vector3(1.0, 0.0, 0.0)],
}

## DECISION (core/blocks/BlockMeshBuilder.gd): never cleared, same reasoning
## as game/BlockFactory.gd's `_materials_by_color` cache -- keyed by the
## shape's own resource path plus the (cube_size, cube_margin) pair that
## produced it, so at most one entry per shipped BlockShape .tres per
## PhysicsTuning variant ever exists for the life of the process (a dozen
## shapes times a handful of tunings across the game and its tests). This is
## what lets 300 falling blocks in tests/bench/bench_rain.gd share meshes
## instead of allocating one ArrayMesh per block.
static var _mesh_cache: Dictionary = {}


## Builds one ArrayMesh for `shape`: for every cell, only the faces whose
## neighbour cell (one of the 6 axis directions away) is *not* also part of
## the shape are emitted, so two adjacent cells fuse into a seamless interior
## instead of drawing (and z-fighting on) two coincident faces. Each face
## spans the full nominal `cube_size` per cell -- not shrunk by `cube_margin`
## like the collision boxes built separately in game/BlockFactory.gd -- so
## neighbouring cells' visuals touch with no gap. DECISION (Bontago-xtq.3):
## the visual is intentionally a hair larger than the collision hull (which
## keeps its `cube_margin` shrink so blocks don't jam on landing) -- this
## already was true per-cell before this change (the old per-cell visual
## mesh matched the collision box exactly, so cube_margin showed as a visible
## gap between placed blocks; now the whole shape reads as solid and only the
## invisible collision hull keeps the placement gap).
##
## Returns null if `shape.sloped_cells` is non-empty or `shape.mesh` is set:
## no shipped shape does either today (Bontago-mv0.17 removed the only
## sloped shape, config/blocks/wedge.tres; no .tres sets `mesh`), and this
## builder has no wedge-face case and isn't meant to duplicate a custom mesh
## across every cell -- game/BlockFactory.gd falls back to its own
## pre-existing per-cell path for such a shape instead (DECISION, see its
## call site).
static func build_mesh(shape: BlockShape, cube_size: float, cube_margin: float) -> ArrayMesh:
	if not shape.sloped_cells.is_empty() or shape.mesh != null:
		return null

	var cache_key: String = "%s|%.6f|%.6f" % [shape.resource_path, cube_size, cube_margin]
	if _mesh_cache.has(cache_key):
		return _mesh_cache[cache_key]

	var mesh: ArrayMesh = _build_mesh_uncached(shape, cube_size)
	_mesh_cache[cache_key] = mesh
	return mesh


static func _build_mesh_uncached(shape: BlockShape, cube_size: float) -> ArrayMesh:
	var cell_set: Dictionary = {}
	for cell: Vector3i in shape.cells:
		cell_set[cell] = true

	var half: float = cube_size * 0.5
	var pivot: Vector3 = shape.bottom_center()

	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()

	for cell: Vector3i in shape.cells:
		var center: Vector3 = (Vector3(cell) - pivot) * cube_size
		for direction: Vector3i in _FACE_DIRECTIONS:
			if cell_set.has(cell + direction):
				continue
			_append_face(center, direction, half, vertices, normals, uvs, indices)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var array_mesh: ArrayMesh = ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return array_mesh


## Appends one quad (4 vertices, 2 triangles) for the face of the cell
## centred at `center` that faces `direction`, mutating the packed arrays in
## place (Godot's PackedArrays are passed by reference).
static func _append_face(
	center: Vector3, direction: Vector3i, half: float,
	vertices: PackedVector3Array, normals: PackedVector3Array,
	uvs: PackedVector2Array, indices: PackedInt32Array
) -> void:
	var normal: Vector3 = Vector3(direction)
	var tangents: Array = _FACE_TANGENTS[direction]
	var u: Vector3 = tangents[0]
	var v: Vector3 = tangents[1]
	var face_center: Vector3 = center + normal * half

	var corners: Array[Vector3] = [
		face_center - u * half - v * half,
		face_center + u * half - v * half,
		face_center + u * half + v * half,
		face_center - u * half + v * half,
	]
	var uv_corners: Array[Vector2] = [
		Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0),
	]

	var base_index: int = vertices.size()
	for i: int in range(4):
		vertices.append(corners[i])
		normals.append(normal)
		uvs.append(uv_corners[i])

	# DECISION (Bontago-xtq.5): (0, 2, 1) / (0, 3, 2), not (0, 1, 2) / (0, 2, 3)
	# -- see the _FACE_TANGENTS doc comment above for why this order (not the
	# corners or normals) is the fix.
	indices.append(base_index)
	indices.append(base_index + 2)
	indices.append(base_index + 1)
	indices.append(base_index)
	indices.append(base_index + 3)
	indices.append(base_index + 2)


## For tests: clears the cache so a test can assert on cache identity (same
## shape/tuning -> same ArrayMesh instance) without interference from another
## test's earlier call.
static func clear_cache() -> void:
	_mesh_cache.clear()
