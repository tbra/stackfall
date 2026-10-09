extends GutTest
## MatchContext port (game/world/MatchContext.gd), MatchContextLive and FieldBody
## (docs/AUTOLOAD_DECOUPLING_PLAN.md, S1b).

var _saved: MatchContext = null


func before_each() -> void:
	_saved = MatchContext.installed()


func after_each() -> void:
	MatchContext.install(_saved)
	Match.set_net_provider(null)
	Match.abort_match()
	MatchTestReset.clear_world()


func test_null_object_defaults() -> void:
	MatchContext.install(null)
	var ctx: MatchContext = MatchContext.current()
	assert_not_null(ctx)
	assert_same(ctx, MatchContext.current(), "the null object is cached")
	assert_true(ctx.has_authority())
	assert_true(ctx.net_is_host())
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
	assert_eq(ctx.qol_claim_radius(), 0.0)
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


func test_install_installed_and_restore() -> void:
	var fake: FakeMatchContext = FakeMatchContext.new()
	MatchContext.install(fake)
	assert_same(MatchContext.installed(), fake)
	assert_same(MatchContext.current(), fake)
	MatchContext.install(null)
	assert_null(MatchContext.installed())
	assert_not_same(MatchContext.current(), fake)


func test_live_context_is_installed_after_boot() -> void:
	assert_not_null(Match.context())
	assert_true(Match.context() is MatchContextLive)
	assert_same(MatchContext.installed(), Match.context())


func test_predelete_uninstalls_only_its_own_context() -> void:
	var node: MatchAutoload = MatchAutoload.new()
	node._context = MatchContextLive.new(node)
	var fake: FakeMatchContext = FakeMatchContext.new()
	MatchContext.install(fake)
	node._notification(Object.NOTIFICATION_PREDELETE)
	assert_same(MatchContext.installed(), fake, "a foreign installed context is left alone")
	MatchContext.install(node._context)
	node._notification(Object.NOTIFICATION_PREDELETE)
	assert_null(MatchContext.installed(), "its own context is uninstalled")
	node.free()


func test_live_parity_with_match() -> void:
	var ctx: MatchContext = Match.context()
	assert_eq(ctx.state(), int(Match.state()))
	assert_eq(ctx.slot_count(), Match.slot_count())
	assert_eq(ctx.config(), Match.config)
	assert_eq(ctx.has_weather(), Match.weather() != null)
	assert_eq(ctx.active_slot(), Match.active_slot())
	assert_eq(ctx.shared_clock_seconds(), SnapshotSync.sky_cycle_seconds())


func test_live_world_accessors_after_register_world() -> void:
	var field: Field = Field.new()
	add_child_autofree(field)
	var registry: BlockRegistry = BlockRegistry.new()
	add_child_autofree(registry)
	var root: Node3D = Node3D.new()
	add_child_autofree(root)
	Match.register_world(field, registry, root)
	var ctx: MatchContext = Match.context()
	assert_same(ctx.field(), field)
	assert_same(ctx.registry(), registry)
	assert_same(ctx.blocks_parent(), root)


func test_authority_follows_provider_while_net_reads_stay_real() -> void:
	var ctx: MatchContext = Match.context()
	Match.set_net_provider(FakeNet.client(1))
	assert_false(ctx.has_authority(), "has_authority honours Match.set_net_provider (D3)")
	assert_eq(ctx.net_is_host(), Net.is_host(), "net_is_host ignores it (D3)")
	assert_eq(ctx.net_is_client(), Net.is_client())
	assert_eq(ctx.net_local_slot(), Net.local_slot())
	Match.set_net_provider(null)
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
	assert_not_null(fb.grid(), "Field overrides the grid() stub")


func test_field_body_base_stubs_are_inert() -> void:
	var base: FieldBody = FieldBody.new()
	add_child_autofree(base)
	assert_null(base.grid())
	assert_eq(base.tilt_vector(), Vector2.ZERO)
	assert_false(base.is_hole_cell(0))
	base.apply_tilt_impulse(Vector2.ONE, 1.0)
	base.apply_replicated_pose(Vector3.ZERO, Quaternion.IDENTITY)
	base.remove_fallen_block(null)


func test_fake_records_commands() -> void:
	var fake: FakeMatchContext = FakeMatchContext.new()
	fake.grant_glue_drops_result = true
	assert_true(fake.grant_glue_drops(2, 3))
	assert_eq(fake.grant_glue_drops_calls, [{"slot_id": 2, "count": 3}] as Array[Dictionary])
