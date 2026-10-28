extends GutTest
## The opt-in experiment "gift loads next": a claimed gift replaces the next piece instead of becoming the
## block after next. The default after-next rule itself is asserted in test_gift_queue_after_next.gd; here
## only the experiment switch, the master switch at match start and the wire round trip.

var _field: Field
var _blocks_root: Node3D
var _registry: BlockRegistry
var _map: MapDef


func _start(qol: QolExperiments, experiments_enabled: bool = true) -> void:
	Match.set_process(false)
	Match.abort_match()
	_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_map)
	config.player_count = 2
	config.sandbox = true
	config.block_timer = MatchConfig.BLOCK_TIMER_MIN
	config.rng_seed = 5101
	config.experiments_enabled = experiments_enabled
	config.qol = qol
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)
	Match._feed.set_feed_timer_enabled(true)


func after_each() -> void:
	Match._net_provider = null
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()
	await get_tree().process_frame


func _loads_next() -> QolExperiments:
	return QolExperiments.with_toggles(null, false, false, false, false, true)


func test_default_claim_is_the_block_after_next() -> void:
	_start(QolExperiments.new())
	Match._gifts._queue_claimed_special(0, &"anvil")
	assert_eq(Match.next_special(0), &"")
	assert_eq(Match.after_next_special(0), &"anvil")


func test_loads_next_claim_replaces_the_next_piece() -> void:
	_start(_loads_next())
	var held: BlockShape = Match.held_shape(0)
	Match._gifts._queue_claimed_special(0, &"anvil")
	assert_eq(Match.held_shape(0), held, "the held piece is untouched")
	assert_eq(Match.next_special(0), &"anvil", "the gift is the next piece")
	assert_eq(Match.after_next_special(0), &"", "nothing is staged after next")


func test_loads_next_gift_is_held_after_one_issue() -> void:
	_start(_loads_next())
	Match._gifts._queue_claimed_special(0, &"anvil")
	Match._feed._consume_and_refeed(0, true)
	assert_eq(Match.held_special(0), &"anvil")


func test_master_switch_off_forces_loads_next_back_to_after_next() -> void:
	_start(_loads_next(), false)
	Match._gifts._queue_claimed_special(0, &"anvil")
	assert_eq(Match.next_special(0), &"")
	assert_eq(Match.after_next_special(0), &"anvil", "switch applied at match start")


func test_backlog_experiment_keeps_the_replace_rule() -> void:
	var qol: QolExperiments = QolExperiments.with_toggles(null, false, true, false, false, false)
	assert_false(qol.gift_after_next_in_force())
	assert_false(QolExperiments.with_toggles(null, false, false, false, true, false).gift_after_next_in_force())
	assert_true(QolExperiments.new().gift_after_next_in_force())


func test_round_trip_keeps_the_flag() -> void:
	var back: QolExperiments = QolExperiments.from_dict(_loads_next().to_dict())
	assert_true(back.gift_loads_next)
	assert_false(back.gift_after_next_in_force())
	var off: QolExperiments = QolExperiments.from_dict(QolExperiments.new().to_dict())
	assert_false(off.gift_loads_next)


func test_old_key_is_ignored() -> void:
	var qol: QolExperiments = QolExperiments.from_dict({"gift_queue_after_next": false})
	assert_false(qol.gift_loads_next)
	assert_true(qol.gift_after_next_in_force())
	var both: QolExperiments = QolExperiments.from_dict({"gift_queue_after_next": true, "gift_loads_next": true})
	assert_true(both.gift_loads_next)


func test_wrong_typed_flag_keeps_the_default() -> void:
	assert_false(QolExperiments.from_dict({"gift_loads_next": "yes"}).gift_loads_next)
