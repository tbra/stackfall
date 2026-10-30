extends GutTest
## The HUD reads of the MatchContext port: the null object, the FakeMatchContext round trips and
## MatchContextLive against the real Match autoload before and during a match.

const SLOT: int = 2

var _saved: MatchContext = null
var _tiny_map: MapDef = null


func before_each() -> void:
	_saved = MatchContext.installed()
	Match.set_process(false)
	Match.abort_match()


func after_each() -> void:
	MatchContext.install(_saved)
	Match._net_provider = null
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _start_match() -> MatchConfig:
	_tiny_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	var field: Field = autofree(Field.new())
	field.map_def = _tiny_map
	add_child_autofree(field)
	var blocks_root: Node3D = autofree(Node3D.new())
	add_child_autofree(blocks_root)
	var registry: BlockRegistry = autofree(BlockRegistry.new())
	add_child_autofree(registry)
	Match.register_world(field, registry, blocks_root)
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 4
	config.ai_count = 2
	Match.start_match(config)
	return config


func test_null_object_hud_reads_are_neutral() -> void:
	MatchContext.install(null)
	var ctx: MatchContext = MatchContext.current()
	assert_null(ctx.next_shape(SLOT))
	assert_eq(ctx.feed_progress(SLOT), 1.0, "nothing is loading")
	assert_eq(ctx.qol_backlog_count(SLOT), 0)
	assert_false(ctx.qol_timer_paused(SLOT))
	assert_eq(ctx.max_height_for_slot(SLOT), 0.0)
	assert_eq(ctx.match_timer_left(), 0.0)
	assert_false(ctx.sudden_death_active())
	assert_eq(ctx.countdown_remaining(), 0.0)
	assert_eq(ctx.eliminated_by(SLOT), -1)
	assert_eq(ctx.gift_states().size(), 0)
	assert_eq(ctx.pending_special_count(SLOT), 0)
	assert_eq(ctx.next_special(SLOT), &"")
	assert_eq(ctx.after_next_special(SLOT), &"")
	assert_eq(ctx.gift_slot_count(SLOT), 0)
	assert_null(ctx.stats())
	assert_eq(ctx.state(), MatchPhase.State.LOBBY)


func test_fake_context_unset_slots_answer_the_null_object_defaults() -> void:
	var fake: FakeMatchContext = FakeMatchContext.new()
	MatchContext.install(fake)
	var ctx: MatchContext = MatchContext.current()
	assert_null(ctx.next_shape(SLOT))
	assert_eq(ctx.feed_progress(SLOT), 1.0)
	assert_eq(ctx.qol_backlog_count(SLOT), 0)
	assert_false(ctx.qol_timer_paused(SLOT))
	assert_eq(ctx.max_height_for_slot(SLOT), 0.0)
	assert_eq(ctx.eliminated_by(SLOT), -1)
	assert_eq(ctx.next_special(SLOT), &"")
	assert_eq(ctx.gift_slot_count(SLOT), 0)
	assert_eq(ctx.state(), MatchPhase.State.LOBBY)


func test_fake_context_round_trips_every_hud_read() -> void:
	var fake: FakeMatchContext = FakeMatchContext.new()
	var shape: BlockShape = load("res://config/blocks/cube.tres") as BlockShape
	fake.next_shape_by_slot[SLOT] = shape
	fake.feed_progress_by_slot[SLOT] = 0.25
	fake.qol_backlog_by_slot[SLOT] = 3
	fake.qol_paused_by_slot[SLOT] = true
	fake.max_height_by_slot[SLOT] = 4.5
	fake.match_timer_left_value = 12.5
	fake.sudden_death_value = true
	fake.countdown_remaining_value = 2.0
	fake.eliminated_by_slot[SLOT] = 1
	var states: Array[Dictionary] = [{"slot": SLOT}]
	fake.gift_states_value = states
	fake.pending_special_count_by_slot[SLOT] = 2
	fake.next_special_by_slot[SLOT] = &"rocket"
	fake.after_next_special_by_slot[SLOT] = &"bomb"
	fake.gift_slot_count_by_slot[SLOT] = 4
	var stats: RefCounted = RefCounted.new()
	fake.stats_value = stats
	fake.state_value = MatchPhase.State.PLAYING
	MatchContext.install(fake)
	var ctx: MatchContext = MatchContext.current()
	assert_same(ctx.next_shape(SLOT), shape)
	assert_eq(ctx.feed_progress(SLOT), 0.25)
	assert_eq(ctx.qol_backlog_count(SLOT), 3)
	assert_true(ctx.qol_timer_paused(SLOT))
	assert_eq(ctx.max_height_for_slot(SLOT), 4.5)
	assert_eq(ctx.match_timer_left(), 12.5)
	assert_true(ctx.sudden_death_active())
	assert_eq(ctx.countdown_remaining(), 2.0)
	assert_eq(ctx.eliminated_by(SLOT), 1)
	assert_eq(ctx.gift_states(), states)
	assert_eq(ctx.pending_special_count(SLOT), 2)
	assert_eq(ctx.next_special(SLOT), &"rocket")
	assert_eq(ctx.after_next_special(SLOT), &"bomb")
	assert_eq(ctx.gift_slot_count(SLOT), 4)
	assert_same(ctx.stats(), stats)
	assert_eq(ctx.state(), MatchPhase.State.PLAYING)
	assert_null(ctx.next_shape(SLOT + 1), "other slots stay at the default")
	assert_eq(ctx.feed_progress(SLOT + 1), 1.0)


func test_live_before_a_match_answers_the_idle_defaults() -> void:
	var live: MatchContext = Match.context()
	assert_eq(live.state(), MatchPhase.State.LOBBY)
	assert_null(live.next_shape(0))
	assert_eq(live.qol_backlog_count(0), 0)
	assert_false(live.qol_timer_paused(0))
	assert_eq(live.max_height_for_slot(0), 0.0)
	assert_eq(live.match_timer_left(), 0.0)
	assert_false(live.sudden_death_active())
	assert_eq(live.countdown_remaining(), 0.0)
	assert_eq(live.eliminated_by(0), -1)
	assert_eq(live.gift_states().size(), 0)
	assert_eq(live.pending_special_count(0), 0)
	assert_eq(live.next_special(0), &"")
	assert_eq(live.after_next_special(0), &"")
	assert_eq(live.gift_slot_count(0), 0)


func test_live_in_a_match_reads_what_the_match_reports() -> void:
	var config: MatchConfig = _start_match()
	var live: MatchContext = Match.context()
	assert_ne(live.state(), MatchPhase.State.LOBBY, "a started match leaves the lobby phase")
	assert_eq(live.state(), int(Match.state()))
	assert_eq(live.slot_count(), config.player_count)
	assert_not_null(live.stats(), "a live match has per-slot stats")
	assert_same(live.stats(), Match.stats())
	assert_eq(live.countdown_remaining(), Match.countdown_remaining())
	assert_eq(live.match_timer_left(), Match.match_timer_left())
	assert_eq(live.sudden_death_active(), Match.sudden_death_active())
	assert_eq(live.gift_states(), Match.gift_states())
	for slot_id: int in range(config.player_count):
		assert_same(live.next_shape(slot_id), Match.next_shape(slot_id))
		assert_eq(live.feed_progress(slot_id), Match.feed_progress(slot_id))
		assert_eq(live.qol_backlog_count(slot_id), Match.qol_backlog_count(slot_id))
		assert_eq(live.qol_timer_paused(slot_id), Match.qol_timer_paused(slot_id))
		assert_eq(live.max_height_for_slot(slot_id), Match.max_height_for_slot(slot_id))
		assert_eq(live.eliminated_by(slot_id), Match.eliminated_by(slot_id))
		assert_eq(live.pending_special_count(slot_id), Match.pending_special_count(slot_id))
		assert_eq(live.next_special(slot_id), Match.next_special(slot_id))
		assert_eq(live.after_next_special(slot_id), Match.after_next_special(slot_id))
		assert_eq(live.gift_slot_count(slot_id), Match.gift_slot_count(slot_id))
	assert_eq(live.eliminated_by(0), -1, "nobody has been eliminated at the start")
	assert_eq(live.max_height_for_slot(0), 0.0, "no blocks settled yet")


func test_live_returns_to_idle_defaults_after_abort() -> void:
	_start_match()
	Match.abort_match()
	var live: MatchContext = Match.context()
	assert_eq(live.state(), MatchPhase.State.LOBBY)
	assert_eq(live.countdown_remaining(), 0.0)
	assert_eq(live.match_timer_left(), 0.0)
