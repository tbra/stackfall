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


func _quiet_config() -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.weather_mode = MatchConfig.WeatherMode.OFF
	return config


## Bontago-1pi.11.85.2 review carry-over: the lazy path leaves the same state as the normal one.
func test_start_match_lazy_activation_matches_the_normal_path() -> void:
	var lazy: MatchAutoload = _deferred()
	var eager: MatchAutoload = _deferred()
	eager.late_activate()
	lazy.start_match(_quiet_config())
	eager.start_match(_quiet_config())
	assert_true(lazy.is_late_active(), "start_match activated lazily")
	assert_eq(lazy.state(), eager.state())
	assert_eq(lazy.slot_count(), eager.slot_count())
	assert_gt(lazy.slot_count(), 0)
	assert_eq(lazy.team_of(0), eager.team_of(0))
	assert_not_null(lazy.stats())
	assert_not_null(lazy._lifecycle)
	lazy.abort_match()
	eager.abort_match()


## A second replicated packet right after the first must not rebuild the controllers, and the
## first payload must be the one that landed.
func test_double_apply_replicated_activates_once_and_first_payload_lands() -> void:
	var m: MatchAutoload = _deferred()
	watch_signals(Events)
	m.apply_replicated_state_change(MatchPhase.State.LOADING)
	var lifecycle: RefCounted = m._lifecycle
	var feed: RefCounted = m._feed
	assert_eq(m.state(), MatchPhase.State.LOADING, "the first payload landed")
	m.apply_replicated_countdown(3)
	m.apply_replicated_state_change(MatchPhase.State.LOADING)
	assert_same(m._lifecycle, lifecycle, "controllers built exactly once")
	assert_same(m._feed, feed)
	assert_eq(m.get_child_count(), 1, "one GiftFxPresenter, not two")
	assert_eq(m.state(), MatchPhase.State.LOADING)


## Bontago-6a4 (review follow-up of 1pi.11.85.2): Net.host_game() emits net_mode_changed; Main's
## handler (connected first, in _ready) must activate Match + MatchNet before any later listener
## or poll runs. The real autoloads are put back into the pre-activation state first.
const MAIN_SCENE: PackedScene = preload("res://game/Main.tscn")

var _seen_after_main: Array[bool] = []


func _on_mode_after_main(_mode: int) -> void:
	_seen_after_main.append(Match.is_late_active() and MatchNet.is_late_active())


const MATCH_CONTROLLER_FIELDS: PackedStringArray = [
	"_feed", "_placement", "_territory", "_lifecycle", "_gifts", "_stats", "_weather",
]
var _saved_match: Dictionary = {}
var _saved_gift_fx: Node = null
var _saved_weather_net: Node = null


## Puts the live autoloads in the pre-activation state, keeping the old controllers aside so
## _restore_live_autoloads() can reinstate them exactly (test only).
func _unactivate_live_autoloads() -> void:
	_saved_match.clear()
	for field: String in MATCH_CONTROLLER_FIELDS:
		_saved_match[field] = Match.get(field)
	_saved_gift_fx = Match.get_node_or_null("GiftFxPresenter")
	if _saved_gift_fx != null:
		Match.remove_child(_saved_gift_fx)
	_saved_weather_net = MatchNet.get_node_or_null("WeatherNet")
	if _saved_weather_net != null:
		MatchNet.remove_child(_saved_weather_net)
	Events.feed_block_issued.disconnect(Match._on_feed_block_issued)
	Events.match_state_changed.disconnect(Match._on_cat_match_state_changed)
	Match._late_active = false
	MatchNet._late_active = false


## Drops everything the test's re-activation built and reinstates the original controllers,
## so later scripts see no duplicate Events handlers.
func _restore_live_autoloads() -> void:
	var fresh: Array[Object] = []
	for field: String in MATCH_CONTROLLER_FIELDS:
		fresh.append(Match.get(field) as Object)
	var fresh_gift_fx: Node = Match.get_node_or_null("GiftFxPresenter")
	var fresh_weather: Node = MatchNet.get_node_or_null("WeatherNet")
	if fresh_gift_fx != null:
		Match.remove_child(fresh_gift_fx)
		fresh.append(fresh_gift_fx)
	if fresh_weather != null:
		MatchNet.remove_child(fresh_weather)
		fresh.append(fresh_weather)
	_disconnect_targets(Events, fresh)
	for child: Node in get_tree().root.get_children():
		_disconnect_targets(child, fresh)
	if Events.feed_block_issued.is_connected(Match._on_feed_block_issued):
		Events.feed_block_issued.disconnect(Match._on_feed_block_issued)
	if Events.match_state_changed.is_connected(Match._on_cat_match_state_changed):
		Events.match_state_changed.disconnect(Match._on_cat_match_state_changed)
	Events.feed_block_issued.connect(Match._on_feed_block_issued)
	Events.match_state_changed.connect(Match._on_cat_match_state_changed)
	for field: String in MATCH_CONTROLLER_FIELDS:
		Match.set(field, _saved_match[field])
	if _saved_gift_fx != null:
		Match.add_child(_saved_gift_fx)
		Match.set("_gift_fx", _saved_gift_fx)
	if _saved_weather_net != null:
		MatchNet.add_child(_saved_weather_net)
		MatchNet.set("_weather_net", _saved_weather_net)
	for node: Node in [fresh_gift_fx, fresh_weather]:
		if node != null:
			node.free()
	Match._late_active = true
	MatchNet._late_active = true


func _disconnect_targets(source: Object, targets: Array[Object]) -> void:
	for sig: Dictionary in source.get_signal_list():
		for conn: Dictionary in source.get_signal_connection_list(sig["name"]):
			var callable: Callable = conn["callable"]
			if targets.has(callable.get_object()):
				source.disconnect(sig["name"], callable)


func test_net_mode_changed_activates_match_and_matchnet_before_any_later_listener() -> void:
	Match.set_process(false)
	Match.abort_match()
	SnapshotSync.end_match()
	assert_true(Net.is_offline(), "fixture: the real Net starts offline")
	var main: Variant = MAIN_SCENE.instantiate()
	var tiny_map: MapDef = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	tiny_map.field_radius = 20.0
	(main.get_node("Field") as Field).map_def = tiny_map
	add_child_autofree(main)
	_unactivate_live_autoloads()
	assert_false(Match.is_late_active() or MatchNet.is_late_active(), "fixture: pre-activation")
	_seen_after_main.clear()
	Events.net_mode_changed.connect(_on_mode_after_main)  # after Main's handler: stands in for the first poll/RPC
	assert_eq(Net.host_game(AgentProbe.free_udp_port(), "Hostie"), OK)
	Events.net_mode_changed.disconnect(_on_mode_after_main)
	assert_eq(_seen_after_main.size(), 1, "the later listener ran")
	assert_true(_seen_after_main[0], "Match and MatchNet were already active when it ran")
	assert_true(Match.is_late_active())
	assert_true(MatchNet.is_late_active())
	assert_not_null(MatchNet.get_node_or_null("WeatherNet"), "WeatherNet child built by activation")
	_restore_live_autoloads()
	Net.leave()
	Match.abort_match()
	SnapshotSync.end_match()
	Match.set_process(true)
	await get_tree().process_frame
