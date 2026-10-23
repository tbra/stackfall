extends GutTest
## Match.debug_queue_special's config gate: a sandbox match and a scripted_gifts match
## (the tutorial) may force a special; a config with both flags false is refused
## (pinned in test_gift_claim.gd), and an invalid slot is refused either way.

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
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _config(sandbox: bool, scripted_gifts: bool) -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.block_timer = 6.0
	config.rng_seed = 4242
	config.gifts_enabled = true
	config.sandbox = sandbox
	config.scripted_gifts = scripted_gifts
	return config


func _start_playing(config: MatchConfig) -> void:
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)


func test_sandbox_config_accepts_a_forced_special() -> void:
	_start_playing(_config(true, false))
	watch_signals(Events)

	assert_true(Match.debug_queue_special(0, &"anvil"))
	assert_eq(Match.pending_special_count(0), 1, "the special is the next gift")
	assert_signal_emitted(Events, "gift_claimed")


func test_scripted_gifts_config_accepts_a_forced_special() -> void:
	_start_playing(_config(false, true))
	assert_false(Match.config.sandbox, "fixture: the tutorial shape is not a sandbox")
	watch_signals(Events)

	assert_true(Match.debug_queue_special(0, &"anvil"), "the tutorial can force its special")
	assert_eq(Match.pending_special_count(0), 1, "the special is the next gift")
	assert_signal_emitted(Events, "gift_claimed")


func test_scripted_gifts_config_refuses_an_invalid_slot() -> void:
	_start_playing(_config(false, true))
	watch_signals(Events)

	assert_false(Match.debug_queue_special(-1, &"anvil"))
	assert_false(Match.debug_queue_special(Match.slot_count(), &"anvil"))
	assert_signal_not_emitted(Events, "gift_claimed")


func test_sandbox_config_refuses_an_invalid_slot() -> void:
	_start_playing(_config(true, false))
	watch_signals(Events)

	assert_false(Match.debug_queue_special(-1, &"anvil"))
	assert_false(Match.debug_queue_special(Match.slot_count(), &"anvil"))
	assert_signal_not_emitted(Events, "gift_claimed")
