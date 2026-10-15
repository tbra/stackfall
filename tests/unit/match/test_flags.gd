extends GutTest
## Home and goal flags: where they stand (spec 2.2) and the goal's capture ring
## (spec 2.3).

const FIELD_RADIUS: float = 20.0

## Stand-in for MatchConfig.player_colors; the point is that Field takes its
## colors from a config array rather than inventing them.
static func _slot_colors() -> PackedColorArray:
	return PackedColorArray([
		Color(0.9, 0.25, 0.25),
		Color(0.25, 0.55, 0.95),
		Color(0.35, 0.8, 0.4),
		Color(0.95, 0.8, 0.25),
	])


func _map() -> MapDef:
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_flags"
	map_def.field_radius = FIELD_RADIUS
	map_def.cell_size = 2.0
	map_def.territory_res = 32
	return map_def


func _make_field() -> Field:
	var field: Field = Field.new()
	field.map_def = _map()
	add_child_autofree(field)
	return field


# --- Positions (spec 2.2) ---------------------------------------------------

func test_two_home_flags_sit_opposite_each_other() -> void:
	var field: Field = _make_field()
	var first: Vector2 = field.home_flag_position(0, 2)
	var second: Vector2 = field.home_flag_position(1, 2)
	var ring: float = field.map_def.home_flag_ring_radius()

	assert_almost_eq(first.length(), ring, 0.0001, "Home flags sit at field_radius - home_flag_edge_inset.")
	assert_almost_eq(second.length(), ring, 0.0001)
	assert_almost_eq(
		absf(first.angle_to(second)), PI, 0.0001, "Two players sit pi apart."
	)


func test_extra_goal_flags_are_symmetric_on_the_inner_ring() -> void:
	var field: Field = _make_field()
	var positions: PackedVector2Array = field.goal_flag_positions(3)
	var ring: float = FIELD_RADIUS * field.map_def.goal_flag_radius_fraction

	assert_eq(positions.size(), 3)
	var sum: Vector2 = Vector2.ZERO
	for position: Vector2 in positions:
		assert_almost_eq(
			position.length(), ring, 0.0001, "Extra goals sit at 0.4 * field_radius."
		)
		sum += position
	assert_almost_eq(sum.length(), 0.0, 0.0001, "Symmetric placement sums to the center.")


# --- The flag nodes ---------------------------------------------------------

func test_place_flags_builds_a_flag_per_slot_and_goal() -> void:
	var field: Field = _make_field()
	field.place_flags(4, _slot_colors(), 3)

	assert_eq(field.home_flags().size(), 4)
	assert_eq(field.goal_flags().size(), 3)
	for slot_id: int in range(4):
		var flag: HomeFlag = field.home_flags()[slot_id]
		var expected: Vector2 = field.home_flag_position(slot_id, 4)
		assert_eq(flag.slot_id(), slot_id)
		assert_almost_eq(flag.position.x, expected.x, 0.0001)
		assert_almost_eq(flag.position.z, expected.y, 0.0001)
		assert_almost_eq(
			flag.color().r, _slot_colors()[slot_id].r, 0.0001,
			"Flag colors come from MatchConfig.player_colors, not a literal."
		)


# --- Capture ring (spec 2.3) ------------------------------------------------

func test_capture_ring_appears_and_tracks_progress() -> void:
	var field: Field = _make_field()
	field.place_flags(2, _slot_colors(), 2)

	field.set_capture_progress(1, 0.5)
	for flag: GoalFlag in field.goal_flags():
		assert_true(flag.ring_visible(), "Every goal flag shows the capture ring.")
		assert_eq(flag.capture_team(), 1)
		assert_almost_eq(flag.capture_progress(), 0.5, 0.0001)


func test_capture_ring_hides_when_the_capture_breaks() -> void:
	var field: Field = _make_field()
	field.place_flags(2, _slot_colors(), 1)

	field.set_capture_progress(1, 0.8)
	field.set_capture_progress(-1, 0.0)
	var flag: GoalFlag = field.goal_flags()[0]
	assert_false(flag.ring_visible(), "team_id -1 with progress 0 clears the ring.")
	assert_eq(flag.capture_team(), -1)


# --- Beacon visuals (M7 P8, Bontago-xtq.33) ----------------------------------

func test_home_beacon_ring_and_crystal_follow_set_slots_color() -> void:
	var field: Field = _make_field()
	field.place_flags(4, _slot_colors(), 1)

	for slot_id: int in range(4):
		var flag: HomeFlag = field.home_flags()[slot_id]
		var expected: Color = _slot_colors()[slot_id]
		var ring: MeshInstance3D = flag.get_node(^"Ring") as MeshInstance3D
		var crystal: MeshInstance3D = flag.get_node(^"Crystal") as MeshInstance3D
		var ring_material: StandardMaterial3D = ring.material_override as StandardMaterial3D
		# Bontago-mp0.3.1: the crystal now draws with
		# shaders/territory/beacon_crystal.gdshader (toon banding + a hard specular
		# facet highlight, owner feedback: "Same for the beacons"), so its
		# colour lives in the "albedo_color" shader parameter instead of
		# StandardMaterial3D's own `.albedo_color` -- see HomeFlag._build()'s
		# own DECISION comment.
		var crystal_material: ShaderMaterial = crystal.material_override as ShaderMaterial
		assert_not_null(crystal_material, "the crystal must draw with the dedicated cel-shading shader.")
		var crystal_albedo: Color = crystal_material.get_shader_parameter(&"albedo_color")
		assert_almost_eq(
			ring_material.albedo_color.r, expected.r, 0.0001,
			"The ring is tinted the slot's own color."
		)
		assert_almost_eq(
			crystal_albedo.r, expected.r, 0.0001,
			"The crystal is tinted the slot's own color."
		)


# --- Beacon size at gameplay scale (Bontago-xtq.41: owner playtest "the ------
# beacons are way too small") -------------------------------------------------

func test_goal_beacon_uses_the_neutral_color_not_a_slot_color() -> void:
	var field: Field = _make_field()
	field.place_flags(2, _slot_colors(), 1)

	var flag: GoalFlag = field.goal_flags()[0]
	var ring: MeshInstance3D = flag.get_node(^"Ring") as MeshInstance3D
	var ring_material: StandardMaterial3D = ring.material_override as StandardMaterial3D
	assert_eq(
		ring_material.albedo_color, flag.beacon_visuals.neutral_color,
		"The goal beacon's ring/crystal use BeaconVisualTuning's neutral color, "
		+ "never a player's slot color (place_flags() never calls set_slot() on it)."
	)

