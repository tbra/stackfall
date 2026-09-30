class_name DistantBirds
extends Node3D
## Bontago-adt.1: small flocks of birds circling far outside the play area.
## One MultiMeshInstance3D; every bit of motion (orbit, heading, bank, wing
## flap) is done in shaders/distant_birds.gdshader from TIME and per-instance
## custom data, so it runs with no per-frame script and also in the editor and
## the baked demo scene. Flock placement is deterministic (seeded) and lives
## in a SkyThemeDef-referenced BirdFlockConfig-style set of fields on the theme.

const SHADER: Shader = preload("res://shaders/distant_birds.gdshader")
## Wing half-span in mesh units (the instance scale is the bird size in m).
const HALF_SPAN: float = 1.0
const BODY_LENGTH_FRONT: float = 0.55
const BODY_LENGTH_BACK: float = 0.4
const WING_ROOT_X: float = 0.1
const WING_TIP_X: float = -0.25

var _instance: MultiMeshInstance3D = null


## Rebuilds the flocks from `theme` (birds hidden when it has none or
## `enabled` is false). Safe to call repeatedly.
func configure(theme: SkyThemeDef, enabled: bool) -> void:
	if _instance != null:
		_instance.queue_free()
		_instance = null
	if theme == null or theme.bird_material == null or theme.bird_flock_count <= 0 or not enabled:
		visible = false
		return
	visible = true
	var per_flock: int = maxi(theme.birds_per_flock, 1)
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = build_bird_mesh()
	multimesh.instance_count = theme.bird_flock_count * per_flock
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = theme.bird_seed
	var index: int = 0
	for flock: int in range(theme.bird_flock_count):
		var azimuth: float = rng.randf() * TAU
		var distance: float = rng.randf_range(theme.bird_distance_min_m, theme.bird_distance_max_m)
		var altitude: float = rng.randf_range(theme.bird_altitude_min_m, theme.bird_altitude_max_m)
		# The orbit centre sits on the flock's own ring: the shader adds
		# radius * (cos, sin) around it, so keep radius well below distance.
		var centre: Vector3 = Vector3(cos(azimuth) * distance, altitude, sin(azimuth) * distance)
		var radius: float = rng.randf_range(theme.bird_orbit_radius_min_m, theme.bird_orbit_radius_max_m)
		var phase: float = rng.randf() * TAU
		var direction: float = 1.0 if rng.randf() < 0.5 else -1.0
		var angular_speed: float = direction * theme.bird_speed_mps / maxf(radius, 1.0)
		var size: float = rng.randf_range(theme.bird_size_min_m, theme.bird_size_max_m)
		for _bird: int in range(per_flock):
			multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), centre))
			multimesh.set_instance_custom_data(index, Color(radius, phase, angular_speed, rng.randf()))
			index += 1
	_instance = MultiMeshInstance3D.new()
	_instance.name = "Flocks"
	_instance.multimesh = multimesh
	_instance.material_override = theme.bird_material
	add_to_group(WeatherFogShader.GROUP)
	WeatherFogShader.apply(theme.bird_material as ShaderMaterial)
	_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The shader moves vertices far from the instance origins, so the culling
	# box must cover the whole sky volume.
	var extent: float = theme.bird_distance_max_m + theme.bird_orbit_radius_max_m + theme.bird_altitude_max_m
	_instance.custom_aabb = AABB(Vector3(-extent, -extent, -extent), Vector3.ONE * extent * 2.0)
	add_child(_instance)


## A flat V: nose, tail and two wing tips. UV.x = 0 on the body, 1 at the tips.
static func build_bird_mesh() -> ArrayMesh:
	var vertices: PackedVector3Array = PackedVector3Array([
		Vector3(BODY_LENGTH_FRONT, 0.0, 0.0),
		Vector3(-BODY_LENGTH_BACK, 0.0, 0.0),
		Vector3(WING_ROOT_X, 0.0, -HALF_SPAN),
		Vector3(WING_ROOT_X, 0.0, HALF_SPAN),
		Vector3(WING_TIP_X, 0.0, -HALF_SPAN),
		Vector3(WING_TIP_X, 0.0, HALF_SPAN),
	])
	var uvs: PackedVector2Array = PackedVector2Array([
		Vector2.ZERO, Vector2.ZERO, Vector2.ONE, Vector2.ONE, Vector2.ONE, Vector2.ONE,
	])
	# Left wing: nose-tip_root-tail; right wing mirrored. Tips use UV.x = 1.
	var indices: PackedInt32Array = PackedInt32Array([0, 2, 1, 0, 1, 3, 2, 4, 1, 3, 1, 5])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Weather fog changed (vfx/weather/WeatherFogShader.gd).
func refresh_weather_fog() -> void:
	if _instance != null:
		WeatherFogShader.apply(_instance.material_override as ShaderMaterial)


func flock_instance() -> MultiMeshInstance3D:
	return _instance
