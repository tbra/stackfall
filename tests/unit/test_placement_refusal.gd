extends GutTest
## autoload/match/MatchPlacement.gd's request_place(): a manual (auto_drop ==
## false) release outside the placing player's own territory (spec 2.5's
## contract; docs/AGENT_WORKFLOW.md Bontago-mv0.24, owner test 2026-09-22).
##
## The owner's test of the original found a refused drop is simply not a
## drop: nothing spawns, nothing is consumed, and the player keeps holding the
## same piece and may try again -- superseding spec 2.2's older "thrown off
## the map with a visible reject animation" line for this case (see
## Events.placement_rejected's own doc comment). An auto-drop still relocates
## to the closest valid point as before, and now also tells the owning client
## exactly where it landed via Events.placement_relocated, so
## game/PlayerController.gd can snap its cursor and camera there.
##
## Fixture mirrors tests/unit/test_match_flow.gd's own (tiny map, real Field/
## Match, no live peer) rather than reusing its private helpers across files.

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
	Match.set_net_provider(null)
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _config(player_count: int = 2) -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	# Script swap first: Object.set_script() resets script-level state to the
	# new script's declared defaults (test_match_flow.gd's own
	# _tiny_map_config() DECISION has the full story).
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = player_count
	config.hot_seat = false
	config.block_timer = 6.0
	config.rng_seed = 24680
	return config


func _run_countdown() -> void:
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)


func _home_world_position(slot_id: int) -> Vector3:
	var home: Vector2 = Match.slot(slot_id).home_position
	return _field.to_global(Vector3(home.x, 5.0, home.y))


# --- Outcome 1: a manual out-of-zone drop is refused, not burned ------------

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
		"Owner test 2026-09-22: a refused manual drop must not spawn a block, burned or otherwise."
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


## Bontago-xtq.23 (owner playtest 2026-09-24): the report's "the block still
## drops more or less in place" hypothesis this pins down and refutes is that
## a refused manual click somehow burns the slot's release lock -- if it did,
## the *next* interval's early release would find itself already locked out
## for no reason. Sets up the lock first (one legitimate early release) so the
## refused click below has a lock to (not) clobber, rather than the ambient
## default-false a refusal can't be shown to have touched either way.
func test_manual_drop_outside_territory_never_touches_an_existing_release_lock() -> void:
	Match.start_match(_config())
	_run_countdown()
	var slot_id: int = 0

	var early: StringName = Match.request_place(
		slot_id, _home_world_position(slot_id), 0, Quaternion.IDENTITY, false
	)
	assert_eq(early, PlacementRules.REASON_OK, "fixture: the early release itself must succeed.")
	assert_true(
		Match.is_release_locked(slot_id),
		"fixture: an early release locks the next piece until the interval boundary (spec 2.4)."
	)
	var seq_before: int = Match.feed_seq(slot_id)

	var reason: StringName = Match.request_place(
		slot_id, _home_world_position(1), 0, Quaternion.IDENTITY, false
	)

	assert_eq(
		reason, PlacementRules.REASON_NO_BLOCK,
		"a release-locked slot refuses any manual click regardless of the point's own territory."
	)
	assert_true(
		Match.is_release_locked(slot_id),
		"a refused manual click must never clear a release lock it didn't cause."
	)
	assert_eq(Match.feed_seq(slot_id), seq_before, "the refusal must not consume anything either.")
	assert_eq(_blocks_root.get_child_count(), 1, "still just the one early-released block, nothing burned.")


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
	var tuning: TerritoryTuning = load("res://config/territory_tuning.tres")
	# Just past the home circle's own radius, so validate_point() refuses the
	# raw point but a valid one sits only a couple of metres away -- well
	# inside auto_drop_search_max_radius (config/territory_tuning.tres: step
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

	# Bontago-xtq.23 (owner playtest 2026-09-24, "the block still drops more
	# or less in place"): the relocated point is by construction near the
	# invalid one it replaces (closest_valid_point() widens outward one step
	# at a time), which is exactly what reads as "in place" to the owner --
	# so pin down that it is nonetheless genuinely inside the acting slot's
	# OWN territory, never merely close, not still contested/enemy ground.
	var cell: Vector2i = Match.cell_grid().world_to_cell(relocated_point)
	assert_eq(
		Match.raster().team_at(cell.x, cell.y), Match.slot(slot_id).team_id,
		"the relocated point must be owned by the acting slot's own team, not just nearby."
	)


## Bontago-xtq.23 (owner playtest 2026-09-24, root cause): the ghost sits well
## past auto_drop_search_max_radius (12 m) from the acting slot's own
## territory -- the exact case that used to fall through the ring search
## straight to NO_ORIGIN and get thrown off the map even though the slot's own
## territory was sitting right there on the disk. PlacementRules.
## closest_valid_point()'s disk-scan fallback must still find it and relocate,
## the same as the near case above, just farther out.
func test_auto_drop_far_outside_the_zone_still_relocates_instead_of_being_thrown() -> void:
	Match.start_match(_config())
	_run_countdown()
	var slot_id: int = 0
	var home: Vector2 = Match.slot(slot_id).home_position
	var tuning: TerritoryTuning = load("res://config/territory_tuning.tres")
	assert_gt(tuning.auto_drop_search_max_radius, 0.0, "sanity: the tunable exists.")
	# Twice auto_drop_search_max_radius past the home circle's own rim -- the
	# ring search alone cannot reach this; only the disk scan can.
	var far_local: Vector2 = home + Vector2(
		tuning.home_radius + tuning.auto_drop_search_max_radius * 2.0, 0.0
	)
	var far_world: Vector3 = _field.to_global(Vector3(far_local.x, 5.0, far_local.y))
	watch_signals(Events)

	var reason: StringName = Match.request_place(slot_id, far_world, 0, Quaternion.IDENTITY, true)

	assert_eq(reason, PlacementRules.REASON_OK,
		"A far auto-drop with owned territory elsewhere on the disk must relocate, not burn.")
	assert_eq(_blocks_root.get_child_count(), 1, "Exactly one block spawned -- not thrown, not duplicated.")
	assert_signal_emitted(Events, "placement_relocated")
	var params: Array = get_signal_parameters(Events, "placement_relocated")
	assert_eq(int(params[0]), slot_id)
	var relocated_point: Vector2 = params[1]

	var cell: Vector2i = Match.cell_grid().world_to_cell(relocated_point)
	assert_eq(
		Match.raster().team_at(cell.x, cell.y), Match.slot(slot_id).team_id,
		"The relocated point must be owned by the acting slot's own team."
	)
	var block: Node3D = _blocks_root.get_child(0) as Node3D
	var spawned_local: Vector3 = _field.to_local(block.global_position)
	assert_almost_eq(relocated_point.x, spawned_local.x, 0.01,
		"The block actually landed at the reported relocation point, not thrown off elsewhere.")
	assert_almost_eq(relocated_point.y, spawned_local.z, 0.01)


func test_auto_drop_inside_the_zone_never_emits_placement_relocated() -> void:
	Match.start_match(_config())
	_run_countdown()
	watch_signals(Events)

	var reason: StringName = Match.request_place(0, _home_world_position(0), 0, Quaternion.IDENTITY, true)

	assert_eq(reason, PlacementRules.REASON_OK)
	assert_signal_not_emitted(Events, "placement_relocated", "a valid auto-drop never relocates.")


# --- Outcome 3: PlayerController reacts only to its own slot's relocation ---

func test_playercontroller_moves_its_cursor_on_its_own_slots_placement_relocated() -> void:
	Match.start_match(_config())
	_run_countdown()

	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	controller._ghost = ghost
	controller.set_acting_slot(0)

	var point: Vector2 = Match.slot(0).home_position + Vector2(2.0, 0.0)

	# A relocation for a different slot must be ignored entirely.
	Events.placement_relocated.emit(1, point)
	assert_eq(controller._cursor, Vector3.ZERO, "another slot's relocation must not move this controller's cursor.")

	Events.placement_relocated.emit(0, point)
	var expected_world: Vector3 = _field.to_global(Vector3(point.x, 0.0, point.y))
	assert_true(
		controller._cursor.is_equal_approx(expected_world),
		"the controller's own slot's relocation must move the cursor to the reported disk-local point."
	)


## Bontago-xtq.23 (brief hypothesis (b): "verify PlayerController actually
## handles Events.placement_relocated for the LOCAL slot ... camera + ghost
## jump"): the cursor moving (test above) is necessary but not sufficient --
## spec 2.5's own expiry contract is "the block AND THE CAMERA jump", so this
## pins the camera rig's own follow target down too, wired exactly the way
## game/HotSeat.gd/Sandbox.gd wire a live controller (set_camera_rig()).
func test_playercontroller_moves_the_camera_on_its_own_slots_placement_relocated() -> void:
	Match.start_match(_config())
	_run_countdown()

	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	var rig: CameraRig = autofree(load("res://game/CameraRig.tscn").instantiate())
	add_child_autofree(rig)
	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	controller._ghost = ghost
	controller.set_camera_rig(rig)
	controller.set_acting_slot(0)

	var point: Vector2 = Match.slot(0).home_position + Vector2(2.0, 0.0)
	var expected_world: Vector3 = _field.to_global(Vector3(point.x, 0.0, point.y))

	# A relocation for a different slot must not move this controller's camera.
	Events.placement_relocated.emit(1, point)
	assert_eq(rig._follow_position, Vector3.ZERO, "another slot's relocation must not move this controller's camera.")

	Events.placement_relocated.emit(0, point)
	# X/Z only: the ghost's own hover height (PhysicsTuning.hover_height above
	# whatever the disk surface probe hit) offsets rotated_center_world()'s Y
	# from the flat `expected_world` this test builds at y = 0, but the
	# straight-down raycast the ghost repositions from starts at the same X/Z
	# the cursor jumped to, so those two components must still match.
	assert_almost_eq(rig._follow_position.x, expected_world.x, 0.05)
	assert_almost_eq(rig._follow_position.z, expected_world.z, 0.05)
	assert_false(
		rig._follow_position.is_equal_approx(Vector3.ZERO),
		"the camera rig's follow target must actually have moved off its untouched fixture default."
	)


## Bontago-sen.1 (owner 2026-09-30): a held gift is exempt from the territory
## check; the host decides from its own held state.
func _hold_gift(slot_id: int) -> void:
	# debug_queue_special is sandbox-only; flip the flag just for the queue
	# call so the placement rules below run with sandbox off.
	Match.config.sandbox = true
	assert_true(Match.debug_queue_special(slot_id, &"earthquake"))
	Match.config.sandbox = false
	assert_eq(
		Match.request_place(slot_id, _home_world_position(slot_id), 0, Quaternion.IDENTITY, false),
		PlacementRules.REASON_OK, "fixture: ordinary piece placed so the gift is fed."
	)
	assert_eq(Match.held_special(slot_id), &"earthquake", "fixture: the gift is now held.")


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


func test_held_gift_throw_outside_own_territory_is_accepted_plain_throw_refused() -> void:
	Match.start_match(_config())
	_run_countdown()
	Match._feed.set_feed_timer_enabled(true)
	var foreign: Vector3 = _home_world_position(1)
	assert_ne(
		Match.request_throw(0, foreign, 0, Quaternion.IDENTITY, Vector3.ZERO),
		PlacementRules.REASON_OK, "control: a plain block throw is refused."
	)
	_hold_gift(0)
	assert_eq(
		Match.request_throw(0, foreign, 0, Quaternion.IDENTITY, Vector3.ZERO),
		PlacementRules.REASON_OK, "a held gift may be thrown from outside own territory."
	)


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


## Bontago-sen.9: dropping a held gift delivers the gift (the spawned block
## carries the armed SpecialBehavior) rather than a plain block.
func _special_behavior_of(block: Block) -> SpecialBehavior:
	for child: Node in block.get_children():
		if child is SpecialBehavior:
			return child as SpecialBehavior
	return null


func test_dropping_held_gift_spawns_block_with_its_special_and_consumes_it() -> void:
	Match.start_match(_config())
	_run_countdown()
	Match._feed.set_feed_timer_enabled(true)
	_hold_gift(0)
	watch_signals(Events)
	var foreign: Vector3 = _home_world_position(1)
	assert_eq(Match.request_place(0, foreign, 0, Quaternion.IDENTITY, false), PlacementRules.REASON_OK)
	var gift_block: Block = null
	for child: Node in _blocks_root.get_children():
		var block: Block = child as Block
		if block != null and _special_behavior_of(block) != null:
			gift_block = block
	assert_not_null(gift_block, "the dropped gift block must carry a SpecialBehavior")
	assert_signal_emitted_with_parameters(Events, "special_consumed", [0, &"earthquake"])
	assert_eq(Match.held_special(0), &"", "the gift is consumed by the drop")


func test_dropping_held_gift_via_auto_drop_also_delivers_the_special() -> void:
	Match.start_match(_config())
	_run_countdown()
	Match._feed.set_feed_timer_enabled(true)
	_hold_gift(0)
	var foreign: Vector3 = _home_world_position(1)
	assert_eq(Match.request_place(0, foreign, 0, Quaternion.IDENTITY, true), PlacementRules.REASON_OK)
	var found: bool = false
	for child: Node in _blocks_root.get_children():
		if child is Block and _special_behavior_of(child as Block) != null:
			found = true
	assert_true(found, "a forced drop of a held gift must still deliver the special")
