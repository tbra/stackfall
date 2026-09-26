class_name HomeFlag
extends Node3D
## A player's home flag (spec 2.2): "Each player's home flag sits at
## 0.85 * field_radius, spaced evenly around the edge."
##
## Visual only. The home *circle* the flag anchors is an InfluenceCircle built
## by the match from the same MapDef.home_flag_position(), and whether the
## flag is still standing is PlayerSlot.home_flag_alive -- no rule lives here.
##
## M7 P8 (Bontago-xtq.33, docs/M7_ART_DIRECTION.md Q6): the flag is now a
## procedural "beacon" -- a low neutral socket, a luminous ring in the
## owner's color, and a faceted crystal on top -- replacing the earlier
## pole-and-banner placeholder (M2, no art yet). All three pieces are built
## from primitives/an ArrayMesh here, no imported assets, no shader (P2 owns
## toon shading; materials stay plain StandardMaterial3D). Sizes, colors and
## emission strengths live in BeaconVisualTuning
## (config/beacon_visual_tuning.tres). Only the socket ever stays a fixed
## size across every flag; the ring and crystal scale with banner_scale(), so
## GoalFlag's beacon reads as the same shape at a larger scale (see its own
## class doc) exactly like the old pole/banner did.

@export var visuals: TerritoryVisuals = preload("res://config/territory_visuals.tres")
@export var beacon_visuals: BeaconVisualTuning = preload("res://config/beacon_visual_tuning.tres")

var _slot_id: int = -1
var _color: Color = Color.WHITE
var _socket: MeshInstance3D = null
var _beacon_ring: MeshInstance3D = null
var _beacon_ring_material: StandardMaterial3D = null
var _crystal: MeshInstance3D = null
var _crystal_material: StandardMaterial3D = null


func _ready() -> void:
	_build()
	_apply_color()


func _build() -> void:
	var scale_factor: float = banner_scale()

	_socket = MeshInstance3D.new()
	_socket.name = &"Socket"
	var socket_mesh: CylinderMesh = CylinderMesh.new()
	socket_mesh.top_radius = beacon_visuals.socket_radius
	socket_mesh.bottom_radius = beacon_visuals.socket_radius
	socket_mesh.height = beacon_visuals.socket_height
	_socket.mesh = socket_mesh
	var socket_material: StandardMaterial3D = StandardMaterial3D.new()
	socket_material.albedo_color = beacon_visuals.socket_color
	_socket.material_override = socket_material
	_socket.position = Vector3(0.0, beacon_visuals.socket_height * 0.5, 0.0)
	add_child(_socket)

	var ring_outer: float = beacon_visuals.ring_outer_radius * scale_factor
	var ring_inner: float = maxf(
		ring_outer - beacon_visuals.ring_thickness * scale_factor, 0.001
	)
	_beacon_ring = MeshInstance3D.new()
	_beacon_ring.name = &"Ring"
	_beacon_ring.mesh = _build_beacon_ring_mesh(ring_outer, ring_inner)
	_beacon_ring_material = StandardMaterial3D.new()
	_beacon_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beacon_ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beacon_ring_material.emission_enabled = true
	_beacon_ring.material_override = _beacon_ring_material
	_beacon_ring.position = Vector3(
		0.0, beacon_visuals.socket_height + beacon_visuals.ring_lift, 0.0
	)
	add_child(_beacon_ring)

	var crystal_radius: float = beacon_visuals.crystal_radius * scale_factor
	var crystal_height: float = beacon_visuals.crystal_height * scale_factor
	_crystal = MeshInstance3D.new()
	_crystal.name = &"Crystal"
	_crystal.mesh = _build_crystal_mesh(
		beacon_visuals.crystal_facets, crystal_radius, crystal_height * 0.5
	)
	_crystal_material = StandardMaterial3D.new()
	_crystal_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_crystal_material.emission_enabled = true
	_crystal.material_override = _crystal_material
	_crystal.position = Vector3(
		0.0, beacon_visuals.socket_height + crystal_height * 0.5, 0.0
	)
	add_child(_crystal)


## How much bigger than BeaconVisualTuning's base ring/crystal sizes this
## flag's beacon is; the socket stays a constant base for every flag.
## GoalFlag overrides it.
func banner_scale() -> float:
	return 1.0


## Which slot this flag belongs to, and the color it flies. The color comes
## from MatchConfig.player_colors by way of Field.place_flags().
func set_slot(slot_id: int, color: Color) -> void:
	_slot_id = slot_id
	_color = color
	_apply_color()


func slot_id() -> int:
	return _slot_id


func color() -> Color:
	return _color


func _apply_color() -> void:
	if _beacon_ring_material == null or _crystal_material == null:
		return
	_beacon_ring_material.albedo_color = _color
	_beacon_ring_material.emission = _color
	_beacon_ring_material.emission_energy_multiplier = beacon_visuals.ring_emission
	_crystal_material.albedo_color = _color
	_crystal_material.emission = _color
	_crystal_material.emission_energy_multiplier = beacon_visuals.crystal_emission


## A full annulus lying flat at y=0 in local space (see GoalFlag._build_arc()
## for the same idea swept over less than a full turn, for the capture ring).
func _build_beacon_ring_mesh(outer: float, inner: float) -> ArrayMesh:
	var segments: int = maxi(beacon_visuals.ring_segments, 3)
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	for i: int in range(segments):
		var a0: float = TAU * float(i) / float(segments)
		var a1: float = TAU * float(i + 1) / float(segments)
		var d0: Vector3 = Vector3(sin(a0), 0.0, cos(a0))
		var d1: Vector3 = Vector3(sin(a1), 0.0, cos(a1))
		var o0: Vector3 = d0 * outer
		var o1: Vector3 = d1 * outer
		var i0: Vector3 = d0 * inner
		var i1: Vector3 = d1 * inner
		vertices.append_array([i0, o0, o1, i0, o1, i1])
	for _v: int in range(vertices.size()):
		normals.append(Vector3.UP)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh_out: ArrayMesh = ArrayMesh.new()
	mesh_out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh_out


## A faceted bipyramid (two low-poly cones base to base) centered on the
## origin, apex at +/-half_height -- reads as a cut gem rather than a smooth
## cone. Each triangle gets its own three vertices and its own flat normal
## (_add_facet()), so the facets stay sharp with plain StandardMaterial3D (no
## shader here; P2 owns toon shading).
func _build_crystal_mesh(facets: int, radius: float, half_height: float) -> ArrayMesh:
	var sides: int = maxi(facets, 3)
	var waist: PackedVector3Array = PackedVector3Array()
	for i: int in range(sides):
		var angle: float = TAU * float(i) / float(sides)
		waist.append(Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))
	var top: Vector3 = Vector3(0.0, half_height, 0.0)
	var bottom: Vector3 = Vector3(0.0, -half_height, 0.0)

	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	for i: int in range(sides):
		var a: Vector3 = waist[i]
		var b: Vector3 = waist[(i + 1) % sides]
		_add_facet(vertices, normals, top, a, b)
		_add_facet(vertices, normals, bottom, b, a)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh_out: ArrayMesh = ArrayMesh.new()
	mesh_out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh_out


## Appends one flat-shaded triangle (apex, a, b) with its own three vertices
## and the true geometric face normal, flipped outward (away from the
## bipyramid's own center) so it renders correctly however the winding falls.
func _add_facet(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	apex: Vector3,
	a: Vector3,
	b: Vector3
) -> void:
	var normal: Vector3 = (b - a).cross(apex - a).normalized()
	if normal.dot(apex + a + b) < 0.0:
		normal = -normal
	vertices.append_array([apex, a, b])
	normals.append_array([normal, normal, normal])
