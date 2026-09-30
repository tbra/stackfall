class_name CloudSea
extends Node3D
## Bontago-adt.1: the near/mid-field cloud sea below the floating disc --
## real 3D stylized cumulus. One MultiMeshInstance3D draws flat-bottomed
## low-poly spheres ("puffs") clustered into cumulus clumps scattered on a
## ring around and below the disc; shaders/cloud_puffs.gdshader toon-shades
## them from theme colours, drifts every clump slowly around the disc and
## billows the surfaces, all from TIME and per-instance custom data -- no
## per-frame script, so it animates in the game, the editor and the baked
## demo. Distant clumps fade into the sky panorama's own lower hemisphere
## (the far cloud sea), sampled along the view ray, so there is no seam.
##
## Placement is deterministic (SkyThemeDef.cloud_seed). Every puff top stays
## at or below SkyThemeDef.cloud_top_max_m, far under the disc's underside
## and the 0..72 m play volume. game/Skybox.gd owns one of these and calls
## configure() on theme and graphics-preset changes.

## Render layer bit the puffs live on (layer 19). game/DiscMirror.gd's
## MIRROR_CULL_MASK (also the disc ReflectionProbe's mask) excludes it: the
## planar-mirror camera sits below the disc plane, among the puffs, and
## anything below a mirror must never appear in its reflection.
const RENDER_LAYER_BIT: int = 1 << 18
## Sky-material uniforms the puff shader shares so its far fade matches the
## sky drawn behind it exactly.
const SHARED_SKY_PARAMETERS: Array[StringName] = [
	&"panorama", &"exposure", &"seam_blend_width", &"grade_amount", &"grade_dark", &"grade_mid",
	&"grade_light", &"grade_gamma",
]
const YAW_PARAMETER: StringName = &"sky_yaw_offset_deg"
const PITCH_PARAMETER: StringName = &"sky_pitch_offset_deg"
const FLAT_BASE_PARAMETER: StringName = &"flat_base"
## Icosphere subdivision of the puff mesh (2 = 320 triangles). The mesh is
## only a hull: the shader carves the round, lumpy silhouette per pixel
## (its hull_margin covers this tessellation's chord error).
const PUFF_SUBDIVISIONS: int = 2
## Puff layout inside a clump, as fractions of the clump radius / height:
## centre and rim puff radius, dome fall-off of the tops toward the rim,
## horizontal spread, and the share/size/placement of the small
## "cauliflower" puffs sitting on the bigger ones.
const CORE_RADIUS_FRACTION: float = 0.58
const RIM_RADIUS_FRACTION: float = 0.3
const DOME_FALLOFF: float = 0.7
const SPREAD_FRACTION: float = 0.9
const DETAIL_SHARE: float = 0.4
const DETAIL_RADIUS_MIN_FRACTION: float = 0.3
const DETAIL_RADIUS_MAX_FRACTION: float = 0.5
const DETAIL_SURFACE_OFFSET: float = 0.8
const DETAIL_MIN_UP: float = 0.25
const SIZE_JITTER: float = 0.15
const TOP_JITTER_MIN: float = 0.82
const STRETCH_MAX: float = 1.2

## One placement layer: the sea below the disc, or the cloud banks past its
## edge. Both draw through the same MultiMesh.
class _Layer:
	extends RefCounted
	var clumps: int = 0
	var ring_inner_m: float = 0.0
	var ring_outer_m: float = 0.0
	var radial_bias: float = 1.0
	var base_min_m: float = 0.0
	var base_max_m: float = 0.0
	var top_max_m: float = 0.0
	var radius_min_m: float = 1.0
	var radius_max_m: float = 1.0


var _instance: MultiMeshInstance3D = null
var _material: ShaderMaterial = null
## Highest puff top written by the last configure() (tracked here because a
## headless RenderingServer does not keep MultiMesh instance data).
var _highest_top: float = -INF


## Weather fog changed (vfx/weather/WeatherFogShader.gd).
func refresh_weather_fog() -> void:
	WeatherFogShader.apply(_material)


## Rebuilds the puffs from `theme`. `density` (GraphicsPreset.cloud_puff_density,
## 0..1) scales the theme's clump count; 0 hides the cloud sea. `sky_material`
## is the active sky material whose panorama/grade uniforms the puffs copy.
func configure(theme: SkyThemeDef, density: float, sky_material: Material = null) -> void:
	if _instance != null:
		_instance.queue_free()
		_instance = null
	_material = null
	_highest_top = -INF
	var layers: Array[_Layer] = _layers_for(theme, density)
	var clumps: int = 0
	for layer: _Layer in layers:
		clumps += layer.clumps
	if theme == null or theme.cloud_puff_material == null or clumps <= 0 or theme.cloud_puffs_per_clump <= 0:
		visible = false
		return
	_material = theme.cloud_puff_material.duplicate() as ShaderMaterial
	if _material == null:
		visible = false
		return
	visible = true
	add_to_group(WeatherFogShader.GROUP)
	WeatherFogShader.apply(_material)
	_material.set_shader_parameter(YAW_PARAMETER, theme.sky_yaw_offset_deg)
	_material.set_shader_parameter(PITCH_PARAMETER, theme.sky_pitch_offset_deg)
	_material.set_shader_parameter(FLAT_BASE_PARAMETER, theme.cloud_flat_base)
	# Transparent-pass draw (see the shader's DECISION): first among
	# transparents, so ghosts, particles and birds blend over the clouds.
	_material.render_priority = RenderingServer.MATERIAL_RENDER_PRIORITY_MIN
	var sky: ShaderMaterial = sky_material as ShaderMaterial
	if sky != null:
		for parameter: StringName in SHARED_SKY_PARAMETERS:
			var value: Variant = sky.get_shader_parameter(parameter)
			if value != null:
				_material.set_shader_parameter(parameter, value)

	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = build_puff_mesh(theme.cloud_flat_base)
	multimesh.instance_count = clumps * theme.cloud_puffs_per_clump
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = theme.cloud_seed
	var index: int = 0
	for layer: _Layer in layers:
		for _clump: int in range(layer.clumps):
			index = _add_clump(multimesh, index, theme, layer, rng)
	_instance = MultiMeshInstance3D.new()
	_instance.name = "Puffs"
	_instance.multimesh = multimesh
	_instance.material_override = _material
	_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_instance.layers = RENDER_LAYER_BIT
	# The shader orbits puffs around the disc axis, so the culling box must
	# cover the whole ring at every angle.
	var extent: float = 0.0
	var low: float = INF
	var high: float = -INF
	for layer: _Layer in layers:
		if layer.clumps <= 0:
			continue
		extent = maxf(extent, layer.ring_outer_m + layer.radius_max_m * 2.0)
		low = minf(low, layer.base_min_m - layer.radius_max_m)
		high = maxf(high, layer.top_max_m)
	_instance.custom_aabb = AABB(Vector3(-extent, low, -extent), Vector3(extent * 2.0, high - low, extent * 2.0))
	add_child(_instance)


## The sea layer and (when the theme has any) the cloud-bank layer, with the
## density preset applied to both clump counts.
static func _layers_for(theme: SkyThemeDef, density: float) -> Array[_Layer]:
	var layers: Array[_Layer] = []
	if theme == null:
		return layers
	var scale: float = clampf(density, 0.0, 1.0)
	var sea: _Layer = _Layer.new()
	sea.clumps = int(round(float(theme.cloud_clump_count) * scale))
	sea.ring_inner_m = theme.cloud_ring_inner_m
	sea.ring_outer_m = theme.cloud_ring_outer_m
	sea.radial_bias = theme.cloud_radial_bias
	sea.base_min_m = theme.cloud_base_min_m
	sea.base_max_m = theme.cloud_base_max_m
	sea.top_max_m = theme.cloud_top_max_m
	sea.radius_min_m = theme.cloud_clump_radius_min_m
	sea.radius_max_m = theme.cloud_clump_radius_max_m
	layers.append(sea)
	var banks: _Layer = _Layer.new()
	banks.clumps = int(round(float(theme.cloud_bank_count) * scale))
	banks.ring_inner_m = theme.cloud_bank_ring_inner_m
	banks.ring_outer_m = theme.cloud_bank_ring_outer_m
	banks.radial_bias = 1.0
	banks.base_min_m = theme.cloud_bank_base_min_m
	banks.base_max_m = theme.cloud_bank_base_max_m
	banks.top_max_m = theme.cloud_bank_top_max_m
	banks.radius_min_m = theme.cloud_bank_radius_min_m
	banks.radius_max_m = theme.cloud_bank_radius_max_m
	layers.append(banks)
	return layers


## Writes one clump's puffs from `index`; returns the next free index.
func _add_clump(multimesh: MultiMesh, index: int, theme: SkyThemeDef, layer: _Layer, rng: RandomNumberGenerator) -> int:
	var azimuth: float = rng.randf() * TAU
	# Uniform over the ring's area, not its radius.
	# A radial bias above 1 crowds clumps toward the inner (near) edge.
	var inner_sq: float = layer.ring_inner_m * layer.ring_inner_m
	var outer_sq: float = layer.ring_outer_m * layer.ring_outer_m
	var ring_radius: float = sqrt(lerpf(inner_sq, outer_sq, pow(rng.randf(), maxf(layer.radial_bias, 0.01))))
	var centre: Vector3 = Vector3(cos(azimuth) * ring_radius, 0.0, sin(azimuth) * ring_radius)
	var clump_radius: float = rng.randf_range(layer.radius_min_m, layer.radius_max_m)
	var clump_height: float = clump_radius * theme.cloud_clump_height_ratio * rng.randf_range(1.0 - SIZE_JITTER, 1.0 + SIZE_JITTER)
	var base_y: float = rng.randf_range(layer.base_min_m, layer.base_max_m)
	base_y = minf(base_y, layer.top_max_m - clump_height)
	var speed: float = rng.randf_range(theme.cloud_drift_speed_min_mps, theme.cloud_drift_speed_max_mps)
	var angular_speed: float = speed / maxf(ring_radius, 1.0)
	var flat: float = theme.cloud_flat_base
	var total: int = theme.cloud_puffs_per_clump
	var detail_count: int = int(float(total) * DETAIL_SHARE) if total > 2 else 0
	var body_count: int = total - detail_count
	var body_centres: Array[Vector3] = []
	var body_radii: Array[float] = []
	for puff: int in range(body_count):
		var spread: float = 0.0 if puff == 0 else sqrt(rng.randf()) * SPREAD_FRACTION
		var angle: float = rng.randf() * TAU
		var offset: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * spread * clump_radius
		var radius: float = clump_radius * lerpf(CORE_RADIUS_FRACTION, RIM_RADIUS_FRACTION, spread)
		radius *= rng.randf_range(1.0 - SIZE_JITTER, 1.0 + SIZE_JITTER)
		var top: float = base_y + clump_height * (1.0 - DOME_FALLOFF * spread * spread) * rng.randf_range(TOP_JITTER_MIN, 1.0)
		var y: float = maxf(top - radius, base_y + radius * flat)
		var at: Vector3 = centre + offset + Vector3(0.0, y, 0.0)
		index = _write_puff(multimesh, index, at, radius, layer, rng, angular_speed, base_y, clump_height)
		body_centres.append(at)
		body_radii.append(radius)
	for _detail: int in range(detail_count):
		var host: int = rng.randi_range(0, body_centres.size() - 1)
		var up: float = rng.randf_range(DETAIL_MIN_UP, 1.0)
		var around: float = rng.randf() * TAU
		var side: float = sqrt(maxf(1.0 - up * up, 0.0))
		var direction: Vector3 = Vector3(cos(around) * side, up, sin(around) * side)
		var radius: float = body_radii[host] * rng.randf_range(DETAIL_RADIUS_MIN_FRACTION, DETAIL_RADIUS_MAX_FRACTION)
		var at: Vector3 = body_centres[host] + direction * body_radii[host] * DETAIL_SURFACE_OFFSET
		index = _write_puff(multimesh, index, at, radius, layer, rng, angular_speed, base_y, clump_height)
	return index


func _write_puff(multimesh: MultiMesh, index: int, at: Vector3, radius: float, layer: _Layer,
		rng: RandomNumberGenerator, angular_speed: float, base_y: float, clump_height: float) -> int:
	# Never let a puff top rise above the ceiling under the disc.
	at.y = minf(at.y, layer.top_max_m - radius)
	_highest_top = maxf(_highest_top, at.y + radius)
	var stretch: float = rng.randf_range(1.0, STRETCH_MAX)
	var basis: Basis = Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(radius * stretch, radius, radius * stretch))
	multimesh.set_instance_transform(index, Transform3D(basis, at))
	multimesh.set_instance_custom_data(index, Color(angular_speed, rng.randf() * TAU, base_y, clump_height))
	return index + 1


## Highest world Y any puff reaches (before billow), for tests and checks.
func highest_puff_top() -> float:
	return _highest_top


func puff_count() -> int:
	return _instance.multimesh.instance_count if _instance != null else 0


func puff_instance() -> MultiMeshInstance3D:
	return _instance


func puff_material() -> ShaderMaterial:
	return _material


## Unit icosphere whose part below y = -`flat_base` is squashed onto that
## plane (a cumulus's flat base). Smooth radial normals; base vertices face
## straight down.
static func build_puff_mesh(flat_base: float) -> ArrayMesh:
	var golden: float = (1.0 + sqrt(5.0)) * 0.5
	var vertices: Array[Vector3] = [
		Vector3(-1, golden, 0), Vector3(1, golden, 0), Vector3(-1, -golden, 0), Vector3(1, -golden, 0),
		Vector3(0, -1, golden), Vector3(0, 1, golden), Vector3(0, -1, -golden), Vector3(0, 1, -golden),
		Vector3(golden, 0, -1), Vector3(golden, 0, 1), Vector3(-golden, 0, -1), Vector3(-golden, 0, 1),
	]
	for i: int in range(vertices.size()):
		vertices[i] = vertices[i].normalized()
	var faces: PackedInt32Array = PackedInt32Array([
		0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11,
		1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9,
		4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1,
	])
	for _level: int in range(PUFF_SUBDIVISIONS):
		var midpoints: Dictionary[Vector2i, int] = {}
		var next: PackedInt32Array = PackedInt32Array()
		for f: int in range(0, faces.size(), 3):
			var a: int = faces[f]
			var b: int = faces[f + 1]
			var c: int = faces[f + 2]
			var ab: int = _midpoint(vertices, midpoints, a, b)
			var bc: int = _midpoint(vertices, midpoints, b, c)
			var ca: int = _midpoint(vertices, midpoints, c, a)
			next.append_array(PackedInt32Array([a, ab, ca, b, bc, ab, c, ca, bc, ab, bc, ca]))
		faces = next
	var positions: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	for v: Vector3 in vertices:
		if v.y < -flat_base:
			positions.append(Vector3(v.x, -flat_base, v.z))
			normals.append(Vector3.DOWN)
		else:
			positions.append(v)
			normals.append(v)
	# Godot treats clockwise triangles as front faces; the table above is
	# counter-clockwise seen from outside, so swap two corners of each.
	for f: int in range(0, faces.size(), 3):
		var swap: int = faces[f + 1]
		faces[f + 1] = faces[f + 2]
		faces[f + 2] = swap
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = faces
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Index of the normalized midpoint of edge a-b, appended once per edge.
static func _midpoint(vertices: Array[Vector3], cache: Dictionary[Vector2i, int], a: int, b: int) -> int:
	var key: Vector2i = Vector2i(mini(a, b), maxi(a, b))
	if cache.has(key):
		return cache[key]
	vertices.append(((vertices[a] + vertices[b]) * 0.5).normalized())
	var index: int = vertices.size() - 1
	cache[key] = index
	return index
