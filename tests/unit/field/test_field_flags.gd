extends GutTest
## FieldFlags (the home and goal flags and the beacon body of a Field), driven
## through its public methods and the Events it listens to.

const FIELD_RADIUS: float = 20.0
const HOLD_S: float = 20.0
const CLAIM_RADIUS: float = 3.0
const WIDE_CLAIM_RADIUS: float = 6.0
const PROGRESS: float = 0.5
const COLORS_A: PackedColorArray = [Color(0.9, 0.25, 0.25), Color(0.25, 0.55, 0.95), Color(0.35, 0.8, 0.4)]
const COLORS_B: PackedColorArray = [Color(1.0, 1.0, 0.0), Color(0.0, 1.0, 1.0), Color(1.0, 0.0, 1.0)]

var _tuning: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")


func _map() -> MapDef:
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_field_flags"
	map_def.field_radius = FIELD_RADIUS
	map_def.cell_size = 2.0
	map_def.territory_res = 32
	return map_def


func _flags() -> FieldFlags:
	var flags: FieldFlags = FieldFlags.new()
	flags.map_def = _map()
	flags.visuals = preload("res://config/territory/territory_visuals.tres")
	flags.tuning = preload("res://config/physics/physics_tuning.tres")
	flags.home_flag_scene = preload("res://game/flags/HomeFlag.tscn")
	flags.goal_flag_scene = preload("res://game/flags/GoalFlag.tscn")
	add_child_autofree(flags)
	return flags


func _placed(slots: int = 2, goals: int = 1, radius: float = CLAIM_RADIUS, hold: float = HOLD_S, counts_up: bool = false) -> FieldFlags:
	var flags: FieldFlags = _flags()
	flags.set_colors(COLORS_A)
	flags.place(slots, goals, radius, hold, counts_up)
	return flags


## A raster where each (x, team) home circle claims the field centre, where the one goal stands.
func _raster(homes: Array[Vector2i]) -> TerritoryRaster:
	var circles: Array[InfluenceCircle] = []
	for home: Vector2i in homes:
		circles.append(InfluenceCircle.new(Vector2(float(home.x), 0.0), _tuning.home_radius, home.y, home.y, true, -1))
	var raster: TerritoryRaster = TerritoryRaster.new(CellGrid.new(FIELD_RADIUS, 1.0), _tuning)
	raster.fill_ownership(circles, TerritorySolver.new(_tuning).solve(circles), true)
	raster.adopt_fill(raster, 0.1, true, false)
	return raster


func _body(flags: FieldFlags) -> AnimatableBody3D:
	return flags.find_child(&"BeaconBody", true, false) as AnimatableBody3D


func _goal(flags: FieldFlags) -> GoalFlag:
	return flags.goal_flags()[0]


func _label(flag: GoalFlag, label_name: StringName) -> Label3D:
	return flag.get_node(NodePath(label_name)) as Label3D


func _ring_size(flag: GoalFlag) -> float:
	return (flag.find_child(&"ClaimRadiusRing", true, false) as MeshInstance3D).mesh.get_aabb().size.x


# --- place and clear --------------------------------------------------------

func test_place_builds_one_home_flag_per_slot_in_owner_colours() -> void:
	var flags: FieldFlags = _placed(3, 0)
	assert_eq(flags.home_flags().size(), 3)
	assert_eq(flags.goal_flags().size(), 0, "no goal count spawns no goal flag")
	for slot_id: int in range(3):
		var flag: HomeFlag = flags.home_flags()[slot_id]
		var local: Vector2 = flags.map_def.home_flag_position(slot_id, 3)
		assert_eq(flag.slot_id(), slot_id)
		assert_eq(flag.color(), COLORS_A[slot_id])
		assert_almost_eq(flag.position.x, local.x, 0.0001)
		assert_almost_eq(flag.position.z, local.y, 0.0001)
		assert_eq(flag.get_parent(), flags)


func test_place_builds_goal_flags_at_the_map_goal_positions() -> void:
	var flags: FieldFlags = _placed(2, 3)
	var expected: PackedVector2Array = flags.map_def.goal_flag_positions(3)
	assert_eq(flags.goal_flags().size(), 3)
	for i: int in range(3):
		assert_almost_eq(flags.goal_flags()[i].position.x, expected[i].x, 0.0001)
		assert_almost_eq(flags.goal_flags()[i].position.z, expected[i].y, 0.0001)


func test_place_with_no_slots_builds_no_home_flags() -> void:
	var flags: FieldFlags = _placed(0, 1)
	assert_eq(flags.home_flags().size(), 0)
	assert_eq(flags.goal_flags().size(), 1)


func test_clear_removes_flags_and_beacon_shapes() -> void:
	var flags: FieldFlags = _placed(2, 1)
	var home: HomeFlag = flags.home_flags()[0]
	var goal: GoalFlag = _goal(flags)
	assert_gt(_body(flags).get_shape_owners().size(), 0, "fixture: beacons carry shapes")
	flags.clear()
	assert_eq(flags.home_flags().size(), 0)
	assert_eq(flags.goal_flags().size(), 0)
	assert_eq(_body(flags).get_shape_owners().size(), 0, "no beacon shape remains")
	await wait_physics_frames(2)
	assert_false(is_instance_valid(home), "the home flag node is freed")
	assert_false(is_instance_valid(goal), "the goal flag node is freed")


# --- the beacon body --------------------------------------------------------

func test_beacon_body_is_a_child_on_the_beacon_layer_with_disk_friction() -> void:
	var flags: FieldFlags = _placed()
	var body: AnimatableBody3D = _body(flags)
	assert_not_null(body, "BeaconBody is found under FieldFlags")
	assert_eq(body.collision_layer, FieldBody.BEACON_COLLISION_LAYER)
	assert_eq(body.collision_mask, 0)
	assert_almost_eq(body.physics_material_override.friction, flags.tuning.disk_friction, 0.0001)


func test_only_home_flags_collide_one_set_of_shapes_each() -> void:
	var flags: FieldFlags = _placed(2, 1)
	var expected: int = 0
	for flag: HomeFlag in flags.home_flags():
		expected += flag.collision_shapes().size()
	assert_gt(expected, 0)
	assert_eq(_body(flags).get_shape_owners().size(), expected)


func test_elimination_removes_only_that_slots_shapes() -> void:
	var flags: FieldFlags = _placed(2, 1)
	var both: int = _body(flags).get_shape_owners().size()
	Events.player_eliminated.emit(1, 1)
	var remaining: int = _body(flags).get_shape_owners().size()
	assert_eq(remaining, both - flags.home_flags()[1].collision_shapes().size(), "slot 1's shapes go")
	assert_gt(remaining, 0, "slot 0 keeps its shapes")
	Events.player_eliminated.emit(1, 1)
	assert_eq(_body(flags).get_shape_owners().size(), remaining, "eliminating again changes nothing")
	Events.player_eliminated.emit(7, 7)
	assert_eq(_body(flags).get_shape_owners().size(), remaining, "an unknown slot changes nothing")


func test_set_sync_switches_the_beacon_body() -> void:
	var flags: FieldFlags = _placed()
	flags.set_sync(false)
	assert_false(_body(flags).sync_to_physics, "the body stops following physics")
	flags.set_sync(true)
	assert_true(_body(flags).sync_to_physics)


# --- goal control and colours ----------------------------------------------

func test_territory_replicated_colours_the_goal_for_its_controller() -> void:
	var flags: FieldFlags = _placed()
	assert_eq(_goal(flags).control(), GoalControl.NEUTRAL, "starts neutral")
	Events.territory_replicated.emit(_raster([Vector2i(-3, 1)]))
	assert_eq(_goal(flags).control(), 1)
	assert_eq(_goal(flags).color(), COLORS_A[1], "the controller's colour")


func test_territory_replicated_marks_an_overlap_contested_and_a_loss_neutral() -> void:
	var flags: FieldFlags = _placed()
	Events.territory_replicated.emit(_raster([Vector2i(-3, 0), Vector2i(3, 1)]))
	assert_eq(_goal(flags).control(), GoalControl.CONTESTED)
	Events.territory_replicated.emit(_raster([]))
	assert_eq(_goal(flags).control(), GoalControl.NEUTRAL)


func test_set_colors_after_place_takes_effect_at_the_next_refresh() -> void:
	var flags: FieldFlags = _placed()
	var raster: TerritoryRaster = _raster([Vector2i(-3, 1)])
	Events.territory_replicated.emit(raster)
	flags.set_colors(COLORS_B)
	assert_eq(_goal(flags).color(), COLORS_A[1], "not immediately")
	Events.territory_replicated.emit(raster)
	assert_eq(_goal(flags).color(), COLORS_B[1], "at the next goal-control refresh")


func test_a_team_without_a_colour_falls_back_to_the_neutral_goal_colour() -> void:
	var flags: FieldFlags = _flags()
	flags.place(2, 1, CLAIM_RADIUS, HOLD_S, false)
	assert_eq(flags.home_flags()[0].color(), flags.visuals.goal_flag_color)


# --- capture progress ------------------------------------------------------

func test_goal_capture_progress_shows_and_clears_the_ring_in_the_team_colour() -> void:
	var flags: FieldFlags = _placed(2, 2)
	Events.goal_capture_progress.emit(1, PROGRESS)
	for goal: GoalFlag in flags.goal_flags():
		var ring: MeshInstance3D = goal.get_node(^"CaptureRing") as MeshInstance3D
		assert_true(ring.visible, "every goal shows the ring")
		assert_eq((ring.material_override as StandardMaterial3D).albedo_color, COLORS_A[1])
	Events.goal_capture_progress.emit(-1, 0.0)
	for goal: GoalFlag in flags.goal_flags():
		assert_false((goal.get_node(^"CaptureRing") as MeshInstance3D).visible, "team -1 clears it")


# --- the goal timer takes its arguments from place() -----------------------

func test_countdown_uses_the_capture_hold_given_to_place() -> void:
	var short: FieldFlags = _placed(2, 1, CLAIM_RADIUS, HOLD_S)
	var long: FieldFlags = _placed(2, 1, CLAIM_RADIUS, HOLD_S * 2.0)
	Events.goal_capture_progress.emit(1, PROGRESS)
	assert_eq(_label(_goal(short), &"TimerLabel").text, "0:10")
	assert_eq(_label(_goal(long), &"TimerLabel").text, "0:20")


func test_no_capture_hold_shows_no_countdown() -> void:
	var flags: FieldFlags = _placed(2, 1, CLAIM_RADIUS, 0.0)
	Events.goal_capture_progress.emit(1, PROGRESS)
	assert_eq(_label(_goal(flags), &"TimerLabel").text, "")


func test_counts_up_gives_a_hold_clock_for_the_controller_only() -> void:
	var up: FieldFlags = _placed(2, 1, CLAIM_RADIUS, HOLD_S, true)
	var down: FieldFlags = _placed(2, 1, CLAIM_RADIUS, HOLD_S, false)
	Events.territory_replicated.emit(_raster([Vector2i(-3, 1)]))
	assert_eq(_label(_goal(up), &"TimerLabel").text, "0:00", "count-up shows the hold of the holder")
	assert_eq(_label(_goal(down), &"TimerLabel").text, "", "a countdown flag shows nothing without a capture")


func test_mode_state_feeds_the_held_count_chip() -> void:
	var flags: FieldFlags = _placed(2, 1, CLAIM_RADIUS, HOLD_S, true)
	Events.mode_state_changed.emit({"mode_id": MatchConfig.GameMode.CAPTURE_THE_FLAG, "extra": {"held_1": 2}})
	Events.territory_replicated.emit(_raster([Vector2i(-3, 1)]))
	assert_eq(_label(_goal(flags), &"MultiplierLabel").text, "x2")


func test_claim_ring_uses_the_zone_radius_given_to_place() -> void:
	var narrow: FieldFlags = _placed(2, 1, CLAIM_RADIUS)
	var wide: FieldFlags = _placed(2, 1, WIDE_CLAIM_RADIUS)
	assert_gt(_ring_size(_goal(narrow)), CLAIM_RADIUS * 2.0)
	assert_gt(_ring_size(_goal(wide)), WIDE_CLAIM_RADIUS * 2.0)
	assert_gt(_ring_size(_goal(wide)), _ring_size(_goal(narrow)), "the larger radius draws the larger zone")


func test_no_zone_radius_draws_no_claim_ring() -> void:
	var flags: FieldFlags = _placed(2, 1, 0.0)
	assert_null(_goal(flags).find_child(&"ClaimRadiusRing", true, false))
