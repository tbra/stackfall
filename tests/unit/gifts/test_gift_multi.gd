extends GutTest
## several gift crates live at once. Pure cap/spacing rules
## plus per-crate claim, expiry and bot targeting through Match._gifts.

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef
var _next_injected_id: int = 1000


func before_each() -> void:
	_next_injected_id = 1000
	Match.set_process(false)
	Match.abort_match()
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
	Match._gifts._gift_config = load("res://config/gifts/gift_config.tres") as GiftConfig
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _start_playing() -> void:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.block_timer = 6.0
	config.rng_seed = 4242
	config.gifts_enabled = true
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)


## A landed crate through the replicated-spawn entry; `age` is spent by ticking the host
## (only valid while no other injected crate is claimable, since the tick also sweeps them).
func _inject(position: Vector2, age: float = 0.0) -> int:
	var gift_id: int = _next_injected_id
	_next_injected_id += 1
	Match._gifts.apply_replicated_spawn(gift_id, position)
	if age > 0.0:
		Match._gifts.tick_host(age)
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


func test_two_crates_live_claim_one_and_expire_other_independently() -> void:
	_start_playing()
	Match._gifts._gift_config = Match._gifts._gift_config.duplicate() as GiftConfig
	Match._gifts._gift_config.life_s = 10.0
	Match._gifts._gift_config.relocate_min_distance_m = 100.0 # no relocation replacement
	var home: Vector2 = Match.slot(0).home_position
	var far: int = _inject(Vector2(0.0, 15.0), 9.5)
	var claimed: int = _inject(home)
	assert_eq(Match.gift_states().size(), 2, "both live together")
	Match._gifts.tick_host(0.001)
	assert_true(Match.gift_state(claimed).is_empty(), "crate in own territory is claimed")
	assert_false(Match.gift_state(far).is_empty(), "the other crate is untouched")
	Match._gifts.tick_host(1.0)
	assert_true(Match.gift_state(far).is_empty(), "second crate expires on its own age")


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
	assert_eq(Match.gift_states().size(), 2, "cap respected, two crates live")
	var states: Array[Dictionary] = Match.gift_states()
	var first: Vector2 = states[0]["position"]
	var second: Vector2 = states[1]["position"]
	assert_gte(first.distance_to(second), cfg.crate_min_separation_m)
