extends GutTest
## Claim order through the public path (spec 1.6): a crate is placed with
## Match.apply_replicated_gift_spawned / apply_replicated_gift_flight, claimed by
## Match._physics_process, and observed through Events and Match getters. The crate
## is freed before Events.gift_claimed fires (GiftCrate listens to that signal), and
## the claim names the nearest living teammate and the drawn special.

class CursorProvider:
	extends RefCounted
	var poses: Dictionary = {}
	func cursor_for_slot(slot_id: int) -> Dictionary:
		return poses.get(slot_id, {})


const DRAWN_ID: StringName = &"special_drawn_for_order_test"
const TICK: float = 1.0 / 60.0
const FIRST_GIFT_ID: int = 9000
## Off every home circle, so only an air touch can claim a crate here.
const OPEN_GROUND: Vector2 = Vector2(0.0, 15.0)

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _map: MapDef
## One entry per received gift_claimed: {"gift_id", "slot", "special", "crate_gone"}.
var _claims: Array[Dictionary] = []


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	Match._gifts.set_special_drawer(Match._gifts._default_special_drawer)
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
	_claims.clear()
	Events.gift_claimed.connect(_on_gift_claimed)


func after_each() -> void:
	if Events.gift_claimed.is_connected(_on_gift_claimed):
		Events.gift_claimed.disconnect(_on_gift_claimed)
	Match.set_replicator(null)
	Match._gifts.set_special_drawer(Match._gifts._default_special_drawer)
	Match._gifts._gift_config = load("res://config/gifts/gift_config.tres") as GiftConfig
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _on_gift_claimed(gift_id: int, slot_id: int, special_id: StringName) -> void:
	_claims.append({"gift_id": gift_id, "slot": slot_id, "special": special_id,
		"crate_gone": Match.gift_state(gift_id).is_empty()})


## teams: slot_team_ids for a TEAMS_2 match, or empty for free-for-all.
func _start(player_count: int, team_ids: PackedInt32Array = PackedInt32Array()) -> void:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_map)
	config.player_count = player_count
	config.block_timer = 6.0
	config.rng_seed = 4242
	config.gifts_enabled = true
	config.special_frequency = 0
	# Forces an id no committed special matches, so the installed drawer below is not replaced.
	config.enabled_specials = [&"__no_special_with_this_id_exists__"]
	config.experiments_enabled = true
	config.qol = QolExperiments.new()
	config.qol.gift_loads_next = true
	if not team_ids.is_empty():
		config.team_mode = MatchConfig.TeamMode.TEAMS_2
		config.slot_team_ids = team_ids
		config.team_numbers = PackedInt32Array([1, 2])
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(TICK)
	Match._gifts.set_special_drawer(func() -> StringName: return DRAWN_ID)


func _tick(times: int = 1) -> void:
	for _i: int in range(times):
		Match._physics_process(TICK)


func _land_crate(gift_id: int, point: Vector2) -> void:
	Match.apply_replicated_gift_spawned(gift_id, point)


func test_landed_claim_frees_the_crate_before_gift_claimed_fires() -> void:
	_start(2)
	_land_crate(FIRST_GIFT_ID, Match.slot(0).home_position)
	assert_false(Match.gift_state(FIRST_GIFT_ID).is_empty(), "fixture: the crate is live before the tick")

	_tick()

	assert_eq(_claims.size(), 1, "exactly one claim")
	assert_true(_claims[0]["crate_gone"], "gift_state is already empty when gift_claimed is received")
	assert_true(Match.gift_state(FIRST_GIFT_ID).is_empty())
	assert_true(Match.gift_states().is_empty())


func test_landed_claim_reports_gift_slot_and_drawn_special_and_queues_it() -> void:
	_start(2)
	_land_crate(FIRST_GIFT_ID, Match.slot(1).home_position)

	_tick()

	assert_eq(_claims.size(), 1)
	assert_eq(_claims[0]["gift_id"], FIRST_GIFT_ID)
	assert_eq(_claims[0]["slot"], 1, "the owner of the ground receives it")
	assert_eq(_claims[0]["special"], DRAWN_ID)
	assert_eq(Match.next_special(1), DRAWN_ID, "the claimed special is the next gift")
	assert_eq(Match.held_special(1), &"", "the current piece is unchanged")
	assert_eq(Match.next_special(0), &"", "the other slot is untouched")


func test_a_claimed_crate_is_not_claimed_again_on_later_ticks() -> void:
	_start(2)
	_land_crate(FIRST_GIFT_ID, Match.slot(0).home_position)

	_tick(5)

	assert_eq(_claims.size(), 1)


func test_nearest_living_teammate_receives_the_claim() -> void:
	# Slots 1 and 2 share team 0; the crate sits on slot 2's home, so slot 2 (not the lowest id) wins.
	_start(4, PackedInt32Array([1, 0, 0, 1]))
	assert_eq(Match.team_of(1), Match.team_of(2), "fixture: slots 1 and 2 are teammates")
	_land_crate(FIRST_GIFT_ID, Match.slot(2).home_position)

	_tick()

	assert_eq(_claims.size(), 1)
	assert_eq(_claims[0]["slot"], 2)
	assert_eq(_claims[0]["special"], DRAWN_ID)
	assert_true(_claims[0]["crate_gone"])
	assert_eq(Match.next_special(2), DRAWN_ID)
	assert_eq(Match.next_special(1), &"", "the farther teammate gets nothing")


func test_team_with_no_living_teammate_leaves_the_crate_and_emits_nothing() -> void:
	_start(4, PackedInt32Array([1, 0, 0, 1]))
	var spot: Vector2 = Match.slot(1).home_position
	_land_crate(FIRST_GIFT_ID, spot)
	# Kill the whole team after the ground was claimed: the crate still sits on its territory.
	Match.slot(1).home_flag_alive = false
	Match.slot(2).home_flag_alive = false

	_tick()

	assert_true(_claims.is_empty(), "no claim event without a living teammate")
	assert_false(Match.gift_state(FIRST_GIFT_ID).is_empty(), "the crate is left untouched")
	assert_eq(Match.next_special(1), &"")
	assert_eq(Match.next_special(2), &"")


func test_air_touch_claim_has_the_same_order_as_a_landed_claim() -> void:
	_start(2)
	var origin: Vector3 = Match._gifts._world_at(OPEN_GROUND, 12.0)
	Match.apply_replicated_gift_flight(FIRST_GIFT_ID, origin, Match._gifts._world_at(OPEN_GROUND, 0.3))
	assert_eq(int(Match.gift_state(FIRST_GIFT_ID)["phase"]), MatchGifts.FALLING, "fixture: the crate is airborne")
	var shape: BlockShape = Match.held_shape(0)
	var cell: Vector3i = shape.cells[0]
	var cube: float = (load("res://config/physics/physics_tuning.tres") as PhysicsTuning).cube_size
	var crate_now: Vector3 = Match.gift_state(FIRST_GIFT_ID)["origin"]
	var provider: CursorProvider = CursorProvider.new()
	provider.poses[0] = {"origin": crate_now - (Vector3(cell) - shape.bottom_center()) * cube,
		"orientation_index": 0, "free_quat": Quaternion.IDENTITY, "age": 0.0}
	Match.set_replicator(provider)

	_tick()

	assert_eq(_claims.size(), 1, "an air touch claims once")
	assert_true(_claims[0]["crate_gone"], "crate freed before gift_claimed, as for a landed claim")
	assert_eq(_claims[0]["gift_id"], FIRST_GIFT_ID)
	assert_eq(_claims[0]["slot"], 0)
	assert_eq(_claims[0]["special"], DRAWN_ID)
	assert_eq(Match.next_special(0), DRAWN_ID)
	assert_true(Match.gift_states().is_empty())
