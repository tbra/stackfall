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
## DECISION (tests/bench/bench_bot_vs_passive.gd, revised twice): Engine.
## time_scale acceleration IS used, but only once this bench's own tick-to-
## seconds arithmetic was made coherent with what Engine.time_scale actually
## does. A first attempt set Engine.time_scale=10 alone and a measured seed=1
## run was "corrupted" (903 passive placements over a 600 s run that should
## hold ~100). A second attempt (this file's own prior revision) guessed the
## cause was Engine.max_physics_steps_per_frame dropping ticks under load and
## raised that cap -- but two direct probes of this engine build (a bare
## SceneTree awaiting `physics_frame` 600 times, and a Node logging its own
## `_physics_process(delta)`/`_process(delta)`) proved that guess wrong:
## physics ticks fire at a REAL, ~unaccelerated Engine.physics_ticks_per_
## second cadence regardless of time_scale (600 ticks measured in 10.00 real
## seconds at time_scale=5) -- time_scale does not need more ticks per frame
## to "keep pace", so nothing was being dropped. What time_scale actually
## does (confirmed by the same probe: avg `_physics_process` delta was
## 0.0833 = 5/60 at time_scale=5, not the unscaled 1/60) is scale the
## *delta value* every _process()/_physics_process() callback receives --
## including autoload/Match.gd's own `_process(delta)` (which drives
## MatchFeed._tick_feed()'s auto-drop countdown) AND every Jolt physics step
## `Match._territory`/every RigidBody3D integrates against. One physics tick
## at time_scale=N therefore represents `N / Engine.physics_ticks_per_second`
## seconds of *simulated* match time, not the unscaled `1 /
## Engine.physics_ticks_per_second` this file's own `_run_ticks()`/`_report()`
## used to assume -- that mismatched conversion, not a dropped tick, is what
## actually produced the ~9x-too-many-placements symptom, and it reproduces
## on a totally idle machine with nothing to contend for.
## The fix: `_run_ticks()`'s own `total_ticks` target and `_report()`'s own
## `elapsed_s` both now multiply/divide by `_time_scale` (see both functions'
## own comments) -- fewer physics ticks are needed to reach the same
## simulated-second budget, which is also where this bench's actual
## wall-clock speedup comes from (physics ticks still cost the same real
## time each; time_scale needing fewer of them for the same sim-time budget
## is the entire saving, not a faster tick rate). Engine.max_physics_steps_
## per_frame is still raised a fixed, modest amount above its own default
## (PHYSICS_STEPS_PER_FRAME_BUFFER) as a defensive margin, independent of
## time_scale, purely against a genuinely slow single real frame (e.g. a
## territory solve or a run of rejected candidate generation) needing to
## catch up more than 8 backlogged ticks -- not the primary mechanism this
## time, but still cheap insurance the two direct probes above cannot rule
## out for this bench's own, heavier fixture. The SANITY CHECK below (derived
## from the live MatchConfig.block_timer: a truly passive slot's expected
## placement rate is 60.0 / block_timer per sim-minute, since its held block
## is only ever released by MatchFeed's own forced auto-drop at every
## interval boundary -- see autoload/match/MatchFeed.gd's `_tick_feed()`/
## `_consume_and_refeed()`) is kept regardless, as the actual guard against
## either mechanism recurring: if the observed rate drifts from that
## expectation beyond tolerance, the result is INVALID, not PASS/FAIL, no
## matter which future engine-timing detail caused it.
## None of tests/bench/bench_headless_bots.gd, bench_specials_chain.gd or
## bench_tower.gd need any of this: none of them grade a real-time-derived
## auto-drop cadence against a physics-tick count the way this bench's whole
## acceptance criterion does.
##
## DECISION, part 2 (Bontago-d5c.7/.12 checkpoint): once the arithmetic above
## was fixed, a seed=1 run at time_scale=5 still graded FAIL, with the bot
## placing at only ~5.2/min against the passive slot's own ~9.5/min (both
## should be near 10/min = 60/block_timer if neither is starved). A matched
## seed=1 run at time_scale=1 (this file's own default, below) placed at a
## clean 10.0/min for the same bot, same seed, same match state, over the
## same first 120 sim-seconds -- i.e. **the bot's own placement rate is not
## stable across time_scale**, so time_scale=5's own FAIL is not trustworthy
## evidence either way for Bontago-d5c.12 (the suspected Hard-bot
## placement-rate defect) and must not be graded. The likely reason (code
## read, not yet reproduced in isolation): game/BotController.gd's own
## GENERATING state is *frame-count*-sliced (`profile.candidates_per_frame`
## per real physics tick, independent of `delta`), so it costs the bot a
## fixed number of REAL ticks per think-cycle regardless of time_scale, while
## every interval-timing rule it is graded against (MatchFeed's own
## `block_timer` boundary) is *delta*-driven and therefore scales with
## time_scale like everything else in the revised DECISION above -- at a
## high enough time_scale, the bot's own fixed real-tick generation cost
## becomes a proportionally larger (inflated) slice of its shrinking
## sim-second budget, which no other slot in this bench (the passive slot's
## whole cadence is 100% delta-driven) suffers from. **DEFAULT_TIME_SCALE is
## therefore 1.0 (no acceleration) for this file's own graded acceptance
## runs** -- back to docs/M5_PLAN.md P6's own "an accepted cost" real-time
## posture -- with `--time-scale=` kept available only for fast, non-graded
## exploration (it must never be used for an actual accept/reject verdict
## until BotController's own GENERATING slicing is made delta-driven too, an
## out-of-scope change for this bench-only package: game/BotController.gd's
## _tick_generating() would need its own review, not a quick fix here).
## A full seed=1 run at the corrected default (time_scale=1, 600 real
## seconds) CONFIRMS Bontago-d5c.12 is real and not a time_scale artefact:
## bot_placements=37 (3.7/min) against passive_placements=99 (9.9/min, sanity
## rel_error=0.010 -- this run's own timing is trustworthy), with only 13
## logged rejections (goal_zone=12, outside_territory=1) -- far too few
## backoffs (rejection_backoff_s=0.5 each) to account for a ~63-placement
## shortfall against the ~100 the interval cap allows. A shorter, separate
## time_scale=1 run (same seed, 120 s) measured a clean 10.0/min for this
## same bot early on, so its rate collapses well after that point rather
## than starting slow -- consistent with, but not independently reproduced
## as caused by, one candidate mechanism found by reading (not fixing, out
## of this package's ownership) autoload/match/MatchFeed.gd:
## `_consume_and_refeed()` only clears `_feed_expired[slot_id]` on its
## `auto_drop == true` branch (lines ~237-242) -- a *locally*-controlled slot
## (a human at the host's own keyboard, or a BotController, both always call
## `request_place(..., auto_drop=false, ...)`, see net/MatchNet.gd's own
## `_on_feed_timer_expired()`: "A slot this instance controls locally... is
## left to its own [Player]Controller", never auto-dropped by net code) that
## ever misses its own `block_timer` boundary even once latches
## `_feed_expired[slot_id]=true` permanently: no code path resets it again
## outside match start/hot-seat-turn-advance (grepped every write site in
## autoload/), so `_tick_feed()`'s own per-slot loop `continue`s forever
## after that point (see its `_feed_time_left[i] > 0.0 or _feed_expired[i]`
## guard), and `_release_locked[slot_id]` -- set true by that same slot's own
## next voluntary placement -- can then never be unlocked again either,
## permanently refusing every later `request_place()` for it with
## REASON_NO_BLOCK. This would explain a rate that is healthy early (nothing
## has missed a window yet) and permanently degraded after one unlucky
## rejection-retry chain pushes a single cycle past its own boundary -- but
## it is a hypothesis from reading, not an isolated repro, and it lives
## entirely in a file this package does not own; report to a MatchFeed-owning
## worker rather than fix here. **P6's own acceptance line cannot be
## satisfied while this holds**, regardless of which mechanism turns out to
## be the true cause, so seeds 2 and 3 were deliberately not run against the
## unfixed match code -- they would very likely reproduce the same shortfall
## without adding new evidence.

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

## --time-scale=<n>; see "DECISION, part 2" above. 1.0 (no acceleration) is
## this file's own default for a reason, not an oversight: a time_scale > 1
## was measured to inflate game/BotController.gd's own frame-count-sliced
## GENERATING cost relative to the sim-second budget it is graded against,
## producing a materially different (and lower) bot placement rate than the
## same seed at time_scale=1 -- not a trustworthy acceleration for this
## bench's own graded acceptance runs. Pass a higher value only for fast,
## explicitly non-graded exploration (e.g. confirming the bench itself still
## runs end to end after an unrelated change), never to decide PASS/FAIL/
## INVALID for docs/M5_PLAN.md P6's own acceptance line.
const TIME_SCALE_ARG_PREFIX: String = "--time-scale="
const DEFAULT_TIME_SCALE: float = 1.0
## --timeout-s=<n>; overrides TIMEOUT_SECONDS for a short diagnostic run
## only (docs/AGENT_WORKFLOW.md probe-budget note) -- the graded acceptance
## run always uses the default 600.0 and never passes this.
const TIMEOUT_ARG_PREFIX: String = "--timeout-s="
## Engine.max_physics_steps_per_frame is raised to its own default (8) plus
## this buffer for the run (see the revised DECISION above) -- independent of
## _time_scale (two direct probes showed time_scale does not raise the
## per-frame tick demand at all), this is defensive insurance against a
## genuinely slow single real frame (e.g. a territory solve, or a run of
## rejected candidate generation) needing to catch up more backlogged ticks
## than the engine's own default cap allows.
const PHYSICS_STEPS_PER_FRAME_BUFFER: int = 8
## Sanity check (see the revised DECISION above): a truly passive slot's
## held block is only ever released by MatchFeed's forced auto-drop, exactly
## once per config.block_timer interval, so its expected placement rate is
## 60.0 / block_timer per sim-minute. Graded only once at least this many
## intervals have elapsed (a handful of intervals is not enough samples to
## judge a rate against); below that the check is skipped rather than judged
## on noise.
const SANITY_MIN_INTERVALS: float = 4.0
## How far the observed passive placement rate may drift from the expected
## one (relative fraction) before the run is graded INVALID instead of
## PASS/FAIL -- generous enough to absorb the +-1-interval edge effects a
## finite run always has, tight enough to still catch the ~9x corruption the
## revised DECISION above documents.
const SANITY_TOLERANCE_FRACTION: float = 0.2

var _field: Field = null
var _blocks_root: Node3D = null
var _registry: BlockRegistry = null
var _bot: BotController = null
var _seed: int = DEFAULT_SEED
var _time_scale: float = DEFAULT_TIME_SCALE
var _timeout_seconds: float = TIMEOUT_SECONDS
var _config: MatchConfig = null
var _original_time_scale: float = 1.0
var _original_max_physics_steps: int = 8
var _bot_placements: int = 0
var _passive_placements: int = 0
var _match_won: bool = false
var _winner_team: int = -1
var _passed: bool = false


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
	_apply_engine_time_scale()

	print(
		"BENCH_BOT_VS_PASSIVE start bot_slot=%d passive_slot=%d ai_difficulty=HARD seed=%d timeout_s=%.1f time_scale=%.2f max_physics_steps_per_frame=%d" % [
			BOT_SLOT, PASSIVE_SLOT, _seed, _timeout_seconds, _time_scale, Engine.max_physics_steps_per_frame,
		]
	)

	_build_fixture()
	_config = _base_config()
	Match.start_match(_config)
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
	_restore_engine_time_scale()
	get_tree().quit(0 if _passed else 1)


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(SEED_ARG_PREFIX):
			_seed = arg.substr(SEED_ARG_PREFIX.length()).to_int()
		elif arg.begins_with(TIME_SCALE_ARG_PREFIX):
			_time_scale = arg.substr(TIME_SCALE_ARG_PREFIX.length()).to_float()
		elif arg.begins_with(TIMEOUT_ARG_PREFIX):
			_timeout_seconds = arg.substr(TIMEOUT_ARG_PREFIX.length()).to_float()


## Coherent time_scale acceleration (see the revised DECISION above): raises
## Engine.max_physics_steps_per_frame alongside Engine.time_scale so a real
## frame that needs more physics ticks to keep the scaled clock's pace never
## has any of them silently dropped. Both originals are captured first so
## _restore_engine_time_scale() can put this process's engine state back
## exactly as it found it, regardless of pass/fail/invalid.
func _apply_engine_time_scale() -> void:
	_original_time_scale = Engine.time_scale
	_original_max_physics_steps = Engine.max_physics_steps_per_frame
	Engine.time_scale = _time_scale
	Engine.max_physics_steps_per_frame = maxi(
		_original_max_physics_steps, _original_max_physics_steps + PHYSICS_STEPS_PER_FRAME_BUFFER
	)


func _restore_engine_time_scale() -> void:
	Engine.time_scale = _original_time_scale
	Engine.max_physics_steps_per_frame = _original_max_physics_steps


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
## never eats into the budget. Stops early the instant Events.match_won
## fires.
##
## Bontago-d5c.7 (see the revised DECISION above): one physics tick at
## Engine.time_scale = `_time_scale` represents `_time_scale /
## Engine.physics_ticks_per_second` seconds of *simulated* match time, not
## the unscaled `1 / Engine.physics_ticks_per_second` this loop would need at
## time_scale=1 -- dividing by `_time_scale` here is what actually produces
## this bench's wall-clock speedup (fewer ticks needed for the same
## simulated-second budget; each tick still costs the same real time to
## execute). `_report()`'s own `elapsed_s` undoes the same division the
## other way, so the two stay in lockstep however `_time_scale` is set.
func _run_ticks() -> int:
	var total_ticks: int = int(round(
		_timeout_seconds * Engine.physics_ticks_per_second / _time_scale
	))
	var tick: int = 0
	while tick < total_ticks and not _match_won:
		await get_tree().physics_frame
		if Match.state() != Match.State.PLAYING:
			continue
		tick += 1
	return tick


## Sanity check (see the revised DECISION above): a passive slot's own
## placement rate is fully determined by config.block_timer, independent of
## the bot's own play -- if it drifts from that expectation by more than
## SANITY_TOLERANCE_FRACTION, this run's engine timing cannot be trusted and
## neither PASS nor FAIL is a meaningful verdict for it.
## Returns [is_valid: bool, note: String].
func _sanity_check(elapsed_s: float) -> Array:
	if _config == null or _config.block_timer <= 0.0:
		return [true, "skipped (block_timer<=0)"]
	var expected_per_min: float = 60.0 / _config.block_timer
	if elapsed_s < _config.block_timer * SANITY_MIN_INTERVALS:
		return [true, "skipped (elapsed_s=%.2f < %.2f min)" % [elapsed_s, _config.block_timer * SANITY_MIN_INTERVALS]]
	var actual_per_min: float = (float(_passive_placements) / elapsed_s) * 60.0
	var rel_error: float = absf(actual_per_min - expected_per_min) / expected_per_min
	var is_valid: bool = rel_error <= SANITY_TOLERANCE_FRACTION
	var note: String = "expected_per_min=%.3f actual_per_min=%.3f rel_error=%.3f" % [
		expected_per_min, actual_per_min, rel_error,
	]
	return [is_valid, note]


func _report(ticks: int, errors: int) -> void:
	# Bontago-d5c.7: the inverse of _run_ticks()'s own division -- each
	# counted tick represents `_time_scale / physics_ticks_per_second`
	# simulated seconds (see the revised DECISION above), not the unscaled
	# `1 / physics_ticks_per_second`.
	var elapsed_s: float = float(ticks) * _time_scale / float(Engine.physics_ticks_per_second)
	var sanity: Array = _sanity_check(elapsed_s)
	var sanity_valid: bool = bool(sanity[0])
	var sanity_note: String = String(sanity[1])
	var core_passed: bool = errors == 0 and _winner_team == BOT_SLOT and elapsed_s < _timeout_seconds
	var result: String = "INVALID" if not sanity_valid else ("PASS" if core_passed else "FAIL")
	_passed = result == "PASS"

	if not _error_logger.messages.is_empty():
		for message: String in _error_logger.messages:
			print("BENCH_BOT_VS_PASSIVE logged_error: %s" % message)

	if not core_passed or not sanity_valid:
		# Cheap diagnosis for a timeout/loss: each slot's own territory share
		# at the moment the run ended (Match.team_of(slot_id) is the identity
		# function today -- MatchConfig.TeamMode beyond OFF is not
		# implemented, see config/MatchConfig.gd -- so team_id == slot_id).
		print(
			"BENCH_BOT_VS_PASSIVE diag bot_team_share=%.4f passive_team_share=%.4f match_won=%s" % [
				Match.territory_share(BOT_SLOT), Match.territory_share(PASSIVE_SLOT), _match_won,
			]
		)

	print("BENCH_BOT_VS_PASSIVE sanity %s" % sanity_note)
	_report_bot_timeline(elapsed_s)

	print(
		"BENCH_BOT_VS_PASSIVE result=%s winner_team=%d elapsed_s=%.2f seed=%d bot_placements=%d passive_placements=%d" % [
			result, _winner_team, elapsed_s, _seed, _bot_placements, _passive_placements,
		]
	)


## Bontago-d5c.12 diagnostic: bot-side cadence, separate from the pass/fail
## line above -- how often the bot actually placed, and why every rejected
## request_place()/request_throw() came back the way it did (game/
## BotController.gd's own _apply_rejection_backoff(), the same reason
## PlacementRules.REASON_* already surfaces to a human PlayerController).
func _report_bot_timeline(elapsed_s: float) -> void:
	var bot_per_min: float = (float(_bot_placements) / elapsed_s) * 60.0 if elapsed_s > 0.0 else 0.0
	var rejections: Dictionary = _bot.rejection_counts() if _bot != null else {}
	print(
		"BENCH_BOT_VS_PASSIVE bot_timeline bot_placements=%d bot_placements_per_min=%.3f rejections=%s" % [
			_bot_placements, bot_per_min, _format_rejection_counts(rejections),
		]
	)


func _format_rejection_counts(counts: Dictionary) -> String:
	if counts.is_empty():
		return "(none)"
	var reasons: Array = counts.keys()
	reasons.sort()
	var parts: Array[String] = []
	for reason: Variant in reasons:
		parts.append("%s=%d" % [String(reason), int(counts[reason])])
	return ",".join(parts)
