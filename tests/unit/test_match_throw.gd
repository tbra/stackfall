extends GutTest
## autoload/match/MatchPlacement.gd's request_throw() (spec 2.5, 3.4, M4 P2c)
## and _spawn_block()'s special-attach extension. Same tiny-map/real-Field
## fixture as tests/unit/test_placement_refusal.gd; SpecialDef attach cases
## seed Match._placement's per-id cache directly rather than adding a real
## .tres under res://config/specials/ (docs/M4_P2_PACKAGES.md P2c: "do not
## add real specials under config/specials/") -- the same "reach into a
## private field directly" convention autoload/Match.gd's own header
## documents for tests.

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
	# abort_match() -> MatchPlacement._clear_blocks() only queue_free()s the
	# spawned Block RigidBody3Ds (deferred to the next idle frame); GUT's
	# end-of-script orphan check runs before that frame, so every spawned
	# block here is freed synchronously instead, exactly like the
	# SpecialBehavior children the individual tests already free by hand.
	for child: Node in _blocks_root.get_children():
		child.free()
	Match.set_process(true)
	MatchTestReset.clear_world()
	# Belt and suspenders: anything else this test's own spawns left queued
	# for a deferred free (Godot's own internal bookkeeping, not this file's
	# code) gets a real idle frame to run before GUT's end-of-script orphan
	# check, which otherwise runs before any such frame does.
	await get_tree().process_frame


func _config(player_count: int = 2) -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = player_count
	config.hot_seat = false
	config.block_timer = 6.0
	config.rng_seed = 13579
	return config


func _run_countdown() -> void:
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)


func _home_world_position(slot_id: int) -> Vector3:
	var home: Vector2 = Match.slot(slot_id).home_position
	return _field.to_global(Vector3(home.x, 5.0, home.y))


## Pushes `special_id` straight onto `slot_id`'s pending queue -- the FIFO
## MatchGifts._claim_gift() would otherwise fill; bypassing the claim/roll
## machinery keeps these tests about request_throw()/_ spawn_block(), not
## about gifts (that is test_gift_claim.gd's job).
func _queue_special(slot_id: int, special_id: StringName = &"test_special") -> void:
	Match._gifts._ensure_capacity(slot_id)
	(Match._gifts._pending_queues[slot_id] as Array).append(special_id)


## Seeds Match._placement's SpecialDef-by-id cache directly with `def`, so
## _attach_pending_special() resolves `def.id` without SpecialDef.
## load_all_specials() ever touching res://config/specials/ (kept genuinely
## empty until P3-P5 land real specials there).
func _install_test_def(def: SpecialDef) -> void:
	Match._placement._special_defs_config = Match.config
	Match._placement._special_defs_by_id[def.id] = def


func _make_test_def(id: StringName = &"test_special") -> SpecialDef:
	var def: SpecialDef = SpecialDef.new()
	def.id = id
	def.arm_delay = 999.0
	def.arm_impulse = 999.0
	def.fuse_timeout_s = 999.0
	return def


# --- REASON_NOT_A_SPECIAL: nothing queued -----------------------------------

func test_throw_with_no_pending_special_is_refused_and_nothing_is_consumed() -> void:
	Match.start_match(_config())
	_run_countdown()
	var slot_id: int = 0
	var seq_before: int = Match.feed_seq(slot_id)
	var shape_before: BlockShape = Match.held_shape(slot_id)

	var reason: StringName = Match.request_throw(
		slot_id, _home_world_position(slot_id), 0, Quaternion.IDENTITY, Vector3(5.0, 0.0, 0.0)
	)

	assert_eq(reason, ThrowRules.REASON_NOT_A_SPECIAL)
	assert_eq(_blocks_root.get_child_count(), 0)
	assert_eq(Match.feed_seq(slot_id), seq_before, "the piece must not be consumed")
	assert_eq(Match.held_shape(slot_id), shape_before)


# --- REASON_OUTSIDE_TERRITORY: refused, never burned ------------------------

func test_throw_outside_territory_is_refused_and_the_piece_stays_held() -> void:
	Match.start_match(_config())
	_run_countdown()
	var slot_id: int = 0
	_queue_special(slot_id)
	var seq_before: int = Match.feed_seq(slot_id)
	var shape_before: BlockShape = Match.held_shape(slot_id)
	watch_signals(Events)

	# Slot 1's home is outside slot 0's own territory.
	var reason: StringName = Match.request_throw(
		slot_id, _home_world_position(1), 0, Quaternion.IDENTITY, Vector3(5.0, 0.0, 0.0)
	)

	assert_eq(reason, ThrowRules.REASON_OUTSIDE_TERRITORY)
	assert_eq(_blocks_root.get_child_count(), 0, "a refused throw must never spawn, burned or otherwise.")
	assert_eq(Match.feed_seq(slot_id), seq_before, "the piece must not be consumed")
	assert_eq(Match.held_shape(slot_id), shape_before)
	assert_eq(Match.pending_special_count(slot_id), 1, "a refused throw must not pop the pending special either")
	assert_signal_emitted_with_parameters(Events, "placement_rejected", [slot_id, ThrowRules.REASON_OUTSIDE_TERRITORY])

	# The refusal must not have jammed anything: a real throw right after
	# still works.
	var second: StringName = Match.request_throw(
		slot_id, _home_world_position(slot_id), 0, Quaternion.IDENTITY, Vector3(5.0, 0.0, 0.0)
	)
	assert_eq(second, PlacementRules.REASON_OK)


# --- Velocity clamp -----------------------------------------------------------

func test_throw_velocity_above_throw_max_speed_is_clamped_not_refused() -> void:
	Match.start_match(_config())
	_run_countdown()
	var slot_id: int = 0
	_queue_special(slot_id)
	var tuning: SpecialTuning = load("res://config/special_tuning.tres")
	var huge: Vector3 = Vector3(1.0, 0.0, 0.0) * (tuning.throw_max_speed * 10.0)

	var reason: StringName = Match.request_throw(
		slot_id, _home_world_position(slot_id), 0, Quaternion.IDENTITY, huge
	)

	assert_eq(reason, PlacementRules.REASON_OK, "an over-speed throw is clamped, never refused")
	assert_eq(_blocks_root.get_child_count(), 1)
	var block: Block = _blocks_root.get_child(0) as Block
	assert_almost_eq(block.linear_velocity.length(), tuning.throw_max_speed, 0.01)
	assert_almost_eq(block.linear_velocity.normalized().x, 1.0, 0.01, "direction must be preserved by the clamp")


# --- Accept: velocity, continuous_cd, special attach, pop-once --------------

func test_accepted_throw_spawns_with_the_requested_velocity_and_continuous_cd() -> void:
	Match.start_match(_config())
	_run_countdown()
	var slot_id: int = 0
	_queue_special(slot_id)
	var velocity: Vector3 = Vector3(3.0, 0.0, 4.0)  # length 5, well under the 25 m/s cap

	var reason: StringName = Match.request_throw(
		slot_id, _home_world_position(slot_id), 0, Quaternion.IDENTITY, velocity
	)

	assert_eq(reason, PlacementRules.REASON_OK)
	assert_eq(_blocks_root.get_child_count(), 1)
	var block: Block = _blocks_root.get_child(0) as Block
	assert_true(block.linear_velocity.is_equal_approx(velocity), "velocity must be exactly what was requested, under the cap")
	assert_true(block.continuous_cd, "spec 3.5: thrown specials always use continuous_cd")


func test_accepted_throw_pops_the_pending_special_exactly_once() -> void:
	Match.start_match(_config())
	_run_countdown()
	var slot_id: int = 0
	_queue_special(slot_id, &"special_a")
	_queue_special(slot_id, &"special_b")
	assert_eq(Match.pending_special_count(slot_id), 2, "setup")

	Match.request_throw(slot_id, _home_world_position(slot_id), 0, Quaternion.IDENTITY, Vector3(1.0, 0.0, 0.0))

	assert_eq(Match.pending_special_count(slot_id), 1, "exactly one pop per spawn")
	assert_eq(Match.held_special(slot_id), &"special_b", "FIFO order preserved")


func test_accepted_throw_attaches_a_special_behavior_bound_to_the_right_def_and_forwards_triggered() -> void:
	Match.start_match(_config())
	_run_countdown()
	var slot_id: int = 0
	_queue_special(slot_id, &"test_special")
	var def: SpecialDef = _make_test_def(&"test_special")
	_install_test_def(def)
	watch_signals(Events)

	Match.request_throw(slot_id, _home_world_position(slot_id), 0, Quaternion.IDENTITY, Vector3(1.0, 0.0, 0.0))

	var block: Block = _blocks_root.get_child(0) as Block
	var behavior: SpecialBehavior = null
	for child: Node in block.get_children():
		if child is SpecialBehavior:
			behavior = child as SpecialBehavior
	assert_not_null(behavior, "a real, roster-resolvable special id must attach a SpecialBehavior")

	behavior.trigger(0)
	assert_signal_emitted_with_parameters(
		Events, "special_triggered", [block.net_id, def.id, block.global_position, 0]
	)
	# Freed immediately (not autofree()'s deferred queue_free()) -- GUT's
	# end-of-script orphan check runs before the next idle frame processes a
	# merely-queued free. block itself is freed synchronously too, by
	# after_each() (see that function's own comment).
	behavior.free()


func test_placeholder_pending_id_spawns_an_ordinary_block_with_no_special_behavior() -> void:
	Match.start_match(_config())
	_run_countdown()
	var slot_id: int = 0
	_queue_special(slot_id, MatchGifts.PENDING_SPECIAL_ID)

	Match.request_throw(slot_id, _home_world_position(slot_id), 0, Quaternion.IDENTITY, Vector3(1.0, 0.0, 0.0))

	var block: Block = _blocks_root.get_child(0) as Block
	for child: Node in block.get_children():
		assert_false(child is SpecialBehavior, "the placeholder id must never attach a real behavior")


# --- Client refusal mirrors request_place()'s own -----------------------------

func test_a_client_call_is_refused_exactly_like_request_place() -> void:
	Match.start_match(_config())
	_run_countdown()
	var slot_id: int = 0
	_queue_special(slot_id)
	Match.set_net_provider(FakeNet.client(slot_id))

	var throw_reason: StringName = Match.request_throw(
		slot_id, _home_world_position(slot_id), 0, Quaternion.IDENTITY, Vector3(1.0, 0.0, 0.0)
	)
	var place_reason: StringName = Match.request_place(
		slot_id, _home_world_position(slot_id), 0, Quaternion.IDENTITY, false
	)

	assert_eq(throw_reason, PlacementRules.REASON_NO_BLOCK)
	assert_eq(throw_reason, place_reason, "a client must be refused the same way for both entry points")
	assert_eq(_blocks_root.get_child_count(), 0, "a client must never spawn anything locally")


# --- A placed (not thrown) special arms too ----------------------------------

func test_request_place_with_a_pending_real_id_also_attaches_the_behavior() -> void:
	Match.start_match(_config())
	_run_countdown()
	var slot_id: int = 0
	_queue_special(slot_id, &"test_special")
	var def: SpecialDef = _make_test_def(&"test_special")
	_install_test_def(def)

	var reason: StringName = Match.request_place(
		slot_id, _home_world_position(slot_id), 0, Quaternion.IDENTITY, false
	)

	assert_eq(reason, PlacementRules.REASON_OK)
	var block: Block = _blocks_root.get_child(0) as Block
	var behavior: SpecialBehavior = null
	for child: Node in block.get_children():
		if child is SpecialBehavior:
			behavior = child as SpecialBehavior
	assert_not_null(behavior, "a placed special must arm too, not only a thrown one")
	behavior.free()  # see the earlier test's own comment on why not autofree()


# --- Bontago-1en.13 review fix: a burn must never consume the queue ---------

## spec 2.5's OPEN "how expiry handles a held special": a forced auto-drop
## with nowhere valid to relocate to still spawns and burns a block (see
## test_placement_refusal.gd's own burn-path tests), but that must not also
## destroy whatever special the slot had queued -- the queue stays intact for
## the slot's next spawn.
func test_auto_drop_burn_does_not_consume_the_pending_special() -> void:
	Match.start_match(_config())
	_run_countdown()
	var slot_id: int = 0
	_queue_special(slot_id, &"test_special")
	var def: SpecialDef = _make_test_def(&"test_special")
	_install_test_def(def)
	assert_eq(Match.pending_special_count(slot_id), 1, "setup")

	# Bontago-xtq.23: closest_valid_point() now falls back to a full-disk
	# scan, so an origin merely far away no longer forces the burn path by
	# itself -- the scan would still find slot_id's own territory and
	# relocate there. Blanking its owned cells in the live raster first
	# (TerritoryTestHelpers.blank_owned_territory()) makes the team genuinely
	# own no valid point anywhere, guaranteeing the burn path, not a
	# relocation.
	TerritoryTestHelpers.blank_owned_territory(Match.raster(), Match.team_of(slot_id))
	var far_world: Vector3 = _field.to_global(Vector3(5000.0, 5.0, 5000.0))
	var reason: StringName = Match.request_place(slot_id, far_world, 0, Quaternion.IDENTITY, true)

	assert_ne(reason, PlacementRules.REASON_OK, "setup: nothing valid within reach must burn, not relocate")
	assert_eq(_blocks_root.get_child_count(), 1, "a forced auto-drop with nowhere to land still spawns (and burns) a block")
	assert_eq(Match.pending_special_count(slot_id), 1, "a burn must never pop the pending special")
	var block: Block = _blocks_root.get_child(0) as Block
	for child: Node in block.get_children():
		assert_false(child is SpecialBehavior, "a burned block must never arm a special")


## The companion case: an auto-drop that *does* find a valid point to
## relocate to is not a burn at all (request_place()'s own `reason ==
## PlacementRules.REASON_OK` path) -- it must still attach and pop exactly
## like any other successful spawn.
func test_auto_drop_that_relocates_still_attaches_and_pops() -> void:
	Match.start_match(_config())
	_run_countdown()
	var slot_id: int = 0
	_queue_special(slot_id, &"test_special")
	var def: SpecialDef = _make_test_def(&"test_special")
	_install_test_def(def)
	var home: Vector2 = Match.slot(slot_id).home_position
	var tuning: TerritoryTuning = load("res://config/territory_tuning.tres")
	# Just past the home circle's own radius, well inside auto_drop_search_
	# max_radius -- the same setup test_placement_refusal.gd's own relocation
	# test uses.
	var desired_local: Vector2 = home + Vector2(tuning.home_radius + 1.5, 0.0)
	var desired_world: Vector3 = _field.to_global(Vector3(desired_local.x, 5.0, desired_local.y))

	var reason: StringName = Match.request_place(slot_id, desired_world, 0, Quaternion.IDENTITY, true)

	assert_eq(reason, PlacementRules.REASON_OK, "setup: must actually relocate, not burn")
	assert_eq(Match.pending_special_count(slot_id), 0, "a successful relocation still pops the pending special")
	var block: Block = _blocks_root.get_child(0) as Block
	var behavior: SpecialBehavior = null
	for child: Node in block.get_children():
		if child is SpecialBehavior:
			behavior = child as SpecialBehavior
	assert_not_null(behavior, "a relocated auto-drop must still attach the special")
	behavior.free()


# --- Bontago-1en.21: Events.special_consumed must fire exactly on a real pop -

## The bug this package fixes: MatchGifts.pop_pending_special() must emit
## Events.special_consumed exactly once, with the popped id, on the accepted-
## throw path -- request_throw()'s own call to _attach_pending_special() is
## its only pop.
func test_accepted_throw_emits_special_consumed_exactly_once_with_the_popped_id() -> void:
	Match.start_match(_config())
	_run_countdown()
	var slot_id: int = 0
	_queue_special(slot_id, &"special_a")
	_queue_special(slot_id, &"special_b")
	watch_signals(Events)

	Match.request_throw(slot_id, _home_world_position(slot_id), 0, Quaternion.IDENTITY, Vector3(1.0, 0.0, 0.0))

	assert_signal_emit_count(Events, "special_consumed", 1, "exactly one pop per accepted throw")
	assert_signal_emitted_with_parameters(Events, "special_consumed", [slot_id, &"special_a"])


## The place-spawn twin of the throw test above -- request_place()'s own call
## to _attach_pending_special(), on its non-burn path.
func test_request_place_emits_special_consumed_exactly_once_with_the_popped_id() -> void:
	Match.start_match(_config())
	_run_countdown()
	var slot_id: int = 0
	_queue_special(slot_id, &"test_special")
	var def: SpecialDef = _make_test_def(&"test_special")
	_install_test_def(def)
	watch_signals(Events)

	Match.request_place(slot_id, _home_world_position(slot_id), 0, Quaternion.IDENTITY, false)

	assert_signal_emit_count(Events, "special_consumed", 1, "exactly one pop per accepted placement")
	assert_signal_emitted_with_parameters(Events, "special_consumed", [slot_id, &"test_special"])


## The P2c-i rule this package must not break: a burned auto-drop (nowhere
## valid to relocate to) keeps the special queued, so it must never emit
## Events.special_consumed either -- the companion case to
## test_auto_drop_burn_does_not_consume_the_pending_special above.
func test_auto_drop_burn_never_emits_special_consumed() -> void:
	Match.start_match(_config())
	_run_countdown()
	var slot_id: int = 0
	_queue_special(slot_id, &"test_special")
	var def: SpecialDef = _make_test_def(&"test_special")
	_install_test_def(def)
	watch_signals(Events)

	# Bontago-xtq.23: guarantee the genuine no-valid-point-anywhere case (see
	# test_auto_drop_burn_does_not_consume_the_pending_special's own comment)
	# rather than relying on distance, which the full-disk scan fallback now
	# always resolves to a relocation instead.
	TerritoryTestHelpers.blank_owned_territory(Match.raster(), Match.team_of(slot_id))
	var far_world: Vector3 = _field.to_global(Vector3(5000.0, 5.0, 5000.0))
	var reason: StringName = Match.request_place(slot_id, far_world, 0, Quaternion.IDENTITY, true)

	assert_ne(reason, PlacementRules.REASON_OK, "setup: nothing valid within reach must burn, not relocate")
	assert_signal_not_emitted(Events, "special_consumed", "a burn must never emit special_consumed")
