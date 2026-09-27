extends GutTest
## game/DiscBody.gd: the disc's purely-visual thickness (Bontago-mp0.3.2,
## owner feedback: "The disc is just a thin mirror currently, the mockup has
## a much thicker metallic disc with a soft glowing border going round the
## rim.") plus its Bontago-pt.12 chamfer/texture redesign (owner: "the
## glowing strip currently sits slightly outside the disc as its own
## separate element ... the disc has a chamfered edge that makes up the
## glowing strip", "it lacks the texture ... visible where it interacts with
## the sun"). These tests pin the band/chamfer mesh geometry -- height,
## footprint, the ROUND/OVAL shape-following contract, the chamfer's flush
## no-gap seam with the true disc edge, and the shared procedural surface
## texture -- without needing a live Field or a renderer (ArrayMesh geometry
## is plain CPU data, readable headless).

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
	# assertion, not these. Zeroing the chamfer keeps the band's own AABB
	# spanning the full band_height budget for these footprint-only checks.
	visuals.band_radius_scale = 1.0
	visuals.chamfer_height_fraction = 0.0
	return visuals


func _make_body(map_def: MapDef, visuals: DiscBodyVisuals = null) -> DiscBody:
	var body: DiscBody = DiscBody.new()
	add_child_autofree(body)
	body.configure(map_def, visuals if visuals != null else _default_visuals(), SEGMENTS)
	return body


func test_configure_builds_a_band_and_chamfer_mesh() -> void:
	var body: DiscBody = _make_body(_map(MapDef.MapShape.ROUND))
	assert_not_null(body.band_mesh_instance())
	assert_not_null(body.band_mesh_instance().mesh)
	assert_not_null(body.chamfer_mesh_instance())
	assert_not_null(body.chamfer_mesh_instance().mesh)


func test_band_height_matches_the_configured_fraction_of_diameter() -> void:
	var visuals: DiscBodyVisuals = DiscBodyVisuals.new()
	visuals.band_height_fraction = 0.05
	visuals.chamfer_height_fraction = 0.0
	var map_def: MapDef = _map(MapDef.MapShape.ROUND, 10.0)
	var body: DiscBody = _make_body(map_def, visuals)

	var aabb: AABB = body.band_mesh_instance().mesh.get_aabb()
	# diameter 20 * 0.05 == 1.0 m of band_height_fraction, plus disk_height
	# (0.2 m) since the band's own top now sits flush at the true playing
	# surface (y = 0) whenever the chamfer above it is zeroed out -- see
	# game/DiscBody.gd's own rebuild().
	assert_almost_eq(aabb.size.y, 1.2, 0.01)
	assert_almost_eq(aabb.position.y, -1.2, 0.01)
	assert_almost_eq(aabb.position.y + aabb.size.y, 0.0, 0.01)


func test_chamfer_eats_into_the_top_of_the_bands_own_height_budget() -> void:
	var visuals: DiscBodyVisuals = DiscBodyVisuals.new()
	visuals.band_height_fraction = 0.05
	visuals.chamfer_height_fraction = 0.2
	var map_def: MapDef = _map(MapDef.MapShape.ROUND, 10.0)
	var body: DiscBody = _make_body(map_def, visuals)

	var band_aabb: AABB = body.band_mesh_instance().mesh.get_aabb()
	var chamfer_aabb: AABB = body.chamfer_mesh_instance().mesh.get_aabb()
	# band_height (1.0 m) * chamfer_height_fraction (0.2) == 0.2 m of chamfer
	# depth, carved off the top of the combined band+disk_height budget
	# (1.2 m) rather than added on top of it -- the total drop from the true
	# playing surface (y = 0) to the band's own bottom stays
	# band_height + disk_height, same as before this package.
	assert_almost_eq(band_aabb.size.y, 1.0, 0.01)
	assert_almost_eq(chamfer_aabb.size.y, 0.2, 0.01)
	assert_almost_eq(chamfer_aabb.position.y + chamfer_aabb.size.y, 0.0, 0.01,
		"the chamfer's own top ring sits flush at the true playing surface.")
	assert_almost_eq(band_aabb.position.y + band_aabb.size.y, chamfer_aabb.position.y, 0.01,
		"watertight seam: the band's own top ring meets the chamfer's own bottom ring exactly.")


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


## Bontago-pt.12 (owner: "the glowing strip currently sits slightly outside
## the disc as its own separate element ... the disc has a chamfered edge
## that makes up the glowing strip"). The chamfer's own TOP ring must sit
## exactly at the true field_radius edge -- not band_radius_scale's proud
## lip -- so there is no floating gap between the disc's true boundary and
## the glow, unlike the old separate rim mesh this package replaces.
func test_chamfer_top_ring_is_flush_with_the_true_field_radius_edge() -> void:
	var visuals: DiscBodyVisuals = DiscBodyVisuals.new()
	visuals.band_radius_scale = 1.1
	visuals.chamfer_height_fraction = 0.5
	visuals.band_height_fraction = 0.05
	var map_def: MapDef = _map(MapDef.MapShape.ROUND, 10.0)
	var body: DiscBody = _make_body(map_def, visuals)

	var mesh: ArrayMesh = body.chamfer_mesh_instance().mesh as ArrayMesh
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var saw_top_vertex: bool = false
	for vertex: Vector3 in verts:
		if is_equal_approx(vertex.y, 0.0):
			saw_top_vertex = true
			var radius: float = Vector2(vertex.x, vertex.z).length()
			assert_almost_eq(radius, 10.0, 0.02,
				"the chamfer's own top ring must sit exactly at field_radius, flush with the overlay's own top-face boundary -- no proud/offset gap.")
	assert_true(saw_top_vertex, "fixture: the chamfer mesh must carry at least one true top-edge (y == 0) vertex.")


## The chamfer's own footprint must actually slope outward to the band's own
## (proud) radius -- proving it is a real bevel, not a flat vertical strip
## sitting at the true radius.
func test_chamfer_slopes_outward_to_the_bands_own_proud_radius() -> void:
	var visuals: DiscBodyVisuals = DiscBodyVisuals.new()
	visuals.band_radius_scale = 1.1
	visuals.chamfer_height_fraction = 0.5
	visuals.band_height_fraction = 0.05
	var map_def: MapDef = _map(MapDef.MapShape.ROUND, 10.0)
	var body: DiscBody = _make_body(map_def, visuals)

	var chamfer_aabb: AABB = body.chamfer_mesh_instance().mesh.get_aabb()
	assert_almost_eq(chamfer_aabb.size.x, 22.0, 0.1, "2 * field_radius * band_radius_scale.")


func test_reconfigure_reuses_the_same_mesh_instances() -> void:
	var map_def: MapDef = _map(MapDef.MapShape.ROUND)
	var body: DiscBody = _make_body(map_def)
	var band: MeshInstance3D = body.band_mesh_instance()
	var chamfer: MeshInstance3D = body.chamfer_mesh_instance()

	body.configure(map_def, DiscBodyVisuals.new(), SEGMENTS)

	assert_same(body.band_mesh_instance(), band)
	assert_same(body.chamfer_mesh_instance(), chamfer)


func test_bottom_cap_disabled_still_builds_a_valid_open_band() -> void:
	var visuals: DiscBodyVisuals = DiscBodyVisuals.new()
	visuals.bottom_cap_enabled = false
	var body: DiscBody = _make_body(_map(MapDef.MapShape.ROUND), visuals)
	assert_not_null(body.band_mesh_instance().mesh)
	assert_true(body.band_mesh_instance().mesh.get_surface_count() > 0)


# --- Bontago-mp0.3.8/pt.12: chamfer screen-space-minimum-width shader wiring,
# plus pt.12's shared procedural surface texture -----------------------------

## The chamfer's dashing-at-distance fix (shaders/disc_rim.gdshader) needs a
## ShaderMaterial carrying the tuning resource's own colors/energy/widening
## factor, not the band's plain StandardMaterial3D -- pins the wiring so a
## future edit cannot silently drop back to a fixed material that cannot do
## the distance-based widening. Also pins the pt.12 surface-texture uniforms
## (procedural normal map + anisotropy) the chamfer shares with the band.
func test_chamfer_material_is_a_shader_material_wired_from_visuals() -> void:
	var visuals: DiscBodyVisuals = DiscBodyVisuals.new()
	visuals.chamfer_glow_color = Color(0.2, 0.4, 0.6)
	visuals.chamfer_glow_energy = 3.3
	visuals.band_color = Color(0.1, 0.11, 0.12)
	visuals.chamfer_screen_min_width_factor = 0.0099
	visuals.surface_anisotropy = 0.42
	visuals.surface_noise_strength = 0.77
	var body: DiscBody = _make_body(_map(MapDef.MapShape.ROUND), visuals)

	var material: ShaderMaterial = body.chamfer_mesh_instance().material_override as ShaderMaterial
	assert_not_null(material, "the chamfer's own material must be a ShaderMaterial.")
	assert_eq(material.shader.resource_path, "res://shaders/disc_rim.gdshader")
	assert_eq(material.get_shader_parameter(&"rim_color"), visuals.chamfer_glow_color)
	assert_eq(material.get_shader_parameter(&"rim_emission_energy"), visuals.chamfer_glow_energy)
	assert_eq(material.get_shader_parameter(&"band_color"), visuals.band_color)
	assert_eq(
		material.get_shader_parameter(&"min_screen_width_factor"),
		visuals.chamfer_screen_min_width_factor
	)
	assert_eq(material.get_shader_parameter(&"surface_anisotropy"), visuals.surface_anisotropy)
	assert_eq(
		material.get_shader_parameter(&"surface_noise_strength"), visuals.surface_noise_strength
	)
	assert_not_null(material.get_shader_parameter(&"surface_noise"),
		"the chamfer must sample the same procedural normal-map texture the band does.")


## _build_ring_mesh()'s own `with_gradient` contract (see its class doc): the
## chamfer's own top-ring vertices carry COLOR.r == 0.0, the bottom-ring
## vertices COLOR.r == 1.0, so shaders/disc_rim.gdshader's vertex()/
## fragment() can tell them apart without a second uniform. Read straight
## back out of the committed ArrayMesh's own vertex color array -- plain CPU
## mesh data, exactly like this file's other geometry assertions.
func test_chamfer_mesh_carries_a_top_to_bottom_gradient_vertex_color() -> void:
	var body: DiscBody = _make_body(_map(MapDef.MapShape.ROUND))
	var mesh: ArrayMesh = body.chamfer_mesh_instance().mesh as ArrayMesh
	var arrays: Array = mesh.surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	assert_true(colors.size() > 0, "fixture: the chamfer mesh must carry vertex colors.")

	var saw_top: bool = false
	var saw_bottom: bool = false
	for color: Color in colors:
		if is_equal_approx(color.r, 0.0):
			saw_top = true
		elif is_equal_approx(color.r, 1.0):
			saw_bottom = true
		else:
			fail_test("unexpected chamfer vertex color.r %f (must be 0.0 or 1.0)." % color.r)
	assert_true(saw_top, "the chamfer mesh must carry at least one top-edge (COLOR.r == 0.0) vertex.")
	assert_true(saw_bottom, "the chamfer mesh must carry at least one bottom-edge (COLOR.r == 1.0) vertex.")


## The band's own material must stay a plain StandardMaterial3D with no
## gradient vertex colors -- this package's chamfer-only glow/gradient logic
## must not leak onto it.
func test_band_material_and_mesh_are_unaffected_by_the_gradient() -> void:
	var body: DiscBody = _make_body(_map(MapDef.MapShape.ROUND))
	assert_true(body.band_mesh_instance().material_override is StandardMaterial3D)
	var mesh: ArrayMesh = body.band_mesh_instance().mesh as ArrayMesh
	var arrays: Array = mesh.surface_get_arrays(0)
	assert_null(arrays[Mesh.ARRAY_COLOR], "the band mesh must carry no vertex colors.")


## Bontago-pt.12 (owner: "it lacks the texture ... visible where it interacts
## with the sun"): the band's own StandardMaterial3D must wire up the
## procedural anisotropic/normal-map surface texture from visuals.
func test_band_material_wires_up_the_procedural_surface_texture() -> void:
	var visuals: DiscBodyVisuals = DiscBodyVisuals.new()
	visuals.surface_anisotropy = 0.55
	visuals.surface_noise_strength = 0.44
	var body: DiscBody = _make_body(_map(MapDef.MapShape.ROUND), visuals)

	var material: StandardMaterial3D = body.band_mesh_instance().material_override as StandardMaterial3D
	assert_true(material.anisotropy_enabled)
	assert_almost_eq(material.anisotropy, 0.55, 0.001)
	assert_true(material.normal_enabled)
	assert_almost_eq(material.normal_scale, 0.44, 0.001)
	assert_not_null(material.normal_texture)


## Both surface_anisotropy == 0 and surface_noise_strength == 0 must fully
## disable their respective material features (a plain isotropic, unbumped
## surface), not just zero out an ignored parameter.
func test_surface_texture_can_be_disabled() -> void:
	var visuals: DiscBodyVisuals = DiscBodyVisuals.new()
	visuals.surface_anisotropy = 0.0
	visuals.surface_noise_strength = 0.0
	var body: DiscBody = _make_body(_map(MapDef.MapShape.ROUND), visuals)

	var material: StandardMaterial3D = body.band_mesh_instance().material_override as StandardMaterial3D
	assert_false(material.anisotropy_enabled)
	assert_false(material.normal_enabled)


## Both the band and the chamfer mesh need real generated UV/tangent data
## (not just normals) for the anisotropic highlight and normal-map bump to
## orient correctly -- SurfaceTool.generate_tangents() silently no-ops
## without a valid UV channel, so this pins that the UV array is actually
## populated (a future edit that drops _add_quad()'s set_uv() calls would
## otherwise pass every other test here while quietly breaking the texture).
func test_band_and_chamfer_meshes_carry_generated_uv_data() -> void:
	var body: DiscBody = _make_body(_map(MapDef.MapShape.ROUND))
	for instance: MeshInstance3D in [body.band_mesh_instance(), body.chamfer_mesh_instance()]:
		var mesh: ArrayMesh = instance.mesh as ArrayMesh
		var arrays: Array = mesh.surface_get_arrays(0)
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		assert_true(uvs.size() > 0, "%s mesh must carry generated UV data." % instance.name)
