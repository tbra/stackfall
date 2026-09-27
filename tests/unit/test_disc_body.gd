extends GutTest
## game/DiscBody.gd: the disc's purely-visual thickness (Bontago-mp0.3.2,
## owner feedback: "The disc is just a thin mirror currently, the mockup has
## a much thicker metallic disc with a soft glowing border going round the
## rim."). These tests pin the band/rim mesh geometry -- height, footprint,
## and the ROUND/OVAL shape-following contract this package's own brief asks
## for -- without needing a live Field or a renderer (ArrayMesh geometry is
## plain CPU data, readable headless).

const SEGMENTS: int = 24


func _map(shape: MapDef.MapShape, radius: float = 10.0, aspect: float = 0.65) -> MapDef:
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_disc_body"
	map_def.field_radius = radius
	map_def.disk_height = 0.2
	map_def.map_shape = shape
	map_def.oval_aspect = aspect
	return map_def


func _default_visuals() -> DiscBodyVisuals:
	var visuals: DiscBodyVisuals = DiscBodyVisuals.new()
	# Footprint assertions below want an exact field_radius circle/ellipse;
	# band_radius_scale's hair's-width z-fighting nudge (config/
	# DiscBodyVisuals.gd's own DECISION) is covered by its own dedicated
	# assertion, not these.
	visuals.band_radius_scale = 1.0
	return visuals


func _make_body(map_def: MapDef, visuals: DiscBodyVisuals = null) -> DiscBody:
	var body: DiscBody = DiscBody.new()
	add_child_autofree(body)
	body.configure(map_def, visuals if visuals != null else _default_visuals(), SEGMENTS)
	return body


func test_configure_builds_a_band_and_rim_mesh() -> void:
	var body: DiscBody = _make_body(_map(MapDef.MapShape.ROUND))
	assert_not_null(body.band_mesh_instance())
	assert_not_null(body.band_mesh_instance().mesh)
	assert_not_null(body.rim_mesh_instance())
	assert_not_null(body.rim_mesh_instance().mesh)


func test_band_height_matches_the_configured_fraction_of_diameter() -> void:
	var visuals: DiscBodyVisuals = DiscBodyVisuals.new()
	visuals.band_height_fraction = 0.05
	var map_def: MapDef = _map(MapDef.MapShape.ROUND, 10.0)
	var body: DiscBody = _make_body(map_def, visuals)

	var aabb: AABB = body.band_mesh_instance().mesh.get_aabb()
	# diameter 20 * 0.05 == 1.0 m of band_height_fraction, plus disk_height
	# (0.2 m) since the band's own top now sits flush at the true playing
	# surface (y = 0), not the overlay's own underside -- see game/
	# DiscBody.gd's own DECISION (Bontago-mp0.3.2 review pass 3).
	assert_almost_eq(aabb.size.y, 1.2, 0.01)
	assert_almost_eq(aabb.position.y, -1.2, 0.01)
	assert_almost_eq(aabb.position.y + aabb.size.y, 0.0, 0.01)


func test_round_band_footprint_is_the_field_radius_circle() -> void:
	var map_def: MapDef = _map(MapDef.MapShape.ROUND, 12.0)
	var body: DiscBody = _make_body(map_def)

	var aabb: AABB = body.band_mesh_instance().mesh.get_aabb()
	assert_almost_eq(aabb.size.x, 24.0, 0.05, "x footprint spans 2 * field_radius.")
	assert_almost_eq(aabb.size.z, 24.0, 0.05, "z footprint spans 2 * field_radius (round).")


func test_oval_band_footprint_follows_the_true_ellipse() -> void:
	var map_def: MapDef = _map(MapDef.MapShape.OVAL, 12.0, 0.5)
	var body: DiscBody = _make_body(map_def)

	var aabb: AABB = body.band_mesh_instance().mesh.get_aabb()
	assert_almost_eq(aabb.size.x, 24.0, 0.05, "x footprint stays field_radius; only z narrows.")
	assert_almost_eq(aabb.size.z, 12.0, 0.05, "z footprint is 2 * field_radius * oval_aspect.")


func test_ring_shape_falls_back_to_the_round_bounding_circle() -> void:
	# This package's own brief: shapes this hard fall back to the same round
	# bounding circle the top-surface CylinderMesh already draws for them.
	var map_def: MapDef = _map(MapDef.MapShape.RING, 12.0)
	var body: DiscBody = _make_body(map_def)

	var aabb: AABB = body.band_mesh_instance().mesh.get_aabb()
	assert_almost_eq(aabb.size.x, 24.0, 0.05)
	assert_almost_eq(aabb.size.z, 24.0, 0.05)


func test_rim_is_a_thin_strip_scaled_slightly_outside_the_band() -> void:
	var visuals: DiscBodyVisuals = DiscBodyVisuals.new()
	visuals.band_height_fraction = 0.05
	visuals.rim_height_fraction = 0.2
	visuals.rim_radius_scale = 1.1
	# Isolated from rim_lift's own dedicated test below -- this test is only
	# about height/radius-scale behavior.
	visuals.rim_lift = 0.0
	var map_def: MapDef = _map(MapDef.MapShape.ROUND, 10.0)
	var body: DiscBody = _make_body(map_def, visuals)

	var band_aabb: AABB = body.band_mesh_instance().mesh.get_aabb()
	var rim_aabb: AABB = body.rim_mesh_instance().mesh.get_aabb()
	assert_almost_eq(rim_aabb.size.y, 0.2, 0.01, "20% of the 1.0 m band height.")
	assert_almost_eq(rim_aabb.position.y, band_aabb.position.y + band_aabb.size.y - 0.2, 0.01,
		"flush against the band's own top edge.")
	assert_true(rim_aabb.size.x > band_aabb.size.x, "the rim lip is scaled proud of the band.")


## Bontago-mp0.3.8 (owner: fix the rim/overlay z-fight by lifting the lip
## above the top surface instead of scaling its radius out further). rim_lift
## raises only the rim's own top_y -- the band (and the true playing surface
## it sits flush with) are untouched.
func test_rim_lift_raises_the_rim_above_the_true_playing_surface() -> void:
	var visuals: DiscBodyVisuals = DiscBodyVisuals.new()
	visuals.rim_lift = 0.05
	var map_def: MapDef = _map(MapDef.MapShape.ROUND, 10.0)
	var body: DiscBody = _make_body(map_def, visuals)

	var band_aabb: AABB = body.band_mesh_instance().mesh.get_aabb()
	var rim_aabb: AABB = body.rim_mesh_instance().mesh.get_aabb()
	assert_almost_eq(band_aabb.position.y + band_aabb.size.y, 0.0, 0.01,
		"the band's own top edge is unaffected by rim_lift, still flush at y = 0.")
	assert_almost_eq(rim_aabb.position.y + rim_aabb.size.y, 0.05, 0.01,
		"the rim's own top edge is raised by exactly rim_lift.")


func test_reconfigure_reuses_the_same_mesh_instances() -> void:
	var map_def: MapDef = _map(MapDef.MapShape.ROUND)
	var body: DiscBody = _make_body(map_def)
	var band: MeshInstance3D = body.band_mesh_instance()
	var rim: MeshInstance3D = body.rim_mesh_instance()

	body.configure(map_def, DiscBodyVisuals.new(), SEGMENTS)

	assert_same(body.band_mesh_instance(), band)
	assert_same(body.rim_mesh_instance(), rim)


func test_bottom_cap_disabled_still_builds_a_valid_open_band() -> void:
	var visuals: DiscBodyVisuals = DiscBodyVisuals.new()
	visuals.bottom_cap_enabled = false
	var body: DiscBody = _make_body(_map(MapDef.MapShape.ROUND), visuals)
	assert_not_null(body.band_mesh_instance().mesh)
	assert_true(body.band_mesh_instance().mesh.get_surface_count() > 0)


# --- Bontago-mp0.3.8: rim screen-space-minimum-width shader wiring -----------

## The rim's dashing-at-distance fix (shaders/disc_rim.gdshader) needs a
## ShaderMaterial carrying the tuning resource's own colors/energy/widening
## factor, not the band's plain StandardMaterial3D -- pins the wiring so a
## future edit cannot silently drop back to a fixed material that cannot do
## the distance-based widening (see that shader's own header comment for why
## a fixed material cannot fix the underlying report either way).
func test_rim_material_is_a_shader_material_wired_from_visuals() -> void:
	var visuals: DiscBodyVisuals = DiscBodyVisuals.new()
	visuals.rim_color = Color(0.2, 0.4, 0.6)
	visuals.rim_emission_energy = 3.3
	visuals.band_color = Color(0.1, 0.11, 0.12)
	visuals.rim_screen_min_width_factor = 0.0099
	var body: DiscBody = _make_body(_map(MapDef.MapShape.ROUND), visuals)

	var material: ShaderMaterial = body.rim_mesh_instance().material_override as ShaderMaterial
	assert_not_null(material, "the rim's own material must be a ShaderMaterial.")
	assert_eq(material.shader.resource_path, "res://shaders/disc_rim.gdshader")
	assert_eq(material.get_shader_parameter(&"rim_color"), visuals.rim_color)
	assert_eq(material.get_shader_parameter(&"rim_emission_energy"), visuals.rim_emission_energy)
	assert_eq(material.get_shader_parameter(&"band_color"), visuals.band_color)
	assert_eq(
		material.get_shader_parameter(&"min_screen_width_factor"),
		visuals.rim_screen_min_width_factor
	)


## _build_band_mesh()'s own `with_gradient` contract (see its class doc): the
## rim's own top-ring vertices carry COLOR.r == 0.0, the bottom-ring vertices
## COLOR.r == 1.0, so shaders/disc_rim.gdshader's vertex()/fragment() can tell
## them apart without a second uniform. Read straight back out of the
## committed ArrayMesh's own vertex color array -- plain CPU mesh data,
## exactly like this file's other geometry assertions.
func test_rim_mesh_carries_a_top_to_bottom_gradient_vertex_color() -> void:
	var body: DiscBody = _make_body(_map(MapDef.MapShape.ROUND))
	var mesh: ArrayMesh = body.rim_mesh_instance().mesh as ArrayMesh
	var arrays: Array = mesh.surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	assert_true(colors.size() > 0, "fixture: the rim mesh must carry vertex colors.")

	var saw_top: bool = false
	var saw_bottom: bool = false
	for color: Color in colors:
		if is_equal_approx(color.r, 0.0):
			saw_top = true
		elif is_equal_approx(color.r, 1.0):
			saw_bottom = true
		else:
			fail_test("unexpected rim vertex color.r %f (must be 0.0 or 1.0)." % color.r)
	assert_true(saw_top, "the rim mesh must carry at least one top-edge (COLOR.r == 0.0) vertex.")
	assert_true(saw_bottom, "the rim mesh must carry at least one bottom-edge (COLOR.r == 1.0) vertex.")


## The band's own material must stay untouched by this package's rim-only
## fix -- still a plain StandardMaterial3D, no gradient vertex colors.
func test_band_material_and_mesh_are_unaffected_by_the_rim_fix() -> void:
	var body: DiscBody = _make_body(_map(MapDef.MapShape.ROUND))
	assert_true(body.band_mesh_instance().material_override is StandardMaterial3D)
	var mesh: ArrayMesh = body.band_mesh_instance().mesh as ArrayMesh
	var arrays: Array = mesh.surface_get_arrays(0)
	assert_null(arrays[Mesh.ARRAY_COLOR], "the band mesh must carry no vertex colors.")
