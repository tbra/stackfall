class_name HoneyCoatTuning
extends Resource
## Look of the honey glaze (Bontago-1pi.85.64): placed glued blocks wear a thin
## glossy translucent amber skin with a few small drips; the held ghost with glue
## charges wears a faint stable amber tint (no drips) so its validity colour reads.
## Fed to shaders/honey_coat.gdshader by build_material() / build_ghost_material() /
## build_drip_material().

## Honey amber; alpha is the placed glaze's opacity (translucent: the block colour shows through).
@export var color: Color = Color(1.0, 0.6, 0.04, 0.12)
## Deep amber the glaze darkens toward at grazing angles.
@export var deep_amber: Color = Color(0.7, 0.32, 0.0)
## How far (m) the glaze swells off the block surface (avoids z-fighting).
@export_range(0.0, 0.1, 0.002) var thickness_m: float = 0.012
## Ghost preview: glaze opacity. Low, so the green/red validity tint stays readable.
@export_range(0.0, 1.0, 0.01) var ghost_alpha: float = 0.14
@export_range(0.0, 1.0, 0.01) var roughness: float = 0.05
## Fresnel exponent and glow of the grazing rim.
@export_range(0.5, 8.0, 0.1) var rim_power: float = 3.5
@export_range(0.0, 4.0, 0.05) var rim_strength: float = 2.0
## Gloss: clearcoat amount and roughness, wet highlight power and strength, colour.
@export_range(0.0, 1.0, 0.01) var clearcoat_amount: float = 1.0
@export_range(0.0, 1.0, 0.01) var clearcoat_roughness: float = 0.03
@export_range(1.0, 128.0, 1.0) var shine_power: float = 12.0
@export_range(0.0, 4.0, 0.05) var shine_strength: float = 1.6
@export var shine_color: Color = Color(1.0, 0.96, 0.75)
## Drips (placed blocks only): density per metre of bottom edge, hard cap, opacity,
## longest sag (m), lobe radius (m), sag cycle speed (cycles/s), shortest sag as a
## fraction of the longest, and teardrop narrowing at the tip (1 = no taper).
@export_range(0.5, 30.0, 0.1) var drip_scale: float = 3.0
@export_range(0, 64, 1) var max_drips: int = 10
@export_range(0.0, 1.0, 0.01) var drip_alpha: float = 0.85
@export_range(0.02, 1.5, 0.01) var drip_length_m: float = 0.16
@export_range(0.01, 0.3, 0.005) var drip_radius_m: float = 0.04
@export_range(0.0, 3.0, 0.01) var drip_speed: float = 0.2
@export_range(0.0, 1.0, 0.01) var sag_base: float = 0.5
@export_range(0.1, 1.0, 0.01) var tear_narrow: float = 0.55
## Drip animation off (static drips) when false; the graphics preset gates this.
@export var animate_drips: bool = true
## Draw order among transparent surfaces; above the ghost's own material so the glaze is not painted over.
@export_range(0, 127, 1) var render_priority: int = 10

const SHADER_PATH: String = "res://shaders/honey_coat.gdshader"
const DRIPS_NODE_NAME: String = "HoneyDrips"
const KEY_PRECISION: float = 1000.0
const SPHERE_SEGMENTS: int = 10
const SPHERE_RINGS: int = 6
const EDGE_COUNT_INDEX: int = 2
const DOWN_FACING_NORMAL_Y: float = -0.9


## One ShaderMaterial for the glaze on every placed mesh. animated=false (Low
## preset) freezes the drip sag by zeroing the speed.
func build_material(animated: bool = true) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load(SHADER_PATH) as Shader
	material.render_priority = render_priority
	material.set_shader_parameter(&"honey_color", color)
	material.set_shader_parameter(&"deep_amber", deep_amber)
	material.set_shader_parameter(&"thickness", thickness_m)
	material.set_shader_parameter(&"roughness_value", roughness)
	material.set_shader_parameter(&"rim_power", rim_power)
	material.set_shader_parameter(&"rim_strength", rim_strength)
	material.set_shader_parameter(&"clearcoat_amount", clearcoat_amount)
	material.set_shader_parameter(&"clearcoat_roughness", clearcoat_roughness)
	material.set_shader_parameter(&"shine_power", shine_power)
	material.set_shader_parameter(&"shine_strength", shine_strength)
	material.set_shader_parameter(&"shine_color", shine_color)
	material.set_shader_parameter(&"ghost_alpha", ghost_alpha)
	material.set_shader_parameter(&"drip_alpha", drip_alpha)
	material.set_shader_parameter(&"drip_length", drip_length_m)
	material.set_shader_parameter(&"drip_speed", drip_speed if (animated and animate_drips) else 0.0)
	material.set_shader_parameter(&"sag_base", sag_base)
	material.set_shader_parameter(&"tear_narrow", tear_narrow)
	material.set_shader_parameter(&"drip_mesh", false)
	material.set_shader_parameter(&"ghost_mode", false)
	return material


## The held ghost's preview glaze: same shader, faint and stable (no drips).
func build_ghost_material(animated: bool = true) -> ShaderMaterial:
	var material: ShaderMaterial = build_material(animated)
	material.set_shader_parameter(&"ghost_mode", true)
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
