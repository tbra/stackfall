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
	var map_def: MapDef = _map(MapDef.MapShape.ROUND, 10.0)
	var body: DiscBody = _make_body(map_def, visuals)

	var band_aabb: AABB = body.band_mesh_instance().mesh.get_aabb()
	var rim_aabb: AABB = body.rim_mesh_instance().mesh.get_aabb()
	assert_almost_eq(rim_aabb.size.y, 0.2, 0.01, "20% of the 1.0 m band height.")
	assert_almost_eq(rim_aabb.position.y, band_aabb.position.y + band_aabb.size.y - 0.2, 0.01,
		"flush against the band's own top edge.")
	assert_true(rim_aabb.size.x > band_aabb.size.x, "the rim lip is scaled proud of the band.")


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
