class_name HoneyCoatTuning
extends Resource
## Look of the honey coat drawn over glue-charged ghosts (Bontago-1pi.85.51).
## Fed to shaders/honey_coat.gdshader by build_material() / build_drip_material();
## a later package can reuse the same resource and shader unchanged on placed
## glued blocks (material_overlay + attach_drips).

## Honey gold; alpha is the coat's base opacity (near opaque so it hides the colour below).
@export var color: Color = Color(0.98, 0.7, 0.06, 0.93)
## How far (m) the coat swells outward from the block surface (also avoids z-fighting).
@export_range(0.0, 0.3, 0.005) var thickness_m: float = 0.03
## Drip lobes per metre of bottom edge (also the lump frequency of the coat).
@export_range(0.5, 30.0, 0.1) var drip_scale: float = 6.0
## Sag cycle speed, cycles per second (slow, viscous).
@export_range(0.0, 3.0, 0.01) var drip_speed: float = 0.35
## How much the coat pools and the drip lengths vary (0..1).
@export_range(0.0, 1.0, 0.01) var drip_depth: float = 0.25
@export_range(0.0, 1.0, 0.01) var roughness: float = 0.05
## Fresnel exponent of the thick darkened rim (higher = thinner rim).
@export_range(0.5, 8.0, 0.1) var rim_power: float = 2.5
## Rim glow multiplier.
@export_range(0.0, 4.0, 0.05) var rim_strength: float = 1.2
## Longest a hanging drip sags below the block's bottom edge (m).
@export_range(0.05, 1.5, 0.01) var drip_length_m: float = 0.45
## Radius (m) of a hanging drip lobe.
@export_range(0.01, 0.3, 0.005) var drip_radius_m: float = 0.08
## Hard cap on drip lobes per mesh.
@export_range(0, 64, 1) var max_drips: int = 24
## Surface lumpiness: how much the coat swells where it pools (0..1) and how
## strongly the lumps tilt the normal so highlights roll across flat faces.
@export_range(0.0, 2.0, 0.01) var lump_swell: float = 0.6
@export_range(0.0, 1.5, 0.01) var lump_tilt: float = 0.45
## Deep amber the coat darkens toward at pools and rims.
@export var deep_amber: Color = Color(0.62, 0.28, 0.0)
## How much the grazing rim darkens toward deep_amber (thick-coat look).
@export_range(0.0, 1.0, 0.01) var rim_darken: float = 0.55
## Gloss: clearcoat amount and roughness, wet highlight power and strength, colour.
@export_range(0.0, 1.0, 0.01) var clearcoat_amount: float = 1.0
@export_range(0.0, 1.0, 0.01) var clearcoat_roughness: float = 0.03
@export_range(1.0, 128.0, 1.0) var shine_power: float = 28.0
@export_range(0.0, 4.0, 0.05) var shine_strength: float = 1.6
@export var shine_color: Color = Color(1.0, 0.96, 0.75)
## Self-glow and albedo darkening (higher body_darken = brighter body).
@export_range(0.0, 1.0, 0.01) var base_glow: float = 0.04
@export_range(0.1, 1.0, 0.01) var body_darken: float = 0.7
## Drips: shortest sag as a fraction of the longest, teardrop narrowing at the tip
## (1 = no taper) and how much lengths differ per drip.
@export_range(0.0, 1.0, 0.01) var sag_base: float = 0.35
@export_range(0.1, 1.0, 0.01) var tear_narrow: float = 0.55
@export_range(0.0, 4.0, 0.05) var reach_variation: float = 2.0
## Drip animation off (static drips) when false; the graphics preset gates this.
@export var animate_drips: bool = true
## Draw order among transparent surfaces; above the ghost's own material so the coat is not painted over.
@export_range(0, 127, 1) var render_priority: int = 10

const SHADER_PATH: String = "res://shaders/honey_coat.gdshader"
const DRIPS_NODE_NAME: String = "HoneyDrips"
const KEY_PRECISION: float = 1000.0
const SPHERE_SEGMENTS: int = 12
const SPHERE_RINGS: int = 8
const EDGE_COUNT_INDEX: int = 2
const DOWN_FACING_NORMAL_Y: float = -0.9


## One ShaderMaterial for the coat on every mesh. animated=false (Low preset)
## freezes the sag by zeroing the speed.
func build_material(animated: bool = true) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load(SHADER_PATH) as Shader
	material.render_priority = render_priority
	material.set_shader_parameter(&"honey_color", color)
	material.set_shader_parameter(&"thickness", thickness_m)
	material.set_shader_parameter(&"drip_scale", drip_scale)
	material.set_shader_parameter(&"drip_speed", drip_speed if (animated and animate_drips) else 0.0)
	material.set_shader_parameter(&"drip_depth", drip_depth)
	material.set_shader_parameter(&"roughness_value", roughness)
	material.set_shader_parameter(&"rim_power", rim_power)
	material.set_shader_parameter(&"rim_strength", rim_strength)
	material.set_shader_parameter(&"drip_length", drip_length_m)
	for name: StringName in [&"lump_swell", &"lump_tilt", &"rim_darken", &"clearcoat_amount", &"clearcoat_roughness", &"shine_power", &"shine_strength", &"base_glow", &"body_darken", &"sag_base", &"tear_narrow", &"reach_variation"]:
		material.set_shader_parameter(name, get(name))
	material.set_shader_parameter(&"deep_amber", deep_amber)
	material.set_shader_parameter(&"shine_color", shine_color)
	material.set_shader_parameter(&"drip_mesh", false)
	return material


## Same look as build_material() but for the hanging lobes (drip_mesh = true).
func build_drip_material(animated: bool = true) -> ShaderMaterial:
	var material: ShaderMaterial = build_material(animated)
	material.set_shader_parameter(&"drip_mesh", true)
	return material


## Anchors (mesh space) spaced 1/drip_scale apart along the boundary edges of
## downward-facing triangles, capped at max_drips.
func drip_anchors(mesh: Mesh) -> PackedVector3Array:
	var edges: Dictionary = {}
	for surface: int in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var indices: PackedInt32Array = PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			indices = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
		if indices.is_empty():
			indices = PackedInt32Array(range(verts.size()))
		for tri: int in range(0, indices.size() - 2, 3):
			var a: Vector3 = verts[indices[tri]]
			var b: Vector3 = verts[indices[tri + 1]]
			var c: Vector3 = verts[indices[tri + 2]]
			# Front faces wind clockwise, so (c - a) x (b - a) is the outward normal.
			var normal: Vector3 = (c - a).cross(b - a).normalized()
			if normal.y > DOWN_FACING_NORMAL_Y:
				continue
			for pair: Array in [[a, b], [b, c], [c, a]]:
				var from: Vector3 = pair[0] as Vector3
				var to: Vector3 = pair[1] as Vector3
				var key: String = _edge_key(from, to)
				if edges.has(key):
					var seen: Array = edges[key] as Array
					seen[EDGE_COUNT_INDEX] = int(seen[EDGE_COUNT_INDEX]) + 1
				else:
					edges[key] = [from, to, 1]
	var anchors: PackedVector3Array = PackedVector3Array()
	var keys: Array = edges.keys()
	keys.sort()
	for key: String in keys:
		var edge: Array = edges[key] as Array
		if int(edge[EDGE_COUNT_INDEX]) > 1:
			continue
		var start: Vector3 = edge[0] as Vector3
		var end: Vector3 = edge[1] as Vector3
		var count: int = maxi(int(round(start.distance_to(end) * drip_scale)), 1)
		for i: int in range(count):
			anchors.append(start.lerp(end, (float(i) + 0.5) / float(count)))
	if anchors.size() > max_drips:
		anchors.resize(max_drips)
	return anchors


func _edge_key(a: Vector3, b: Vector3) -> String:
	var ka: String = _point_key(a)
	var kb: String = _point_key(b)
	return ka + "|" + kb if ka < kb else kb + "|" + ka


func _point_key(p: Vector3) -> String:
	return "%d,%d,%d" % [round(p.x * KEY_PRECISION), round(p.y * KEY_PRECISION), round(p.z * KEY_PRECISION)]


## Adds (replacing any old set) a HoneyDrips node of hanging lobes under the
## downward-facing boundary edges of mesh_instance's mesh. Returns the lobe count.
func attach_drips(mesh_instance: MeshInstance3D, material: ShaderMaterial) -> int:
	HoneyCoatTuning.remove_drips(mesh_instance)
	if mesh_instance.mesh == null:
		return 0
	var holder: Node3D = Node3D.new()
	holder.name = DRIPS_NODE_NAME
	var lobe: SphereMesh = SphereMesh.new()
	lobe.radius = drip_radius_m
	lobe.height = drip_radius_m * 2.0
	lobe.radial_segments = SPHERE_SEGMENTS
	lobe.rings = SPHERE_RINGS
	var anchors: PackedVector3Array = drip_anchors(mesh_instance.mesh)
	for anchor: Vector3 in anchors:
		var drip: MeshInstance3D = MeshInstance3D.new()
		drip.mesh = lobe
		drip.material_override = material
		drip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		drip.position = anchor
		holder.add_child(drip)
	mesh_instance.add_child(holder)
	return anchors.size()


static func remove_drips(mesh_instance: MeshInstance3D) -> void:
	var old: Node = mesh_instance.get_node_or_null(DRIPS_NODE_NAME)
	if old != null:
		mesh_instance.remove_child(old)
		old.queue_free()
