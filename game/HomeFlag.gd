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
##
## Bontago-mp0.3.1 (Graphics pass 2, owner feedback: "Same for the beacons"
## [as the blocks' cel-shading detail], "pulsating glow from the beacons"):
## the crystal now draws with shaders/beacon_crystal.gdshader (toon banding +
## a hard specular facet highlight, matching the block shader's technique)
## instead of a plain StandardMaterial3D; the ring stays unshaded (it is
## meant to read as constantly luminous, not lit). Both the ring's scale and
## the ring/crystal emission energy are animated every frame by
## _apply_pulse(), driven by BeaconVisualTuning's pulse_* tunables -- no
## per-flag phase offset, so every beacon on the disk pulses in lockstep.

const CRYSTAL_SHADER: Shader = preload("res://shaders/beacon_crystal.gdshader")

@export var visuals: TerritoryVisuals = preload("res://config/territory_visuals.tres")
@export var beacon_visuals: BeaconVisualTuning = preload("res://config/beacon_visual_tuning.tres")

var _slot_id: int = -1
var _color: Color = Color.WHITE
var _socket: MeshInstance3D = null
var _beacon_ring: MeshInstance3D = null
var _beacon_ring_material: StandardMaterial3D = null
var _crystal: MeshInstance3D = null
var _crystal_material: ShaderMaterial = null
var _pulse_time_s: float = 0.0


func _ready() -> void:
	_build()
	_apply_color()
	_apply_pulse(0.0)


## Advances the shared pulse phase and pushes it onto the ring's own scale and
## the ring/crystal emission energy every frame (owner feedback: "pulsating
## glow from the beacons").
func _process(delta: float) -> void:
	_apply_pulse(delta)


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
	socket_material.metallic = beacon_visuals.socket_metallic
	socket_material.roughness = beacon_visuals.socket_roughness
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
	_crystal_material = ShaderMaterial.new()
	_crystal_material.shader = CRYSTAL_SHADER
	_crystal_material.set_shader_parameter(&"toon_band_count", beacon_visuals.crystal_toon_band_count)
	_crystal_material.set_shader_parameter(&"shadow_floor", beacon_visuals.crystal_shadow_floor)
	_crystal_material.set_shader_parameter(&"shadow_tint", beacon_visuals.crystal_shadow_tint)
	_crystal_material.set_shader_parameter(&"highlight_boost", beacon_visuals.crystal_highlight_boost)
	_crystal_material.set_shader_parameter(&"specular_strength", beacon_visuals.crystal_specular_strength)
	_crystal_material.set_shader_parameter(&"specular_sharpness", beacon_visuals.crystal_specular_sharpness)
	_crystal_material.set_shader_parameter(&"specular_softness", beacon_visuals.crystal_specular_softness)
	_crystal_material.set_shader_parameter(&"emission_scale", beacon_visuals.emission_scale)
	_crystal_material.set_shader_parameter(&"core_glow", beacon_visuals.crystal_core_glow)
	_crystal_material.set_shader_parameter(&"edge_glow", beacon_visuals.crystal_edge_glow)
	_crystal_material.set_shader_parameter(&"edge_white_mix", beacon_visuals.crystal_edge_white_mix)
	_crystal_material.set_shader_parameter(&"edge_power", beacon_visuals.crystal_edge_power)
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


## Static collision approximating the beacon model (Bontago-6fc.4, owner:
## "proper collision to the home beacons"): the socket cylinder plus the
## crystal's convex hull (the same bipyramid the mesh draws), sized from
## BeaconVisualTuning only. The ring is a flat decoration and adds none.
## Shapes and their transforms are in this flag's local space; Field adds them
## to its own AnimatableBody3D so they tilt with the disc exactly (a child
## CollisionShape3D cannot, this node is not a physics body).
func collision_shapes() -> Array[Shape3D]:
	var socket: CylinderShape3D = CylinderShape3D.new()
	socket.radius = beacon_visuals.socket_radius
	socket.height = beacon_visuals.socket_height
	var radius: float = beacon_visuals.crystal_radius * banner_scale()
	var half_height: float = beacon_visuals.crystal_height * banner_scale() * 0.5
	var points: PackedVector3Array = PackedVector3Array()
	points.append(Vector3(0.0, half_height, 0.0))
	points.append(Vector3(0.0, -half_height, 0.0))
	for i: int in range(maxi(beacon_visuals.crystal_facets, 3)):
		var angle: float = TAU * float(i) / float(maxi(beacon_visuals.crystal_facets, 3))
		points.append(Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))
	var crystal: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
	crystal.points = points
	var shapes: Array[Shape3D] = []
	shapes.append(socket)
	shapes.append(crystal)
	return shapes


## Local transforms matching collision_shapes(), same order.
func collision_transforms() -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []
	transforms.append(Transform3D(Basis.IDENTITY, Vector3(0.0, beacon_visuals.socket_height * 0.5, 0.0)))
	transforms.append(Transform3D(
		Basis.IDENTITY,
		Vector3(0.0, beacon_visuals.socket_height + beacon_visuals.crystal_height * banner_scale() * 0.5, 0.0)
	))
	return transforms


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
	_crystal_material.set_shader_parameter(&"albedo_color", _color)
	_crystal_material.set_shader_parameter(&"emission_color", _color)
	# emission_energy_multiplier/emission_energy are owned by _apply_pulse()
	# below (owner feedback: "pulsating glow from the beacons") -- it always
	# recomputes the full energy from BeaconVisualTuning's base value each
	# frame, so setting it here would just be overwritten on the next
	# _process() tick.


## Bontago-mp0.3.1 (owner feedback: "pulsating glow from the beacons"): a
## single sine wave, shared by the ring's own uniform XZ scale and the
## ring/crystal emission energy, so the whole beacon breathes together rather
## than the ring and crystal pulsing independently. `delta` is unused when
## called from _ready() with 0.0 (pre-first-frame initialization, so the
## beacon never pops from "unpulsed" to "pulsed" on the first real _process()
## tick) -- kept as a parameter anyway so both call sites share one method.
func _apply_pulse(_delta: float) -> void:
	if _beacon_ring_material == null or _crystal_material == null:
		return
	_pulse_time_s += _delta
	var wave: float = 0.0
	if beacon_visuals.pulse_period_s > 0.0:
		wave = sin(TAU * _pulse_time_s / beacon_visuals.pulse_period_s)

	var ring_scale: float = 1.0 + wave * beacon_visuals.pulse_scale_amplitude + _extra_ring_scale()
	_beacon_ring.scale = Vector3(ring_scale, 1.0, ring_scale)

	var energy_mult: float = 1.0 + wave * beacon_visuals.pulse_emission_amplitude
	_beacon_ring_material.emission_energy_multiplier = (
		beacon_visuals.ring_emission * beacon_visuals.emission_scale * energy_mult * _emission_boost()
	)
	_crystal_material.set_shader_parameter(
		&"emission_energy", beacon_visuals.crystal_emission * energy_mult * _emission_boost()
	)


## Extra emission multiplier applied on top of the pulse (GoalFlag raises it
## when claimed/contested). 1.0 for a plain home beacon.
func _emission_boost() -> float:
	return 1.0


## Extra ring scale fraction applied on top of the pulse (GoalFlag's claim flash).
func _extra_ring_scale() -> float:
	return 0.0


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
