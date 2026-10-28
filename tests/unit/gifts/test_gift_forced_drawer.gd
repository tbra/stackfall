extends GutTest
## MatchGifts.set_special_drawer(): a drawer installed before a match's first
## crate claim (the sandbox's forced special) is what the claim draws, not
## replaced by the lazy weighted install; restoring brings the weighted draw back.

const FORCED_ID: StringName = &"forced_id"

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef


func before_each() -> void:
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
	Match.restore_default_special_drawer()
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _start_playing() -> void:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.rng_seed = 4242
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)


## Claims one crate on slot 0's home flag and returns the id it drew.
func _claim_drawn_id(gift_id: int) -> StringName:
	var drawn: Array[StringName] = []
	var on_claim: Callable = func(_gift: int, _slot: int, special_id: StringName) -> void:
		drawn.append(special_id)
	Events.gift_claimed.connect(on_claim)
	Match._gifts.apply_replicated_spawn(gift_id, Match.slot(0).home_position)
	var step: float = 1.0 / Match._territory_tuning.solve_hz
	Match._territory._run_territory_step(step)
	Match._gifts.tick_host(step)
	Events.gift_claimed.disconnect(on_claim)
	return drawn[0] if not drawn.is_empty() else &""


func test_forced_drawer_survives_the_first_claim_with_the_full_roster() -> void:
	_start_playing()
	Match.set_special_drawer(func() -> StringName: return FORCED_ID)
	assert_eq(_claim_drawn_id(2000), FORCED_ID)
	assert_eq(_claim_drawn_id(2001), FORCED_ID, "and the second claim")


func test_restore_default_brings_back_the_weighted_draw() -> void:
	_start_playing()
	Match.set_special_drawer(func() -> StringName: return FORCED_ID)
	Match.restore_default_special_drawer()
	var drawn: StringName = _claim_drawn_id(2000)
	assert_ne(drawn, FORCED_ID)
	assert_ne(drawn, MatchGifts.PENDING_SPECIAL_ID, "the weighted roster draw is installed")


func test_restore_default_with_no_special_enabled_drops_the_forced_drawer() -> void:
	_start_playing()
	Match.config.enabled_specials = [MatchGifts.ALL_DISABLED_SENTINEL]
	Match.set_special_drawer(func() -> StringName: return FORCED_ID)
	Match.restore_default_special_drawer()
	assert_eq(_claim_drawn_id(2000), MatchGifts.PENDING_SPECIAL_ID)
