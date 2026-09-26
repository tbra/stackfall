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
	var ring: float = FIELD_RADIUS * field.map_def.home_flag_radius_fraction

	assert_almost_eq(first.length(), ring, 0.0001, "Home flags sit at 0.85 * field_radius.")
	assert_almost_eq(second.length(), ring, 0.0001)
	assert_almost_eq(
		absf(first.angle_to(second)), PI, 0.0001, "Two players sit pi apart."
	)


func test_eight_home_flags_are_spaced_evenly() -> void:
	var field: Field = _make_field()
	var ring: float = FIELD_RADIUS * field.map_def.home_flag_radius_fraction
	for slot_id: int in range(8):
		var here: Vector2 = field.home_flag_position(slot_id, 8)
		var next: Vector2 = field.home_flag_position(slot_id + 1, 8)
		assert_almost_eq(here.length(), ring, 0.0001)
		assert_almost_eq(
			absf(here.angle_to(next)), PI / 4.0, 0.0001, "Eight players step by pi/4."
		)


func test_slot_zero_starts_at_plus_x() -> void:
	var field: Field = _make_field()
	var first: Vector2 = field.home_flag_position(0, 5)
	assert_almost_eq(first.y, 0.0, 0.0001)
	assert_gt(first.x, 0.0)


func test_one_goal_flag_is_the_center() -> void:
	var field: Field = _make_field()
	var positions: PackedVector2Array = field.goal_flag_positions(1)
	assert_eq(positions.size(), 1)
	assert_almost_eq(positions[0].length(), 0.0, 0.0001)


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


func test_placing_flags_again_replaces_the_old_ones() -> void:
	var field: Field = _make_field()
	field.place_flags(4, _slot_colors(), 2)
	field.place_flags(2, _slot_colors(), 1)

	assert_eq(field.home_flags().size(), 2)
	assert_eq(field.goal_flags().size(), 1)


# --- Capture ring (spec 2.3) ------------------------------------------------

func test_capture_ring_appears_and_tracks_progress() -> void:
	var field: Field = _make_field()
	field.place_flags(2, _slot_colors(), 2)

	field.set_capture_progress(1, 0.5)
	for flag: GoalFlag in field.goal_flags():
		assert_true(flag.ring_visible(), "Every goal flag shows the capture ring.")
		assert_eq(flag.capture_team(), 1)
		assert_almost_eq(flag.capture_progress(), 0.5, 0.0001)
		assert_not_null(flag.ring_mesh(), "The arc mesh is built.")


func test_capture_ring_hides_when_the_capture_breaks() -> void:
	var field: Field = _make_field()
	field.place_flags(2, _slot_colors(), 1)

	field.set_capture_progress(1, 0.8)
	field.set_capture_progress(-1, 0.0)
	var flag: GoalFlag = field.goal_flags()[0]
	assert_false(flag.ring_visible(), "team_id -1 with progress 0 clears the ring.")
	assert_eq(flag.capture_team(), -1)


func test_capture_ring_grows_with_progress() -> void:
	var field: Field = _make_field()
	field.place_flags(2, _slot_colors(), 1)
	var flag: GoalFlag = field.goal_flags()[0]

	field.set_capture_progress(0, 0.25)
	var quarter: int = flag.ring_mesh().get_faces().size()
	field.set_capture_progress(0, 1.0)
	var full: int = flag.ring_mesh().get_faces().size()
	assert_gt(full, quarter, "A fuller ring is a longer arc.")


func test_events_goal_capture_progress_drives_the_ring() -> void:
	var field: Field = _make_field()
	field.place_flags(2, _slot_colors(), 1)

	Events.goal_capture_progress.emit(1, 0.4)
	var flag: GoalFlag = field.goal_flags()[0]
	assert_eq(flag.capture_team(), 1, "Field listens on the Events bus, not a node path.")
	assert_almost_eq(flag.capture_progress(), 0.4, 0.0001)


# --- Beacon visuals (M7 P8, Bontago-xtq.33) ----------------------------------

func test_home_beacon_has_a_socket_ring_and_crystal() -> void:
	var field: Field = _make_field()
	field.place_flags(2, _slot_colors(), 1)

	var flag: HomeFlag = field.home_flags()[0]
	var socket: Node = flag.get_node(^"Socket")
	var ring: Node = flag.get_node(^"Ring")
	var crystal: Node = flag.get_node(^"Crystal")
	assert_true(socket is MeshInstance3D, "Socket is a mesh.")
	assert_true(ring is MeshInstance3D, "Ring is a mesh.")
	assert_true(crystal is MeshInstance3D, "Crystal is a mesh.")
	assert_not_null((socket as MeshInstance3D).mesh)
	assert_not_null((ring as MeshInstance3D).mesh)
	assert_not_null((crystal as MeshInstance3D).mesh)


func test_goal_beacon_also_has_a_socket_ring_and_crystal() -> void:
	var field: Field = _make_field()
	field.place_flags(2, _slot_colors(), 1)

	var flag: GoalFlag = field.goal_flags()[0]
	assert_not_null(flag.get_node(^"Socket"))
	assert_not_null(flag.get_node(^"Ring"))
	assert_not_null(flag.get_node(^"Crystal"))


func test_home_beacon_ring_and_crystal_follow_set_slots_color() -> void:
	var field: Field = _make_field()
	field.place_flags(4, _slot_colors(), 1)

	for slot_id: int in range(4):
		var flag: HomeFlag = field.home_flags()[slot_id]
		var expected: Color = _slot_colors()[slot_id]
		var ring: MeshInstance3D = flag.get_node(^"Ring") as MeshInstance3D
		var crystal: MeshInstance3D = flag.get_node(^"Crystal") as MeshInstance3D
		var ring_material: StandardMaterial3D = ring.material_override as StandardMaterial3D
		var crystal_material: StandardMaterial3D = crystal.material_override as StandardMaterial3D
		assert_almost_eq(
			ring_material.albedo_color.r, expected.r, 0.0001,
			"The ring is tinted the slot's own color."
		)
		assert_almost_eq(
			crystal_material.albedo_color.r, expected.r, 0.0001,
			"The crystal is tinted the slot's own color."
		)


func test_home_beacon_socket_stays_a_neutral_color_regardless_of_slot() -> void:
	var field: Field = _make_field()
	field.place_flags(2, _slot_colors(), 1)

	var flag: HomeFlag = field.home_flags()[0]
	var socket: MeshInstance3D = flag.get_node(^"Socket") as MeshInstance3D
	var socket_material: StandardMaterial3D = socket.material_override as StandardMaterial3D
	assert_eq(
		socket_material.albedo_color, flag.beacon_visuals.socket_color,
		"The socket never carries an owner's color, only the ring/crystal do."
	)


# --- Beacon size at gameplay scale (Bontago-xtq.41: owner playtest "the ------
# beacons are way too small") -------------------------------------------------

## Guards the xtq.41 size-up against a future re-shrink: a block cell is 1m,
## and docs/M7_ART_DIRECTION.md's mockup (08-cel-shaded-home-beacons.png)
## reads the crystal at roughly two to three cells tall and the ring wider
## than one cell at the real follow-camera distance (config/camera_tuning.tres
## follow_distance 9.0), not the far overview framing earlier screenshots used.
func test_home_beacon_reads_clearly_at_gameplay_scale() -> void:
	var tuning: BeaconVisualTuning = preload("res://config/beacon_visual_tuning.tres")
	const BLOCK_CELL_M: float = 1.0

	assert_gt(
		tuning.crystal_height, BLOCK_CELL_M * 1.5,
		"HomeFlag's crystal must read as at least ~1.5-2 block cells tall."
	)
	assert_lt(
		tuning.crystal_height, BLOCK_CELL_M * 3.5,
		"HomeFlag's crystal must not dwarf a 1m block cell either."
	)
	assert_gt(
		tuning.ring_outer_radius * 2.0, BLOCK_CELL_M,
		"The ring's diameter must read wider than a single block cell."
	)


## GoalFlag.banner_scale() returns goal_scale_factor, so its crystal must stay
## both larger than a HomeFlag's own and within the mockup's cell-count range.
func test_goal_beacon_crystal_stays_larger_but_within_gameplay_scale() -> void:
	var tuning: BeaconVisualTuning = preload("res://config/beacon_visual_tuning.tres")
	var goal_crystal_height: float = tuning.crystal_height * tuning.goal_scale_factor

	assert_gt(
		goal_crystal_height, tuning.crystal_height,
		"The goal beacon's crystal must stay larger than a HomeFlag's own."
	)
	assert_lt(
		goal_crystal_height, 3.5,
		"Even the larger goal variant should stay near the mockup's 2-3 cell crystal."
	)


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
