extends GutTest
## every Match facade getter/command that Main, the menu, the lobby, the
## browsers or the HUD can reach before late_activate() answers an idle default and never errors;
## state-building mutators activate lazily. MatchNet's own getters are plain lookups.

var _previous_context: MatchContext = null


func before_each() -> void:
	_previous_context = MatchContext.installed()


func after_each() -> void:
	MatchContext.install(_previous_context)


## Net.host_game() emits net_mode_changed; Main's
## handler (connected first, in _ready) must activate Match + MatchNet before any later listener
## or poll runs. The real autoloads are put back into the pre-activation state first.
const MAIN_SCENE: PackedScene = preload("res://game/main/Main.tscn")

var _seen_after_main: Array[bool] = []


func _on_mode_after_main(_mode: int) -> void:
	_seen_after_main.append(Match.is_late_active() and MatchNet.is_late_active())


const MATCH_CONTROLLER_FIELDS: PackedStringArray = [
	"_feed", "_placement", "_territory", "_lifecycle", "_gifts", "_stats", "_weather",
]
var _saved_match: Dictionary = {}
var _saved_gift_fx: Node = null
var _saved_weather_net: Node = null
## Events subscriptions of the subtrees taken out of the tree, as {signal, callable}.
var _saved_subscriptions: Array[Dictionary] = []


## Puts the live autoloads in the pre-activation state, keeping the old controllers aside so
## _restore_live_autoloads() can reinstate them exactly (test only).
func _unactivate_live_autoloads() -> void:
	_saved_match.clear()
	for field: String in MATCH_CONTROLLER_FIELDS:
		_saved_match[field] = Match.get(field)
	_saved_gift_fx = Match.get_node_or_null("GiftFxPresenter")
	_saved_weather_net = MatchNet.get_node_or_null("WeatherNet")
	_remember_subscriptions([_saved_gift_fx, _saved_weather_net])
	if _saved_gift_fx != null:
		Match.remove_child(_saved_gift_fx)
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
	_reinstate_subscriptions()
	for node: Node in [fresh_gift_fx, fresh_weather]:
		if node != null:
			node.free()
	Match._late_active = true
	MatchNet._late_active = true


## Notes every Events subscription held by a node of `roots`. Taking a subtree out of the tree
## runs its _exit_tree, which drops subscriptions made in _ready (WeatherPresenter and
## CloudCeiling on match_scope_reset); putting it back does not run _ready again, so the live
## autoloads would stay deaf to the match-scope reset for every later script in the process.
func _remember_subscriptions(roots: Array[Node]) -> void:
	_saved_subscriptions.clear()
	for sig: Dictionary in Events.get_signal_list():
		var signal_name: StringName = StringName(String(sig["name"]))
		for conn: Dictionary in Events.get_signal_connection_list(signal_name):
			var callable: Callable = conn["callable"]
			var target: Object = callable.get_object()
			for root: Node in roots:
				if root != null and target is Node and (target == root or root.is_ancestor_of(target as Node)):
					_saved_subscriptions.append({"signal": signal_name, "callable": callable})


## Re-connects the remembered subscriptions that the round trip dropped.
func _reinstate_subscriptions() -> void:
	for saved: Dictionary in _saved_subscriptions:
		var signal_name: StringName = saved["signal"]
		var callable: Callable = saved["callable"]
		if not Events.is_connected(signal_name, callable):
			Events.connect(signal_name, callable)
	_saved_subscriptions.clear()


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
	var tiny_map: MapDef = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
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
