extends GutTest
## autoload/match/MatchGifts.gd: spawn rolls, the territory-tick claim/expire
## sweep, the pending-special array, and the three replicated gift events
## (spec 1.6).
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
	# A previous script in the same process (Sandbox's forced-special drawer) may have left a custom
	# drawer installed; _special_drawer is deliberately not reset per match.
	Match._gifts.set_special_drawer(Match._gifts._default_special_drawer)
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
	# Several tests below install a custom Callable via set_special_drawer();
	# Match is a singleton that outlives any one test, so a lingering custom
	# drawer (whose closure may capture a now-out-of-scope index array) would
	# corrupt every later test's claims. Always restore the shipped default.
	Match._gifts.set_special_drawer(Match._gifts._default_special_drawer)
	# Regression found while validating this change: test_apply_replicated_
	# claim_respects_the_cap (and, less harmfully, a couple of pre-existing
	# tests above) duplicate-and-mutate Match._gifts._gift_config without
	# ever restoring it. Match is a singleton that outlives this whole
	# script, so a max_pending_specials = 1 left behind silently broke
	# test_match_net.gd's gift-claim replication tests (a false cap on a
	# fresh GiftConfig.tres value) the moment they ran later in the same
	# process. Reload the real resource here so every test in this file
	# starts the next one -- in this script or any other -- with the
	# shipped default.
	Match._gifts._gift_config = load("res://config/gifts/gift_config.tres") as GiftConfig
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _config(player_count: int = 2, gifts_enabled: bool = true) -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = player_count
	config.hot_seat = false
	config.block_timer = 6.0
	config.rng_seed = 4242
	config.gifts_enabled = gifts_enabled
	# These tests cover the rule (a claim replaces the next piece); the
	# after-next trial (default on) is in test_gift_queue_after_next.gd.
	config.qol = QolExperiments.new()
	config.qol.gift_queue_after_next = false
	return config


## An id nothing in res://config/gifts/specials/ will ever match, so
## _ensure_special_drawer_installed()'s own `enabled_specials` filter
## (config/match/MatchConfig.gd, autoload/match/MatchGifts.gd:264-282) always
## computes an empty *filtered* roster regardless of how many real specials
## are committed there.
const _NO_SUCH_SPECIAL_ID: StringName = &"__no_special_with_this_id_exists__"


## DECISION (tests/unit/gifts/test_gift_claim.gd, orchestrator decision 4): several
## tests below are about crate-claim mechanics (the FIFO queue, the claim
## cap, a custom drawer's id passing through unchanged) rather than about
## which real SpecialDef gets drawn, and used to rely on
## res://config/gifts/specials/ genuinely holding no .tres to keep
## _ensure_special_drawer_installed() a no-op on the first claim. P5-EARTHQUAKE's
## earthquake.tres ends that; forcing `enabled_specials` to an id nothing on
## disk can match (the loader's own filter seam) keeps those tests exercising
## exactly the same "no real drawer installed" path -- either because the
## default placeholder drawer must still be returned, or because a
## Match._gifts.set_special_drawer() call made before the first claim must
## not be clobbered by the lazy install -- independent of how many real
## specials future packages land.
func _config_with_no_real_specials(player_count: int = 2, gifts_enabled: bool = true) -> MatchConfig:
	var config: MatchConfig = _config(player_count, gifts_enabled)
	config.enabled_specials = [_NO_SUCH_SPECIAL_ID]
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
	_start_playing(_config_with_no_real_specials())
	var gift_id: int = _inject_crate(0)
	watch_signals(Events)

	_step_territory()

	assert_false(Match._gifts._crates.has(gift_id), "claimed crate must be removed from the live set")
	assert_eq(Match.held_special(0), &"", "claim leaves the current held piece ordinary")
	assert_eq((Match._gifts._pending_queues[0] as Array)[0], MatchGifts.PENDING_SPECIAL_ID)
	assert_signal_emitted_with_parameters(Events, "gift_claimed", [gift_id, 0, MatchGifts.PENDING_SPECIAL_ID])


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
	Match._gifts.tick_host(1.5)

	assert_false(Match._gifts._crates.has(gift_id), "expired crate must be removed from the live set")
	assert_eq(Match.held_special(0), &"", "an expired crate must not grant a special")
	assert_signal_emitted_with_parameters(Events, "gift_expired", [gift_id])


func test_no_spawn_when_gifts_disabled() -> void:
	_start_playing(_config(2, false))
	Match._gifts._gift_config = Match._gifts._gift_config.duplicate() as GiftConfig
	Match._gifts._gift_config.frequency_to_chance_max = 1.0
	Match._gifts._gift_config.first_gift_delay_s = 0.0
	Match.config.special_frequency = 100

	Match._gifts.on_feed_block_issued(0)

	assert_true(Match._gifts._crates.is_empty(), "gifts_enabled = false must never spawn a crate")


## Every claim replaces the one next gift, including when older queue caps
## would have rejected it.
func test_latest_claim_replaces_the_next_gift_and_all_crates_are_claimed() -> void:
	_start_playing(_config_with_no_real_specials())
	Match._gifts._gift_config = Match._gifts._gift_config.duplicate() as GiftConfig
	Match._gifts._gift_config.max_pending_specials = 2
	var drawn_ids: Array[StringName] = [&"special_a", &"special_b", &"special_c"]
	var draw_state: Dictionary = {"index": 0}
	Match._gifts.set_special_drawer(func() -> StringName:
		var id: StringName = drawn_ids[int(draw_state["index"])]
		draw_state["index"] = int(draw_state["index"]) + 1
		return id
	)
	watch_signals(Events)

	var gift_id_1: int = _inject_crate(0)
	assert_true(Match._gifts._claim_gift_for_slot(gift_id_1, 0))
	var gift_id_2: int = _inject_crate(0)
	assert_true(Match._gifts._claim_gift_for_slot(gift_id_2, 0))
	var gift_id_3: int = _inject_crate(0)
	assert_true(Match._gifts._claim_gift_for_slot(gift_id_3, 0))

	assert_eq(Match.pending_special_count(0), 1, "only the latest gift occupies the next slot")
	assert_eq((Match._gifts._pending_queues[0] as Array)[0], &"special_c")
	assert_eq(Match.held_special(0), &"", "the current held piece is unchanged")
	assert_false(Match._gifts._crates.has(gift_id_1), "the first claim must consume its crate")
	assert_false(Match._gifts._crates.has(gift_id_2), "the second claim must consume its crate")
	assert_false(Match._gifts._crates.has(gift_id_3), "the latest claim consumes its crate")
	assert_signal_emit_count(Events, "gift_claimed", 3)


## pop_pending_special() dequeues oldest-first and empties to the blank
## sentinel, exactly like held_special()'s own peek.
func test_pop_pending_special_consumes_only_the_held_gift() -> void:
	_start_playing(_config())
	Match._gifts._ensure_capacity(0)
	Match._gifts._held_specials[0] = &"special_a"
	(Match._gifts._pending_queues[0] as Array).append(&"special_b")

	watch_signals(Events)

	assert_eq(Match.pop_pending_special(0), &"special_a")
	assert_eq(Match.pop_pending_special(0), &"", "the next gift is not yet held")
	assert_eq(Match.pop_pending_special(0), &"", "an empty queue pops to the blank sentinel")
	assert_eq(Match.held_special(0), &"")

	# a real pop emits Events.special_consumed with the id it
	# actually popped; popping an already-empty queue (the third call above)
	# must not emit a third, empty-id event.
	assert_signal_emit_count(Events, "special_consumed", 1, "only the held gift is consumed")
	# Explicit index (0/1): assert_signal_emitted_with_parameters() defaults to
	# -1 (the most recent emission), so checking two distinct emissions of the
	# same signal in order needs each call pinned to its own index.
	assert_signal_emitted_with_parameters(Events, "special_consumed", [0, &"special_a"], 0)


## a claimed Glue gift grants charges at once and never
## becomes the held or next piece; an already queued gift survives.
func test_claimed_glue_grants_charges_without_queueing_or_changing_held_piece() -> void:
	_start_playing(_config_with_no_real_specials())
	Match._gifts.set_special_drawer(func() -> StringName: return &"glue")
	Match._gifts._ensure_capacity(0)
	(Match._gifts._pending_queues[0] as Array).append(&"jumping_bean")
	watch_signals(Events)
	var gift_id: int = _inject_crate(0)

	_step_territory()

	assert_eq(Match.glue_drops_left(0), 5)
	assert_eq(Match.held_special(0), &"")
	assert_eq((Match._gifts._pending_queues[0] as Array), [&"jumping_bean"])
	assert_signal_emitted_with_parameters(Events, "gift_claimed", [gift_id, 0, &"glue"])
	for i: int in range(5):
		assert_true(Match.consume_glue_drop(0))
	assert_eq(Match.glue_drops_left(0), 0, "after five blocks glue is spent")


func test_replicated_glue_claim_does_not_queue_on_client() -> void:
	_start_playing(_config())
	Match._gifts.apply_replicated_claim(1, 0, &"glue")
	assert_eq(Match.pending_special_count(0), 0)


## Enabled-specials checklist: ui/lobby/Lobby.gd
## publishes MatchGifts.ALL_DISABLED_SENTINEL as enabled_specials' sole entry
## when the host unchecks every special checkbox. Distinct from
## test_installing_the_real_drawer_with_an_empty_filtered_roster_keeps_the_
## placeholder() above (which already proves a bogus, non-matching id yields
## the same "keep the placeholder" outcome): this pins the actual sentinel
## constant both files share, and _ensure_special_drawer_installed()'s
## explicit `enabled.has(ALL_DISABLED_SENTINEL)` guard specifically (rather
## than relying on the sentinel merely never matching a real SpecialDef.id on
## disk today).
func test_all_disabled_sentinel_never_draws_a_real_special() -> void:
	var config: MatchConfig = _config()
	config.enabled_specials = [MatchGifts.ALL_DISABLED_SENTINEL]
	_start_playing(config)
	assert_false(Match._gifts._roster_ready, "setup: not installed until the first real claim")

	var gift_id: int = _inject_crate(0)
	_step_territory()

	assert_true(Match._gifts._roster_ready, "the install attempt must run exactly once per match")
	assert_eq((Match._gifts._pending_queues[0] as Array)[0], MatchGifts.PENDING_SPECIAL_ID,
		"the all-disabled sentinel must leave the placeholder drawer installed")
	assert_true(Match._gifts._special_roster.is_empty())


## Review fix #2: outside hot-seat every slot's own feed window
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
	Match._gifts._gift_config.first_gift_delay_s = 0.0
	Match._gifts._gift_config.max_live_crates = 10
	Match.config.special_frequency = 100

	for slot_id: int in range(3):
		Match._gifts.on_feed_block_issued(slot_id)

	assert_eq(Match._gifts._crates.size(), 1, "exactly one roll must happen across all 3 slots' windows")


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

	net.net_match_event(MatchNetScript.EVENT_GIFT_CLAIMED, [-1, 0, MatchGifts.PENDING_SPECIAL_ID, &"cube"])
	assert_signal_not_emitted(Events, "gift_claimed")

	net.net_match_event(MatchNetScript.EVENT_GIFT_EXPIRED, [-1])
	assert_signal_not_emitted(Events, "gift_expired")

	net.set_providers(null, null)


## Review fix #1 regression: a garbage slot_id over the wire must not grow
## _pending_queues, and must not apply any special at all.
func test_replicated_claim_with_a_garbage_slot_id_is_ignored() -> void:
	_start_playing(_config())
	var net: MatchNetScript = MatchNetScript.new()
	net.set_process(false)
	add_child_autofree(net)
	net.set_providers(FakeNet.client(1), Match)
	var before_size: int = Match._gifts._pending_queues.size()

	net.net_match_event(MatchNetScript.EVENT_GIFT_CLAIMED, [7, 999999999, MatchGifts.PENDING_SPECIAL_ID, &"cube"])

	assert_eq(Match._gifts._pending_queues.size(), before_size, "a garbage slot_id must never grow _pending_queues")

	net.set_providers(null, null)


# --- debug_queue_special (game/sandbox/Sandbox.gd's F9 hotkey) -------

func test_debug_queue_special_refused_outside_sandbox() -> void:
	_start_playing(_config_with_no_real_specials())
	assert_false(Match.config.sandbox, "fixture: an ordinary match config is not sandbox")
	watch_signals(Events)

	var accepted: bool = Match.debug_queue_special(0, &"anvil")

	assert_false(accepted, "a real (non-sandbox) match must never grant a free special")
	assert_eq(Match.held_special(0), &"", "nothing must be queued")
	assert_signal_not_emitted(Events, "gift_claimed")


## (chosen option "b")
## supersedes the old "shared team queue" contract below: a crate
## claimed in a team's territory is offered to the ONE teammate whose home
## circle is nearest the crate (MatchGifts._resolve_recipient_slot()), never
## to a queue shared by the whole team. _inject_crate(0) places the crate
## exactly on slot 0's own home -- distance 0 -- so slot 0, not its teammate
## slot 2, is the resolved recipient even though both share a team.
func test_only_the_nearest_teammate_holds_the_special_after_a_claim() -> void:
	var config: MatchConfig = _config_with_no_real_specials(4)
	config.team_mode = MatchConfig.TeamMode.TEAMS_2
	_start_playing(config)
	assert_eq(
		Match.config.team_of_slot(0), Match.config.team_of_slot(2),
		"fixture: TEAMS_2 with 4 players makes slots 0 and 2 teammates (interleaved assignment)"
	)
	watch_signals(Events)

	var gift_id: int = _inject_crate(0)
	_step_territory()

	assert_false(Match._gifts._crates.has(gift_id), "claimed crate must be removed from the live set")
	assert_eq((Match._gifts._pending_queues[0] as Array)[0], MatchGifts.PENDING_SPECIAL_ID, "the nearest teammate gets the next gift")
	assert_eq(Match.held_special(2), &"", "a teammate who isn't the resolved recipient holds nothing")
	assert_signal_emitted_with_parameters(Events, "gift_claimed", [gift_id, 0, MatchGifts.PENDING_SPECIAL_ID])


## a forced drawer left by Sandbox must not survive into a
## normal match.
func test_start_match_restores_default_drawer_after_forced_one() -> void:
	Match._gifts.set_special_drawer(func() -> StringName: return &"forced_id")
	_start_playing(_config())
	assert_ne(Match._gifts._special_drawer.call(), &"forced_id", "normal start drops the forced drawer")


## no spawn roll before first_gift_delay_s of host play; the
## skipped roll is not queued, and the usual chance applies afterwards.
func test_no_gift_spawns_before_first_gift_delay() -> void:
	_start_playing(_config())
	Match._gifts._crates.clear()
	Match._gifts._gift_config = Match._gifts._gift_config.duplicate() as GiftConfig
	Match._gifts._gift_config.frequency_to_chance_max = 1.0
	Match._gifts._gift_config.first_gift_delay_s = 10.0
	Match.config.special_frequency = 100
	Match._gifts._play_time_s = 0.0

	for _i: int in range(5):
		Match._gifts.on_feed_block_issued(0)
	assert_true(Match._gifts._crates.is_empty(), "no crate in the start grace")

	Match._gifts._play_time_s = 9.99
	Match._gifts.on_feed_block_issued(0)
	assert_true(Match._gifts._crates.is_empty(), "still inside the grace at 9.99 s")

	Match._gifts.tick_host(0.02)
	Match._gifts.on_feed_block_issued(0)
	assert_eq(Match._gifts._crates.size(), 1, "chance 1.0 spawns once the grace has passed")
