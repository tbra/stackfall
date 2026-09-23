extends Node3D
## Spec 2.9 / docs/M5_PLAN.md P6's own graded acceptance scenario: a single
## Hard-difficulty BotController (slot 0) against a "passive player" (slot 1 --
## no PlayerController, no BotController, nothing) in a real 2-player match.
## Run headless:
##   godot --headless --path . res://tests/bench/bench_bot_vs_passive.tscn -- --seed=1
## Prints one machine-readable result line, then quits. Run at least 3 times
## with different --seed=<n> values (docs/M5_PLAN.md P6's own acceptance
## line) -- a single seeded pass is not proof the Hard bot reliably wins.
##
## **"Passive player", defined in docs/M5_PLAN.md P6:** a second slot that
## never receives any intent at all. Its held block still auto-drops at
## MatchPlacement.default_ghost_origin(slot_id) every window
## (autoload/match/MatchPlacement.gd's own "the slot's own home flag position
## is the honest stand-in") exactly as the existing auto-drop path already
## guarantees for any silent slot -- nothing in this bench script has to
## drive slot 1 at all; MatchFeed's own timer-expiry path does it.
##
## **Must be a .tscn, not a -s script** -- same reason tests/bench/
## bench_headless_bots.gd's own header gives (autoload identifiers Match/
## Events do not resolve in a bare -s SceneTree).
##
## Follows tests/bench/bench_headless_bots.gd's own Field/BlockRegistry/
## Match-direct fixture pattern (precedent, not a file dependency): a real
## host-authoritative match, no networking, one BotController driving slot 0
## through the same Match.request_place()/request_throw() entry points a
## human PlayerController uses.
##
## Note: headless timing on any one machine is only a proxy for real in-game
## frame time, the same caveat every prior milestone's bench documents.
##
## DECISION (tests/bench/bench_bot_vs_passive.gd): no Engine.time_scale
## acceleration. An earlier draft set Engine.time_scale > 1 to shrink this
## bench's up-to-600-sim-second wall-clock cost, but a measured seed=1 run at
## time_scale=10 proved it actively corrupts this match: autoload/Match.gd's
## own _process() (which drives MatchFeed._tick_feed()'s auto-drop countdown)
## has its delta scaled by Engine.time_scale, while physics ticks (this
## bench's own _run_ticks() loop, and everything Jolt actually simulates) do
## not speed up the same way -- under real machine contention the physics
## side barely kept pace with real time while the feed-timer side raced far
## ahead of it, so the passive slot's block_timer auto-drop fired roughly 9x
## too often relative to the physics clock (measured: 903 passive
## placements over a 600 s run that should hold ~100). None of tests/bench/
## bench_headless_bots.gd, bench_specials_chain.gd or bench_tower.gd use
## time_scale either -- this bench follows their own plain-real-time pattern
## instead. A run can take close to its own 600 s cap on real hardware
## (longer still under shared-machine contention); that is an accepted cost
## per docs/M5_PLAN.md P6 (three seeded runs, sim time is what is graded,
## not wall time).

## Bench-only knobs (CLAUDE.md: no magic numbers scattered through the logic
## below) -- not gameplay tunables, so they live here rather than in a
## config/*.tres resource a real match would ever load.
const PLAYER_COUNT: int = 2
const BOT_SLOT: int = 0
const PASSIVE_SLOT: int = 1
const AI_DIFFICULTY: MatchConfig.AiDifficulty = MatchConfig.AiDifficulty.HARD
const MAP_SIZE: MapDef.MapSize = MapDef.MapSize.MEDIUM
## docs/M5_PLAN.md P6: "600 real-seconds (10 * 60 * Engine.physics_ticks_per_
## second ticks)" -- counted in physics ticks the match spends in
## Match.State.PLAYING, not wall-clock seconds.
const TIMEOUT_SECONDS: float = 600.0
## --seed=<n>; a fixed default so a bare run (no args) is still reproducible.
const SEED_ARG_PREFIX: String = "--seed="
const DEFAULT_SEED: int = 1
## A margin past Match.COUNTDOWN_SECONDS is not needed here (unlike tests/
## bench/bench_headless_bots.gd's _measure_ticks): the tick loop below
## already skips every tick where Match.state() != PLAYING, so the countdown
## never contributes to the 600 s budget regardless of how long it takes.

var _field: Field = null
var _blocks_root: Node3D = null
var _registry: BlockRegistry = null
var _bot: BotController = null
var _seed: int = DEFAULT_SEED
var _bot_placements: int = 0
var _passive_placements: int = 0
var _match_won: bool = false
var _winner_team: int = -1


## Godot's own Logger (OS.add_logger()/remove_logger()) -- the mechanism
## addons/gut/error_tracker.gd already uses to catch push_error() calls and
## uncaught engine-level errors alike, neither of which a plain GDScript
## try/except can observe. Same shape as tests/bench/bench_headless_bots.gd's
## own BenchErrorLogger.
class BenchErrorLogger:
	extends Logger
	var error_count: int = 0
	var messages: Array[String] = []

	func _log_error(
		function: String, file: String, line: int, code: String, rationale: String,
		editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]
	) -> void:
		error_count += 1
		messages.append("%s:%d in %s(): %s (%s)" % [file, line, function, code, rationale])


var _error_logger: BenchErrorLogger = BenchErrorLogger.new()


func _ready() -> void:
	OS.add_logger(_error_logger)
	_parse_args()

	print(
		"BENCH_BOT_VS_PASSIVE start bot_slot=%d passive_slot=%d ai_difficulty=HARD seed=%d timeout_s=%.1f" % [
			BOT_SLOT, PASSIVE_SLOT, _seed, TIMEOUT_SECONDS,
		]
	)

	_build_fixture()
	var config: MatchConfig = _base_config()
	Match.start_match(config)
	_bot = BotController.new()
	add_child(_bot)
	_bot.setup(BOT_SLOT, AI_DIFFICULTY, _field, _registry)

	Events.block_placed.connect(_on_block_placed)
	Events.match_won.connect(_on_match_won)
	Events.feed_timer_expired.connect(_on_feed_timer_expired)

	var ticks: int = await _run_ticks()

	Events.block_placed.disconnect(_on_block_placed)
	Events.match_won.disconnect(_on_match_won)
	Events.feed_timer_expired.disconnect(_on_feed_timer_expired)

	var errors: int = _error_logger.error_count
	OS.remove_logger(_error_logger)

	_report(ticks, errors)


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(SEED_ARG_PREFIX):
			_seed = arg.substr(SEED_ARG_PREFIX.length()).to_int()


func _build_fixture() -> void:
	_field = Field.new()
	_field.map_def = MapDef.for_size(MAP_SIZE)
	add_child(_field)
	_blocks_root = Node3D.new()
	add_child(_blocks_root)
	_registry = BlockRegistry.new()
	add_child(_registry)
	Match.register_world(_field, _registry, _blocks_root)


func _base_config() -> MatchConfig:
	var config: MatchConfig = (load("res://config/match_defaults.tres") as MatchConfig).duplicate(true) as MatchConfig
	config.map_size = MAP_SIZE
	config.player_count = PLAYER_COUNT
	# DECISION (tests/bench/bench_bot_vs_passive.gd): ai_count stays 0 rather
	# than 1. MatchLifecycle._build_slots() sets PlayerSlot.is_bot off
	# ai_count's own trailing-slots convention (`i >= player_count -
	# ai_count`), which would mark slot 1 (not slot 0) as the bot -- the
	# opposite of docs/M5_PLAN.md P6's explicit "slot 0 = bot, slot 1 =
	# passive" setup. is_bot is never read by any placement/feed/territory
	# rule (grep confirms its only readers are MatchLifecycle's own
	# assignment, game/Main.gd's bot-spawning loop and UI/test assertions --
	# none of which this bench goes through), so leaving it false for both
	# slots costs nothing: this bench attaches its one BotController directly
	# to slot 0, exactly like tests/bench/bench_headless_bots.gd's own
	# _spawn_bot_controllers() attaches controllers directly rather than
	# relying on config.ai_count to do it.
	config.ai_count = 0
	config.ai_difficulty = AI_DIFFICULTY
	config.hot_seat = false
	config.sandbox = false
	# DECISION (docs/M5_PLAN.md P6): gifts_enabled = false for this specific
	# bench. A random special claim (by either side) would make the bench's
	# own pass/fail non-deterministic even at a fixed rng_seed, since a
	# crate's claim depends on the live territory solve, not the seed alone,
	# once physics settling time varies run to run. Real special use is
	# already proven deterministically by P3's own unit tests; this bench
	# isolates the placement/territory-scoring win condition.
	config.gifts_enabled = false
	# hole_mode = TEMPORARY and goal_flag_count = 1 already match
	# config/match_defaults.tres's own shipped defaults; set explicitly here
	# so this bench's setup is self-documenting without a reader having to
	# cross-check the .tres file.
	config.hole_mode = MatchConfig.HoleMode.TEMPORARY
	config.goal_flag_count = 1
	config.rng_seed = _seed
	return config


## Block.owner_slot (game/Block.gd) is set by MatchPlacement._spawn_block()
## for every spawned block, including a burned auto-drop -- the one existing
## per-slot attribution Events.block_placed's own (block, shape_id) signature
## doesn't carry directly, so this reads it off the block instead of adding
## new instrumentation to shipped match code.
func _on_block_placed(block: RigidBody3D, _shape_id: StringName) -> void:
	if block == null or not (block is Block):
		return
	var owner_slot: int = (block as Block).owner_slot
	if owner_slot == BOT_SLOT:
		_bot_placements += 1
	elif owner_slot == PASSIVE_SLOT:
		_passive_placements += 1


func _on_match_won(team_id: int) -> void:
	_match_won = true
	_winner_team = team_id


## DECISION (tests/bench/bench_bot_vs_passive.gd): reproduces net/MatchNet.gd's
## own `_on_feed_timer_expired()` "the host drops for every slot it does not
## itself control, from the last cursor it received" fallback (with no cursor
## ever received for a truly silent slot, `default_ghost_origin(slot_id)` is
## exactly what MatchNet itself falls back to). autoload/match/MatchFeed.gd
## only *emits* Events.feed_timer_expired -- the actual auto-drop call
## normally comes from net/MatchNet.gd (a live Net/session layer) or
## game/PlayerController.gd (a human/bot controller), neither of which this
## bench's Field/BlockRegistry/Match-direct fixture (tests/bench/
## bench_headless_bots.gd's own precedent) constructs. Without this handler
## the passive slot's blocks never leave its hand at all (confirmed by a
## seed=1 run: passive_placements=0 across the full 600 s budget) --
## "passive" per docs/M5_PLAN.md P6 means "plays exactly as badly as a human
## who never touches the controls," not "never places a single block," so
## this bench supplies the same fallback net/MatchNet.gd would have, using
## only Match's own public request_place()/default_ghost_origin()/feed_seq()
## API -- no game code changed. feed_seq is left at request_place()'s -1
## sentinel ("trusted local caller", autoload/Match.gd's own doc comment),
## matching how every other host-local call in this fixture already works.
func _on_feed_timer_expired(slot_id: int) -> void:
	if slot_id != PASSIVE_SLOT:
		return
	Match.request_place(
		PASSIVE_SLOT, Match.default_ghost_origin(PASSIVE_SLOT), 0, Quaternion.IDENTITY, true
	)


## Polls one physics tick at a time via SceneTree's own physics_frame signal,
## same mechanism tests/bench/bench_headless_bots.gd's own _measure_ticks()
## uses. Only ticks while PLAYING are counted, so the pre-match countdown
## never eats into the 600 s budget. Stops early the instant Events.match_won
## fires.
func _run_ticks() -> int:
	var total_ticks: int = int(round(TIMEOUT_SECONDS * Engine.physics_ticks_per_second))
	var tick: int = 0
	while tick < total_ticks and not _match_won:
		await get_tree().physics_frame
		if Match.state() != Match.State.PLAYING:
			continue
		tick += 1
	return tick


func _report(ticks: int, errors: int) -> void:
	var elapsed_s: float = float(ticks) / float(Engine.physics_ticks_per_second)
	var passed: bool = errors == 0 and _winner_team == BOT_SLOT and elapsed_s < TIMEOUT_SECONDS

	if not _error_logger.messages.is_empty():
		for message: String in _error_logger.messages:
			print("BENCH_BOT_VS_PASSIVE logged_error: %s" % message)

	if not passed:
		# Cheap diagnosis for a timeout/loss: each slot's own territory share
		# at the moment the run ended (Match.team_of(slot_id) is the identity
		# function today -- MatchConfig.TeamMode beyond OFF is not
		# implemented, see config/MatchConfig.gd -- so team_id == slot_id).
		print(
			"BENCH_BOT_VS_PASSIVE diag bot_team_share=%.4f passive_team_share=%.4f match_won=%s" % [
				Match.territory_share(BOT_SLOT), Match.territory_share(PASSIVE_SLOT), _match_won,
			]
		)

	print(
		"BENCH_BOT_VS_PASSIVE result=%s winner_team=%d elapsed_s=%.2f seed=%d bot_placements=%d passive_placements=%d" % [
			"PASS" if passed else "FAIL", _winner_team, elapsed_s, _seed, _bot_placements, _passive_placements,
		]
	)
	get_tree().quit(0 if passed else 1)
