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


func _uniform_names() -> Array:
	var shader: Shader = load("res://shaders/sky/cloud_puffs.gdshader") as Shader
	var names: Array = []
	for entry: Dictionary in shader.get_shader_uniform_list():
		names.append(entry["name"])
	return names


## The shader's declared default of a float uniform (the dummy renderer cannot report it).
func _declared_default(uniform_name: String) -> float:
	var declaration: RegEx = RegEx.new()
	declaration.compile("uniform\\s+float\\s+%s\\b[^=;]*=\\s*([-+0-9.eE]+)\\s*;" % uniform_name)
	var code: String = (load("res://shaders/sky/cloud_puffs.gdshader") as Shader).code
	var found: RegExMatch = declaration.search(code)
	assert_not_null(found, "uniform float %s has a declared default" % uniform_name)
	return found.get_string(1).to_float() if found != null else 0.0


func test_hull_covers_the_chord_error() -> void:
	assert_true(_uniform_names().has("hull_chord_margin"))
	# The hull's chord error: how far inside the unit sphere the mesh's flat faces are at worst.
	var chord_margin: float = _declared_default("hull_chord_margin")
	var hull_margin: float = _declared_default("hull_margin")
	assert_gt(chord_margin, 0.0, "the shader inflates its hull past the chord error")
	var silhouette: float = 1.0 + CloudSea.hull_inflate(ShaderMaterial.new()) - hull_margin
	var push: float = CloudSea.hull_inflate(ShaderMaterial.new()) + chord_margin
	var high_inradius: float = _inradius(CloudSea.build_puff_mesh(1.0, 1))
	assert_lt(high_inradius, 0.97, "the High preset's 80-face puff is visibly coarser than a sphere")
	assert_gte(high_inradius * (1.0 + push), silhouette, "with the chord margin its hull holds the largest lump")
	assert_lt(high_inradius * (1.0 + push - chord_margin), silhouette, "positive control: without it the faces slice lump tops")
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

