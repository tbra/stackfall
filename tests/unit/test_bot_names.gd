extends GutTest
## Bontago-1pi.62: the owner's bot-name lists, the pure picking rules, the
## MatchConfig wire round trip and the host's per-seat assignment.

var _tiny_map: MapDef


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_tiny_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	var field: Field = autofree(Field.new())
	field.map_def = _tiny_map
	add_child_autofree(field)
	var blocks_root: Node3D = autofree(Node3D.new())
	add_child_autofree(blocks_root)
	var registry: BlockRegistry = autofree(BlockRegistry.new())
	add_child_autofree(registry)
	Match.register_world(field, registry, blocks_root)


func after_each() -> void:
	Match.set_net_provider(null)
	Match.set_replicator(null)
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _bot_config(player_count: int, ai_count: int) -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = player_count
	config.ai_count = ai_count
	config.hot_seat = false
	return config


func test_owner_lists_are_kept_and_pooled() -> void:
	assert_eq(BotNames.TACTICIANS.size(), 20)
	assert_eq(BotNames.TERRITORY.size(), 18)
	assert_true(BotNames.all_names().has("SirStackALot"))
	assert_eq(BotNames.all_names().size(), 20 + 20 + 19 + 20 + 18)


func test_random_and_themed_names_come_from_the_pool() -> void:
	var pool: PackedStringArray = BotNames.all_names()
	assert_true(pool.has(BotNames.get_random_name()))
	assert_true(BotNames.SMASHERS.has(BotNames.get_themed_name(1)))
	assert_true(pool.has(BotNames.get_themed_name(99)), "an unknown theme falls back to any name")
	assert_true(pool.has(BotNames.get_random_name_with(_rng(1))))


func test_assign_is_deterministic_for_a_seed() -> void:
	var first: PackedStringArray = BotNames.assign(PackedStringArray(), 7, PackedStringArray(), _rng(42))
	var second: PackedStringArray = BotNames.assign(PackedStringArray(), 7, PackedStringArray(), _rng(42))
	assert_eq(first, second)


func test_assign_gives_distinct_names_and_avoids_humans() -> void:
	var humans: PackedStringArray = PackedStringArray(["tetra", "Vertex"])
	for seed_value: int in range(20):
		var names: PackedStringArray = BotNames.assign(PackedStringArray(), 8, humans, _rng(seed_value))
		assert_eq(names.size(), 8)
		var seen: Dictionary = {}
		for bot_name: String in names:
			assert_false(seen.has(bot_name.to_lower()), "duplicate %s" % bot_name)
			seen[bot_name.to_lower()] = true
			assert_false(humans.has(bot_name) or bot_name.to_lower() == "tetra", "collides with a human")


func test_assign_keeps_valid_existing_names_and_replaces_clashes() -> void:
	var kept: PackedStringArray = BotNames.assign(PackedStringArray(["Apex", "Quake"]), 3, PackedStringArray(), _rng(5))
	assert_eq(kept[0], "Apex")
	assert_eq(kept[1], "Quake")
	assert_false(kept[2] in ["Apex", "Quake"])
	var shrunk: PackedStringArray = BotNames.assign(kept, 1, PackedStringArray(), _rng(9))
	assert_eq(shrunk, PackedStringArray(["Apex"]))
	var clash: PackedStringArray = BotNames.assign(PackedStringArray(["Apex"]), 1, PackedStringArray(["Apex"]), _rng(5))
	assert_ne(clash[0], "Apex", "a human now holds that name")


func test_config_round_trips_bot_names_and_rejects_junk() -> void:
	var config: MatchConfig = MatchConfig.new()
	config.bot_names = PackedStringArray(["Apex", "Quake"])
	var copy: MatchConfig = MatchConfig.from_dict(config.to_dict())
	assert_eq(copy.bot_names, config.bot_names)
	assert_true(MatchConfig.from_dict({"bot_names": "Apex"}).bot_names.is_empty())
	assert_true(MatchConfig.from_dict({"bot_names": [1, 2]}).bot_names.is_empty())
	assert_false(MatchConfig.new().to_dict().has("bot_names"), "legacy dict unchanged")


func test_bot_label_falls_back_to_player_n() -> void:
	var names: PackedStringArray = PackedStringArray(["Apex"])
	assert_eq(PlayerNames.bot_label(2, 0, names), "Apex")
	assert_eq(PlayerNames.bot_label(3, 1, names), "Player 4")
	assert_eq(PlayerNames.bot_label(3, -1, names), "Player 4")


func test_host_names_bots_once_and_a_client_build_reads_the_same_names() -> void:
	Match.start_match(_bot_config(4, 3))
	var host_names: Array[String] = []
	for index: int in range(1, 4):
		host_names.append(Match.slot(index).display_name)
		assert_true(BotNames.all_names().has(Match.slot(index).display_name), "bot %d" % index)
	assert_eq(Match.slot(0).is_bot, false)
	assert_eq(Match.config.bot_names.size(), 3)
	var wire: Dictionary = Match.config.to_dict()
	var client_config: MatchConfig = MatchConfig.from_dict(wire)
	assert_eq(client_config.bot_names, Match.config.bot_names, "replicated in the match-start dict")
	# Play again with the same seats: the same names.
	Match.start_match(_bot_config(4, 3))
	for index: int in range(1, 4):
		assert_eq(Match.slot(index).display_name, host_names[index - 1], "stable across matches")
	# A bot seat removed keeps the survivors' names.
	Match.start_match(_bot_config(3, 2))
	assert_eq(Match.slot(1).display_name, host_names[0])
	assert_eq(Match.slot(2).display_name, host_names[1])


func test_match_start_reuses_names_the_lobby_already_assigned() -> void:
	var config: MatchConfig = _bot_config(3, 2)
	config.bot_names = PackedStringArray(["Gizmo", "Titan"])
	Match.start_match(config)
	assert_eq(Match.slot(1).display_name, "Gizmo")
	assert_eq(Match.slot(2).display_name, "Titan")
