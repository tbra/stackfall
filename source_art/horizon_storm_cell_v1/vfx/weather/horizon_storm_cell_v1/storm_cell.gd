extends Node3D
## Standalone distant storm cell. This scene owns its geometry and animation so
## a sky integration can place it without depending on Skybox or CloudSea internals.

const RAIN_SHADER: Shader = preload("res://vfx/weather/horizon_storm_cell_v1/rain.gdshader")

@export var seed_value: int = 24019
@export_enum("Broad anvil", "Centered five towers", "Offset five towers") var silhouette_style: int = 2
@export_range(0.0, 8.0, 0.1) var first_flash_delay_s: float = 1.2
@export_range(1.0, 12.0, 0.5) var flash_interval_min_s: float = 2.5
@export_range(1.0, 20.0, 0.5) var flash_interval_max_s: float = 6.0

const PROFILE_X_SEGMENTS: int = 56
const SECTION_SEGMENTS: int = 24
const CLOUD_HALF_WIDTH_M: float = 28.0
const RAIN_STREAK_COUNT: int = 160
const RAIN_CURTAIN_HEIGHT_M: float = 30.0
const RAIN_FALL_SPEED_MS: float = 4.2

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _bolt: MeshInstance3D
var _bolt_material: StandardMaterial3D
var _flash_light: OmniLight3D
var _flash_cooldown: float = 0.0
var _flash_phase: int = 0
var _phase_elapsed_s: float = 0.0


func _ready() -> void:
	_rng.seed = seed_value
	_build_cloud()
	_build_rain()
	_build_lightning()
	_flash_cooldown = first_flash_delay_s


func _process(delta: float) -> void:
	if _flash_phase == 0:
		_flash_cooldown -= delta
		if _flash_cooldown <= 0.0:
			_start_flash()
		return
	_phase_elapsed_s += delta
	match _flash_phase:
		1:
			if _phase_elapsed_s >= 0.055:
				_set_flash_energy(0.0)
				_next_flash_phase(2)
		2:
			if _phase_elapsed_s >= 0.070:
				_set_flash_energy(2.8)
				_next_flash_phase(3)
		3:
			if _phase_elapsed_s >= 0.050:
				_set_flash_energy(0.0)
				_next_flash_phase(4)
		4:
			if _phase_elapsed_s >= 0.22:
				_bolt.visible = false
				_flash_phase = 0
				_flash_cooldown = _rng.randf_range(flash_interval_min_s, flash_interval_max_s)


func _build_cloud() -> void:
	var cloud: MeshInstance3D = MeshInstance3D.new()
	cloud.name = "CloudMass"
	cloud.mesh = _make_cloud_cell_mesh()
	cloud.material_override = _make_cloud_material()
	cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cloud)


func set_silhouette_style(style_index: int) -> void:
	silhouette_style = clampi(style_index, 0, 2)
	var previous: Node = get_node_or_null("CloudMass")
	if previous != null:
		previous.free()
	_build_cloud()


func _make_cloud_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return material


func _make_cloud_cell_mesh() -> ArrayMesh:
	var vertices: Array[Vector3] = []
	var normals: Array[Vector3] = []
	var colors: Array[Color] = []
	var peaks: Array[Dictionary] = []
	match silhouette_style:
		0:
			peaks.append_array([
				{"center": -15.0, "height": 3.8, "half_width": 8.5},
				{"center": -6.5, "height": 8.0, "half_width": 9.5},
				{"center": 4.5, "height": 12.0, "half_width": 9.5},
				{"center": 15.0, "height": 5.0, "half_width": 8.5},
			])
		1:
			peaks.append_array([
				{"center": -22.0, "height": 4.5, "half_width": 7.8},
				{"center": -11.0, "height": 9.0, "half_width": 8.2},
				{"center": 0.0, "height": 13.0, "half_width": 8.8},
				{"center": 11.0, "height": 9.0, "half_width": 8.2},
				{"center": 22.0, "height": 4.5, "half_width": 7.8},
			])
		_:
			peaks.append_array([
				{"center": -22.0, "height": 3.5, "half_width": 6.0},
				{"center": -12.0, "height": 10.5, "half_width": 8.5},
				{"center": -1.0, "height": 10.5, "half_width": 11.5},
				{"center": 10.0, "height": 14.0, "half_width": 7.7},
				{"center": 20.0, "height": 4.8, "half_width": 7.0},
			])
	var profiles: Array[Dictionary] = []
	for x_index: int in range(PROFILE_X_SEGMENTS + 1):
		var x: float = lerpf(-CLOUD_HALF_WIDTH_M, CLOUD_HALF_WIDTH_M, float(x_index) / float(PROFILE_X_SEGMENTS))
		profiles.append(_cloud_profile(x, peaks))
	for x_index: int in range(PROFILE_X_SEGMENTS):
		var left: Dictionary = profiles[x_index]
		var right: Dictionary = profiles[x_index + 1]
		for section: int in range(SECTION_SEGMENTS):
			var angle_a: float = TAU * float(section) / float(SECTION_SEGMENTS)
			var angle_b: float = TAU * float(section + 1) / float(SECTION_SEGMENTS)
			var angle_mid: float = (angle_a + angle_b) * 0.5
			var a: Vector3 = _cloud_surface_point(left, angle_a)
			var b: Vector3 = _cloud_surface_point(right, angle_a)
			var c: Vector3 = _cloud_surface_point(left, angle_b)
			var d: Vector3 = _cloud_surface_point(right, angle_b)
			var outward: Vector3 = Vector3(0.0, sin(angle_mid), cos(angle_mid))
			var normal_a: Vector3 = Vector3(0.0, sin(angle_a), cos(angle_a)).normalized()
			var normal_b: Vector3 = normal_a
			var normal_c: Vector3 = Vector3(0.0, sin(angle_b), cos(angle_b)).normalized()
			var normal_d: Vector3 = normal_c
			_append_cloud_face(vertices, normals, colors, a, b, c, normal_a, normal_b, normal_c, outward)
			_append_cloud_face(vertices, normals, colors, c, b, d, normal_c, normal_b, normal_d, outward)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(vertices)
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(normals)
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray(colors)
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _cloud_profile(x: float, peaks: Array[Dictionary]) -> Dictionary:
	var normalized_x: float = x / CLOUD_HALF_WIDTH_M
	var support_exponent: float = 2.0 if silhouette_style < 2 else 4.0
	var support_power: float = 0.5 if silhouette_style < 2 else 0.34
	var support: float = pow(maxf(1.0 - pow(absf(normalized_x), support_exponent), 0.0), support_power)
	var roughness: float = 0.0 if silhouette_style == 0 else (0.58 if silhouette_style == 1 else 1.0)
	var broad_wobble: float = sin(x * 0.57 + 1.1) * 0.42 * roughness
	var small_wobble: float = (sin(x * 1.13 - 0.4) * 0.22 + sin(x * 2.6 + 2.5) * 0.09) * roughness
	var bottom: float = (-4.5 + broad_wobble + small_wobble) * support
	var base_top: float = (0.9 + broad_wobble * 0.65 + small_wobble) * support
	var top: float = base_top
	var peak_smoothing_width: float = 1.35
	for peak: Dictionary in peaks:
		var distance: float = absf(x - float(peak["center"])) / float(peak["half_width"])
		if distance >= 1.0:
			continue
		var dome: float = sqrt(maxf(1.0 - distance * distance, 0.0))
		var candidate: float = base_top + float(peak["height"]) * dome * support
		top = _smooth_max(top, candidate, peak_smoothing_width * support + 0.01)
	var depth_base: float = 7.5 if silhouette_style == 0 else (8.8 if silhouette_style == 1 else 9.2)
	var depth_swell: float = 0.17 if silhouette_style == 0 else (0.21 if silhouette_style == 1 else 0.24)
	var depth: float = depth_base * support + maxf(top - base_top, 0.0) * depth_swell + absf(small_wobble) * support
	return {"x": x, "bottom": bottom, "top": top, "depth": depth}


func _smooth_max(a: float, b: float, width: float) -> float:
	var blend: float = clampf(0.5 + 0.5 * (b - a) / maxf(width, 0.001), 0.0, 1.0)
	return lerpf(a, b, blend) + width * blend * (1.0 - blend)


func _cloud_surface_point(profile: Dictionary, angle: float) -> Vector3:
	var bottom: float = float(profile["bottom"])
	var top: float = float(profile["top"])
	var center_y: float = (bottom + top) * 0.5
	var half_height: float = (top - bottom) * 0.5
	return Vector3(float(profile["x"]), center_y + half_height * sin(angle), float(profile["depth"]) * cos(angle))


func _cloud_color(height: float, outward: Vector3) -> Color:
	var height_share: float = clampf((height + 5.2) / 19.0, 0.0, 1.0)
	var color: Color = Color("35445a").lerp(Color("65768e"), pow(height_share, 0.82))
	if outward.y < -0.45:
		color = color.darkened(0.12)
	return color


func _append_cloud_face(vertices: Array[Vector3], normals: Array[Vector3], colors: Array[Color], a: Vector3, b_in: Vector3, c_in: Vector3, normal_a_in: Vector3, normal_b_in: Vector3, normal_c_in: Vector3, outward: Vector3) -> void:
	var b: Vector3 = b_in
	var c: Vector3 = c_in
	var normal_a: Vector3 = normal_a_in
	var normal_b: Vector3 = normal_b_in
	var normal_c: Vector3 = normal_c_in
	var face_normal: Vector3 = (b - a).cross(c - a)
	if face_normal.length_squared() < 0.000001:
		return
	if face_normal.dot(outward) < 0.0:
		var swap: Vector3 = b
		b = c
		c = swap
		swap = normal_b
		normal_b = normal_c
		normal_c = swap
	vertices.append(a)
	vertices.append(b)
	vertices.append(c)
	normals.append(normal_a)
	normals.append(normal_b)
	normals.append(normal_c)
	colors.append(_cloud_color(a.y, normal_a))
	colors.append(_cloud_color(b.y, normal_b))
	colors.append(_cloud_color(c.y, normal_c))


func _build_rain() -> void:
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = Vector2(0.11, 1.55)
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = RAIN_STREAK_COUNT
	for index: int in range(RAIN_STREAK_COUNT):
		var position: Vector3 = Vector3(
			_rng.randf_range(-17.0, 17.0),
			0.0,
			_rng.randf_range(-6.2, 6.2)
		)
		var tilt: float = deg_to_rad(_rng.randf_range(-9.0, 9.0))
		var scale_y: float = _rng.randf_range(0.7, 1.45)
		var basis: Basis = Basis(Vector3.BACK, tilt).scaled(Vector3(1.0, scale_y, 1.0))
		multimesh.set_instance_transform(index, Transform3D(basis, position))
		multimesh.set_instance_custom_data(index, Color(_rng.randf(), 0.0, 0.0, 1.0))
	var rain: MultiMeshInstance3D = MultiMeshInstance3D.new()
	rain.name = "RainCurtain"
	rain.multimesh = multimesh
	rain.position.y = -20.7
	rain.material_override = _make_rain_material()
	rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rain)


func _make_rain_material() -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = RAIN_SHADER
	material.set_shader_parameter("curtain_height", RAIN_CURTAIN_HEIGHT_M)
	material.set_shader_parameter("fall_speed", RAIN_FALL_SPEED_MS)
	material.set_shader_parameter("tint", Color(0.66, 0.79, 0.98, 0.45))
	return material


func _build_lightning() -> void:
	var main_path: PackedVector3Array = PackedVector3Array([
		Vector3(-1.5, -3.2, 7.6), Vector3(-0.3, -5.1, 7.7),
		Vector3(-1.0, -6.4, 7.8), Vector3(0.5, -8.0, 7.8),
		Vector3(-0.2, -9.2, 7.9), Vector3(1.0, -11.1, 7.9),
		Vector3(0.4, -12.2, 8.0), Vector3(1.8, -14.4, 8.0),
	])
	var branch_path: PackedVector3Array = PackedVector3Array([
		Vector3(-0.7, -7.0, 7.8), Vector3(-3.0, -8.3, 7.9),
		Vector3(-2.4, -9.4, 8.0), Vector3(-4.2, -10.8, 8.0),
	])
	_bolt_material = StandardMaterial3D.new()
	_bolt_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bolt_material.albedo_color = Color(0.55, 0.84, 1.0)
	_bolt_material.emission_enabled = true
	_bolt_material.emission = Color(0.24, 0.63, 1.0)
	_bolt_material.emission_energy_multiplier = 4.0
	_bolt_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var bolt_mesh: ArrayMesh = _make_lightning_mesh(main_path, branch_path)
	_bolt = MeshInstance3D.new()
	_bolt.name = "Lightning"
	_bolt.mesh = bolt_mesh
	_bolt.material_override = _bolt_material
	_bolt.visible = false
	_bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bolt)
	_flash_light = OmniLight3D.new()
	_flash_light.name = "FlashLight"
	_flash_light.light_color = Color(0.48, 0.72, 1.0)
	_flash_light.light_energy = 0.0
	_flash_light.omni_range = 58.0
	_flash_light.shadow_enabled = false
	_flash_light.position = Vector3(0.0, -7.0, 0.0)
	add_child(_flash_light)


func _make_lightning_mesh(main_path: PackedVector3Array, branch_path: PackedVector3Array) -> ArrayMesh:
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_ribbon(tool, main_path, 0.52, 0.12)
	_append_ribbon(tool, branch_path, 0.25, 0.06)
	return tool.commit()


func _append_ribbon(tool: SurfaceTool, points: PackedVector3Array, width_start: float, width_end: float) -> void:
	for index: int in range(points.size() - 1):
		var start: Vector3 = points[index]
		var end: Vector3 = points[index + 1]
		var direction: Vector2 = Vector2(end.x - start.x, end.y - start.y).normalized()
		var side: Vector2 = Vector2(-direction.y, direction.x)
		var share_a: float = float(index) / float(points.size() - 1)
		var share_b: float = float(index + 1) / float(points.size() - 1)
		var width_a: float = lerpf(width_start, width_end, share_a) * 0.5
		var width_b: float = lerpf(width_start, width_end, share_b) * 0.5
		var a: Vector3 = start + Vector3(side.x, side.y, 0.0) * width_a
		var b: Vector3 = start - Vector3(side.x, side.y, 0.0) * width_a
		var c: Vector3 = end + Vector3(side.x, side.y, 0.0) * width_b
		var d: Vector3 = end - Vector3(side.x, side.y, 0.0) * width_b
		for point: Vector3 in [a, b, c, b, d, c]:
			tool.set_normal(Vector3(0.0, 0.0, 1.0))
			tool.add_vertex(point)


func _start_flash() -> void:
	_bolt.visible = true
	_set_flash_energy(3.4)
	_next_flash_phase(1)


func _set_flash_energy(value: float) -> void:
	_flash_light.light_energy = value
	_bolt_material.emission_energy_multiplier = 4.0 if value > 0.0 else 0.0


func _next_flash_phase(phase: int) -> void:
	_flash_phase = phase
	_phase_elapsed_s = 0.0
