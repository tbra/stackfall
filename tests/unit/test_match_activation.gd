extends GutTest
## Bontago-1pi.11.77.10 (S2c): Match builds its controllers in late_activate(), not in _ready()
## when Boot defers activation; the MatchContext answers null-object defaults until then.

var _previous_context: MatchContext = null


func before_each() -> void:
	_previous_context = MatchContext.installed()


func after_each() -> void:
	MatchContext.install(_previous_context)


func _deferred_match() -> MatchAutoload:
	var node: MatchAutoload = MatchAutoload.new()
	node.force_defer_activation = true
	add_child_autofree(node)
	return node


func test_deferred_instance_is_inactive_after_ready() -> void:
	var node: MatchAutoload = _deferred_match()
	assert_false(node.is_late_active())
	assert_null(node._feed)
	assert_null(node._lifecycle)
	assert_null(node._gift_fx)
	assert_false(node.is_processing())
	assert_false(node.is_physics_processing())


func test_context_answers_defaults_while_inactive() -> void:
	var node: MatchAutoload = _deferred_match()
	var context: MatchContext = node.context()
	assert_eq(context.state(), MatchPhase.State.LOBBY)
	assert_eq(context.slot_count(), 0)
	assert_null(context.slot(0))
	assert_eq(context.slot_color(0, Color.RED), Color.RED)
	assert_eq(context.active_slot(), -1)
	assert_null(context.raster())
	assert_null(context.cell_grid())
	assert_eq(context.qol_claim_radius(), 0.0)
	assert_eq(context.glue_drops_left(0), 0)
	assert_false(context.feed_timer_enabled())
	assert_eq(context.feed_time_left(0), 0.0)
	assert_false(context.has_weather())
	assert_false(context.grant_glue_drops(0, 1))
	assert_false(context.start_cat(0, Vector3.ZERO, null))


func test_late_activate_builds_controllers_in_order_once() -> void:
	var node: MatchAutoload = _deferred_match()
	node.late_activate()
	assert_true(node.is_late_active())
	for controller: RefCounted in [node._feed, node._placement, node._territory, node._lifecycle,
			node._gifts, node._stats, node._weather]:
		assert_not_null(controller)
	assert_eq(node._feed.get_script().resource_path, LateScripts.MATCH_FEED)
	assert_eq(node._weather.get_script().resource_path, LateScripts.MATCH_WEATHER)
	assert_not_null(node._gift_fx)
	assert_eq(node._gift_fx.get_script().resource_path, LateScripts.GIFT_FX_PRESENTER)
	assert_true(node.is_processing())
	var feed: RefCounted = node._feed
	var children: int = node.get_child_count()
	node.late_activate()
	assert_eq(node._feed, feed, "second call is a no-op")
	assert_eq(node.get_child_count(), children)
	assert_eq(node.state(), MatchPhase.State.LOBBY)


func test_headless_ready_activates_immediately() -> void:
	var node: MatchAutoload = MatchAutoload.new()
	add_child_autofree(node)
	assert_true(node.is_late_active())
	assert_not_null(node._lifecycle)
