extends GutTest
## Owner playtest report (Bontago-1pi.2): "Unclaimed presents should respawn
## in different places when unclaimed." Covers
## autoload/match/MatchGifts._relocate_after_expiry()/_pick_relocation_point():
## an expired (unclaimed) crate is immediately replaced by a fresh one at a
## new valid random location at least GiftConfig.relocate_min_distance_m away
## from the one it replaces, using the same seeded gift-spawn RNG and
## GiftSpawner.pick_spawn_point() location logic _try_spawn() itself uses, so
## replays stay deterministic under a fixed rng_seed. Same tiny-map fixture
## and Match._gifts direct-access convention as tests/unit/test_gift_claim.gd.

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef

## Far from both slots' own home circles (home_flag_radius_fraction * 20 on
## the +/-x axis, home_radius 6.0 -- see config/territory_tuning.tres), well
## inside the disk minus GiftConfig.spawn_edge_margin_m, so it neither gets
## claimed by anyone's territory before life_s elapses nor sits outside
## pick_spawn_point()'s own effective radius.
const _OLD_POSITION: Vector2 = Vector2(0.0, 15.0)


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
	# Same restore convention as test_gift_claim.gd's own after_each: a
	# duplicated _gift_config left behind by an earlier test must never leak
	# into a later one via the Match singleton.
	Match._gifts._gift_config = load("res://config/gift_config.tres") as GiftConfig
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _config(player_count: int = 2) -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = player_count
	config.hot_seat = false
	config.block_timer = 6.0
	config.rng_seed = 4242
	config.gifts_enabled = true
	return config


func _start_playing(config: MatchConfig) -> void:
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)


func _inject_crate_at(position: Vector2) -> int:
	var gift_id: int = Match._gifts._next_gift_id
	Match._gifts._next_gift_id += 1
	Match._gifts._crates[gift_id] = {"position": position, "age": 0.0, "node": null}
	return gift_id


func test_expired_crate_is_replaced_by_a_new_one_at_least_min_distance_away() -> void:
	_start_playing(_config())
	Match._gifts._gift_config = Match._gifts._gift_config.duplicate() as GiftConfig
	Match._gifts._gift_config.life_s = 1.0
	Match._gifts._gift_config.relocate_min_distance_m = 3.0
	var old_gift_id: int = _inject_crate_at(_OLD_POSITION)
	watch_signals(Events)

	Match._gifts.tick_host(1.5)

	assert_false(Match._gifts._crates.has(old_gift_id), "the expired crate must be removed")
	assert_signal_emitted_with_parameters(Events, "gift_expired", [old_gift_id])
	assert_eq(Match._gifts._crates.size(), 1,
		"exactly one replacement must exist -- the relocated crate counts as the live crate")
	assert_signal_emitted(Events, "gift_spawned", "the replacement must replicate through the ordinary spawn event")

	var new_gift_id: int = Match._gifts._crates.keys()[0]
	assert_ne(new_gift_id, old_gift_id, "the replacement must be a new crate, not the same id")
	var new_position: Vector2 = Match._gifts._crates[new_gift_id]["position"]
	assert_eq(int(Match._gifts._crates[new_gift_id]["phase"]), MatchGifts.FALLING,
		"an expired landed gift is replaced by a fresh descending gift")
	assert_ne(new_position, _OLD_POSITION, "the replacement must land somewhere different")
	assert_gte(new_position.distance_to(_OLD_POSITION), Match._gifts._gift_config.relocate_min_distance_m,
		"the replacement must clear GiftConfig.relocate_min_distance_m from the crate it replaces")


func test_relocation_point_pick_is_deterministic_for_the_same_seed() -> void:
	_start_playing(_config())
	var raster: TerritoryRaster = Match.raster()
	var grid: CellGrid = Match.cell_grid()

	Match._gifts._rng.seed = 777
	var point_a: Vector2 = Match._gifts._pick_relocation_point(raster, grid, _OLD_POSITION)
	Match._gifts._rng.seed = 777
	var point_b: Vector2 = Match._gifts._pick_relocation_point(raster, grid, _OLD_POSITION)

	assert_eq(point_a, point_b, "the same rng seed must reproduce the same relocation point")
	assert_false(GiftSpawner.is_no_spawn_point(point_a), "setup: most of this fixture's disk is still open")


## DECISION (autoload/match/MatchGifts.gd, Bontago-1pi.2): when no candidate
## can clear relocate_min_distance_m within spawn_max_attempts retries, this
## falls back to the pre-Bontago-1pi.2 behavior -- the crate simply stays
## expired with no immediate replacement -- rather than forcing a spawn at a
## too-close point.
func test_falls_back_to_no_replacement_when_no_point_can_clear_the_distance() -> void:
	_start_playing(_config())
	Match._gifts._gift_config = Match._gifts._gift_config.duplicate() as GiftConfig
	Match._gifts._gift_config.life_s = 1.0
	# Larger than any possible in-disk distance (field_radius 20 * 2 diameter),
	# so no candidate pick_spawn_point() could ever return satisfies it.
	Match._gifts._gift_config.relocate_min_distance_m = 1000.0
	var old_gift_id: int = _inject_crate_at(_OLD_POSITION)
	watch_signals(Events)

	Match._gifts.tick_host(1.5)

	assert_false(Match._gifts._crates.has(old_gift_id), "the expired crate must still be removed")
	assert_signal_emitted_with_parameters(Events, "gift_expired", [old_gift_id])
	assert_true(Match._gifts._crates.is_empty(), "no replacement must spawn when no point clears the distance")
	assert_signal_not_emitted(Events, "gift_spawned")
