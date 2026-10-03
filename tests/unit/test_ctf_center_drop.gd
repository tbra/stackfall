extends GutTest
## Bontago-1pi.51 (owner playtest 2026-10-03, two players over direct IP, Capture
## the Flag): "we weren't able to drop blocks in the middle of the map". Owner
## follow-up: CTF was also played with several goal beacons, and "the goal
## beacons normal clear zone is enough so no extra clear zone is needed".
##
## The rule these tests pin (SPEC.md 2.2 "Goal no-build zones [OWNER]"): the ONLY
## no-build zones are one TerritoryTuning.goal_zone_radius disc (4 m) around each
## ACTUAL goal beacon. The default match has ONE beacon at the exact map centre
## (PlayerSlot.goal_positions_for(1) -> Vector2.ZERO), so that disc blocks the
## middle; with 2..5 beacons they sit on a ring at 0.4 * field_radius and the
## exact centre is ordinary ground (placeable once a team owns it). Nothing may
## stamp a zone anywhere that has no beacon: not at the centre, not from a
## previous match, not from a lobby config that lost its goal count on the wire.
## They also pin the refusal reasons a player sees at the centre, and that the
## QoL claim-radius multiplier (Bontago-1pi.18.3) never widens the disc.
##
## Fixture mirrors tests/unit/test_sandbox_placement.gd Part 1: tiny 20 m map,
## real Field/Match, default config otherwise (hole_mode TEMPORARY, qol null).
## Ownership around the centre is fabricated by feeding home + block circles to
## the live raster, the way tests/unit/test_qol_experiments.gd fabricates its
## beacon fixtures; nothing ticks Match, so no solve overwrites it.

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

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_tiny_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _tiny_map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)


func after_each() -> void:
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _config(mode: int, goal_flags: int, qol: QolExperiments = null) -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.hot_seat = false
	config.block_timer = 6.0
	config.rng_seed = 51051
	config.game_mode = mode as MatchConfig.GameMode
	config.goal_flag_count = goal_flags
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


## Both teams built toward the middle: their block circles overlap in a lens
## around the centre (the "two players racing for the beacon" situation).
func _both_teams_reach_the_centre(solve_steps: int) -> void:
	var circles: Array[InfluenceCircle] = [
		_home_circle(0), _block_circle(BLOCK_CIRCLE_X, 0), _home_circle(1), _block_circle(-BLOCK_CIRCLE_X, 1)
	]
	for _i: int in range(solve_steps):
		_feed_raster(circles, 0.1)


func _feed_raster(circles: Array[InfluenceCircle], delta: float) -> void:
	var tuning: TerritoryTuning = Match._territory_tuning
	Match.raster().update(circles, TerritorySolver.new(tuning).solve(circles), delta, true, false)


func _world(point: Vector2) -> Vector3:
	return _field.to_global(Vector3(point.x, 5.0, point.y))


func _place(slot_id: int, point: Vector2) -> StringName:
	return Match.request_place(slot_id, _world(point), 0, Quaternion.IDENTITY, false)


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
		var zoned: bool = raster.is_goal_zone_index(index)
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
		if raster.is_goal_zone_index(index):
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


func test_drop_just_outside_the_disc_is_accepted_when_owned() -> void:
	_start_ctf()
	_team0_owns_the_centre()
	assert_eq(
		_place(0, Vector2(4.6, 0.0)), PlacementRules.REASON_OK,
		"4.6 m from the beacon: owned, outside the disc, not contested"
	)
	assert_eq(_blocks_root.get_child_count(), 1)


func test_unowned_neighbourhood_of_the_centre_is_outside_territory_not_goal_zone() -> void:
	_start_ctf()
	# Only the two home flags exist: 17 m from the centre, 6 m home circles.
	assert_eq(
		_place(0, Vector2(6.0, 0.0)), PlacementRules.REASON_OUTSIDE_TERRITORY,
		"before anyone builds toward the middle the area around the disc is simply unowned"
	)
	assert_eq(_place(0, CENTRE), PlacementRules.REASON_GOAL_ZONE, "the disc check runs before ownership")


func test_overlap_lens_beside_the_disc_is_contested_then_a_hole() -> void:
	_start_ctf()
	_both_teams_reach_the_centre(1)
	var lens_point: Vector2 = Vector2(0.0, 5.0)
	assert_eq(
		_place(0, lens_point), PlacementRules.REASON_CONTESTED,
		"both teams' influence covers this point (SPEC.md 2.2 overlap holes, hole_mode TEMPORARY)"
	)
	_both_teams_reach_the_centre(int(ceil(Match._territory_tuning.hole_delay / 0.1)) + 1)
	assert_eq(
		_place(0, lens_point), PlacementRules.REASON_HOLE,
		"after hole_delay the contested cells become a hole"
	)


# --- The QoL claim-radius multiplier -----------------------------------------------

func test_claim_radius_multiplier_does_not_widen_the_no_build_disc() -> void:
	var qol: QolExperiments = QolExperiments.new()
	qol.goal_radius_enabled = true
	qol.goal_radius_multiplier = 4.0
	_start_ctf(1, qol)
	var tuning: TerritoryTuning = Match._territory_tuning
	assert_gt(Match._territory._claim_radius(), tuning.goal_zone_radius, "fixture: the claim radius really is widened")
	assert_eq(Match._territory._goal_radii[0], tuning.goal_zone_radius, "the no-build radius is untouched")
	_team0_owns_the_centre()
	assert_eq(_place(0, Vector2(4.6, 0.0)), PlacementRules.REASON_OK, "4.6 m is still outside the disc with the toggle on")


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
			assert_false(Match.raster().is_goal_zone_index(index), "no zone cell anywhere (goal count %d)" % count)
		Match.abort_match()


func test_goal_count_survives_the_lobby_wire() -> void:
	# net_match_start sends config.to_dict() and a client rebuilds it with from_dict();
	# a lost or clamped goal count there would stamp the centre disc on the client.
	for count: int in GOAL_COUNTS:
		var sent: MatchConfig = _config(MatchConfig.GameMode.CAPTURE_THE_FLAG, count)
		sent.sanitize()
		var received: MatchConfig = MatchConfig.from_dict(sent.to_dict())
		assert_eq(received.goal_flag_count, count, "from_dict keeps goal_flag_count %d" % count)
		assert_eq(received.game_mode, MatchConfig.GameMode.CAPTURE_THE_FLAG, "...and the mode")
		assert_eq(received.effective_goal_flag_count(), count, "...so the effective count is the lobby's")


func test_a_keyframe_replaces_a_stale_centre_zone_on_the_client_mirror() -> void:
	_start_ctf(3)
	var host: TerritoryRaster = Match.raster()
	var mirror: TerritoryRaster = TerritoryRaster.new(host.grid(), Match._territory_tuning)
	mirror.reset()
	mirror.set_goal_zones(PackedVector2Array([CENTRE]), Match._territory_tuning.goal_zone_radius)
	var centre_cell: Vector2i = host.grid().world_to_cell(CENTRE)
	assert_true(mirror.is_goal_zone(centre_cell.x, centre_cell.y), "fixture: the mirror starts with the 1-beacon layout")
	mirror.apply_replicated_state(host.owner_bytes(), host.state_bytes())
	assert_false(mirror.is_goal_zone(centre_cell.x, centre_cell.y), "the host's 3-beacon keyframe clears the centre")
	assert_eq(mirror.state_bytes(), host.state_bytes(), "the mirror's zone bits are the host's, cell for cell")


func test_a_new_match_does_not_inherit_the_previous_matchs_centre_zone() -> void:
	_start_ctf(1)
	var centre_cell: Vector2i = Match.raster().grid().world_to_cell(CENTRE)
	assert_true(Match.raster().is_goal_zone(centre_cell.x, centre_cell.y), "fixture: match 1 zoned the centre")
	Match.abort_match()
	_start_ctf(3)
	centre_cell = Match.raster().grid().world_to_cell(CENTRE)
	assert_false(Match.raster().is_goal_zone(centre_cell.x, centre_cell.y), "match 2 (3 beacons) has no centre zone")
	_assert_zone_cells_are_exactly_the_beacon_discs(_beacons(), Match._territory_tuning.goal_zone_radius, "match 2")


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


func test_with_several_beacons_an_unbuilt_centre_is_outside_territory_never_goal_zone() -> void:
	for count: int in [2, 3, 4, 5]:
		_start_ctf(count)
		assert_eq(
			_place(0, CENTRE), PlacementRules.REASON_OUTSIDE_TERRITORY,
			"%d flags: before anyone's tower reaches the middle the player reads 'outside territory'" % count
		)
		Match.abort_match()


func test_with_several_beacons_where_both_teams_meet_the_centre_is_contested_then_a_hole() -> void:
	_start_ctf(3)
	_both_teams_reach_the_centre(1)
	assert_eq(_place(0, CENTRE), PlacementRules.REASON_CONTESTED, "the lens where both teams' influence meets")
	_both_teams_reach_the_centre(int(ceil(Match._territory_tuning.hole_delay / 0.1)) + 1)
	assert_eq(_place(0, CENTRE), PlacementRules.REASON_HOLE, "...then a hole; never a goal zone")
