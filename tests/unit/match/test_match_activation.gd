extends GutTest
## S2c: Match builds its controllers in late_activate(), not in _ready()
## when Boot defers activation; the MatchContext answers null-object defaults until then.

var _previous_context: MatchContext = null


func before_each() -> void:
	_previous_context = MatchContext.installed()


func after_each() -> void:
	MatchContext.install(_previous_context)


func _inactive_context() -> MatchContext:
	var node: MatchAutoload = MatchAutoload.new()
	autofree(node)
	return MatchContextLive.new(node)


func test_context_answers_defaults_while_inactive() -> void:
	var context: MatchContext = _inactive_context()
	assert_eq(context.state(), MatchPhase.State.LOBBY)
	assert_eq(context.slot_count(), 0)
	assert_null(context.slot(0))
	assert_eq(context.slot_color(0, Color.RED), Color.RED)
	assert_null(context.raster())
	assert_null(context.cell_grid())
	assert_eq(context.glue_drops_left(0), 0)
	assert_false(context.feed_timer_enabled())
	assert_eq(context.feed_time_left(0), 0.0)
	assert_false(context.has_weather())
	assert_false(context.grant_glue_drops(0, 1))
	assert_false(context.start_cat(0, Vector3.ZERO, null))
