extends GutTest
## autoload/match/MatchGifts.gd: spawn rolls, the territory-tick claim/expire
## sweep, the pending-special array, and the three replicated gift events
## (spec 2.6, docs/M4_PLAN.md P1).
##
## Same tiny-map fixture as test_match_flow.gd/test_match_net.gd, and the same
## Match._gifts direct-access convention Match.gd's own header documents for
## _held_shapes/_raster/_solver.

const MatchNetScript := preload("res://net/MatchNet.gd")

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
	Match.abort_match()
	Match.set_process(true)


func _config(player_count: int = 2, gifts_enabled: bool = true) -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = player_count
	config.hot_seat = false
	config.block_timer = 6.0
	config.rng_seed = 4242
	config.gifts_enabled = gifts_enabled
	return config


func _start_playing(config: MatchConfig) -> void:
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)


func _step_territory(times: int = 1) -> void:
	var step: float = 1.0 / Match._territory_tuning.solve_hz
	for _i: int in range(times):
		Match._run_territory_step(step)


## A crate placed exactly on a slot's own home flag is on ground that slot
## already owns and nobody contests -- the same "own home flag reads valid"
## assumption test_match_flow.gd's _home_world_position() relies on.
func _inject_crate(slot_id: int) -> int:
	var home: Vector2 = Match.slot(slot_id).home_position
	var gift_id: int = Match._gifts._next_gift_id
	Match._gifts._next_gift_id += 1
	Match._gifts._crates[gift_id] = {"position": home, "age": 0.0, "node": null}
	return gift_id


func test_crate_on_owned_uncontested_cell_is_claimed_and_grants_special() -> void:
	_start_playing(_config())
	var gift_id: int = _inject_crate(0)
	watch_signals(Events)

	_step_territory()

	assert_false(Match._gifts._crates.has(gift_id), "claimed crate must be removed from the live set")
	assert_eq(Match.held_special(0), MatchGifts.PENDING_SPECIAL_ID)
	assert_signal_emitted_with_parameters(Events, "gift_claimed", [gift_id, 0])


func test_crate_expires_after_life_s_without_being_claimed() -> void:
	_start_playing(_config())
	Match._gifts._gift_config = Match._gifts._gift_config.duplicate() as GiftConfig
	Match._gifts._gift_config.life_s = 1.0
	# Off every home flag and off-center, so nobody's home circle claims it.
	var gift_id: int = Match._gifts._next_gift_id
	Match._gifts._next_gift_id += 1
	Match._gifts._crates[gift_id] = {"position": Vector2(19.0, 19.0), "age": 0.0, "node": null}
	watch_signals(Events)

	_step_territory()
	assert_true(Match._gifts._crates.has(gift_id), "must still be alive before life_s elapses")
	Match._gifts.claim_or_expire_gifts(1.5)

	assert_false(Match._gifts._crates.has(gift_id), "expired crate must be removed from the live set")
	assert_eq(Match.held_special(0), &"", "an expired crate must not grant a special")
	assert_signal_emitted_with_parameters(Events, "gift_expired", [gift_id])


func test_no_spawn_when_gifts_disabled() -> void:
	_start_playing(_config(2, false))
	Match._gifts._gift_config = Match._gifts._gift_config.duplicate() as GiftConfig
	Match._gifts._gift_config.frequency_to_chance_max = 1.0
	Match.config.special_frequency = 100

	Match._gifts.on_feed_block_issued(0)

	assert_true(Match._gifts._crates.is_empty(), "gifts_enabled = false must never spawn a crate")


func test_second_claim_replaces_the_pending_special() -> void:
	_start_playing(_config())
	Match._gifts._ensure_capacity(0)
	Match._gifts._held_specials[0] = &"stale_pending"
	var gift_id: int = _inject_crate(0)

	_step_territory()

	assert_eq(Match.held_special(0), MatchGifts.PENDING_SPECIAL_ID)
	assert_false(Match._gifts._crates.has(gift_id))


func test_reset_clears_crates_and_held_specials() -> void:
	_start_playing(_config())
	_inject_crate(0)
	_inject_crate(1)
	Match._gifts._ensure_capacity(0)
	Match._gifts._held_specials[0] = MatchGifts.PENDING_SPECIAL_ID

	Match.abort_match()

	assert_true(Match._gifts._crates.is_empty())
	assert_eq(Match.held_special(0), &"")


func test_net_mirrors_gift_spawned_claimed_and_expired() -> void:
	_start_playing(_config())
	var net: MatchNetScript = MatchNetScript.new()
	net.set_process(false)
	add_child_autofree(net)
	net.set_providers(FakeNet.client(1), Match)
	watch_signals(Events)

	net.net_match_event(MatchNetScript.EVENT_GIFT_SPAWNED, [7, Vector2(1.0, 2.0)])
	assert_signal_emitted_with_parameters(Events, "gift_spawned", [7, Vector2(1.0, 2.0)])
	assert_true(Match._gifts._crates.has(7))

	net.net_match_event(MatchNetScript.EVENT_GIFT_CLAIMED, [7, 1])
	assert_signal_emitted_with_parameters(Events, "gift_claimed", [7, 1])
	assert_eq(Match.held_special(1), MatchGifts.PENDING_SPECIAL_ID)
	assert_false(Match._gifts._crates.has(7))

	net.net_match_event(MatchNetScript.EVENT_GIFT_SPAWNED, [8, Vector2(3.0, 4.0)])
	net.net_match_event(MatchNetScript.EVENT_GIFT_EXPIRED, [8])
	assert_signal_emitted_with_parameters(Events, "gift_expired", [8])
	assert_false(Match._gifts._crates.has(8))

	net.set_providers(null, null)


## Review fix #2 (Bontago-4fa): outside hot-seat every slot's own feed window
## fires on_feed_block_issued() independently, so an unconditional roll would
## have given a 3-player match ~3 rolls per window. Only the lowest-indexed
## alive slot (0, since all three are alive) actually rolls.
func test_only_the_lowest_alive_slot_rolls_per_window() -> void:
	_start_playing(_config(3))
	# _start_playing() already ran one window (match start) with the default
	# GiftConfig/special_frequency; wipe whatever that produced so only the
	# three calls below are being measured.
	Match._gifts._crates.clear()
	Match._gifts._next_gift_id = 0
	Match._gifts._gift_config = Match._gifts._gift_config.duplicate() as GiftConfig
	Match._gifts._gift_config.frequency_to_chance_max = 1.0
	Match._gifts._gift_config.max_live_crates = 10
	Match.config.special_frequency = 100

	for slot_id: int in range(3):
		Match._gifts.on_feed_block_issued(slot_id)

	assert_eq(Match._gifts._crates.size(), 1, "exactly one roll must happen across all 3 slots' windows")


## Review fix #3a: a client never spawns, claims or expires anything itself --
## it only ever mirrors the three replicated events into visuals.
func test_client_never_spawns_claims_or_expires() -> void:
	_start_playing(_config())
	Match.set_net_provider(FakeNet.client(1))
	Match._gifts._gift_config = Match._gifts._gift_config.duplicate() as GiftConfig
	Match._gifts._gift_config.frequency_to_chance_max = 1.0
	Match.config.special_frequency = 100
	var gift_id: int = _inject_crate(0)

	Match._gifts.on_feed_block_issued(0)
	assert_eq(Match._gifts._crates.size(), 1, "a client must never spawn a crate of its own")

	Match._gifts.claim_or_expire_gifts(1000.0)
	assert_true(Match._gifts._crates.has(gift_id), "a client must never claim or expire a crate itself")

	Match.set_net_provider(null)


## Review fix #3b: EVENT_GIFT_SPAWNED's wire-safety gate (_gift_wire_ok)
## rejects a negative id, a non-finite position and an out-of-disk position;
## EVENT_GIFT_CLAIMED/EVENT_GIFT_EXPIRED with a negative id are ignored too.
func test_gift_wire_rejects_malformed_payloads() -> void:
	_start_playing(_config())
	var net: MatchNetScript = MatchNetScript.new()
	net.set_process(false)
	add_child_autofree(net)
	net.set_providers(FakeNet.client(1), Match)
	watch_signals(Events)

	net.net_match_event(MatchNetScript.EVENT_GIFT_SPAWNED, [-1, Vector2(1.0, 1.0)])
	assert_signal_not_emitted(Events, "gift_spawned")

	net.net_match_event(MatchNetScript.EVENT_GIFT_SPAWNED, [9, Vector2(INF, 0.0)])
	assert_signal_not_emitted(Events, "gift_spawned")
	assert_false(Match._gifts._crates.has(9))

	# field_radius is 20.0 in this fixture's tiny map (before_each).
	net.net_match_event(MatchNetScript.EVENT_GIFT_SPAWNED, [9, Vector2(999.0, 0.0)])
	assert_signal_not_emitted(Events, "gift_spawned")
	assert_false(Match._gifts._crates.has(9))

	net.net_match_event(MatchNetScript.EVENT_GIFT_CLAIMED, [-1, 0])
	assert_signal_not_emitted(Events, "gift_claimed")

	net.net_match_event(MatchNetScript.EVENT_GIFT_EXPIRED, [-1])
	assert_signal_not_emitted(Events, "gift_expired")

	net.set_providers(null, null)


## Review fix #1 regression: a garbage slot_id over the wire must not grow
## _held_specials, and must not apply any special at all.
func test_replicated_claim_with_a_garbage_slot_id_is_ignored() -> void:
	_start_playing(_config())
	var net: MatchNetScript = MatchNetScript.new()
	net.set_process(false)
	add_child_autofree(net)
	net.set_providers(FakeNet.client(1), Match)
	var before_size: int = Match._gifts._held_specials.size()

	net.net_match_event(MatchNetScript.EVENT_GIFT_CLAIMED, [7, 999999999])

	assert_eq(Match._gifts._held_specials.size(), before_size, "a garbage slot_id must never grow _held_specials")

	net.set_providers(null, null)
