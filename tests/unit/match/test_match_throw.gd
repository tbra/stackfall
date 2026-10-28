extends "res://tests/unit/match/match_world_test.gd"
## MatchPlacement.request_throw and special attach (spec 1.4, 3.4, M4 P2c).

func after_each() -> void:
	Match._net_provider = null
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
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = player_count
	config.block_timer = 6.0
	config.rng_seed = 13579
	# Old gift rule (a claim replaces the next piece); the default after-next rule is in test_gift_queue_after_next.gd.
	config.experiments_enabled = true
	config.qol = QolExperiments.new()
	config.qol.gift_loads_next = true
	return config


func _queue_special(slot_id: int, special_id: StringName = &"test_special") -> void:
	Match._gifts._ensure_capacity(slot_id)
	if Match.held_special(slot_id) == &"":
		Match._gifts._held_specials[slot_id] = special_id
		Match._feed._held_is_gift[slot_id] = true
	else:
		(Match._gifts._pending_queues[slot_id] as Array).clear()
		(Match._gifts._pending_queues[slot_id] as Array).append(special_id)
		Match._feed.replace_next_with_gift(slot_id)


## Seeds Match._placement's SpecialDef-by-id cache directly with `def`, so
## _attach_pending_special() resolves `def.id` without SpecialDef.
## load_all_specials() ever touching res://config/gifts/specials/ (kept genuinely
## empty until P3-P5 land real specials there).
func _install_test_def(def: SpecialDef) -> void:
	Match._placement._special_defs_config = Match.config
	Match._placement._special_defs_by_id[def.id] = def


func _make_test_def(id: StringName = &"test_special") -> SpecialDef:
	var def: SpecialDef = SpecialDef.new()
	def.id = id
	def.throwable = true
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
		slot_id, _home_world_position(slot_id), 0, Quaternion.IDENTITY, Vector3(1.0, 0.0, 0.0)
	)

	assert_eq(reason, ThrowRules.REASON_NOT_A_SPECIAL)
	assert_eq(_blocks_root.get_child_count(), 0)
	assert_eq(Match.feed_seq(slot_id), seq_before, "the piece must not be consumed")
	assert_eq(Match.held_shape(slot_id), shape_before)


# --- Held gifts waive territory -------------------------------

# --- Refusal (off the disk): never burned ------------------------------------

func test_throw_off_the_disk_is_refused_and_the_piece_stays_held() -> void:
	Match.start_match(_config())
	_run_countdown()
	var slot_id: int = 0
	_queue_special(slot_id)
	var seq_before: int = Match.feed_seq(slot_id)
	var shape_before: BlockShape = Match.held_shape(slot_id)
	watch_signals(Events)

	var off_disk: Vector3 = _home_world_position(slot_id) + Vector3(1000.0, 0.0, 1000.0)
	var reason: StringName = Match.request_throw(
		slot_id, off_disk, 0, Quaternion.IDENTITY, Vector3(1.0, 0.0, 0.0)
	)

	assert_ne(reason, PlacementRules.REASON_OK)
	assert_eq(_blocks_root.get_child_count(), 0, "a refused throw must never spawn, burned or otherwise.")
	assert_eq(Match.feed_seq(slot_id), seq_before, "the piece must not be consumed")
	assert_eq(Match.held_shape(slot_id), shape_before)
	assert_eq(Match.pending_special_count(slot_id), 1, "a refused throw must not pop the pending special either")
	assert_signal_emitted_with_parameters(Events, "placement_rejected", [slot_id, reason])

	# The refusal must not have jammed anything: a real throw right after
	# still works.
	var second: StringName = Match.request_throw(
		slot_id, _home_world_position(slot_id), 0, Quaternion.IDENTITY, Vector3(1.0, 0.0, 0.0)
	)
	assert_eq(second, PlacementRules.REASON_OK)


# --- Velocity clamp -----------------------------------------------------------

func test_throw_velocity_above_throw_max_speed_is_clamped_not_refused() -> void:
	Match.start_match(_config())
	_run_countdown()
	var slot_id: int = 0
	_queue_special(slot_id)
	var tuning: SpecialTuning = load("res://config/gifts/special_tuning.tres")
	var huge: Vector3 = Vector3(1.0, 0.0, 0.0) * (tuning.throw_max_speed * 10.0)

	var reason: StringName = Match.request_throw(
		slot_id, _home_world_position(slot_id), 0, Quaternion.IDENTITY, huge
	)

	# the `velocity` slot carries a unit camera aim; a speed-sized vector is
	# outside the accepted band and refused unconsumed (the host never trusts a client speed).
	assert_eq(reason, PlacementRules.REASON_NO_BLOCK)
	assert_eq(_blocks_root.get_child_count(), 0)
	assert_true(Match.held_special(slot_id) != &"", "nothing consumed")

	var aim: Vector3 = Vector3(1.0, 0.0, 0.0)
	assert_eq(Match.request_throw(slot_id, _home_world_position(slot_id), 0, Quaternion.IDENTITY, aim), PlacementRules.REASON_OK)
	var block: Block = _blocks_root.get_child(0) as Block
	# An unresolved-def gift is normalised through GiftAim's ballistic throw, never the raw velocity.
	var fixed: Vector3 = GiftAim.throw_velocity(aim, Match._placement._special_tuning, Match._placement._throw_range_scale())
	assert_true(block.linear_velocity.is_equal_approx(fixed), "host-computed trajectory")
	assert_gt(block.linear_velocity.x, 0.0, "the heading is preserved")


# --- Accept: velocity, continuous_cd, special attach, pop-once --------------

func test_real_crate_claim_can_be_thrown_and_activated() -> void:
	var all_defs: Array[SpecialDef] = SpecialDef.load_all_specials()
	var defs: Array[SpecialDef] = []
	for roster_def: SpecialDef in all_defs:
		if roster_def.throwable:
			defs.append(roster_def)
	assert_false(defs.is_empty(), "the shipped roster must contain a throwable special")
	var config: MatchConfig = _config()
	config.enabled_specials = [defs[0].id]
	config.special_frequency = 0  # The injected crate is the only gift in this path.
	Match.start_match(config)
	_run_countdown()
	var home: Vector2 = Match.slot(0).home_position
	var gift_id: int = Match._gifts._next_gift_id
	Match._gifts._spawn_crate_at(home)
	watch_signals(Events)

	Match._gifts._claim_gift(gift_id, Match.slot(0).team_id)

	assert_true(Match.gift_state(gift_id).is_empty(), "territory claims the spawned crate")
	assert_eq(Match.held_special(0), &"", "the claim keeps the current held block ordinary")
	assert_eq(Match.pending_special_count(0), 1, "only the injected crate was claimed")
	assert_eq(Match.request_place(0, _home_world_position(0), 0, Quaternion.IDENTITY, false), PlacementRules.REASON_OK)
	assert_eq(Match.held_special(0), defs[0].id, "the claimed gift is now held")
	var reason: StringName = Match.request_throw(
		0, _home_world_position(0), 0, Quaternion.IDENTITY, Vector3(1.0, 0.0, 0.0)
	)
	assert_eq(reason, PlacementRules.REASON_OK)
	assert_eq(Match.pending_special_count(0), 0, "the throw consumes the claimed special")
	var block: Block = _blocks_root.get_child(_blocks_root.get_child_count() - 1) as Block
	var behavior: SpecialBehavior = null
	for child: Node in block.get_children():
		if child is SpecialBehavior:
			behavior = child as SpecialBehavior
	assert_not_null(behavior, "the thrown block must carry its behavior")
	if behavior == null:
		return
	behavior.trigger(0)
	assert_signal_emitted_with_parameters(
		Events, "special_triggered", [block.net_id, defs[0].id, block.global_position, 0]
	)
	behavior.free()


func test_accepted_throw_spawns_with_the_requested_velocity_and_continuous_cd() -> void:
	Match.start_match(_config())
	_run_countdown()
	var slot_id: int = 0
	_queue_special(slot_id)
	var velocity: Vector3 = Vector3(0.6, 0.0, 0.8)  # unit camera aim

	var reason: StringName = Match.request_throw(
		slot_id, _home_world_position(slot_id), 0, Quaternion.IDENTITY, velocity
	)

	assert_eq(reason, PlacementRules.REASON_OK)
	assert_eq(_blocks_root.get_child_count(), 1)
	var block: Block = _blocks_root.get_child(0) as Block
	var fixed: Vector3 = GiftAim.throw_velocity(velocity, Match._placement._special_tuning, Match._placement._throw_range_scale())
	assert_true(block.linear_velocity.is_equal_approx(fixed), "normalised, not the raw client velocity")
	assert_true(block.continuous_cd, "spec 2.7: thrown specials always use continuous_cd")


# --- Client refusal mirrors request_place()'s own -----------------------------

func test_a_client_call_is_refused_exactly_like_request_place() -> void:
	Match.start_match(_config())
	_run_countdown()
	var slot_id: int = 0
	_queue_special(slot_id)
	Match._net_provider = FakeNet.client(slot_id)

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

# --- review fix: a burn must never consume the queue ---------

## spec 1.4's OPEN "how expiry handles a held special": a forced auto-drop
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

	# closest_valid_point() now falls back to a full-disk
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


# --- Events.special_consumed must fire exactly on a real pop -
