extends GutTest
## the owner's bot-name lists, the pure picking rules, the
## MatchConfig wire round trip and the host's per-seat assignment.

var _tiny_map: MapDef


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_tiny_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
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
	Match._net_provider = null
	Match.set_replicator(null)
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _bot_config(player_count: int, ai_count: int) -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = player_count
	config.ai_count = ai_count
	config.hot_seat = false
	return config


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
