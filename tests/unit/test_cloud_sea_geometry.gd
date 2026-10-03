extends GutTest
## Bontago-mp0.93 pass 2: the overcast (upper) puff layer is seen from below, where flat
## bases meant huge featureless slabs with razor-flat bottoms. Its puffs now have their own
## base: round bottoms (no base plane), squashed to the old low profile, each hanging a random
## depth below its clump's level so no two share a plane, small puffs also bulging from the
## underside, and a camera-clearance fade in the shader. The sea keeps its flat-bottomed
## cumulus. The multimesh is not readable headless, so the geometry is pinned through the
## pure placement function, the mesh builder and the values CloudSea tracks and passes on.


var _skybox: Skybox = null


func after_each() -> void:
	Settings.set_graphics_preset(&"high")


func _upper_sea() -> CloudSea:
	Settings.set_graphics_preset(&"high")
	var sky: Sky = Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	var environment: Environment = Environment.new()
	environment.sky = sky
	var skybox: Skybox = Skybox.new()
	skybox.config = SkyboxConfig.new()
	skybox.environment = environment
	skybox.theme = Skybox.load_theme("sunset")
	add_child_autofree(skybox)
	skybox.apply_theme(skybox.theme)
	_skybox = skybox
	return skybox.get_cloud_sea()


func test_round_bottom_rests_on_the_clump_level_a_flat_one_is_cut_there() -> void:
	# A round puff (flat = 1) sits with its lowest point on the base level; the old flat-bottomed
	# puff had its plane (0.15 of the radius under the centre) on it.
	assert_almost_eq(CloudSea.puff_centre_y(0.0, 10.0, 100.0, 1.0), 110.0, 0.0001)
	assert_almost_eq(CloudSea.puff_centre_y(0.0, 10.0, 100.0, 0.15), 101.5, 0.0001)
	# A puff whose top is already high enough is not pushed down or up.
	assert_almost_eq(CloudSea.puff_centre_y(150.0, 10.0, 100.0, 1.0), 140.0, 0.0001)


func test_sink_lets_round_bottoms_hang_below_the_clump_level_at_different_depths() -> void:
	var shallow: float = CloudSea.puff_centre_y(0.0, 10.0, 100.0, 1.0, 1.0) - 10.0
	var deep: float = CloudSea.puff_centre_y(0.0, 10.0, 100.0, 1.0, 6.0) - 10.0
	assert_almost_eq(shallow, 99.0, 0.0001)
	assert_almost_eq(deep, 94.0, 0.0001)
	assert_ne(shallow, deep, "puffs of one clump with different sinks share no base plane")
	assert_almost_eq(CloudSea.puff_centre_y(0.0, 10.0, 100.0, 1.0), 110.0, 0.0001, "no sink keeps the old rule")


func test_round_mesh_has_no_base_plane_and_the_flat_mesh_keeps_its_plane() -> void:
	var round_mesh: ArrayMesh = CloudSea.build_puff_mesh(1.0)
	var arrays: Array = round_mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var lowest: float = INF
	for i: int in range(vertices.size()):
		lowest = minf(lowest, vertices[i].y)
		assert_almost_eq(vertices[i].length(), 1.0, 0.0001, "every vertex of a round puff is on the unit sphere")
		assert_almost_eq(normals[i].distance_to(vertices[i]), 0.0, 0.001, "radial normals, no base normals pointing down")
	assert_lt(lowest, -0.8, "the lower half exists")
	var flat_lowest: float = INF
	for v: Vector3 in (CloudSea.build_puff_mesh(0.15).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		flat_lowest = minf(flat_lowest, v.y)
	assert_almost_eq(flat_lowest, -0.15, 0.0001, "the sea's puff mesh keeps its flat base")


func test_upper_layer_uses_its_own_round_base_and_the_sea_keeps_the_theme_flat_base() -> void:
	var sea: CloudSea = _upper_sea()
	var tuning: WeatherCeilingTuning = sea.upper_tuning
	assert_not_null(tuning)
	assert_gte(tuning.upper_flat_base, 0.9, "round bottoms: no base plane for a camera below to see as a slab")
	assert_lt(tuning.upper_puff_squash, 1.0, "round puffs stay low and wide")
	assert_gt(tuning.upper_base_sink_m, 0.0, "per-puff depth jitter breaks coplanar bottoms")
	assert_gt(tuning.upper_belly_depth, 0.0, "detail puffs also bulge from the underside")
	assert_almost_eq(float(sea.upper_instance().get_instance_shader_parameter(&"flat_base_override")),
		tuning.upper_flat_base, 0.0001)
	assert_null(sea.puff_instance().get_instance_shader_parameter(&"flat_base_override"),
		"the sea keeps the material's flat_base (the shader default of -1)")
	var material: ShaderMaterial = sea.puff_material()
	assert_almost_eq(float(material.get_shader_parameter(&"base_clear_start_m")), tuning.upper_clear_fade_start_m, 0.0001)
	assert_almost_eq(float(material.get_shader_parameter(&"base_clear_end_m")), tuning.upper_clear_fade_end_m, 0.0001)
	assert_gt(tuning.upper_clear_fade_end_m, tuning.upper_clear_fade_start_m)


func test_upper_puffs_never_hang_far_below_the_layer_height() -> void:
	var sea: CloudSea = _upper_sea()
	var tuning: WeatherCeilingTuning = sea.upper_tuning
	var lowest: float = sea.upper_lowest_bottom()
	assert_ne(lowest, INF, "the layer wrote puffs")
	# Body puffs hang at most upper_base_sink_m under their clump's level, which starts that much
	# above height_m; only the bulging detail puffs may dip a few metres under it.
	var allowance: float = tuning.upper_clump_radius_max_m * 0.05
	assert_gte(lowest, tuning.height_m - allowance, "rain starts under the layer, not inside its bulges")
	assert_lt(lowest, tuning.height_m + tuning.upper_base_sink_m + tuning.upper_base_spread_m,
		"the layer still reaches down to its base height")


func test_pass_one_look_is_still_reachable_from_tuning() -> void:
	# The old flat-bottomed look is the same code with the old values (also how the capture
	# tool makes its before/after sheet).
	var sea: CloudSea = _upper_sea()
	var tuning: WeatherCeilingTuning = sea.upper_tuning
	var saved_flat: float = tuning.upper_flat_base
	var saved_sink: float = tuning.upper_base_sink_m
	var saved_squash: float = tuning.upper_puff_squash
	var saved_belly: float = tuning.upper_belly_depth
	tuning.upper_belly_depth = -0.25
	tuning.upper_flat_base = 0.15
	tuning.upper_base_sink_m = 0.0
	tuning.upper_puff_squash = 1.0
	sea.configure(_skybox.theme, 1.0, _skybox.theme.sky_material)
	assert_almost_eq(float(sea.upper_instance().get_instance_shader_parameter(&"flat_base_override")), 0.15, 0.0001)
	assert_gte(sea.upper_lowest_bottom(), tuning.height_m - 0.5, "flat bottoms sit on height_m")
	tuning.upper_flat_base = saved_flat
	tuning.upper_base_sink_m = saved_sink
	tuning.upper_puff_squash = saved_squash
	tuning.upper_belly_depth = saved_belly


func test_shader_has_round_bottoms_and_the_clearance_fade() -> void:
	var shader: Shader = load("res://shaders/cloud_puffs.gdshader") as Shader
	var code_lines: PackedStringArray = PackedStringArray()
	for line: String in shader.code.split("\n"):
		code_lines.append(line.split("//")[0])
	var code: String = "\n".join(code_lines)
	assert_true(code.contains("instance uniform float flat_base_override"), "the upper layer carries its own base plane")
	assert_true(code.contains("bool round_bottom = base_flat >= round_base_from;"))
	assert_true(code.contains("bool on_base = mesh_n.y < -0.7 && !round_bottom;"), "a round puff has no base fragments")
	assert_true(code.contains("if (!round_bottom && entry.y < -base_flat) {"), "no plane cut under a round puff")
	assert_true(code.contains("base_ramp = 1.0 - smoothstep(min(round_under_start, 0.99), 1.0, -n.y);"),
		"the underbelly bounce follows the normal on a round bottom")
	assert_true(code.contains("if (floor_on > 0.5 && base_clear_end_m > 0.0) {"), "the fade is the upper layer's only")
	assert_true(code.contains("surface.y - cam.y"), "the fade follows the surface height above the camera")
	assert_true(code.contains("if (clearance < bayer4(FRAGCOORD.xy)) {"), "ordered dither, like the near fade")


func test_shader_hull_covers_the_chord_error_and_upper_rim_is_calmer_on_side_faces() -> void:
	var shader: Shader = load("res://shaders/cloud_puffs.gdshader") as Shader
	var code_lines: PackedStringArray = PackedStringArray()
	for line: String in shader.code.split("
"):
		code_lines.append(line.split("//")[0])
	var code: String = "
".join(code_lines)
	assert_true(code.contains("uniform float hull_chord_margin = 0.05;"))
	assert_true(code.contains("+ hull_margin + hull_chord_margin;"), "the hull is inflated past the faces' chord error")
	assert_true(code.contains("uniform float upper_rim_down_shift = 0.1;"))
	assert_true(code.contains("smoothstep(-0.25 - upper_rim_down_shift * floor_on, 0.25 - upper_rim_down_shift * floor_on, -n.y)"),
		"only the upper layer gets the calmer rim; the sea keeps rim *= 1 - smoothstep(-0.25, 0.25, -n.y)")
	# The hull's chord error: how far inside the unit sphere the mesh's flat faces are at worst.
	var silhouette: float = 1.0 + CloudSea.hull_inflate(ShaderMaterial.new()) - 0.04
	var push: float = CloudSea.hull_inflate(ShaderMaterial.new()) + 0.05
	var high_inradius: float = _inradius(CloudSea.build_puff_mesh(1.0, 1))
	assert_lt(high_inradius, 0.97, "the High preset's 80-face puff is visibly coarser than a sphere")
	assert_gte(high_inradius * (1.0 + push), silhouette, "with the chord margin its hull holds the largest lump")
	assert_lt(high_inradius * (1.0 + push - 0.05), silhouette, "positive control: without it the faces slice lump tops")
	assert_gte(_inradius(CloudSea.build_puff_mesh(1.0, 2)) * (1.0 + push), silhouette)


## Smallest distance from the origin to a face plane of a unit-sphere mesh.
func _inradius(mesh: ArrayMesh) -> float:
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var faces: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var smallest: float = INF
	for f: int in range(0, faces.size(), 3):
		var a: Vector3 = vertices[faces[f]]
		var normal: Vector3 = (vertices[faces[f + 1]] - a).cross(vertices[faces[f + 2]] - a).normalized()
		smallest = minf(smallest, absf(normal.dot(a)))
	return smallest
