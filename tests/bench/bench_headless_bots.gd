extends Node3D
## Spec 2.9 / docs/archive/M5_PLAN.md P5's own graded harness: eight `BotController`s
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
##    BotController ever starts thinking. `docs/archive/M5_PLAN.md` P5's own wording
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
## **E6 (Bontago-1t5.29, docs/BOT_AI_REDESIGN.md 2.5):** `-- --bot-brain=v2|legacy`
## [`--bot-brain-slots=<csv>`] [`--bot-difficulty=easy|normal|hard`] [`--run-seconds=<n>`] picks the decision pipeline (same flag names
## and meaning as game/MainHeadlessBotsFlow.gd; DECISION: the ~12-line parser is repeated here
## because the flow's own is an instance method of a Main-bound object). The bench ticks each
## bot itself (its own _physics_process is disabled) so one Time.get_ticks_usec pair brackets
## exactly one bot's per-frame work, then prints `BENCH_HEADLESS_BOTS e6 ...` with per-bot think
## time per frame (mean/p99/max over frames where the bot was thinking), the all-bots max per
## frame and the decision latency (feed boundary -> the bot's decision ready). No BotController
## timing hook is needed; the E6 bars are printed as e6_bars=PASS|FAIL and never gate `result=`.
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
## docs/BOT_AI_REDESIGN.md 2.5 E6 bars.
const E6_PER_BOT_MAX_MS: float = 1.2
const E6_ALL_BOTS_MAX_MS: float = 3.0
const E6_DECISION_LATENCY_MAX_S: float = 0.5
const P99_FRACTION: float = 0.99
const USEC_PER_MS: float = 1000.0
const ARG_BRAIN: String = "--bot-brain="
const ARG_BRAIN_SLOTS: String = "--bot-brain-slots="
const ARG_DIFFICULTY: String = "--bot-difficulty="
const ARG_RUN_SECONDS: String = "--run-seconds="

var _field: Field = null
var _blocks_root: Node3D = null
var _registry: BlockRegistry = null
var _bot_controllers: Array[BotController] = []
var _placement_count: int = 0
var _eliminated_or_won: bool = false
var _run_seconds: float = RUN_SECONDS
var _brain: BotController.Brain = BotController.Brain.LEGACY
var _brain_slots: PackedInt32Array = PackedInt32Array()
## E6 samples (normal scenario only): slot -> PackedInt64Array of usec per thinking frame.
var _think_us: Dictionary = {}
var _frame_total_us: PackedInt64Array = PackedInt64Array()
var _feed_frame: Dictionary = {}  # slot -> physics frame of the last feed boundary
var _latency_s: PackedFloat64Array = PackedFloat64Array()
## Cost of the IDLE -> THINKING tick (BotWorldView snapshot build), kept apart from the
## budgeted BotThink.step() frames so the report says which of the two breaks a bar.
var _begin_us: PackedInt64Array = PackedInt64Array()
## Cost of the ACTING tick (request_place / request_throw: spawns the block on the host).
var _act_us: PackedInt64Array = PackedInt64Array()
var _begin_frame: Dictionary = {}  # slot -> physics frame the bot started thinking
var _feed_latency_s: PackedFloat64Array = PackedFloat64Array()
var _difficulty: MatchConfig.AiDifficulty = MatchConfig.AiDifficulty.NORMAL
var _collect_e6: bool = false


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


func _arg(args: PackedStringArray, prefix: String) -> String:
	for a: String in args:
		if a.begins_with(prefix):
			return a.trim_prefix(prefix)
	return ""


func _parse_args() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var brain_text: String = _arg(args, ARG_BRAIN).to_lower()
	if brain_text == "v2":
		_brain = BotController.Brain.V2
	elif not brain_text.is_empty() and brain_text != "legacy":
		push_warning("--bot-brain=%s is not legacy|v2; legacy used" % brain_text)
	for part: String in _arg(args, ARG_BRAIN_SLOTS).split(",", false):
		if part.strip_edges().is_valid_int():
			_brain_slots.append(int(part))
	match _arg(args, ARG_DIFFICULTY).to_lower():
		"easy", "0":
			_difficulty = MatchConfig.AiDifficulty.EASY
		"hard", "2":
			_difficulty = MatchConfig.AiDifficulty.HARD
	var seconds_text: String = _arg(args, ARG_RUN_SECONDS)
	if seconds_text.is_valid_float():
		_run_seconds = float(seconds_text)


func _brain_name() -> String:
	return "v2" if _brain == BotController.Brain.V2 else "legacy"


func _ready() -> void:
	_parse_args()
	OS.add_logger(_error_logger)

	print(
		"BENCH_HEADLESS_BOTS start brain=%s bots=%d run_seconds=%.1f starved_run_seconds=%.1f rng_seed=%d" % [
			_brain_name(), BOT_COUNT, _run_seconds, STARVED_RUN_SECONDS, RNG_SEED,
		]
	)

	var normal: Dictionary = await _run_scenario_normal()
	var starved: Dictionary = await _run_scenario_starved()

	OS.remove_logger(_error_logger)
	_e6_report()
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
	config.ai_difficulty = _difficulty
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
		if _brain_slots.is_empty() or _brain_slots.has(slot_id):
			bot.set_brain(_brain)
		# The bench ticks each bot itself so one timer pair brackets one bot's frame work.
		bot.set_physics_process(false)
		_bot_controllers.append(bot)


func _free_bot_controllers() -> void:
	for bot: BotController in _bot_controllers:
		if bot != null and is_instance_valid(bot):
			bot.queue_free()
	_bot_controllers.clear()


func _on_block_placed(_block: RigidBody3D, _shape_id: StringName) -> void:
	_placement_count += 1


func _on_feed_issued(slot_id: int, _shape_id: StringName, _next_id: StringName) -> void:
	_feed_frame[slot_id] = Engine.get_physics_frames()


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
		_tick_bots()
	var avg_step_ms: float = step_time_sum_ms / float(tick) if tick > 0 else 0.0
	return {"avg_step_ms": avg_step_ms, "ticks": tick}


## Ticks every bot once (timed). A bot counts as thinking on a frame that starts in
## non-IDLE state or leaves IDLE (that tick builds the world snapshot); the decision is "ready"
## the first frame it reaches ACTING. Latency = start of thinking (the release boundary: the
## reaction delay, release lock and held shape are all satisfied) -> ACTING; the longer
## feed -> ACTING span (includes the reaction delay and release lock) is printed as feed_*.
func _tick_bots() -> void:
	var delta: float = 1.0 / float(Engine.physics_ticks_per_second)
	var frame_total_us: int = 0
	for bot: BotController in _bot_controllers:
		var slot_id: int = bot.bound_slot()
		var state_before: int = int(bot.get("_state"))
		var start_us: int = Time.get_ticks_usec()
		bot._physics_process(delta)
		var used_us: int = Time.get_ticks_usec() - start_us
		frame_total_us += used_us
		if not _collect_e6:
			continue
		var state_after: int = int(bot.get("_state"))
		var is_begin_tick: bool = state_before == BotController.State.IDLE and state_after != BotController.State.IDLE
		if is_begin_tick:
			_begin_us.append(used_us)
		elif state_before == BotController.State.ACTING:
			_act_us.append(used_us)
		elif state_before != BotController.State.IDLE or state_after != BotController.State.IDLE:
			var samples: PackedInt64Array = _think_us.get(slot_id, PackedInt64Array()) as PackedInt64Array
			samples.append(used_us)
			_think_us[slot_id] = samples
		if state_before == BotController.State.IDLE and state_after != BotController.State.IDLE:
			_begin_frame[slot_id] = Engine.get_physics_frames()
		if state_after == BotController.State.ACTING and _begin_frame.has(slot_id):
			_latency_s.append(float(Engine.get_physics_frames() - int(_begin_frame[slot_id])) * delta)
			if _feed_frame.has(slot_id):
				_feed_latency_s.append(float(Engine.get_physics_frames() - int(_feed_frame[slot_id])) * delta)
			_begin_frame.erase(slot_id)
	if _collect_e6:
		_frame_total_us.append(frame_total_us)


func _p99_us(samples: PackedInt64Array) -> int:
	if samples.is_empty():
		return 0
	var sorted: PackedInt64Array = samples.duplicate()
	sorted.sort()
	return sorted[mini(sorted.size() - 1, int(floor(float(sorted.size()) * P99_FRACTION)))]


func _e6_report() -> void:
	var worst_max_ms: float = 0.0
	for slot_id: int in _think_us.keys():
		var samples: PackedInt64Array = _think_us[slot_id]
		var sum_us: int = 0
		var max_us: int = 0
		for v: int in samples:
			sum_us += v
			max_us = maxi(max_us, v)
		worst_max_ms = maxf(worst_max_ms, float(max_us) / USEC_PER_MS)
		print("BENCH_HEADLESS_BOTS e6_bot slot=%d think_frames=%d mean_ms=%.3f p99_ms=%.3f max_ms=%.3f" % [
			slot_id, samples.size(), float(sum_us) / float(samples.size()) / USEC_PER_MS,
			float(_p99_us(samples)) / USEC_PER_MS, float(max_us) / USEC_PER_MS,
		])
	var begin_sum: int = 0
	var begin_max: int = 0
	for v: int in _begin_us:
		begin_sum += v
		begin_max = maxi(begin_max, v)
	print("BENCH_HEADLESS_BOTS e6_begin_tick (IDLE->THINKING snapshot build) count=%d mean_ms=%.3f p99_ms=%.3f max_ms=%.3f" % [
		_begin_us.size(), float(begin_sum) / maxf(1.0, float(_begin_us.size())) / USEC_PER_MS,
		float(_p99_us(_begin_us)) / USEC_PER_MS, float(begin_max) / USEC_PER_MS,
	])
	var act_sum: int = 0
	var act_max: int = 0
	for v: int in _act_us:
		act_sum += v
		act_max = maxi(act_max, v)
	print("BENCH_HEADLESS_BOTS e6_act_tick (ACTING: place/throw request) count=%d mean_ms=%.3f p99_ms=%.3f max_ms=%.3f" % [
		_act_us.size(), float(act_sum) / maxf(1.0, float(_act_us.size())) / USEC_PER_MS,
		float(_p99_us(_act_us)) / USEC_PER_MS, float(act_max) / USEC_PER_MS,
	])
	var all_max_us: int = 0
	for v: int in _frame_total_us:
		all_max_us = maxi(all_max_us, v)
	var lat_max: float = 0.0
	var lat_sum: float = 0.0
	for latency: float in _latency_s:
		lat_max = maxf(lat_max, latency)
		lat_sum += latency
	var feed_max: float = 0.0
	for latency: float in _feed_latency_s:
		feed_max = maxf(feed_max, latency)
	var lat_mean: float = lat_sum / float(_latency_s.size()) if not _latency_s.is_empty() else 0.0
	var all_max_ms: float = float(all_max_us) / USEC_PER_MS
	var bars_ok: bool = (
		maxf(maxf(worst_max_ms, float(begin_max) / USEC_PER_MS), float(act_max) / USEC_PER_MS) <= E6_PER_BOT_MAX_MS and all_max_ms <= E6_ALL_BOTS_MAX_MS
		and lat_max <= E6_DECISION_LATENCY_MAX_S
	)
	print(
		(
			"BENCH_HEADLESS_BOTS e6 brain=%s worst_think_step_max_ms=%.3f all_bots_max_frame_ms=%.3f "
			+ "decisions=%d latency_mean_s=%.3f latency_max_s=%.3f feed_latency_max_s=%.3f difficulty=%d bars(per_bot<=%.1f,all<=%.1f,lat<=%.1f) e6_bars=%s"
		) % [
			_brain_name(), worst_max_ms, all_max_ms, _latency_s.size(),
			lat_mean, lat_max, feed_max, int(_difficulty), E6_PER_BOT_MAX_MS, E6_ALL_BOTS_MAX_MS, E6_DECISION_LATENCY_MAX_S,
			"PASS" if bars_ok else "FAIL",
		]
	)


func _run_scenario_normal() -> Dictionary:
	_build_fixture()
	var config: MatchConfig = _base_config()
	Match.start_match(config)
	_spawn_bot_controllers(config)

	Events.block_placed.connect(_on_block_placed)
	Events.player_eliminated.connect(_on_player_eliminated)
	Events.match_won.connect(_on_match_won)
	Events.feed_block_issued.connect(_on_feed_issued)

	await get_tree().create_timer(Match.COUNTDOWN_SECONDS + COUNTDOWN_MARGIN_S).timeout
	var placements_before: int = _placement_count
	_eliminated_or_won = false
	_collect_e6 = true

	var timing: Dictionary = await _measure_ticks(_run_seconds)
	_collect_e6 = false
	Events.feed_block_issued.disconnect(_on_feed_issued)

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
	# slot's home_flag_alive is false (docs/archive/M5_PLAN.md P5's own "DECISION"
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
