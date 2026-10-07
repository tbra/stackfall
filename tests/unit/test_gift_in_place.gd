extends GutTest
## Bontago-1pi.85.24 (docs/GIFT_PLAYTEST2_PLAN.md PB): releasing a held Stackfall, Volcano or
## Earthquake activates it in place through MatchGiftActivation: no carrier body, the effect
## starts at the release point, the held gift is consumed once. Fixture from
## test_gift_playtest2_contracts.gd.

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
	Match.set_net_provider(null)
	Match._placement._activation.clear()
	Match.abort_match()
	for child: Node in Match.get_children():
		if child is StackfallRain:
			child.free()
	for child: Node in _field.get_children():
		if child is VolcanoStructure:
			child.free()
	for child: Node in _blocks_root.get_children():
		child.free()
	Match.set_process(true)
	MatchTestReset.clear_world()
	await get_tree().process_frame


func _config() -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.hot_seat = false
	config.block_timer = 6.0
	config.rng_seed = 13579
	return config


func _start() -> void:
	Match.start_match(_config())
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)


func _home_world_position(slot_id: int) -> Vector3:
	var home: Vector2 = Match.slot(slot_id).home_position
	return _field.to_global(Vector3(home.x, 5.0, home.y))


func _queue_special(slot_id: int, special_id: StringName) -> void:
	Match._gifts._ensure_capacity(slot_id)
	Match._gifts._held_specials[slot_id] = special_id
	Match._feed._held_is_gift[slot_id] = true


func _release(slot_id: int, gift_id: StringName) -> StringName:
	_queue_special(slot_id, gift_id)
	return Match.request_place(slot_id, _home_world_position(slot_id), 0, Quaternion.IDENTITY, false)


func _anchor_count() -> int:
	return Match._placement._activation.live_anchor_count()


func _structure() -> VolcanoStructure:
	for child: Node in _field.get_children():
		if child is VolcanoStructure:
			return child as VolcanoStructure
	return null


func _rain() -> StackfallRain:
	for child: Node in Match.get_children():
		if child is StackfallRain:
			return child as StackfallRain
	return null


func test_shipped_defs_activate_in_place_without_arm_delay() -> void:
	for id: String in ["stackfall", "volcano", "earthquake", "propeller", "black_hole"]:
		var def: SpecialDef = SpecialDef.find_by_id(StringName(id))
		assert_not_null(def, id)
		assert_true(def.activates_in_place, id)
		assert_eq(def.arm_delay, 0.0, id)
	assert_false(SpecialDef.find_by_id(&"bomb").activates_in_place)
	var anvil: SpecialDef = SpecialDef.find_by_id(&"anvil")
	assert_false(anvil.activates_in_place, "the anvil is a physical carrier")
	assert_gt(anvil.sky_drop_height_m, 0.0, "the anvil falls from the sky")
	assert_false(SpecialDef.find_by_id(&"rocket").activates_in_place)


func test_volcano_release_spawns_no_block_and_raises_structure_at_release_point() -> void:
	_start()
	watch_signals(Events)
	var seq_before: int = Match.feed_seq(0)
	assert_eq(_release(0, &"volcano"), PlacementRules.REASON_OK)
	assert_eq(_blocks_root.get_child_count(), 0, "no carrier in blocks_parent")
	assert_eq(_registry.tracked_block_count(), 0, "nothing registered")
	assert_eq(Match.held_special(0), &"", "gift consumed")
	assert_eq(Match.feed_seq(0), seq_before + 1, "feed advanced exactly once")
	assert_signal_emit_count(Events, "special_consumed", 1)
	assert_signal_emit_count(Events, "special_triggered", 1)
	var params: Array = get_signal_parameters(Events, "special_triggered", 0)
	assert_eq(params[0], MatchGiftActivation.IN_PLACE_NET_ID)
	assert_eq(params[1], &"volcano")
	var structure: VolcanoStructure = _structure()
	assert_not_null(structure, "structure raised")
	var home: Vector2 = Match.slot(0).home_position
	var at: Vector3 = _field.world_from_disk_local(home, _field.surface_y())
	assert_almost_eq(structure.global_position.x, at.x, 0.01)
	assert_almost_eq(structure.global_position.z, at.z, 0.01)
	assert_eq(_anchor_count(), 0, "instant effect frees its anchor at once")


func test_stackfall_release_spawns_no_block_and_starts_rain_for_the_owner() -> void:
	_start()
	assert_eq(_release(0, &"stackfall"), PlacementRules.REASON_OK)
	assert_eq(_blocks_root.get_child_count(), 0)
	assert_eq(_registry.tracked_block_count(), 0)
	var rain: StackfallRain = _rain()
	assert_not_null(rain, "rain started")
	assert_eq(rain.owner_slot, 0)
	assert_eq(Match.held_special(0), &"")
	assert_eq(_anchor_count(), 0, "anchor freed after the instant effect")


func test_stackfall_seed_differs_between_activations() -> void:
	_start()
	assert_eq(_release(0, &"stackfall"), PlacementRules.REASON_OK)
	var first: StackfallRain = _rain()
	assert_not_null(first)
	var first_seed: int = first._rng.seed
	first.set_physics_process(false)
	first.free()
	assert_eq(_release(0, &"stackfall"), PlacementRules.REASON_OK)
	var second: StackfallRain = _rain()
	assert_not_null(second)
	assert_ne(first_seed, second._rng.seed)


func test_earthquake_release_shakes_without_a_body_and_frees_anchor_after_the_shake() -> void:
	_start()
	assert_eq(_release(0, &"earthquake"), PlacementRules.REASON_OK)
	assert_eq(_blocks_root.get_child_count(), 0, "no carrier on the disc")
	assert_eq(_registry.tracked_block_count(), 0)
	assert_eq(_anchor_count(), 1, "the anchor carries the 4 s shake")
	assert_eq(Match.held_special(0), &"")
	var effect: EarthquakeEffect = SpecialDef.find_by_id(&"earthquake").effect as EarthquakeEffect
	var anchor: Block = null
	for child: Node in Match.get_children():
		if child is Block and child.has_meta(MatchGiftActivation.IN_PLACE_META):
			anchor = child as Block
	assert_not_null(anchor)
	assert_eq(anchor.collision_layer, 0, "anchor does not collide")
	var behavior: SpecialBehavior = null
	for child: Node in anchor.get_children():
		if child is SpecialBehavior:
			behavior = child as SpecialBehavior
	assert_not_null(behavior)
	behavior.set_physics_process(false)
	var ticks: int = int(ceil(effect.disc_force.duration_s * Engine.physics_ticks_per_second)) + 4
	for _i: int in range(ticks):
		behavior.advance(1.0 / Engine.physics_ticks_per_second)
	assert_true(behavior.is_triggered(), "the shake ended")
	await get_tree().process_frame
	assert_eq(_anchor_count(), 0, "anchor freed when the shake completed")


func test_other_gift_still_drops_a_carrier() -> void:
	_start()
	assert_eq(_release(0, &"bomb"), PlacementRules.REASON_OK)
	assert_eq(_blocks_root.get_child_count(), 1, "bomb keeps its falling carrier")
	assert_eq(_anchor_count(), 0)


func test_rejected_release_keeps_the_gift_queued() -> void:
	_start()
	_queue_special(0, &"volcano")
	var far: Vector3 = _field.to_global(Vector3(500.0, 5.0, 500.0))
	var reason: StringName = Match.request_place(0, far, 0, Quaternion.IDENTITY, false)
	assert_ne(reason, PlacementRules.REASON_OK)
	assert_eq(Match.held_special(0), &"volcano", "a refused click keeps the gift")
	assert_null(_structure())
	assert_eq(_anchor_count(), 0)


func test_try_activate_declines_without_the_held_gift() -> void:
	_start()
	var activation: MatchGiftActivation = Match._placement._activation
	var def: SpecialDef = SpecialDef.find_by_id(&"volcano")
	assert_false(activation.try_activate(0, def, Vector2.ZERO), "gift not held")
	assert_eq(_anchor_count(), 0)


func test_clear_frees_live_anchors() -> void:
	_start()
	assert_eq(_release(0, &"earthquake"), PlacementRules.REASON_OK)
	assert_eq(_anchor_count(), 1)
	Match._placement._activation.clear()
	await get_tree().process_frame
	assert_eq(_anchor_count(), 0)

## Review of 1pi.85.24: an abort (or a restart) frees live anchors through the shared
## match reset, not only through the lifetime backstop.
func test_abort_match_frees_live_anchors() -> void:
	_start()
	assert_eq(_release(0, &"earthquake"), PlacementRules.REASON_OK)
	assert_eq(_anchor_count(), 1)
	Match.abort_match()
	await get_tree().process_frame
	assert_eq(_anchor_count(), 0)


## Bontago-1pi.85.44: an ordinary piece (held id &"") must never query the special roster, so
## neither a manual release nor a feed auto-drop may log the "unknown special id" warning.
func test_ordinary_piece_never_queries_specials_on_place_or_auto_drop() -> void:
	_start()
	Match._placement._warned_special_ids.clear()
	assert_eq(Match.held_special(0), &"")
	assert_eq(Match.request_place(0, _home_world_position(0), 0, Quaternion.IDENTITY, false), PlacementRules.REASON_OK)
	assert_eq(Match.request_place(0, _home_world_position(0), 0, Quaternion.IDENTITY, true), PlacementRules.REASON_OK)
	assert_eq(_blocks_root.get_child_count(), 2, "ordinary pieces still place")
	assert_true(Match._placement._warned_special_ids.is_empty(), "no special lookup for an ordinary piece")
