extends Node3D
## Spec 2.9 / docs/M5_PLAN.md P5's own graded harness: eight `BotController`s
## driving a real match end to end (gifts on, every landed special enabled),
## the milestone's "finishes without errors" acceptance line, proven by the
## match actually *running*, not merely not crashing in the first second.
## Run headless:
##   godot --headless --path . res://tests/bench/bench_headless_bots.tscn
## Prints one machine-readable result line per scenario, then a combined
## `BENCH_HEADLESS_BOTS result=PASS|FAIL` line, then quits.
##
## **Must be a .tscn, not a -s script** -- same reason tests/bench/
## bench_specials_chain.gd's own header gives (autoload identifiers Match/
## Events do not resolve in a bare -s SceneTree).
##
## **Two scenarios, one process:**
## 1. `_run_scenario_normal()` -- 8 bot slots, gifts on, every landed special
##    enabled, a fixed seed, run for RUN_SECONDS (several placement windows
##    at MatchConfig.block_timer's default 6.0 s). PASS requires no
##    push_error/uncaught engine error logged during the run (a custom
##    Logger subclass below, the same OS.add_logger() mechanism GUT's own
##    addons/gut/error_tracker.gd uses to catch engine errors a plain
##    `try`/`except` cannot) **and** at least MIN_PLACEMENTS successful
##    Events.block_placed emits (or a player_eliminated/match_won, either of
##    which already proves the match ran for real).
## 2. `_run_scenario_starved()` -- the same fixture, rebuilt fresh
##    (Match.abort_match() -> a new Match.start_match()), with one bot slot's
##    home flag marked dead (`PlayerSlot.home_flag_alive = false`) before its
##    BotController ever starts thinking. `docs/M5_PLAN.md` P5's own wording
##    ("its slot eliminated or home overlapped") -- of the two, "eliminated"
##    is the one this bench can force deterministically with the public API
##    already available to a bench script; the milestone's actual pass/fail
##    line for this scenario is the physics-step budget, not which internal
##    branch handled it, so it satisfies "one bot's territory is starved"
##    without needing to reach into core/rules/ raster internals a bench has
##    no business touching. `# DECISION` (bench-only): this exercises
##    BotController._tick_idle()'s own cheap "no home flag, skip straight
##    back to IDLE" early-return every frame for that one bot, not literally
##    `_apply_rejection_backoff()` -- both are the same class of "a bot must
##    not spend its full candidate-generation budget when it has nothing
##    useful to do," which is what this scenario's frame-budget assertion
##    actually measures. asserts the physics-step average stays inside the
##    60 fps budget with 7 active bots + 1 permanently-idle one.
##
## Note: headless timing on any one machine is only a proxy for real in-game
## frame time (no rendering, no vsync, possibly different CPU contention),
## the same caveat every prior milestone's bench documents -- treat the
## printed numbers as a relative regression check, not an absolute 60 fps
## guarantee. A windowed run on real hardware is the owner's own manual step
## for that.

## Bench-only knobs (CLAUDE.md: no magic numbers scattered through the logic
## below) -- not gameplay tunables, so they live here rather than in a
## config/*.tres resource a real match would ever load.
const BOT_COUNT: int = 8
const RUN_SECONDS: float = 25.0
const STARVED_RUN_SECONDS: float = 10.0
## Loose floor: 8 bots over four-plus 6 s block_timer windows plausibly place
## several times each; MatchFeed's own auto-drop guarantees at least one per
## slot per window even in the worst case where every bot's own request is
## somehow rejected every cycle, so this is a smoke-test floor, not a tight
## bound.
const MIN_PLACEMENTS: int = 16
const TARGET_STEP_MS: float = 1000.0 / 60.0
## Well clear of bench_specials_chain.gd's own 20260923 seed, so a future
## third bench sharing this file's convention has an obvious next value to
## pick.
const RNG_SEED: int = 20260924
## Which trailing slot loses its home flag for the starved scenario -- any
## bot slot works; the last one keeps the "trailing ai_count slots are bots"
## convention obvious in the printed report.
const STARVED_SLOT: int = BOT_COUNT - 1
## A margin past Match.COUNTDOWN_SECONDS, same shape as tests/bench/
## bench_specials_chain.gd's own wait.
const COUNTDOWN_MARGIN_S: float = 0.5

var _field: Field = null
var _blocks_root: Node3D = null
var _registry: BlockRegistry = null
var _bot_controllers: Array[BotController] = []
var _placement_count: int = 0
var _eliminated_or_won: bool = false


## Godot's own Logger (OS.add_logger()/remove_logger()) -- the mechanism
## addons/gut/error_tracker.gd already uses to catch push_error() calls and
## uncaught engine-level errors alike, neither of which a plain GDScript
## try/except can observe. `_log_error` is Logger's virtual override; the
## exact signature (including `script_backtraces: Array[ScriptBacktrace]`)
## must match the engine's own or the override silently never fires.
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

	print(
		"BENCH_HEADLESS_BOTS start bots=%d run_seconds=%.1f starved_run_seconds=%.1f rng_seed=%d" % [
			BOT_COUNT, RUN_SECONDS, STARVED_RUN_SECONDS, RNG_SEED,
		]
	)

	var normal: Dictionary = await _run_scenario_normal()
	var starved: Dictionary = await _run_scenario_starved()

	OS.remove_logger(_error_logger)
	_report(normal, starved)


func _build_fixture() -> void:
	_field = Field.new()
	_field.map_def = MapDef.for_size(MapDef.MapSize.MEDIUM)
	add_child(_field)
	_blocks_root = Node3D.new()
	add_child(_blocks_root)
	_registry = BlockRegistry.new()
	add_child(_registry)
	Match.register_world(_field, _registry, _blocks_root)


func _teardown_fixture() -> void:
	_free_bot_controllers()
	Match.abort_match()
	_field.clear_match_state()
	_field.queue_free()
	_blocks_root.queue_free()
	_registry.queue_free()
	_field = null
	_blocks_root = null
	_registry = null


func _base_config() -> MatchConfig:
	var config: MatchConfig = (load("res://config/match_defaults.tres") as MatchConfig).duplicate(true) as MatchConfig
	config.map_size = MapDef.MapSize.MEDIUM
	config.player_count = BOT_COUNT
	config.ai_count = BOT_COUNT
	config.ai_difficulty = MatchConfig.AiDifficulty.NORMAL
	config.hot_seat = false
	config.sandbox = false
	config.rng_seed = RNG_SEED
	config.gifts_enabled = true
	# enabled_specials stays the shipped default (an empty Array) --
	# autoload/match/MatchGifts.gd's own doc: "empty means every special",
	# i.e. every landed special is already enabled with no override needed.
	return config


func _spawn_bot_controllers(config: MatchConfig) -> void:
	for slot_id: int in range(config.player_count):
		var bot: BotController = BotController.new()
		add_child(bot)
		bot.setup(slot_id, config.ai_difficulty, _field, _registry)
		_bot_controllers.append(bot)


func _free_bot_controllers() -> void:
	for bot: BotController in _bot_controllers:
		if bot != null and is_instance_valid(bot):
			bot.queue_free()
	_bot_controllers.clear()


func _on_block_placed(_block: RigidBody3D, _shape_id: StringName) -> void:
	_placement_count += 1


func _on_player_eliminated(_slot_id: int, _team_id: int) -> void:
	_eliminated_or_won = true


func _on_match_won(_team_id: int) -> void:
	_eliminated_or_won = true


## Polls one physics tick at a time via SceneTree's own `physics_frame`
## signal (emitted once per real physics step, whether or not the caller
## awaits it) rather than a manual _physics_process phase flag, so the two
## scenarios below can each just `await` their own measurement window
## sequentially. Only ticks while PLAYING are counted, so the countdown that
## precedes this call (always awaited separately, same as tests/bench/
## bench_specials_chain.gd) can never skew the averaged step time.
func _measure_ticks(seconds: float) -> Dictionary:
	var total_ticks: int = int(round(seconds * Engine.physics_ticks_per_second))
	var tick: int = 0
	var step_time_sum_ms: float = 0.0
	while tick < total_ticks:
		await get_tree().physics_frame
		if Match.state() != Match.State.PLAYING:
			continue
		tick += 1
		step_time_sum_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var avg_step_ms: float = step_time_sum_ms / float(tick) if tick > 0 else 0.0
	return {"avg_step_ms": avg_step_ms, "ticks": tick}


func _run_scenario_normal() -> Dictionary:
	_build_fixture()
	var config: MatchConfig = _base_config()
	Match.start_match(config)
	_spawn_bot_controllers(config)

	Events.block_placed.connect(_on_block_placed)
	Events.player_eliminated.connect(_on_player_eliminated)
	Events.match_won.connect(_on_match_won)

	await get_tree().create_timer(Match.COUNTDOWN_SECONDS + COUNTDOWN_MARGIN_S).timeout
	var placements_before: int = _placement_count
	_eliminated_or_won = false

	var timing: Dictionary = await _measure_ticks(RUN_SECONDS)

	Events.block_placed.disconnect(_on_block_placed)
	Events.player_eliminated.disconnect(_on_player_eliminated)
	Events.match_won.disconnect(_on_match_won)

	var placements: int = _placement_count - placements_before
	var errors_before_teardown: int = _error_logger.error_count
	_teardown_fixture()

	return {
		"avg_step_ms": timing["avg_step_ms"],
		"ticks": timing["ticks"],
		"placements": placements,
		"eliminated_or_won": _eliminated_or_won,
		"errors": errors_before_teardown,
	}


func _run_scenario_starved() -> Dictionary:
	_build_fixture()
	var config: MatchConfig = _base_config()
	Match.start_match(config)
	# Starve one bot's territory before it ever takes a single think-tick:
	# BotController._tick_idle() skips straight back to IDLE every frame a
	# slot's home_flag_alive is false (docs/M5_PLAN.md P5's own "DECISION"
	# above), so this bot spends this whole scenario doing the cheapest
	# possible thing every frame instead of a real generate/act cycle.
	var starved_slot: PlayerSlot = Match.slot(STARVED_SLOT)
	starved_slot.home_flag_alive = false
	_spawn_bot_controllers(config)

	await get_tree().create_timer(Match.COUNTDOWN_SECONDS + COUNTDOWN_MARGIN_S).timeout
	var errors_before_run: int = _error_logger.error_count

	var timing: Dictionary = await _measure_ticks(STARVED_RUN_SECONDS)

	var errors_after: int = _error_logger.error_count
	_teardown_fixture()

	return {
		"avg_step_ms": timing["avg_step_ms"],
		"ticks": timing["ticks"],
		"errors": errors_after - errors_before_run,
	}


func _report(normal: Dictionary, starved: Dictionary) -> void:
	var normal_activity_ok: bool = (
		int(normal["placements"]) >= MIN_PLACEMENTS or bool(normal["eliminated_or_won"])
	)
	var normal_ok: bool = int(normal["errors"]) == 0 and normal_activity_ok
	var starved_ok: bool = (
		int(starved["errors"]) == 0 and float(starved["avg_step_ms"]) <= TARGET_STEP_MS
	)
	var passed: bool = normal_ok and starved_ok

	print(
		(
			"BENCH_HEADLESS_BOTS scenario=normal placements=%d eliminated_or_won=%s "
			+ "avg_physics_step_ms=%.4f equivalent_fps=%.1f errors=%d"
		) % [
			int(normal["placements"]), bool(normal["eliminated_or_won"]),
			float(normal["avg_step_ms"]),
			1000.0 / float(normal["avg_step_ms"]) if float(normal["avg_step_ms"]) > 0.0 else 0.0,
			int(normal["errors"]),
		]
	)
	print(
		(
			"BENCH_HEADLESS_BOTS scenario=starved starved_slot=%d avg_physics_step_ms=%.4f "
			+ "equivalent_fps=%.1f target_step_ms=%.4f errors=%d"
		) % [
			STARVED_SLOT, float(starved["avg_step_ms"]),
			1000.0 / float(starved["avg_step_ms"]) if float(starved["avg_step_ms"]) > 0.0 else 0.0,
			TARGET_STEP_MS, int(starved["errors"]),
		]
	)
	if not _error_logger.messages.is_empty():
		for message: String in _error_logger.messages:
			print("BENCH_HEADLESS_BOTS logged_error: %s" % message)

	print(
		"BENCH_HEADLESS_BOTS result=%s bots=%d note=headless_timing_is_a_proxy_only" % [
			"PASS" if passed else "FAIL", BOT_COUNT,
		]
	)
	get_tree().quit(0 if passed else 1)
