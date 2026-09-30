extends GutTest
## Bontago-470.7: goal controller derivation (GoalControl) and the goal
## beacon's claimed / contested / neutral visuals.

const MAP_RADIUS: float = 20.0

var _tuning: TerritoryTuning = preload("res://config/territory_tuning.tres")
var _grid: CellGrid = null
var _solver: TerritorySolver = null
var _raster: TerritoryRaster = null


func before_each() -> void:
	_grid = CellGrid.new(MAP_RADIUS, 1.0)
	_solver = TerritorySolver.new(_tuning)
	_raster = TerritoryRaster.new(_grid, _tuning)


func _home(x: float, z: float, team: int) -> InfluenceCircle:
	return InfluenceCircle.new(Vector2(x, z), _tuning.home_radius, team, team, true, -1)


func _block(x: float, z: float, radius: float, team: int) -> InfluenceCircle:
	return InfluenceCircle.new(Vector2(x, z), radius, team, team, false, 0)


func _step(circles: Array[InfluenceCircle]) -> void:
	_raster.update(circles, _solver.solve(circles), 0.1, true, false)


func _goal(x: float, z: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x, z)])


func test_unowned_goal_is_neutral() -> void:
	_step([_home(-15.0, 0.0, 0)] as Array[InfluenceCircle])
	assert_eq(GoalControl.owners(_raster, _goal(5.5, 0.5))[0], GoalControl.NEUTRAL)


func test_goal_inside_home_connected_territory_is_claimed() -> void:
	_step([_home(-3.0, 0.0, 1)] as Array[InfluenceCircle])
	assert_eq(GoalControl.owners(_raster, _goal(0.5, 0.5))[0], 1)


func test_goal_under_a_block_cut_off_from_home_is_neutral() -> void:
	var cut: Array[InfluenceCircle] = [_home(-15.0, 0.0, 0), _block(6.0, 0.0, 3.0, 0)]
	_step(cut)
	assert_eq(GoalControl.owners(_raster, _goal(6.5, 0.5))[0], GoalControl.NEUTRAL,
		"A tower not connected to a living home gives no claim.")
	var linked: Array[InfluenceCircle] = [
		_home(-3.0, 0.0, 0), _block(2.0, 0.0, 4.0, 0), _block(6.0, 0.0, 3.0, 0)
	]
	_step(linked)
	assert_eq(GoalControl.owners(_raster, _goal(6.5, 0.5))[0], 0,
		"Connected through the chain, the same goal is claimed.")


func test_goal_in_an_overlap_is_contested() -> void:
	_step([_home(-3.0, 0.0, 0), _home(3.0, 0.0, 1)] as Array[InfluenceCircle])
	assert_eq(GoalControl.owners(_raster, _goal(0.5, 0.5))[0], GoalControl.CONTESTED)
	var teams: PackedInt32Array = GoalControl.nearby_teams(_raster, Vector2(0.5, 0.5), 5.0, 16)
	assert_true(teams.has(0) and teams.has(1), "Both contesting teams are found nearby.")


func test_claim_vanishes_when_the_home_is_gone() -> void:
	_step([_home(-3.0, 0.0, 0)] as Array[InfluenceCircle])
	assert_eq(GoalControl.owners(_raster, _goal(0.5, 0.5))[0], 0)
	# Eliminated home: its circle is no longer collected, only the orphan block is.
	_step([_block(0.0, 0.0, 3.0, 0)] as Array[InfluenceCircle])
	assert_eq(GoalControl.owners(_raster, _goal(0.5, 0.5))[0], GoalControl.NEUTRAL)


func test_client_mirror_derives_the_same_owners() -> void:
	var circles: Array[InfluenceCircle] = [_home(-3.0, 0.0, 0), _home(6.0, 0.0, 1), _home(-14.0, 8.0, 2)]
	_step(circles)
	var goals: PackedVector2Array = PackedVector2Array([
		Vector2(-3.5, 0.5), Vector2(0.5, 0.5), Vector2(6.5, 0.5), Vector2(12.5, 12.5)
	])
	var mirror: TerritoryRaster = TerritoryRaster.new(CellGrid.new(MAP_RADIUS, 1.0), _tuning)
	mirror.apply_replicated_state(_raster.owner_bytes(), _raster.state_bytes())
	var host_owners: PackedInt32Array = GoalControl.owners(_raster, goals)
	assert_eq(GoalControl.owners(mirror, goals), host_owners)
	assert_true(host_owners.has(GoalControl.CONTESTED) or host_owners.has(0))


# --- Beacon visuals ---------------------------------------------------------

func _flag() -> GoalFlag:
	var flag: GoalFlag = (load("res://game/GoalFlag.tscn") as PackedScene).instantiate() as GoalFlag
	add_child_autofree(flag)
	return flag


func test_neutral_goal_keeps_the_neutral_look_and_no_beam() -> void:
	var flag: GoalFlag = _flag()
	assert_false(flag.beam_visible())
	assert_eq(flag.shown_color(), flag.beacon_visuals.neutral_color)
	assert_eq(flag._emission_boost(), 1.0)


func test_claimed_goal_takes_owner_color_beam_and_boost() -> void:
	var flag: GoalFlag = _flag()
	var team_color: Color = Color(0.2, 0.4, 0.9)
	flag.set_control(1, team_color, PackedColorArray())
	assert_true(flag.beam_visible())
	assert_eq(flag.shown_color(), team_color)
	assert_gt(flag._emission_boost(), flag.beacon_visuals.claimed_emission_boost - 0.001)
	assert_gt(flag.flash_amount(), 0.0, "A new claim flashes.")
	flag.set_control(GoalControl.NEUTRAL, Color.WHITE, PackedColorArray())
	assert_false(flag.beam_visible())
	assert_eq(flag.shown_color(), flag.beacon_visuals.neutral_color)


func test_first_neutral_call_does_not_flash_and_claim_change_does() -> void:
	var flag: GoalFlag = _flag()
	flag.set_control(GoalControl.NEUTRAL, Color.WHITE, PackedColorArray())
	assert_eq(flag.flash_amount(), 0.0)
	flag.set_control(0, Color.RED, PackedColorArray())
	flag._process(10.0)
	assert_eq(flag.flash_amount(), 0.0, "The flash decays.")
	flag.set_control(0, Color.RED, PackedColorArray())
	assert_eq(flag.flash_amount(), 0.0, "Same owner again does not re-flash.")
	flag.set_control(1, Color.BLUE, PackedColorArray())
	assert_gt(flag.flash_amount(), 0.0)


func test_contested_goal_flickers_between_the_contesting_colors() -> void:
	var flag: GoalFlag = _flag()
	var pair: PackedColorArray = PackedColorArray([Color.RED, Color.BLUE])
	flag.set_control(GoalControl.CONTESTED, Color.WHITE, pair)
	assert_true(flag.beam_visible())
	var seen: Dictionary = {}
	for i: int in range(40):
		flag._process(0.05)
		seen[flag.shown_color()] = true
	assert_true(seen.has(Color.RED) and seen.has(Color.BLUE), "Both colours appear over time.")


func test_field_pushes_raster_control_onto_goal_beacons() -> void:
	var map_def: MapDef = MapDef.new()
	map_def.field_radius = MAP_RADIUS
	map_def.cell_size = 1.0
	var field: Field = Field.new()
	field.map_def = map_def
	add_child_autofree(field)
	var colors: PackedColorArray = PackedColorArray([Color.RED, Color.BLUE])
	field.place_flags(2, colors, 1)
	var flag: GoalFlag = field.goal_flags()[0]
	_step([_home(0.0, 0.0, 1)] as Array[InfluenceCircle])
	field.refresh_goal_control(_raster)
	assert_eq(flag.control(), 1)
	assert_eq(flag.shown_color(), Color.BLUE)
