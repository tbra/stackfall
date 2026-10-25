extends GutTest
## MatchContext port (game/world/MatchContext.gd), MatchContextLive and FieldBody.

var _saved: MatchContext = null


func before_each() -> void:
	_saved = MatchContext.installed()


func after_each() -> void:
	MatchContext.install(_saved)
	Match._net_provider = null
	Match.abort_match()
	MatchTestReset.clear_world()


func test_null_object_defaults() -> void:
	MatchContext.install(null)
	var ctx: MatchContext = MatchContext.current()
	assert_not_null(ctx)
	assert_same(ctx, MatchContext.current(), "the null object is cached")
	assert_true(ctx.has_authority())
	assert_false(ctx.net_is_client())
	assert_true(ctx.net_is_offline())
	assert_eq(ctx.net_local_slot(), -1)
	assert_false(ctx.net_is_local_slot(0))
	assert_null(ctx.config())
	assert_null(ctx.physics_tuning())
	assert_eq(ctx.state(), MatchPhase.State.LOBBY)
	assert_eq(ctx.slot_count(), 0)
	assert_null(ctx.slot(0))
	assert_eq(ctx.slot_color(0, Color.RED), Color.RED)
	assert_eq(ctx.active_slot(), -1)
	assert_null(ctx.field())
	assert_null(ctx.registry())
	assert_null(ctx.blocks_parent())
	assert_null(ctx.raster())
	assert_null(ctx.cell_grid())
	assert_eq(ctx.glue_drops_left(0), 0)
	assert_false(ctx.feed_timer_enabled())
	assert_eq(ctx.feed_time_left(0), 0.0)
	assert_false(ctx.has_weather())
	assert_eq(ctx.weather_seed(), 0)
	assert_eq(ctx.weather_event_index(), 0)
	assert_eq(ctx.shared_clock_seconds(), 0.0)
	assert_false(ctx.start_cat(0, Vector3.ZERO, null))
	assert_false(ctx.grant_glue_drops(0, 1))
	assert_false(ctx.convert_block_owner(null, 0))
	assert_null(ctx.spawn_special_projectile(null, Vector3.ZERO, Basis.IDENTITY, 0, Vector3.ZERO, null, null))
	var orphan: Node = Node.new()
	ctx.add_match_child(orphan)
	assert_true(orphan.is_queued_for_deletion(), "the null context discards the node")
	orphan.free()


func test_authority_follows_provider_while_net_reads_stay_real() -> void:
	var ctx: MatchContext = Match.context()
	Match._net_provider = FakeNet.client(1)
	assert_false(ctx.has_authority(), "has_authority honours the injected net provider (D3)")
	assert_eq(ctx.net_is_client(), Net.is_client())
	assert_eq(ctx.net_local_slot(), Net.local_slot())
	Match._net_provider = null
	assert_true(ctx.has_authority())


func test_field_is_a_field_body_and_round_trips_disk_local() -> void:
	var field: Field = Field.new()
	add_child_autofree(field)
	assert_true(field is FieldBody)
	var fb: FieldBody = field
	assert_same(fb.map_definition(), field.map_def)
	field.position = Vector3(3.0, 0.5, -2.0)
	var local: Vector2 = Vector2(4.0, -1.5)
	var world: Vector3 = fb.world_from_disk_local(local, 0.25)
	assert_almost_eq(fb.disk_local_from_world(world), local, Vector2(0.0001, 0.0001))
	assert_almost_eq(fb.surface_y(), 0.5, 0.0001)



# --- local player: held view, reads and intents ------------------------------------------


func test_null_object_local_held_is_an_empty_stable_view() -> void:
	MatchContext.install(null)
	var ctx: MatchContext = MatchContext.current()
	var view: LocalHeldView = ctx.local_held()
	assert_not_null(view)
	assert_null(view.shape)
	assert_eq(view.slot_id, -1)
	assert_same(ctx.local_held(), view, "one store per context")


func test_null_object_local_player_reads_and_intents_are_neutral() -> void:
	MatchContext.install(null)
	var ctx: MatchContext = MatchContext.current()
	assert_null(ctx.held_shape(0))
	assert_eq(ctx.held_special(0), &"")
	assert_eq(ctx.feed_seq(0), 0)
	assert_false(ctx.is_release_locked(0))
	assert_eq(ctx.gift_slot_head(0), &"")
	assert_eq(ctx.default_ghost_origin(0), Vector3.ZERO)
	assert_null(ctx.active_cat())
	assert_eq(ctx.submit_place(0, Vector3.ZERO, 0, Quaternion.IDENTITY, false), &"")
	assert_eq(ctx.submit_throw(0, Vector3.ZERO, 0, Quaternion.IDENTITY, Vector3.FORWARD), &"")
	assert_false(ctx.submit_use_gift_slot(0))


func test_each_context_has_its_own_held_view() -> void:
	var a: FakeMatchContext = FakeMatchContext.new()
	var b: FakeMatchContext = FakeMatchContext.new()
	a.local_held().publish(1, load("res://config/blocks/cube.tres"), Vector3.ONE, 0,
			Quaternion.IDENTITY, true, 0.0, 10)
	assert_not_null(a.local_held().shape)
	assert_null(b.local_held().shape, "publishing into one context leaves another untouched")


func test_fake_context_view_is_readable_and_settable_through_the_port() -> void:
	var fake: FakeMatchContext = FakeMatchContext.new()
	MatchContext.install(fake)
	var mine: LocalHeldView = LocalHeldView.new()
	fake.set_local_held(mine)
	assert_same(MatchContext.current().local_held(), mine, "a reader sees the view the test supplied")
	MatchContext.current().local_held().publish(2, null, Vector3.UP, 1, Quaternion.IDENTITY, true, 1.0, 7)
	assert_eq(mine.slot_id, 2, "a writer through the port lands in the supplied view")
	assert_eq(mine.origin, Vector3.UP)


func test_live_context_returns_the_same_view_on_every_call() -> void:
	var live: MatchContext = Match.context()
	var view: LocalHeldView = live.local_held()
	assert_not_null(view)
	assert_same(live.local_held(), view)
	view.publish(0, null, Vector3(2.0, 0.0, 0.0), 0, Quaternion.IDENTITY, true, 0.0, 1)
	assert_eq(live.local_held().origin, Vector3(2.0, 0.0, 0.0), "a publish is visible to the next reader")
	view.clear()
