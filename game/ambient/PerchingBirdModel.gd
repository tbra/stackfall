class_name PerchingBirdModel
extends RefCounted
## Bontago-adt.3: procedural low-poly model of the cosmetic perching bird. The
## body and head are lofted from rings so the silhouette has a real pointed
## beak, perky head, wings folded along the back and a wedge tail; each face
## gets its own vertices (flat shading + per-face vertex colour: slate back,
## cream belly, rust breast). CUSTOM0 carries a smoothed normal for the outline
## pass. Everything is in units of body length (scaled by the node scale); the
## model points along +X with +Y up.

const BODY_RINGS: Array[Vector3] = [
	Vector3(-0.52, 0.02, 0.02), Vector3(-0.36, 0.1, 0.09), Vector3(-0.1, 0.2, 0.19),
	Vector3(0.15, 0.23, 0.21), Vector3(0.32, 0.19, 0.17), Vector3(0.42, 0.11, 0.1),
]
const BODY_SIDES: int = 6
const HEAD_RINGS: Array[Vector3] = [
	Vector3(-0.08, 0.08, 0.08), Vector3(0.0, 0.13, 0.12), Vector3(0.09, 0.1, 0.09), Vector3(0.15, 0.04, 0.04),
]
const HEAD_SIDES: int = 6
const HEAD_OFFSET: Vector3 = Vector3(0.4, 0.2, 0.0)
const BEAK_LENGTH: float = 0.2
const BEAK_RADIUS: float = 0.05
const BEAK_OFFSET: Vector3 = Vector3(0.13, -0.01, 0.0)
const BEAK_SIDES: int = 4
const EYE_SIZE: float = 0.045
const EYE_OFFSET: Vector3 = Vector3(0.07, 0.04, 0.085)
const TAIL_OFFSET: Vector3 = Vector3(-0.44, 0.03, 0.0)
const TAIL_POLYGON: Array[Vector2] = [
	Vector2(0.0, -0.06), Vector2(-0.42, -0.14), Vector2(-0.48, 0.0), Vector2(-0.42, 0.14), Vector2(0.0, 0.06),
]
const TAIL_THICKNESS: float = 0.018
const TAIL_PITCH_RAD: float = -0.2
const WING_PIVOT: Vector3 = Vector3(0.1, 0.19, 0.12)
const WING_POLYGON: Array[Vector2] = [
	Vector2(0.14, 0.0), Vector2(0.1, 0.35), Vector2(-0.12, 0.72), Vector2(-0.3, 0.55), Vector2(-0.24, 0.3), Vector2(-0.22, 0.0),
]
const WING_THICKNESS: float = 0.014
const LEG_LENGTH: float = 0.2
const LEG_WIDTH: float = 0.035
const LEG_OFFSET: Vector3 = Vector3(0.04, -0.2, 0.09)
## Body-centre height above the surface the feet stand on.
const STAND_HEIGHT: float = 0.4
const FOLD_YAW_RAD: float = 1.5708
const FOLD_PITCH_RAD: float = 0.3
const FOLDED_CHORD_SCALE: float = 0.55
const FOLDED_SPAN_SCALE: float = 0.62
const BELLY_NORMAL_Y: float = -0.35
const BREAST_MIN_X: float = 0.1
const BREAST_MAX_NORMAL_Y: float = 0.3
const WELD_SCALE: float = 10000.0


## Builds the bird under `root` at body length `length`. Returns
## {"head","tail","left","right","legs"} nodes for the animation code.
static func build(root: Node3D, length: float, body_color: Color, life: AmbientLifeConfig, material: Material) -> Dictionary:
	var belly: Color = life.perch_belly_color
	var breast: Color = life.perch_breast_color
	var wing_color: Color = life.perch_wing_color
	var beak_color: Color = life.perch_beak_color
	var eye_color: Color = life.perch_outline_color
	var nodes: Dictionary = {}
	_add_mesh(root, _loft(BODY_RINGS, BODY_SIDES, true, true,
		func(centre: Vector3, normal: Vector3) -> Color: return _body_color(centre, normal, body_color, belly, breast)),
		Vector3.ZERO, length, material)
	var head: Node3D = Node3D.new()
	head.name = "Head"
	head.position = HEAD_OFFSET * length
	root.add_child(head)
	nodes["head"] = head
	_add_mesh(head, _loft(HEAD_RINGS, HEAD_SIDES, true, true,
		func(_centre: Vector3, normal: Vector3) -> Color: return belly if normal.y < BELLY_NORMAL_Y else body_color),
		Vector3.ZERO, length, material)
	var beak_rings: Array[Vector3] = [Vector3(0.0, BEAK_RADIUS, BEAK_RADIUS), Vector3(BEAK_LENGTH, 0.0, 0.0)]
	_add_mesh(head, _loft(beak_rings, BEAK_SIDES, false, false,
		func(_centre: Vector3, _normal: Vector3) -> Color: return beak_color),
		BEAK_OFFSET * length, length, material)
	for side: float in [-1.0, 1.0]:
		_add_mesh(head, _prism(_square(EYE_SIZE), EYE_SIZE, eye_color),
			Vector3(EYE_OFFSET.x, EYE_OFFSET.y, EYE_OFFSET.z * side) * length, length, material)
	var tail: Node3D = Node3D.new()
	tail.name = "Tail"
	tail.position = TAIL_OFFSET * length
	root.add_child(tail)
	nodes["tail"] = tail
	_add_mesh(tail, _prism(TAIL_POLYGON, TAIL_THICKNESS, wing_color), Vector3.ZERO, length, material)
	tail.rotation.z = TAIL_PITCH_RAD
	nodes["left"] = _make_wing(root, 1.0, length, wing_color, material)
	nodes["right"] = _make_wing(root, -1.0, length, wing_color, material)
	var legs: Node3D = Node3D.new()
	legs.name = "Legs"
	root.add_child(legs)
	nodes["legs"] = legs
	for side: float in [-1.0, 1.0]:
		_add_mesh(legs, _prism(_square(LEG_WIDTH), LEG_LENGTH, beak_color),
			Vector3(LEG_OFFSET.x, LEG_OFFSET.y - LEG_LENGTH * 0.5, LEG_OFFSET.z * side) * length, length, material)
	return nodes


## `up_angle` lifts the wing tips (rad), `span_scale` lengthens/shortens the
## wing, `fold` (0..1) sweeps it back along the flank into the resting pose.
static func pose_wings(left: Node3D, right: Node3D, up_angle: float, span_scale: float, fold: float) -> void:
	for side: float in [1.0, -1.0]:
		var wing: Node3D = left if side > 0.0 else right
		var chord: float = lerpf(1.0, FOLDED_CHORD_SCALE, fold)
		var span: float = lerpf(span_scale, FOLDED_SPAN_SCALE, fold)
		var rotation_basis: Basis = (
			Basis(Vector3.BACK, fold * FOLD_PITCH_RAD)
			* Basis(Vector3.UP, -side * fold * FOLD_YAW_RAD)
			* Basis(Vector3.RIGHT, -side * up_angle)
		)
		wing.basis = rotation_basis * Basis.from_scale(Vector3(chord, 1.0, span))


static func _make_wing(root: Node3D, side: float, length: float, colour: Color, material: Material) -> Node3D:
	var pivot: Node3D = Node3D.new()
	pivot.name = "WingLeft" if side > 0.0 else "WingRight"
	pivot.position = Vector3(WING_PIVOT.x, WING_PIVOT.y, WING_PIVOT.z * side) * length
	root.add_child(pivot)
	var polygon: Array[Vector2] = []
	for point: Vector2 in WING_POLYGON:
		polygon.append(Vector2(point.x, point.y * side))
	_add_mesh(pivot, _prism(polygon, WING_THICKNESS, colour), Vector3.ZERO, length, material)
	return pivot


static func _square(size: float) -> Array[Vector2]:
	var half: float = size * 0.5
	return [Vector2(-half, -half), Vector2(-half, half), Vector2(half, half), Vector2(half, -half)]


static func _body_color(centre: Vector3, normal: Vector3, back: Color, belly: Color, breast: Color) -> Color:
	if normal.y < BELLY_NORMAL_Y:
		return belly
	if centre.x > BREAST_MIN_X and normal.y < BREAST_MAX_NORMAL_Y:
		return breast
	return back


## Lofts a faceted solid along +X through `rings` (x, radius_y, radius_z) with
## `sides` faces round and optional end caps (only where the end radius is > 0).
static func _loft(rings: Array[Vector3], sides: int, cap_start: bool, cap_end: bool, face_color: Callable) -> ArrayMesh:
	var polygons: Array[PackedVector3Array] = []
	var loops: Array[PackedVector3Array] = []
	for ring: Vector3 in rings:
		var loop: PackedVector3Array = PackedVector3Array()
		for i: int in range(sides):
			var angle: float = TAU * float(i) / float(sides)
			loop.append(Vector3(ring.x, ring.y * sin(angle), ring.z * cos(angle)))
		loops.append(loop)
	for r: int in range(rings.size() - 1):
		for i: int in range(sides):
			var j: int = (i + 1) % sides
			polygons.append(PackedVector3Array([loops[r][i], loops[r + 1][i], loops[r + 1][j], loops[r][j]]))
	if cap_start and rings[0].y > 0.0:
		var start_cap: PackedVector3Array = loops[0].duplicate()
		start_cap.reverse()
		polygons.append(start_cap)
	if cap_end and rings[rings.size() - 1].y > 0.0:
		polygons.append(loops[rings.size() - 1])
	return _mesh_from_polygons(polygons, face_color)


## Extrudes a convex XZ `outline` by +-thickness/2 in Y.
static func _prism(outline: Array[Vector2], thickness: float, colour: Color) -> ArrayMesh:
	var half: float = thickness * 0.5
	var area: float = 0.0
	for i: int in range(outline.size()):
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % outline.size()]
		area += a.x * b.y - b.x * a.y
	var points: Array[Vector2] = outline.duplicate()
	if area > 0.0:
		points.reverse()
	var top: PackedVector3Array = PackedVector3Array()
	var bottom: PackedVector3Array = PackedVector3Array()
	for point: Vector2 in points:
		top.append(Vector3(point.x, half, point.y))
		bottom.append(Vector3(point.x, -half, point.y))
	var polygons: Array[PackedVector3Array] = [top]
	var reversed_bottom: PackedVector3Array = bottom.duplicate()
	reversed_bottom.reverse()
	polygons.append(reversed_bottom)
	for i: int in range(points.size()):
		var j: int = (i + 1) % points.size()
		polygons.append(PackedVector3Array([top[j], top[i], bottom[i], bottom[j]]))
	return _mesh_from_polygons(polygons, func(_centre: Vector3, _normal: Vector3) -> Color: return colour)


static func _weld_key(point: Vector3) -> Vector3i:
	return Vector3i(roundi(point.x * WELD_SCALE), roundi(point.y * WELD_SCALE), roundi(point.z * WELD_SCALE))


static func _mesh_from_polygons(polygons: Array[PackedVector3Array], face_color: Callable) -> ArrayMesh:
	var accum: Dictionary = {}
	var faces: Array[Dictionary] = []
	var solid_centre: Vector3 = Vector3.ZERO
	var vertex_total: int = 0
	for listed: PackedVector3Array in polygons:
		for point: Vector3 in listed:
			solid_centre += point
			vertex_total += 1
	solid_centre /= float(maxi(vertex_total, 1))
	for source: PackedVector3Array in polygons:
		if source.size() < 3:
			continue
		var polygon: PackedVector3Array = source
		var cross: Vector3 = (polygon[1] - polygon[0]).cross(polygon[2] - polygon[0])
		if cross.length() < 0.000001 and polygon.size() > 3:
			cross = (polygon[2] - polygon[1]).cross(polygon[3] - polygon[1])
		var normal: Vector3 = cross.normalized() if cross.length() > 0.000001 else Vector3.UP
		var centre: Vector3 = Vector3.ZERO
		for point: Vector3 in polygon:
			centre += point
		centre /= float(polygon.size())
		# Outward normal for a convex-ish solid. Godot front faces are wound
		# clockwise seen from outside, i.e. the cross product points inward.
		if normal.dot(centre - solid_centre) < 0.0:
			normal = -normal
		else:
			polygon = polygon.duplicate()
			polygon.reverse()
		for point: Vector3 in polygon:
			var key: Vector3i = _weld_key(point)
			accum[key] = (accum.get(key, Vector3.ZERO) as Vector3) + normal
		faces.append({"polygon": polygon, "normal": normal, "centre": centre})
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_custom_format(0, SurfaceTool.CUSTOM_RGB_FLOAT)
	for face: Dictionary in faces:
		var polygon: PackedVector3Array = face["polygon"] as PackedVector3Array
		var normal: Vector3 = face["normal"] as Vector3
		var colour: Color = face_color.call(face["centre"] as Vector3, normal) as Color
		for i: int in range(1, polygon.size() - 1):
			for point: Vector3 in [polygon[0], polygon[i], polygon[i + 1]]:
				var smooth: Vector3 = (accum[_weld_key(point)] as Vector3).normalized()
				surface.set_color(colour)
				surface.set_normal(normal)
				surface.set_custom(0, Color(smooth.x, smooth.y, smooth.z))
				surface.add_vertex(point)
	return surface.commit()


static func _add_mesh(parent: Node3D, mesh: Mesh, at: Vector3, size: float, material: Material) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	instance.scale = Vector3.ONE * size
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance
