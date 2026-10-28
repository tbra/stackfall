extends "res://tests/unit/match/match_world_test.gd"
## SPEC 1.5 goal no-build zones: only a disc around each ACTUAL goal beacon blocks building;
## with one beacon that is the map centre, with 2..5 beacons the centre is ordinary ground.

const CENTRE: Vector2 = Vector2.ZERO
## Tiny-map home flags sit at 0.85 * 20 m on the x axis (slot 0 at +x, slot 1 at -x).
const BLOCK_CIRCLE_X: float = 7.0
const BLOCK_CIRCLE_RADIUS: float = 10.0
## A team-0 circle on the exact centre: reaches every beacon of every layout
## (ring radius 0.4 * 20 m = 8 m) and overlaps team 0's home circle (11 m out).
const CENTRE_CIRCLE_RADIUS: float = 12.0
const GOAL_COUNTS: Array[int] = [1, 2, 3, 4, 5]
## Cell centres exactly on the disc edge may round either way; ignore that band.
const EDGE_TOLERANCE: float = 0.01

func _config(mode: int, goal_flags: int, qol: QolExperiments = null) -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.block_timer = 6.0
	config.rng_seed = 51051
	config.game_mode = mode as MatchConfig.GameMode
	config.goal_flag_count = goal_flags
	config.experiments_enabled = true
	config.qol = qol
	return config


func _start_ctf(goal_flags: int = 1, qol: QolExperiments = null) -> void:
	_start(MatchConfig.GameMode.CAPTURE_THE_FLAG, goal_flags, qol)


func _start(mode: int, goal_flags: int, qol: QolExperiments = null) -> void:
	Match.start_match(_config(mode, goal_flags, qol))
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)
	assert_eq(Match.state(), Match.State.PLAYING, "fixture: the match is running")


func _beacons() -> PackedVector2Array:
	return PlayerSlot.goal_positions_for(Match.config.effective_goal_flag_count(), Match.config.map_def())


func _home_circle(slot_id: int) -> InfluenceCircle:
	return InfluenceCircle.new(
		Match.slot(slot_id).home_position, Match._territory_tuning.home_radius, slot_id, slot_id, true, -1
	)


func _block_circle(x: float, team: int) -> InfluenceCircle:
	return InfluenceCircle.new(Vector2(x, 0.0), BLOCK_CIRCLE_RADIUS, team, team, false, 1)


## Team 0 has built a tower toward the centre (a block circle reaching past it,
## connected to its home); team 1 has only its home flag. The centre and its
## whole neighbourhood belong to team 0 and nobody contests them.
func _team0_owns_the_centre() -> void:
	var circles: Array[InfluenceCircle] = [_home_circle(0), _block_circle(BLOCK_CIRCLE_X, 0), _home_circle(1)]
	_feed_raster(circles, 0.1)


## Team 0 owns a disc reaching the centre and every beacon of any goal count;
## team 1 has only its home flag.
func _team0_owns_centre_and_beacons() -> void:
	var circles: Array[InfluenceCircle] = [
		_home_circle(0),
		InfluenceCircle.new(CENTRE, CENTRE_CIRCLE_RADIUS, 0, 0, false, 1),
		_home_circle(1),
	]
	_feed_raster(circles, 0.1)


func _feed_raster(circles: Array[InfluenceCircle], delta: float) -> void:
	var tuning: TerritoryTuning = Match._territory_tuning
	Match.raster().fill_ownership(circles, TerritorySolver.new(tuning).solve(circles), true)
	Match.raster().adopt_fill(Match.raster(), delta, true, false)


func _world(point: Vector2) -> Vector3:
	return _field.to_global(Vector3(point.x, 5.0, point.y))


func _place(slot_id: int, point: Vector2) -> StringName:
	return Match.request_place(slot_id, _world(point), 0, Quaternion.IDENTITY, false)


func _zoned(index: int) -> bool:
	var raster: TerritoryRaster = Match.raster()
	var coords: Vector2i = raster.grid().cell_coords(index)
	return raster.is_goal_zone(coords.x, coords.y)


## Every in-disk cell is zoned exactly when its centre lies within `radius` of
## some beacon: no stray zone anywhere else, no beacon without its full disc.
func _assert_zone_cells_are_exactly_the_beacon_discs(beacons: PackedVector2Array, radius: float, label: String) -> void:
	var raster: TerritoryRaster = Match.raster()
	var grid: CellGrid = raster.grid()
	var stray: int = 0
	var missing: int = 0
	for index: int in grid.in_disk_cells():
		var nearest: float = INF
		for beacon: Vector2 in beacons:
			nearest = minf(nearest, grid.index_center(index).distance_to(beacon))
		var zoned: bool = _zoned(index)
		if zoned and nearest > radius + EDGE_TOLERANCE:
			stray += 1
		elif not zoned and nearest < radius - EDGE_TOLERANCE:
			missing += 1
	assert_eq(stray, 0, "no zone cell farther than %s m from every beacon: %s" % [radius, label])
	assert_eq(missing, 0, "every cell inside a beacon's disc is zoned: %s" % label)


# --- The beacon and its disc ----------------------------------------------------

func test_default_ctf_has_one_centre_beacon_with_a_four_metre_no_build_disc() -> void:
	_start_ctf()
	var beacons: PackedVector2Array = _beacons()
	assert_eq(beacons.size(), 1, "default goal_flag_count 1: a single beacon")
	assert_eq(beacons[0], CENTRE, "...and it stands on the exact middle of the map")
	var tuning: TerritoryTuning = Match._territory_tuning
	assert_eq(tuning.goal_zone_radius, 4.0, "SPEC.md 2.2 provisional goal_zone_radius")

	var raster: TerritoryRaster = Match.raster()
	var zone_cells: int = 0
	for index: int in raster.grid().in_disk_cells():
		if _zoned(index):
			zone_cells += 1
	# pi * 4^2 = 50.3 one-metre cells.
	assert_between(zone_cells, 45, 57, "one disc of ~50 cells (4 m radius), nothing larger")

	for inside: Vector2 in [CENTRE, Vector2(3.5, 0.0), Vector2(0.0, -3.5), Vector2(-2.5, 2.5)]:
		var cell: Vector2i = raster.grid().world_to_cell(inside)
		assert_true(raster.is_goal_zone(cell.x, cell.y), "inside the disc: %s" % inside)
	for outside: Vector2 in [Vector2(4.6, 0.0), Vector2(0.0, 4.6), Vector2(-3.5, 3.5)]:
		var cell: Vector2i = raster.grid().world_to_cell(outside)
		assert_false(raster.is_goal_zone(cell.x, cell.y), "outside the disc: %s" % outside)

	assert_eq(Match._territory._goal_radii.size(), 1)
	assert_eq(Match._territory._goal_radii[0], 4.0, "the replicated/drawn circle is the same 4 m")


# --- The refusal at the middle (one beacon: by design) --------------------------

func test_drop_on_the_centre_is_refused_goal_zone_even_when_the_team_owns_it() -> void:
	_start_ctf()
	_team0_owns_the_centre()
	var cell: Vector2i = Match.raster().grid().world_to_cell(CENTRE)
	assert_eq(Match.raster().team_at(cell.x, cell.y), 0, "fixture: team 0 owns the centre cell")
	assert_false(Match.raster().is_contested(cell.x, cell.y), "fixture: nobody contests it")
	watch_signals(Events)

	for point: Vector2 in [CENTRE, Vector2(3.5, 0.0), Vector2(0.0, 3.5)]:
		assert_eq(
			_place(0, point), PlacementRules.REASON_GOAL_ZONE,
			"%s is inside the beacon's 4 m no-build disc" % point
		)
	assert_signal_emitted_with_parameters(Events, "placement_rejected", [0, PlacementRules.REASON_GOAL_ZONE])
	assert_eq(String(PlacementRules.REASON_GOAL_ZONE), "goal_zone", "what ui/HUD.show_reject() formats: 'Rejected: goal zone'")
	assert_eq(_blocks_root.get_child_count(), 0, "a refused manual drop spawns nothing")
	assert_eq(
		Match.preview_placement(0, _world(CENTRE), 0, Quaternion.IDENTITY), PlacementRules.Result.GOAL_ZONE,
		"the ghost previews the same result (hatched hole tint)"
	)


# --- The QoL claim-radius multiplier -----------------------------------------------

# --- Several goal beacons: zones follow the beacons, nothing else ------------------

func test_every_goal_count_zones_only_the_actual_beacons_in_ctf_and_classic() -> void:
	for mode: int in [MatchConfig.GameMode.CAPTURE_THE_FLAG, MatchConfig.GameMode.CLASSIC]:
		for count: int in GOAL_COUNTS:
			_start(mode, count)
			var beacons: PackedVector2Array = _beacons()
			var radius: float = Match._territory_tuning.goal_zone_radius
			var label: String = "mode %d, %d goal flags" % [mode, count]
			assert_eq(Match.config.goal_flag_count, count, "the lobby's goal count reaches the running config: %s" % label)
			assert_eq(beacons.size(), count, "one beacon per requested goal flag: %s" % label)
			assert_eq(Match._territory._goal_positions, beacons, "the drawn/replicated beacons are the actual ones: %s" % label)
			assert_eq(Match._territory._goal_radii.size(), count, "one drawn circle per beacon: %s" % label)
			_assert_zone_cells_are_exactly_the_beacon_discs(beacons, radius, label)
			var centre_cell: Vector2i = Match.raster().grid().world_to_cell(CENTRE)
			assert_eq(
				Match.raster().is_goal_zone(centre_cell.x, centre_cell.y), count == 1,
				"only a beacon ON the centre zones the centre (default 1 flag does; 2..5 do not): %s" % label
			)
			Match.abort_match()


func test_domination_has_no_beacons_and_no_zones() -> void:
	for count: int in GOAL_COUNTS:
		_start(MatchConfig.GameMode.DOMINATION, count)
		assert_eq(_beacons().size(), 0, "Domination plays without goal flags (goal count %d is ignored)" % count)
		for index: int in Match.raster().grid().in_disk_cells():
			assert_false(_zoned(index), "no zone cell anywhere (goal count %d)" % count)
		Match.abort_match()


func test_with_several_beacons_the_centre_is_placeable_and_each_beacon_keeps_its_zone() -> void:
	for count: int in [2, 3, 4, 5]:
		_start_ctf(count)
		var baseline: int = _blocks_root.get_child_count()
		_team0_owns_centre_and_beacons()
		var centre_cell: Vector2i = Match.raster().grid().world_to_cell(CENTRE)
		assert_eq(Match.raster().team_at(centre_cell.x, centre_cell.y), 0, "fixture: team 0 owns the centre (%d flags)" % count)
		for beacon: Vector2 in _beacons():
			assert_eq(
				_place(0, beacon), PlacementRules.REASON_GOAL_ZONE,
				"%d flags: the beacon at %s still has its own no-build disc" % [count, beacon]
			)
		assert_eq(_blocks_root.get_child_count(), baseline, "refused drops spawn nothing")
		assert_eq(
			Match.preview_placement(0, _world(CENTRE), 0, Quaternion.IDENTITY), PlacementRules.Result.VALID,
			"%d flags: the ghost at the exact centre previews valid" % count
		)
		assert_eq(_place(0, CENTRE), PlacementRules.REASON_OK, "%d flags: dropping on the exact centre is accepted" % count)
		assert_eq(_blocks_root.get_child_count(), baseline + 1, "the accepted drop spawned one block")
		Match.abort_match()

