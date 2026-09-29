class_name CloudSea
extends Node3D
## Bontago-adt.1: the stylized cloud sea below the floating disc. A few flat
## radial-disc meshes stacked at different heights, each drawn with
## shaders/cloud_sea.gdshader (cel-banded, TIME-scrolled and domain-warped
## clouds that fade out toward the horizon). No per-frame script: all motion
## is in the shader, so it also animates in the editor and the baked demo.
## game/Skybox.gd owns one of these and calls configure() on theme/preset
## changes.

## Upper bound used when no graphics preset is available.
const MAX_LAYERS: int = 8
const DISC_RINGS: int = 6
const DISC_SEGMENTS: int = 48
## Layer 0 is the top layer; deeper layers use layer_index 1, 2, ...
const LAYER_INDEX_PARAMETER: StringName = &"layer_index"
const LAYER_COUNT_PARAMETER: StringName = &"layer_count"

var _layers: Array[MeshInstance3D] = []


## Rebuilds the layers from `theme`. `layer_limit` caps how many of the
## theme's layers are drawn (GraphicsPreset.cloud_sea_layers); 0 hides all.
func configure(theme: SkyThemeDef, layer_limit: int) -> void:
	for layer: MeshInstance3D in _layers:
		layer.queue_free()
	_layers.clear()
	var heights: PackedFloat32Array = theme.cloud_sea_layer_heights_m if theme != null else PackedFloat32Array()
	var count: int = mini(heights.size(), layer_limit)
	if theme == null or theme.cloud_sea_material == null or count <= 0:
		visible = false
		return
	visible = true
	var mesh: ArrayMesh = build_disc_mesh(theme.cloud_sea_radius_m)
	for index: int in range(count):
		var material: ShaderMaterial = theme.cloud_sea_material.duplicate() as ShaderMaterial
		material.set_shader_parameter(LAYER_INDEX_PARAMETER, float(index))
		material.set_shader_parameter(LAYER_COUNT_PARAMETER, float(count))
		# Draw the deepest layer first so alpha blending composites top over bottom.
		material.render_priority = -index
		var instance: MeshInstance3D = MeshInstance3D.new()
		instance.name = "Layer%d" % index
		instance.mesh = mesh
		instance.material_override = material
		instance.position = Vector3(0.0, heights[index], 0.0)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
		_layers.append(instance)


func layer_count() -> int:
	return _layers.size()


## Flat disc in the XZ plane facing up, radius `radius_m`.
static func build_disc_mesh(radius_m: float) -> ArrayMesh:
	var vertices: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	vertices.append(Vector3.ZERO)
	for ring: int in range(1, DISC_RINGS + 1):
		var ring_radius: float = radius_m * float(ring) / float(DISC_RINGS)
		for segment: int in range(DISC_SEGMENTS):
			var angle: float = TAU * float(segment) / float(DISC_SEGMENTS)
			vertices.append(Vector3(cos(angle) * ring_radius, 0.0, sin(angle) * ring_radius))
	for segment: int in range(DISC_SEGMENTS):
		var next: int = (segment + 1) % DISC_SEGMENTS
		indices.append_array(PackedInt32Array([0, 1 + next, 1 + segment]))
	for ring: int in range(1, DISC_RINGS):
		var inner: int = 1 + (ring - 1) * DISC_SEGMENTS
		var outer: int = 1 + ring * DISC_SEGMENTS
		for segment: int in range(DISC_SEGMENTS):
			var next: int = (segment + 1) % DISC_SEGMENTS
			indices.append_array(PackedInt32Array([
				inner + segment, inner + next, outer + segment,
				inner + next, outer + next, outer + segment,
			]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
