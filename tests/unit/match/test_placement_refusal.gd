extends "res://tests/unit/match/match_world_test.gd"
## autoload/match/MatchPlacement.gd's request_place(): a manual (auto_drop ==
## false) release outside the placing player's own territory (spec 1.4's
## contract).

const MatchNetScript := preload("res://net/MatchNet.gd")

func after_each() -> void:
	Match.set_net_provider(null)
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _config(player_count: int = 2) -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	# Script swap first: Object.set_script() resets script-level state to the
	# new script's declared defaults (test_match_flow.gd's own
	# _tiny_map_config() DECISION has the full story).
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = player_count
	config.hot_seat = false
	config.block_timer = 6.0
	config.rng_seed = 24680
	# Old gift rule (a claim replaces the next piece); the after-next trial is in test_gift_queue_after_next.gd.
	config.qol = QolExperiments.new()
	config.qol.gift_queue_after_next = false
	return config


func test_manual_drop_outside_territory_is_refused_and_the_block_stays_held() -> void:
	Match.start_match(_config())
	_run_countdown()
	var slot_id: int = 0
	var seq_before: int = Match.feed_seq(slot_id)
	var shape_before: BlockShape = Match.held_shape(slot_id)
	watch_signals(Events)

	# Slot 1's home is outside slot 0's own territory.
	var reason: StringName = Match.request_place(
		slot_id, _home_world_position(1), 0, Quaternion.IDENTITY, false
	)

	assert_eq(reason, PlacementRules.REASON_OUTSIDE_TERRITORY)
	assert_eq(
		_blocks_root.get_child_count(), 0,
		"A refused manual drop must not spawn a block, burned or otherwise."
	)
	assert_eq(Match.feed_seq(slot_id), seq_before, "the piece must not be consumed")
	assert_eq(Match.held_shape(slot_id), shape_before, "the player must still be holding the exact same piece")
	assert_eq(get_signal_emit_count(Events, "placement_rejected"), 1)
	assert_signal_emitted_with_parameters(Events, "placement_rejected", [slot_id, PlacementRules.REASON_OUTSIDE_TERRITORY])

	# The refusal must not have jammed anything: a second, valid, drop still
	# works right afterwards.
	var second_reason: StringName = Match.request_place(
		slot_id, _home_world_position(slot_id), 0, Quaternion.IDENTITY, false
	)
	assert_eq(second_reason, PlacementRules.REASON_OK)
	assert_eq(_blocks_root.get_child_count(), 1)


func test_manual_drop_in_a_goal_flags_no_build_zone_is_refused_too() -> void:
	Match.start_match(_config())
	_run_countdown()
	var center_world: Vector3 = _field.to_global(Vector3(0.0, 5.0, 0.0))
	var seq_before: int = Match.feed_seq(0)

	var reason: StringName = Match.request_place(0, center_world, 0, Quaternion.IDENTITY, false)

	assert_eq(reason, PlacementRules.REASON_GOAL_ZONE)
	assert_eq(_blocks_root.get_child_count(), 0)
	assert_eq(Match.feed_seq(0), seq_before, "the piece must not be consumed")


# --- Outcome 2: an auto-drop outside the zone relocates and says where ------

func test_auto_drop_outside_the_zone_relocates_and_emits_placement_relocated() -> void:
	Match.start_match(_config())
	_run_countdown()
	var slot_id: int = 0
	var home: Vector2 = Match.slot(slot_id).home_position
	var tuning: TerritoryTuning = load("res://config/territory/territory_tuning.tres")
	# Just past the home circle's own radius, so validate_point() refuses the
	# raw point but a valid one sits only a couple of metres away -- well
	# inside auto_drop_search_max_radius (config/territory/territory_tuning.tres: step
	# 1.0, max 12.0).
	var desired_local: Vector2 = home + Vector2(tuning.home_radius + 1.5, 0.0)
	var desired_world: Vector3 = _field.to_global(Vector3(desired_local.x, 5.0, desired_local.y))
	watch_signals(Events)

	var reason: StringName = Match.request_place(slot_id, desired_world, 0, Quaternion.IDENTITY, true)

	assert_eq(reason, PlacementRules.REASON_OK, "a successfully relocated auto-drop still reports OK.")
	assert_eq(_blocks_root.get_child_count(), 1)
	assert_signal_emitted(Events, "placement_relocated")
	var params: Array = get_signal_parameters(Events, "placement_relocated")
	assert_eq(int(params[0]), slot_id)
	var relocated_point: Vector2 = params[1]
	assert_ne(
		relocated_point, desired_local,
		"the reported point must be where the block actually landed, not the invalid spot it was asked for."
	)

	# The reported point must be exactly the spawned block's own disk-local
	# origin -- the same frame final_disk_origin already used to spawn it.
	var block: Node3D = _blocks_root.get_child(0) as Node3D
	var spawned_local: Vector3 = _field.to_local(block.global_position)
	assert_almost_eq(relocated_point.x, spawned_local.x, 0.01)
	assert_almost_eq(relocated_point.y, spawned_local.z, 0.01)

	# "the block still drops more
	# or less in place": the relocated point is by construction near the
	# invalid one it replaces (closest_valid_point() widens outward one step
	# at a time), which is exactly what reads as "in place" to the owner --
	# so pin down that it is nonetheless genuinely inside the acting slot's
	# OWN territory, never merely close, not still contested/enemy ground.
	var cell: Vector2i = Match.cell_grid().world_to_cell(relocated_point)
	assert_eq(
		Match.raster().team_at(cell.x, cell.y), Match.slot(slot_id).team_id,
		"the relocated point must be owned by the acting slot's own team, not just nearby."
	)


# --- Outcome 3: PlayerController reacts only to its own slot's relocation ---

## a held gift is exempt from the territory
## check; the host decides from its own held state.
func _hold_gift(slot_id: int, gift_id: StringName = &"bomb") -> void:
	# debug_queue_special is sandbox-only; flip the flag just for the queue
	# call so the placement rules below run with sandbox off.
	Match.config.sandbox = true
	assert_true(Match.debug_queue_special(slot_id, gift_id))
	Match.config.sandbox = false
	assert_eq(
		Match.request_place(slot_id, _home_world_position(slot_id), 0, Quaternion.IDENTITY, false),
		PlacementRules.REASON_OK, "fixture: ordinary piece placed so the gift is fed."
	)
	assert_eq(Match.held_special(slot_id), gift_id, "fixture: the gift is now held.")


func test_held_gift_drops_outside_own_territory_but_plain_block_does_not() -> void:
	Match.start_match(_config())
	_run_countdown()
	Match._feed.set_feed_timer_enabled(true)
	var foreign: Vector3 = _home_world_position(1)
	assert_eq(
		Match.request_place(0, foreign, 0, Quaternion.IDENTITY, false),
		PlacementRules.REASON_OUTSIDE_TERRITORY, "control: a plain block is still refused there."
	)
	_hold_gift(0)
	assert_eq(Match.preview_placement(0, foreign, 0, Quaternion.IDENTITY), PlacementRules.Result.VALID)
	var bad: Vector3 = _field.to_global(Vector3(999.0, 5.0, 999.0))
	assert_ne(Match.request_place(0, bad, 0, Quaternion.IDENTITY, false), PlacementRules.REASON_OK, "off-disk still refused")
	assert_eq(Match.request_place(0, Vector3(NAN, 0, 0), 0, Quaternion.IDENTITY, false), PlacementRules.REASON_NO_BLOCK)
	assert_eq(Match.request_place(0, foreign, 0, Quaternion.IDENTITY, false), PlacementRules.REASON_OK)


func test_client_preview_waives_territory_for_replicated_gift_then_refuses_again() -> void:
	Match.start_match(_config())
	_run_countdown()
	var fake: FakeNet = FakeNet.client(0)
	Match.set_net_provider(fake)
	var net: MatchNetScript = MatchNetScript.new()
	net.set_process(false)
	add_child_autofree(net)
	net.set_providers(fake, Match)
	var foreign: Vector3 = _home_world_position(1)
	var shape_id: StringName = Match.held_shape(0).id
	var seq: int = Match.feed_seq(0)
	assert_eq(
		Match.preview_placement(0, foreign, 0, Quaternion.IDENTITY),
		PlacementRules.Result.OUTSIDE_TERRITORY, "control: plain block on a client."
	)
	net.net_match_event(MatchNetScript.EVENT_GIFT_CLAIMED, [11, 0, MatchGifts.PENDING_SPECIAL_ID, shape_id])
	Match.apply_replicated_feed(0, shape_id, shape_id, seq + 1, Match.feed_time_left(0), false)
	assert_ne(Match.held_special(0), &"", "fixture: client mirrors the held gift.")
	assert_eq(Match.preview_placement(0, foreign, 0, Quaternion.IDENTITY), PlacementRules.Result.VALID)
	Match.apply_replicated_feed(0, shape_id, shape_id, seq + 2, Match.feed_time_left(0), false)
	assert_eq(Match.held_special(0), &"", "fixture: gift consumed.")
	assert_eq(
		Match.preview_placement(0, foreign, 0, Quaternion.IDENTITY),
		PlacementRules.Result.OUTSIDE_TERRITORY, "next plain block is refused again."
	)

