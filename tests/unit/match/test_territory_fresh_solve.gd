extends GutTest
## Match.fresh_solve_matches_live(): the soak audit that re-solves territory from the
## current blocks with no cache and compares the owner cells with the live raster
## (SOAK_PLAN 6.3). True when they agree, and true when the board is not clean
## (a block still awake or a solve pending), where there is nothing to compare.
## Calling it must not change the raster's content revision or ownership hash.
##
## The false case (a stale cache the fresh solve disagrees with) cannot be reached
## through the public interface without corrupting the raster; the seeded mutant
## that makes the solver cache stale proves it, so no test here asserts false.
## Against the pre-body stub (constant false) every test below fails.

const SETTLE_FRAME_CAP: int = 600
const EXTRA_SOLVE_SECONDS: float = 2.0
const STEP: float = 1.0 / 60.0

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	Net.leave()
	_tiny_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
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
	Match._net_provider = null
	Match.set_replicator(null)
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _config(hole_mode: MatchConfig.HoleMode) -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.hot_seat = false
	config.block_timer = 6.0
	config.rng_seed = 13579
	config.hole_mode = hole_mode
	return config


func _start(hole_mode: MatchConfig.HoleMode) -> void:
	Match.start_match(_config(hole_mode))
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(STEP)


func _place(slot_id: int) -> StringName:
	var home: Vector2 = Match.slot(slot_id).home_position
	var world: Vector3 = _field.to_global(Vector3(home.x, 5.0, home.y))
	return Match.request_place(slot_id, world, 0, Quaternion.IDENTITY, false)


## One real physics step, then one Match step.
func _step() -> void:
	await wait_physics_frames(1)
	Match._process(STEP)


## Steps until every block has settled (capped), then lets the territory solve
## catch up so the board is clean.
func _settle() -> void:
	for _i: int in range(SETTLE_FRAME_CAP):
		await _step()
		if _registry.all_settled():
			break
	assert_true(_registry.all_settled(), "fixture: the blocks settled")
	for _i: int in range(int(ceil(EXTRA_SOLVE_SECONDS / STEP))):
		await _step()


func _play_and_settle(hole_mode: MatchConfig.HoleMode) -> void:
	_start(hole_mode)
	assert_eq(_place(0), PlacementRules.REASON_OK, "fixture: slot 0 placed on its home flag")
	assert_eq(_place(1), PlacementRules.REASON_OK, "fixture: slot 1 placed on its home flag")
	await _settle()


# --- Agreement ----------------------------------------------------------------

func test_an_empty_match_matches() -> void:
	_start(MatchConfig.HoleMode.TEMPORARY)
	assert_true(Match.fresh_solve_matches_live(), "no blocks: the fresh solve agrees with the live raster")


func test_settled_blocks_match_with_holes_off() -> void:
	await _play_and_settle(MatchConfig.HoleMode.OFF)
	assert_true(Match.fresh_solve_matches_live())


func test_settled_blocks_match_with_temporary_holes() -> void:
	await _play_and_settle(MatchConfig.HoleMode.TEMPORARY)
	assert_true(Match.fresh_solve_matches_live())


func test_settled_blocks_match_with_permanent_holes() -> void:
	await _play_and_settle(MatchConfig.HoleMode.PERMANENT)
	assert_true(Match.fresh_solve_matches_live())


func test_settled_blocks_actually_own_territory() -> void:
	# Guards the cases above against passing on an empty raster.
	await _play_and_settle(MatchConfig.HoleMode.OFF)
	assert_gt(Match.territory_share(0) + Match.territory_share(1), 0.0, "fixture: the blocks claimed some ground")


# --- Board not clean ----------------------------------------------------------

func test_a_block_still_falling_is_not_compared() -> void:
	_start(MatchConfig.HoleMode.TEMPORARY)
	assert_eq(_place(0), PlacementRules.REASON_OK, "fixture: placed")
	assert_false(_registry.all_settled(), "fixture: the new block is still awake")
	assert_true(Match.fresh_solve_matches_live(), "nothing to compare while a block is awake")


func test_a_pending_solve_is_not_compared() -> void:
	await _play_and_settle(MatchConfig.HoleMode.TEMPORARY)
	var home: Vector2 = Match.slot(0).home_position
	var world: Vector3 = _field.to_global(Vector3(home.x, 5.0, home.y))
	assert_ne(Match.request_place(0, world, 0, Quaternion.IDENTITY, false), &"", "fixture: a request was answered")
	# Stepping Match without letting physics advance leaves the new block awake
	# and any solve it triggers in flight; every call in between must hold.
	for _i: int in range(10):
		Match._process(STEP)
		assert_true(Match.fresh_solve_matches_live(), "true at every step while the board changes")


# --- Read-only ----------------------------------------------------------------

func test_calling_it_leaves_the_raster_untouched() -> void:
	await _play_and_settle(MatchConfig.HoleMode.TEMPORARY)
	var raster: TerritoryRaster = Match.raster()
	var revision: int = raster.content_revision()
	var hash_before: int = raster.ownership_hash()
	for _i: int in range(3):
		assert_true(Match.fresh_solve_matches_live())
	assert_eq(raster.content_revision(), revision, "content revision unchanged")
	assert_eq(raster.ownership_hash(), hash_before, "ownership hash unchanged")
	assert_same(Match.raster(), raster, "and the raster object is the same one")
