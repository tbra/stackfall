extends GutTest
## Bontago-1pi.11.85.1: every Match facade getter/command that Main, the menu, the lobby, the
## browsers or the HUD can reach before late_activate() answers an idle default and never errors;
## state-building mutators activate lazily. MatchNet's own getters are plain lookups.

var _previous_context: MatchContext = null


func before_each() -> void:
	_previous_context = MatchContext.installed()


func after_each() -> void:
	MatchContext.install(_previous_context)


func _deferred() -> MatchAutoload:
	var node: MatchAutoload = MatchAutoload.new()
	node.force_defer_activation = true
	add_child_autofree(node)
	assert_false(node.is_late_active())
	return node


func test_getters_answer_idle_defaults_before_activation() -> void:
	var m: MatchAutoload = _deferred()
	assert_eq(m.state(), MatchPhase.State.LOBBY)
	assert_eq(m.countdown_remaining(), 0.0)
	assert_eq(m.match_timer_left(), 0.0)
	assert_false(m.sudden_death_active())
	assert_eq(m.slot_count(), 0)
	assert_null(m.slot(0))
	assert_eq(m.team_of(0), -1)
	assert_eq(m.active_slot(), -1)
	assert_null(m.held_shape(0))
	assert_null(m.next_shape(0))
	assert_eq(m.held_special(0), &"")
	assert_eq(m.next_special(0), &"")
	assert_eq(m.pending_special_count(0), 0)
	assert_eq(m.glue_drops_left(0), 0)
	assert_eq(m.glue_revision(0), 0)
	assert_eq(m.feed_time_left(0), 0.0)
	assert_eq(m.feed_progress(0), 0.0)
	assert_eq(m.qol_backlog_count(0), 0)
	assert_false(m.qol_timer_paused(0))
	assert_eq(m.qol_claim_radius(), 0.0)
	assert_eq(m.gift_slot_head(0), &"")
	assert_eq(m.gift_slot_count(0), 0)
	assert_true(m.gift_slot_contents(0).is_empty())
	assert_false(m.gift_slot_enabled())
	assert_false(m.feed_timer_enabled())
	assert_eq(m.noted_aim(0), Vector3.ZERO)
	assert_false(m.is_pose_well_formed(Vector3.ZERO, 0, Quaternion.IDENTITY))
	assert_eq(m.blocks_spawned(), 0)
	assert_eq(m.feed_seq(0), 0)
	assert_false(m.is_release_locked(0))
	assert_eq(m.default_ghost_origin(0), Vector3.ZERO)
	assert_eq(m.disconnect_grace_left(0), 0.0)
	assert_null(m.raster())
	assert_null(m.groups())
	assert_null(m.bot_mode_goal(0))
	assert_null(m.cell_grid())
	assert_eq(m.territory_share(0), 0.0)
	assert_eq(m.winner_team(), -1)
	assert_true(m.circle_render_arrays().is_empty())
	assert_eq(m.circle_wire_xz_bound(), 0.0)
	assert_eq(m.circle_wire_radius_max(), 0.0)
	assert_true(m.mode_state_snapshot().is_empty())
	assert_true(m.gift_state(0).is_empty())
	assert_true(m.gift_states().is_empty())
	assert_eq(m.max_height_for_slot(0), 0.0)
	assert_null(m.stats())
	assert_null(m.weather())
	assert_null(m.active_cat())
	assert_eq(m.slot_color(0, Color.RED), MatchConfig.default_player_colors()[0])
	assert_true(m._held_shapes.is_empty())
	assert_null(m._raster)
	assert_null(m._solver)
	assert_false(m.is_late_active(), "getters never activate")


func test_commands_are_safe_noops_before_activation() -> void:
	var m: MatchAutoload = _deferred()
	m.abort_match()
	m.set_countdown_held(true)
	m.advance_turn()
	m.on_peer_left(0)
	m.on_peer_rejoined(0)
	m.debug_unlock_slot(0)
	m.set_feed_timer_enabled(true)
	m.note_aim(0, Vector3.FORWARD)
	m.punch_special_hole(Vector2.ZERO, 1.0, 1.0)
	assert_eq(m.pop_pending_special(0), &"")
	assert_false(m.grant_glue_drops(0, 1))
	assert_false(m.consume_glue_drop(0))
	assert_false(m.debug_queue_special(0, &"bomb"))
	assert_false(m.request_use_gift_slot(0))
	assert_ne(m.request_place(0, Vector3.ZERO, 0, Quaternion.IDENTITY, false), PlacementRules.REASON_OK,
		"a pre-activation placement is refused, never accepted")
	assert_ne(m.request_throw(0, Vector3.ZERO, 0, Quaternion.IDENTITY, Vector3.ZERO),
		PlacementRules.REASON_OK)
	assert_eq(m.preview_placement(0, Vector3.ZERO, 0, Quaternion.IDENTITY), PlacementRules.Result.EMPTY)
	assert_false(m.is_late_active(), "no-op commands never activate")


func test_process_and_physics_are_idle_before_activation() -> void:
	var m: MatchAutoload = _deferred()
	m._process(0.1)
	m._physics_process(0.1)
	assert_false(m.is_late_active())


func test_state_building_mutator_activates_lazily() -> void:
	var m: MatchAutoload = _deferred()
	m.apply_replicated_state_change(MatchPhase.State.LOBBY)
	assert_true(m.is_late_active(), "a replicated packet activates the controllers")
	assert_not_null(m._lifecycle)
	assert_eq(m.state(), MatchPhase.State.LOBBY)


func test_ensure_active_builds_controllers() -> void:
	var m: MatchAutoload = _deferred()
	m.set_net_provider(null)
	m.abort_match()
	assert_false(m.is_late_active())
	m._ensure_active()
	assert_true(m.is_late_active())


func test_match_net_getters_are_plain_lookups_before_activation() -> void:
	var m: MatchAutoload = _deferred()
	var net: Node = load("res://net/MatchNet.gd").new() as Node
	net.set("force_defer_activation", true)
	add_child_autofree(net)
	net.call(&"set_providers", null, m)
	assert_false(net.call(&"is_late_active"))
	assert_eq(net.call(&"intents_sent", 0), 0)
	assert_eq(net.call(&"intents_accepted", 0), 0)
	assert_eq(net.call(&"intents_refused", 0), 0)
	assert_eq(net.call(&"auto_drops", 0), 0)
	assert_eq(net.call(&"cursors_refused", 0), 0)
	assert_eq(net.call(&"replicated_block_count"), 0)
	assert_eq(net.call(&"duplicate_net_id_count"), 0)
	assert_true((net.call(&"cursor_for_slot", 0) as Dictionary).is_empty())
	assert_null(net.get("_weather_net"))
	net.call(&"reset_counters")
	assert_false(net.call(&"is_late_active"), "getters never activate MatchNet")
