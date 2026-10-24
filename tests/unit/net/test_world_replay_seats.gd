extends GutTest
## spec 2.4 / 1.8 mid-match seating policy of MatchWorldReplay, through its public surface:
## which seat a late joiner gets, whether a returning peer may reclaim its seat, and the
## slot-replay row built from the real host. Over the real Match and a FakeNet session.
## Each test names the seat-rule mutation it kills.

var _field: Field
var _registry: BlockRegistry
var _blocks_root: Node3D
var _net_config: NetConfig = preload("res://config/net/net_config.tres")


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()


func after_each() -> void:
	Match._net_provider = null
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _build_world() -> void:
	_field = Field.new()
	_field.map_def = MapDef.base().scaled(0.75)
	add_child_autofree(_field)
	_blocks_root = Node3D.new()
	add_child_autofree(_blocks_root)
	_registry = BlockRegistry.new()
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)


func _config(players: int, bots: int) -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.disc_size_step = 1
	config.player_count = players
	config.ai_count = bots
	config.team_mode = MatchConfig.TeamMode.OFF
	config.block_timer = 6.0
	config.rng_seed = 4242
	config.game_mode = MatchConfig.GameMode.CLASSIC
	config.round_timer_minutes = 5
	config.allow_mid_match_join = true
	return config


func _run_countdown() -> void:
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)


func _play(config: MatchConfig) -> void:
	Match.start_match(config)
	_run_countdown()
	assert_eq(Match.state(), Match.State.PLAYING, "fixture should reach PLAYING")


## The policy under test over a host session where `peer_slots` (peer id -> slot) hold seats.
func _replay(peer_slots: Dictionary) -> MatchWorldReplay:
	var session: FakeNet = FakeNet.host(peer_slots, [0])
	Match._net_provider = session
	return MatchWorldReplay.new(
		FakeSessionPort.new(session), MatchHostPort.new(Match), _net_config,
		WorldReplaySeams.make(Callable(), Callable())
	)


# --- pick_open_seat ------------------------------------------------------------

## Kills: picking the highest open seat; ignoring the held check (would return 0).
func test_the_lowest_open_human_seat_is_picked() -> void:
	_build_world()
	var replay: MatchWorldReplay = _replay({1: 0, 2: 2})
	_play(_config(4, 0))
	assert_eq(replay.pick_open_seat(), 1, "slots 0 and 2 are held: 1 is the lowest open")


## Kills: giving away a held seat, or stopping the scan at the first held seat.
func test_a_seat_held_by_a_peer_is_never_given_away() -> void:
	_build_world()
	var replay: MatchWorldReplay = _replay({1: 0, 2: 1, 3: 2})
	_play(_config(4, 0))
	assert_eq(replay.pick_open_seat(), 3)


## Kills: dropping the bot test (a joiner would evict a bot).
func test_a_bot_seat_is_never_taken() -> void:
	_build_world()
	var replay: MatchWorldReplay = _replay({1: 0, 2: 1})
	_play(_config(4, 2))
	assert_true(Match.slot(2).is_bot and Match.slot(3).is_bot, "fixture: slots 2 and 3 are bots")
	assert_eq(replay.pick_open_seat(), -1, "every human seat held, only bots left: spectate")


## Kills: treating an eliminated seat as open.
func test_an_eliminated_seat_is_skipped() -> void:
	_build_world()
	var replay: MatchWorldReplay = _replay({1: 0})
	_play(_config(3, 0))
	Match.slot(1).home_flag_alive = false
	assert_eq(replay.pick_open_seat(), 2, "slot 1 is out, 2 is the lowest open")


## Kills: ignoring the disconnect grace in the seat scan, or never releasing it.
func test_a_seat_reserved_by_a_disconnect_grace_is_skipped() -> void:
	_build_world()
	var replay: MatchWorldReplay = _replay({1: 0})
	_play(_config(3, 0))
	Match.on_peer_left(1)
	assert_gt(Match.disconnect_grace_left(1), 0.0, "fixture: slot 1 is in grace")
	assert_eq(replay.pick_open_seat(), 2, "the departed peer's seat is kept for it")
	Match.on_peer_rejoined(1)
	assert_eq(replay.pick_open_seat(), 1, "grace over: the seat is open again")


## Kills: returning the reserved seat when it is the only one left.
func test_every_seat_held_or_reserved_means_spectate() -> void:
	_build_world()
	var replay: MatchWorldReplay = _replay({1: 0})
	_play(_config(2, 0))
	Match.on_peer_left(1)
	assert_eq(replay.pick_open_seat(), -1)


## Kills: dropping the live-match check (lobby, countdown and aborted match would hand out seats).
func test_no_live_match_means_no_seat() -> void:
	_build_world()
	var replay: MatchWorldReplay = _replay({1: 0})
	assert_false(replay.is_match_live(), "no match yet")
	assert_eq(replay.pick_open_seat(), -1)
	Match.start_match(_config(2, 0))
	assert_true(replay.is_match_live(), "a started match admits a joiner from the countdown on")
	_run_countdown()
	assert_true(replay.is_match_live())
	assert_eq(replay.pick_open_seat(), 1, "playing: the open seat is offered")
	Match.abort_match()
	assert_false(replay.is_match_live(), "an aborted match is not live")
	assert_eq(replay.pick_open_seat(), -1)


# --- seat_reclaimable ----------------------------------------------------------

## Kills: dropping the grace test (a seat nobody left), or never expiring it.
func test_a_seat_is_reclaimable_only_while_its_grace_runs() -> void:
	_build_world()
	var replay: MatchWorldReplay = _replay({1: 0, 2: 1})
	_play(_config(2, 0))
	assert_false(replay.seat_reclaimable(1), "no grace running: nothing to reclaim")
	Match.on_peer_left(1)
	assert_true(replay.seat_reclaimable(1))
	assert_false(replay.seat_reclaimable(0), "only the seat that left")
	for _i: int in range(int(_net_config.disconnect_grace * 60.0) + 10):
		Match._process(1.0 / 60.0)
	assert_false(replay.seat_reclaimable(1), "the grace lapsed")


## Kills: dropping the home-flag test.
func test_a_seat_whose_home_flag_is_gone_is_not_reclaimable() -> void:
	_build_world()
	var replay: MatchWorldReplay = _replay({1: 0, 2: 1})
	_play(_config(2, 0))
	Match.on_peer_left(1)
	assert_true(replay.seat_reclaimable(1))
	Match.slot(1).home_flag_alive = false
	assert_false(replay.seat_reclaimable(1), "the home flag is gone")


## Kills: a bounds slip on slot ids.
func test_out_of_range_seats_are_not_reclaimable() -> void:
	_build_world()
	var replay: MatchWorldReplay = _replay({1: 0})
	_play(_config(2, 0))
	assert_false(replay.seat_reclaimable(-1))
	assert_false(replay.seat_reclaimable(99))


## Kills: dropping the live-match test.
func test_nothing_is_reclaimable_without_a_live_match() -> void:
	_build_world()
	var replay: MatchWorldReplay = _replay({1: 0})
	assert_false(replay.seat_reclaimable(0))


# --- slot_replay_args ----------------------------------------------------------

## Kills: wrong field order or source in the row, a row for the wrong slot.
func test_the_slot_replay_row_carries_the_hosts_feed_state() -> void:
	_build_world()
	var replay: MatchWorldReplay = _replay({1: 0})
	_play(_config(2, 0))
	Match._gifts._queue_claimed_special(1, &"anvil")
	var args: Array = replay.slot_replay_args(1)
	assert_eq(args.size(), 10, "the SLOT_REPLAY wire arity")
	assert_eq(args[0], 1)
	assert_eq(args[1], Match.held_shape(1).id)
	assert_eq(args[2], Match.next_shape(1).id)
	assert_eq(args[3], Match.feed_seq(1))
	assert_almost_eq(float(args[4]), Match.feed_time_left(1), 0.0001)
	assert_eq(args[8], &"anvil", "the staged gift rides in the after-next slot")
	var other: Array = replay.slot_replay_args(0)
	assert_eq(other[0], 0)
	assert_eq(other[1], Match.held_shape(0).id, "each slot gets its own row")
	assert_eq(other[8], &"")


## Kills: sending a row for a slot that holds nothing.
func test_a_slot_that_holds_nothing_has_no_row() -> void:
	_build_world()
	var replay: MatchWorldReplay = _replay({1: 0})
	_play(_config(2, 0))
	assert_eq(replay.slot_replay_args(-1), [], "no such slot")
	assert_eq(replay.slot_replay_args(99), [], "no such slot")


# --- host only -------------------------------------------------------------------

## Kills: dropping the host check (a client would hand out seats it does not own).
func test_a_client_session_hands_out_and_reclaims_nothing() -> void:
	_build_world()
	var host_replay: MatchWorldReplay = _replay({1: 0})
	_play(_config(3, 0))
	Match.on_peer_left(1)
	assert_eq(host_replay.pick_open_seat(), 2, "fixture: the host policy would offer seat 2")
	assert_true(host_replay.seat_reclaimable(1), "fixture: the host policy would let seat 1 back")
	var client_replay: MatchWorldReplay = MatchWorldReplay.new(
		FakeSessionPort.new(FakeNet.client(0)), MatchHostPort.new(Match), _net_config,
		WorldReplaySeams.make(Callable(), Callable())
	)
	assert_eq(client_replay.pick_open_seat(), -1)
	assert_false(client_replay.seat_reclaimable(1))
