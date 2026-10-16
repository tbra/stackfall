extends GutTest
## goal controller derivation (GoalControl) and the goal
## beacon's claimed / contested / neutral visuals.

const MAP_RADIUS: float = 20.0

var _tuning: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")
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


# --- Beacon visuals ---------------------------------------------------------

func _flag() -> GoalFlag:
	var flag: GoalFlag = (load("res://game/flags/GoalFlag.tscn") as PackedScene).instantiate() as GoalFlag
	add_child_autofree(flag)
	return flag


func test_claimed_goal_takes_owner_color_beam_and_boost() -> void:
	var flag: GoalFlag = _flag()
	var team_color: Color = Color(0.2, 0.4, 0.9)
	flag.set_control(1, team_color, PackedColorArray())
	assert_true(flag.beam_visible())
	assert_eq(flag.shown_color(), team_color)
	assert_gt(flag._emission_boost(), flag.beacon_visuals.claimed_emission_boost - 0.001)
	flag.set_control(GoalControl.NEUTRAL, Color.WHITE, PackedColorArray())
	assert_false(flag.beam_visible())
	assert_eq(flag.shown_color(), flag.beacon_visuals.neutral_color)


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
