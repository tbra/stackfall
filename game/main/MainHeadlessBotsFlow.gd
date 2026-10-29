class_name MainHeadlessBotsFlow
extends MainHeadlessBotsFlowPort
## The `--headless-host --bots=<n>` flow, split out of game/main/Main.gd.
## Main loads this script on demand through MenuPrewarmQueue; the flow owns its
## state and connects its own signals and timers.

## Diagnostics-only cadence of the `HEADLESS_BOTS` progress line; not a gameplay tunable.
const HEADLESS_BOTS_REPORT_INTERVAL_S: float = 5.0

## Diagnostics state, null/0 whenever no headless bot match runs.
var _headless_bots_report_timer: Timer = null
var _headless_bots_start_msec: int = 0
var _headless_bots_placements: int = 0
## `--loop-matches` state. Index 0 = no bot match started yet; the args are the command
## line the loop restarts from.
var _headless_loop_enabled: bool = false
var _headless_loop_index: int = 0
var _headless_loop_args: PackedStringArray = PackedStringArray()
## The lobby defaults every loop match starts from (Main's match_config).
var _base_match_config: MatchConfig = null
var _headless_loop_seed: int = -1
var _headless_loop_restart_pending: bool = false

## Physics frame at which the current bot match's diagnostics started (game-time origin).
var _headless_bots_start_physics_frame: int = 0


# --- Headless bot match: `--bots=<n>` -----------------
#
# `godot --headless --path . -- --headless-host --bots=<n> [--players=<n2>]
# [--seconds=<n3>]` starts a **real** networked match (config.sandbox = false;
# the real feed/territory/win loop) with `n` bot-driven
# seats and no human required to click the Lobby's Start button. Unlike
# --hot-seat/--sandbox this does NOT return early out of _ready(): Events wiring
# is already connected and Net.apply_command_line() has already run host_game(),
# so Match.start_match()'s (LOBBY -> LOADING) emit runs the normal
# _build_match_world() exactly as a lobby-started match would; only the wait for a
# human to press Start is skipped, so one bot-controller wiring serves both this
# entry point and a mixed human+bot lobby match. host_game() can still fail (port
# already bound, say) and leave Net at OFFLINE; _net_is_hosting()'s guard refuses
# to build a match in that case rather than running every bot against a session
# nothing can join.

func start_match_with_args(args: PackedStringArray, base_config: MatchConfig) -> void:
	var bots: int = _bots_arg(args)
	if bots <= 0:
		# Feature off by default: every existing `--headless-host`-only
		# command line (no `--bots=`) falls straight through to the normal
		# Lobby wait-for-Start path, unaffected.
		return
	if not _net_is_hosting():
		# --headless-host's host_game() call can fail to bind its port and leave Net at
		# OFFLINE. Net.is_host() cannot see that (it is true on the host **and
		# offline**), so _net_is_hosting() checks Net.mode() directly. A bot match with
		# nobody hosting would run the whole loop against a session no client could
		# reach.
		push_error(
			"--headless-host --bots=%d: Net never became the host (host_game() likely failed to bind its port) -- refusing to start a bot match with no host." % bots
		)
		return
	Match.register_world(world.field, world.registry, world.blocks_container)
	_headless_loop_enabled = _has_loop_matches_arg(args)
	_headless_loop_args = args
	_base_match_config = base_config
	_headless_loop_index = 0
	if _headless_loop_enabled:
		Events.match_state_changed.connect(_on_headless_loop_state_changed)
	if not _headless_loop_enabled:
		# DECISION: a single (non-loop) match also prints its HEADLESS_MATCH line on
		# END, so tools/bot_h2h.py can parse winner_team without --loop-matches.
		Events.match_state_changed.connect(_on_headless_single_state_changed)
	_setup_think_cost(args, bots)
	_start_headless_loop_match(bots, args)

	# `--seconds=<n>` bounds the run with a hard wall-clock quit: the
	# acceptance command has no real win condition to end on within a CI
	# harness's patience.
	var seconds: float = _seconds_arg(args)
	if seconds > 0.0:
		world.parent.get_tree().create_timer(seconds).timeout.connect(_on_headless_bots_seconds_elapsed)


# --- Hard-bot think cost report: `--bot-think-cost=<file>` ---------------------
# Turns on BotThinkCostCollector (unbounded window), runs the match for `--bot-think-cost-seconds=<n>` match
# seconds (default config/bots/bot_think_cost.tres default_duration_s), then prints the BOT_THINK_COST lines and a
# table, writes them to <file> and quits. Combine with --mode=, --bot-difficulty=hard, --match-seed=.
# tools/run_bot_think_cost.ps1 runs the four scenarios.

const THINK_COST_FILE_ARG: String = "bot-think-cost="
const THINK_COST_SECONDS_ARG: String = "bot-think-cost-seconds="

var _think_cost_file: String = ""


func _setup_think_cost(args: PackedStringArray, bots: int) -> void:
	_think_cost_file = MatchLaunch.arg_value(args, THINK_COST_FILE_ARG)
	if _think_cost_file.is_empty():
		return
	var mode: int = MatchLaunch.mode_arg(args)
	var label: String = "mode%d_bots%d" % [mode, bots]
	BotThinkCostCollector.enable(label, 0)
	var seconds: String = MatchLaunch.arg_value(args, THINK_COST_SECONDS_ARG)
	var duration: float = float(seconds) if seconds.is_valid_float() else BotThinkCostReport.SHIPPED_TUNING.default_duration_s
	world.parent.get_tree().create_timer(duration).timeout.connect(_on_think_cost_elapsed)


func _on_think_cost_elapsed() -> void:
	var collector: BotThinkCostCollector = BotThinkCostCollector.current()
	var lines: PackedStringArray = PackedStringArray()
	if collector == null or not collector.has_data():
		lines.append("%s no data (no think finished)" % BotThinkCostReport.TAG)
	else:
		lines.append_array(collector.aggregate().render_lines())
		lines.append_array(collector.aggregate().render_table())
	for line: String in lines:
		print(line)
	var file: FileAccess = FileAccess.open(_think_cost_file, FileAccess.WRITE)
	if file == null:
		push_error("--bot-think-cost: cannot write %s" % _think_cost_file)
	else:
		for line: String in lines:
			file.store_line(line)
		file.close()
	Sfx.quit_tree()


## Builds and starts one headless bot match. With --loop-matches, each match
## after the first gets a fresh rng_seed.
func _start_headless_loop_match(bots: int, args: PackedStringArray) -> void:
	# DECISION: Net.match_config_override() (--match-config=<path>) replaces the default config as the source.
	var base_config: MatchConfig = Net.match_config_override()
	if base_config == null:
		base_config = _base_match_config
	var config: MatchConfig = MatchLaunch.headless_bot_config(base_config, bots, args)
	_headless_loop_index += 1
	var has_match_seed: bool = MatchLaunch.has_match_seed_arg(args)
	if _headless_loop_enabled:
		# DECISION: match 1 keeps the configured seed when one is
		# set; every later match draws a fresh positive seed so repeats differ.
		if has_match_seed:
			# DECISION: with --match-seed the later loop matches derive their
			# seeds deterministically from it instead of drawing fresh random ones.
			config.rng_seed = _derived_loop_seed(MatchLaunch.match_seed_arg(args), _headless_loop_index)
		elif _headless_loop_index > 1 or config.rng_seed < 0:
			config.rng_seed = randi_range(1, 2147483647)
		_headless_loop_seed = config.rng_seed
	else:
		_headless_loop_seed = config.rng_seed
	Match.start_match(config)
	_start_headless_bots_diagnostics()


## `--loop-matches`, same "-"-stripping convention as the other flags.
func _has_loop_matches_arg(args: PackedStringArray) -> bool:
	for raw: String in args:
		if raw.lstrip("-") == "loop-matches":
			return true
	return false


## on END print one compact `HEADLESS_MATCH` summary line and
## restart on the next frame (deferred, so the END emit finishes first; the
## restart goes END -> LOBBY -> LOADING, which tears the old world down).
func _on_headless_loop_state_changed(_from_state: int, to_state: int) -> void:
	if to_state != Match.State.END or _headless_loop_restart_pending:
		return
	print(_headless_match_summary_line())
	_headless_loop_restart_pending = true
	_restart_headless_loop_match.call_deferred()


func _on_headless_single_state_changed(_from_state: int, to_state: int) -> void:
	if to_state == Match.State.END:
		print(_headless_match_summary_line())


func _restart_headless_loop_match() -> void:
	_headless_loop_restart_pending = false
	if not _headless_loop_enabled or not _net_is_hosting() or Match.state() != Match.State.END:
		return
	_start_headless_loop_match(_bots_arg(_headless_loop_args), _headless_loop_args)


## `timed_out`: the --seconds cap hit with the match still PLAYING; the line then
## carries winner_team=-1 and a trailing `timeout=1` (tools/bot_h2h.py counts it as a draw).
func _headless_match_summary_line(timed_out: bool = false) -> String:
	var line: String = "HEADLESS_MATCH index=%d mode=%d seed=%d duration=%.1f winner_team=%d placements=%d homes_alive=%d teams=%s" % [
		_headless_loop_index,
		Match.config.game_mode if Match.config != null else 0,
		_headless_loop_seed, _headless_bots_elapsed_s(), -1 if timed_out else Match.winner_team(),
		_headless_bots_placements, _headless_bots_homes_alive(), _headless_slot_teams(),
	]
	# Appended after `teams=` so the bot_h2h.py regexes keep matching.
	line += " stats=%s" % _headless_stats_string()
	line += " appetite=%s" % _headless_appetite_string()
	return line + " timeout=1" if timed_out else line


## per-slot `slot:placed/lost/peak_height_m` (comma-separated), read from the live
## MatchStats, so bot_h2h-style logs can show blocks lost per placement and tower height.
## Appended after teams= so the existing regexes keep matching.
## a 4th field, peak180 = peak height reached by 180 s of match time (the height
## gate). DECISION: sampled on the 5 s report tick (so <=5 s late, peak is monotone); a match that
## ends before 180 s reports its final peak.
const PEAK_SNAPSHOT_S: float = 180.0
var _peak180: Dictionary = {}


func _snapshot_peak180() -> void:
	var stats: Variant = Match.stats()
	if stats == null or not _peak180.is_empty() or _headless_bots_elapsed_s() < PEAK_SNAPSHOT_S:
		return
	for i: int in range(Match.slot_count()):
		_peak180[i] = stats.height_reached(i)


func _headless_stats_string() -> String:
	var stats: Variant = Match.stats()
	if stats == null:
		return ""
	var parts: PackedStringArray = PackedStringArray()
	for i: int in range(Match.slot_count()):
		var p180: float = float(_peak180.get(i, stats.height_reached(i)))
		parts.append("%d:%d/%d/%.1f/%.1f" % [i, stats.blocks_placed(i), stats.blocks_lost(i), stats.height_reached(i), p180])
	return ",".join(parts)


## Bot slots' drawn risk appetites as `slot:value`, comma-separated; before any `timeout=` token.
func _headless_appetite_string() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for child: Node in world.parent.get_children():
		if child is BotController and not child.is_queued_for_deletion():
			parts.append((child as BotController).appetite_report())
	return ",".join(parts)


## Team id per slot, comma-separated ("0,1,2,..."), so a harness can map candidate seats to teams.
func _headless_slot_teams() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for i: int in range(Match.slot_count()):
		parts.append(str(Match.team_of(i)))
	return ",".join(parts)


## True only when Net actually became the HOST, unlike Net.is_host() (true on the
## host **and offline**), which cannot tell a genuine offline mode apart from
## --headless-host's host_game() having failed to bind. A helper so a test has one
## seam to force either outcome.
func _net_is_hosting() -> bool:
	return Net.mode() == Net.Mode.HOST


## `--bots=<n>`, same "-"-stripping/PREFIX convention as the other arg parsers.
## 0 when absent (feature off by default).
func _bots_arg(args: PackedStringArray) -> int:
	return int(MatchLaunch.arg_value(args, "bots="))


## `--seconds=<n>`, same convention. 0.0 (unbounded -- the match runs until a
## real win condition or the process is killed) when absent.
func _seconds_arg(args: PackedStringArray) -> float:
	return float(MatchLaunch.arg_value(args, "seconds="))


## diagnostics: per team, the most goals it holds in one group, "tN:k/total".
func _headless_bots_goal_coverage() -> String:
	var raster: TerritoryRaster = Match.raster()
	if raster == null or Match.config == null:
		return "n/a"
	var goals: PackedVector2Array = PlayerSlot.goal_positions_for(Match.config.effective_goal_flag_count(), Match.config.map_def())
	var by_group: Dictionary = {}
	for point: Vector2 in goals:
		var team: int = WinChecker.goal_holder(raster, point, Match.qol_claim_radius())
		if team < 0:
			continue
		var key: String = "%d/%d" % [team, raster.group_at_point(point)]
		by_group[key] = int(by_group.get(key, 0)) + 1
	var best_per_team: Dictionary = {}
	for key: String in by_group:
		var team_id: int = int(key.split("/")[0])
		best_per_team[team_id] = maxi(int(best_per_team.get(team_id, 0)), int(by_group[key]))
	var parts: PackedStringArray = PackedStringArray()
	for team_id: int in best_per_team:
		parts.append("t%d:%d/%d" % [team_id, int(best_per_team[team_id]), goals.size()])
	return "[%s]" % ",".join(parts)


# --- Headless bot match diagnostics ---------
#
# The `--headless-host --bots=8 --seconds=60` run has no console to watch, so this
# prints one `HEADLESS_BOTS` line every HEADLESS_BOTS_REPORT_INTERVAL_S and a final
# one right before the --seconds quit: wall-clock time since the match began,
# Match's state name and blocks placed so far (Events.block_placed fires for a
# bot's placements too). Diagnostics only: nothing here feeds a rule.
# BotController's own _state is not exposed, so bots_active is not reported.

func _start_headless_bots_diagnostics() -> void:
	# Idempotent: a --loop-matches restart must not double-connect
	# block_placed or leak a second report Timer.
	stop_diagnostics()
	_headless_bots_start_msec = Time.get_ticks_msec()
	_headless_bots_start_physics_frame = Engine.get_physics_frames()
	_headless_bots_placements = 0
	_peak180.clear()
	Events.block_placed.connect(_on_headless_bots_block_placed)
	_headless_bots_report_timer = Timer.new()
	_headless_bots_report_timer.wait_time = HEADLESS_BOTS_REPORT_INTERVAL_S
	_headless_bots_report_timer.autostart = true
	_headless_bots_report_timer.timeout.connect(_on_headless_bots_report_tick)
	world.parent.add_child(_headless_bots_report_timer)


## Torn down from _end_match_world(). Idempotent: a no-op when
## _start_headless_bots_diagnostics() never ran (report timer null, block_placed
## never connected).
func stop_diagnostics() -> void:
	if Events.block_placed.is_connected(_on_headless_bots_block_placed):
		Events.block_placed.disconnect(_on_headless_bots_block_placed)
	if _headless_bots_report_timer != null and is_instance_valid(_headless_bots_report_timer):
		_headless_bots_report_timer.queue_free()
	_headless_bots_report_timer = null


func _on_headless_bots_block_placed(_block: RigidBody3D, _shape_id: StringName) -> void:
	_headless_bots_placements += 1


func _on_headless_bots_report_tick() -> void:
	_snapshot_peak180()
	print(_headless_bots_periodic_line())


## The --seconds quit timer set up in start_match_with_args(): prints one last
## line (same counters as the periodic line) so the log always ends with a
## placements total, even when the process quits between two report ticks.
func _on_headless_bots_seconds_elapsed() -> void:
	print(_headless_bots_done_line())
	if Match.state() == Match.State.PLAYING:
		print(_headless_match_summary_line(true))
	Sfx.quit_tree()


func _headless_bots_periodic_line() -> String:
	return "HEADLESS_BOTS t=%.1f wall=%.1f state=%s placements=%d mode=%d homes_alive=%d frontier_gap=%.2f goals=%s" % [
		_headless_bots_elapsed_s(), _headless_bots_wall_s(), _headless_bots_state_name(), _headless_bots_placements,
		Match.config.game_mode if Match.config != null else 0, _headless_bots_homes_alive(),
		_headless_bots_frontier_gap(), _headless_bots_goal_coverage(),
	]


func _headless_bots_done_line() -> String:
	return "HEADLESS_BOTS done t=%.1f wall=%.1f placements=%d mode=%d homes_alive=%d" % [
		_headless_bots_elapsed_s(), _headless_bots_wall_s(), _headless_bots_placements,
		Match.config.game_mode if Match.config != null else 0, _headless_bots_homes_alive(),
	]


## diagnostics: smallest (distance to a living enemy home minus
## the circle's radius) over every circle, i.e. how close any team's influence
## frontier is to an enemy home (<= 0 means a circle covers one). -1 when n/a.
func _headless_bots_frontier_gap() -> float:
	var arrays: Dictionary = Match.circle_render_arrays()
	var xs: PackedFloat32Array = arrays.get("xs", PackedFloat32Array()) as PackedFloat32Array
	var zs: PackedFloat32Array = arrays.get("zs", PackedFloat32Array()) as PackedFloat32Array
	var radii: PackedFloat32Array = arrays.get("radii", PackedFloat32Array()) as PackedFloat32Array
	var teams: PackedInt32Array = arrays.get("teams", PackedInt32Array()) as PackedInt32Array
	var best: float = INF
	for i: int in range(mini(teams.size(), radii.size())):
		for slot_index: int in range(Match.slot_count()):
			var slot: PlayerSlot = Match.slot(slot_index)
			if slot == null or not slot.home_flag_alive or Match.team_of(slot_index) == teams[i]:
				continue
			best = minf(best, Vector2(xs[i], zs[i]).distance_to(slot.home_position) - radii[i])
	return best if best != INF else -1.0


## Living home flags (diagnostics: shows whether an Elimination bot match
## eliminated anyone).
func _headless_bots_homes_alive() -> int:
	var alive: int = 0
	for i: int in range(Match.slot_count()):
		var slot: PlayerSlot = Match.slot(i)
		if slot != null and slot.home_flag_alive:
			alive += 1
	return alive


## DECISION: the `t=` / `duration=` fields are GAME time (physics ticks), the same
## clock the --seconds SceneTree timer uses, so `done t=` matches the cap even under an unpaced
## `--fixed-fps 60` run; wall-clock seconds are printed as an extra `wall=` field.
func _headless_bots_elapsed_s() -> float:
	return float(Engine.get_physics_frames() - _headless_bots_start_physics_frame) / float(Engine.physics_ticks_per_second)


func _headless_bots_wall_s() -> float:
	return float(Time.get_ticks_msec() - _headless_bots_start_msec) / 1000.0


## Match.State's name for Match.state() (e.g. "PLAYING"), via Dictionary.find_key()
## on the enum. "UNKNOWN" only if Match.state() is a value the enum does not
## declare.
func _headless_bots_state_name() -> String:
	var key: Variant = Match.State.find_key(Match.state())
	return str(key) if key != null else "UNKNOWN"


# --- Training overrides ---------------------------------
#
# `--bot-difficulty=<easy|normal|hard|0..2>` sets every bot slot; `--bot-difficulty-slots=<slot:level,...>`
# (absolute slot ids; bots occupy the LAST `bots` of `--players` slots) overrides named bot slots only;
# `--round-timer=<minutes>` (0 = off, Elimination only) overrides the round timer after --mode;
# `--match-seed=<int>` is the first match's rng_seed.

const LOOP_SEED_STRIDE: int = 7919
const LOOP_SEED_MAX: int = 2147483647

## Seed of loop match `index` (1-based) from a base seed: index 1 is the base itself.
func _derived_loop_seed(base_seed: int, index: int) -> int:
	if index <= 1:
		return base_seed
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = base_seed + index * LOOP_SEED_STRIDE
	return rng.randi_range(1, LOOP_SEED_MAX)
