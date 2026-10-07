extends GutTest
## Bontago-1pi.85.58: several gift crates live at once. Pure cap/spacing rules
## plus per-crate claim, expiry and bot targeting through Match._gifts.

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
	Match._gifts._gift_config = load("res://config/gift_config.tres") as GiftConfig
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _start_playing() -> void:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.hot_seat = false
	config.block_timer = 6.0
	config.rng_seed = 4242
	config.gifts_enabled = true
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)


func _inject(position: Vector2, age: float = 0.0) -> int:
	var gift_id: int = Match._gifts._next_gift_id
	Match._gifts._next_gift_id += 1
	Match._gifts._crates[gift_id] = {"position": position, "age": age, "node": null}
	return gift_id


func test_live_cap_scales_with_players_and_clamps() -> void:
	var cfg: GiftConfig = GiftConfig.new()
	cfg.max_live_crates = 4
	cfg.players_per_crate = 2
	assert_eq(GiftSpawner.live_cap(cfg, 1), 1)
	assert_eq(GiftSpawner.live_cap(cfg, 2), 1)
	assert_eq(GiftSpawner.live_cap(cfg, 3), 2)
	assert_eq(GiftSpawner.live_cap(cfg, 8), 4)
	cfg.max_live_crates = 2
	assert_eq(GiftSpawner.live_cap(cfg, 8), 2, "ceiling wins")
	assert_eq(GiftSpawner.live_cap(cfg, 0), 2, "unknown players -> ceiling")


func test_should_spawn_respects_scaled_cap() -> void:
	var cfg: GiftConfig = GiftConfig.new()
	cfg.frequency_to_chance_max = 1.0
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	assert_true(GiftSpawner.should_spawn(cfg, 100.0, 1, rng, 4), "4 players allow a second crate")
	assert_false(GiftSpawner.should_spawn(cfg, 100.0, 2, rng, 4), "but not a third")


func test_two_crates_live_claim_one_and_expire_other_independently() -> void:
	_start_playing()
	Match._gifts._gift_config = Match._gifts._gift_config.duplicate() as GiftConfig
	Match._gifts._gift_config.life_s = 10.0
	Match._gifts._gift_config.relocate_min_distance_m = 100.0 # no relocation replacement
	var home: Vector2 = Match.slot(0).home_position
	var claimed: int = _inject(home)
	var far: int = _inject(Vector2(0.0, 15.0), 9.5)
	assert_eq(Match.gift_states().size(), 2, "both live together")
	Match._gifts.claim_or_expire_gifts(0.0)
	assert_false(Match._gifts._crates.has(claimed), "crate in own territory is claimed")
	assert_true(Match._gifts._crates.has(far), "the other crate is untouched")
	Match._gifts.tick_host(1.0)
	assert_false(Match._gifts._crates.has(far), "second crate expires on its own age")


func test_crates_expire_independently() -> void:
	_start_playing()
	Match._gifts._gift_config = Match._gifts._gift_config.duplicate() as GiftConfig
	Match._gifts._gift_config.life_s = 10.0
	Match._gifts._gift_config.relocate_min_distance_m = 100.0
	var old: int = _inject(Vector2(0.0, 15.0), 9.5)
	var young: int = _inject(Vector2(0.0, -15.0), 0.0)
	Match._gifts.tick_host(1.0)
	assert_false(Match._gifts._crates.has(old))
	assert_true(Match._gifts._crates.has(young))


func test_try_spawn_fills_up_to_cap_and_keeps_separation() -> void:
	_start_playing()
	Match._gifts._gift_config = Match._gifts._gift_config.duplicate() as GiftConfig
	var cfg: GiftConfig = Match._gifts._gift_config
	cfg.frequency_to_chance_max = 1.0
	cfg.max_live_crates = 4
	cfg.players_per_crate = 1 # 2 players -> cap 2
	Match.config.special_frequency = 100
	for _i: int in range(6):
		Match._gifts._try_spawn()
	assert_eq(Match._gifts._crates.size(), 2, "cap respected, two crates live")
	var positions: Array[Vector2] = Match._gifts._live_positions()
	assert_gte(positions[0].distance_to(positions[1]), cfg.crate_min_separation_m)


func test_bot_targets_consider_all_gifts() -> void:
	_start_playing()
	var a: int = _inject(Vector2(0.0, 15.0))
	var b: int = _inject(Vector2(0.0, -15.0))
	Match._gifts._crates[a]["phase"] = MatchGifts.LANDED
	Match._gifts._crates[b]["phase"] = MatchGifts.LANDED
	var ids: Array[int] = []
	for state: Dictionary in Match.gift_states():
		ids.append(int(state["id"]))
	assert_eq(ids, [a, b] as Array[int], "bots iterate gift_states(): every live crate")
