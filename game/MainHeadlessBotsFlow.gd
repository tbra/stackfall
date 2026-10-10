class_name MainHeadlessBotsFlow
extends MainHeadlessBotsFlowPort
## Bontago-1pi.11.84 (MF2): the `--headless-host --bots=<n>` flow moved verbatim out of game/Main.gd
## (docs/MENU_FIRST_PLAN.md 3.2). Main loads this script on demand through MenuPrewarmQueue and keeps a
## forwarder for every old member name; the state fields (_headless_*) stay on Main because tests
## and tools read them. DECISION: signal/timer callbacks connect to Main's forwarders so
## `Signal.is_connected(_main._on_headless_bots_block_placed)` keeps working.

## The Main node, typed (the port's `main` is the Node3D it binds).
var main_node: Main:
	get:
		return main as Main

## Physics frame at which the current bot match's diagnostics started (game-time origin).
var _headless_bots_start_physics_frame: int = 0


# --- Headless bot match: `--bots=<n>` (Bontago-d5c.6, M5 P5) -----------------
#
# `godot --headless --path . -- --headless-host --bots=<n> [--players=<n2>]
# [--seconds=<n3>]` starts a **real** networked match (config.sandbox = false,
# config.hot_seat = false -- the real feed/territory/win loop, unlike
# --sandbox above) with `n` bot-driven seats and no human required to click
# the Lobby's Start button. Unlike --hot-seat/--sandbox this does NOT return
# early out of _ready(): Events.match_state_changed/net_mode_changed are
# already connected and Net.apply_command_line() has already run host_game()
# for --headless-host by the time _ready() reaches this call, so
# Match.start_match() below's own (LOBBY -> LOADING) emit runs the normal
# _build_match_world() exactly as a lobby-started match would -- only the
# "wait for a human to press Start" step is skipped. This is deliberate: it
# is what lets _build_match_world()'s own bot-controller wiring (below) serve
# both this entry point and an ordinary mixed human+bot lobby match with one
# piece of code (docs/archive/M5_PLAN.md P5 item 3), rather than a second, divergent
# world-build path. host_game() can still fail (its port already bound, say)
# and leave Net at OFFLINE despite --headless-host being present on the
# command line; _net_is_hosting()'s guard below refuses to build a match in
# that case rather than silently running every bot against a session nothing
# can ever join.

func start_match_with_args(args: PackedStringArray) -> void:
	var bots: int = _bots_arg(args)
	if bots <= 0:
		# Feature off by default: every existing `--headless-host`-only
		# command line (no `--bots=`) falls straight through to the normal
		# Lobby wait-for-Start path, unaffected.
		return
	if not _net_is_hosting():
		# Bontago-d5c.6 review finding 1: --headless-host's own host_game()
		# call (Net.apply_command_line(), already run by the time _ready()
		# reaches this branch -- see this function's own doc above) can fail
		# to bind its port and leave Net at OFFLINE. Net.is_host() cannot see
		# that failure (autoload/Net.gd's own doc: "True on the host **and
		# offline**" -- offline is the normal, successful state for
		# --sandbox/--hot-seat and every existing unit test's own fixture),
		# so _net_is_hosting() below checks Net.mode() directly instead.
		# Building a bot match with nobody actually hosting would run every
		# bot and the whole feed/territory/win loop against a session no
		# client, and no acceptance harness, could ever reach.
		push_error(
			"--headless-host --bots=%d: Net never became the host (host_game() likely failed to bind its port) -- refusing to start a bot match with no host." % bots
		)
		return
	Match.register_world(main_node._field, main_node._registry, main_node._blocks_container)
	main_node._headless_loop_enabled = _has_loop_matches_arg(args)
	main_node._headless_loop_args = args
	main_node._headless_loop_index = 0
	if main_node._headless_loop_enabled:
		Events.match_state_changed.connect(main_node._on_headless_loop_state_changed)
	_setup_bot_record(args)
	_load_bot_weight_overrides(args, bots)
	if not main_node._headless_loop_enabled:
		# DECISION (Bontago-1t5.13): a single (non-loop) match also prints its HEADLESS_MATCH line on
		# END, so tools/bot_h2h.py can parse winner_team without --loop-matches.
		Events.match_state_changed.connect(_on_headless_single_state_changed)
	_start_headless_loop_match(bots, args)

	# `--seconds=<n>` bounds the run with a hard wall-clock quit: the
	# acceptance command has no real win condition to end on within a CI
	# harness's own patience (docs/archive/M5_PLAN.md P5).
	var seconds: float = _seconds_arg(args)
	if seconds > 0.0:
		main_node.get_tree().create_timer(seconds).timeout.connect(main_node._on_headless_bots_seconds_elapsed)


## Builds and starts one headless bot match. Without --loop-matches this is
## exactly the previous Match.start_match + diagnostics pair; with it, each
## match after the first gets a fresh rng_seed.
func _start_headless_loop_match(bots: int, args: PackedStringArray) -> void:
	var config: MatchConfig = _build_headless_bot_config(bots, args)
	main_node._headless_loop_index += 1
	var has_match_seed: bool = _has_match_seed_arg(args)
	if main_node._headless_loop_enabled:
		# DECISION (Bontago-8or.21): match 1 keeps the configured seed when one is
		# set; every later match draws a fresh positive seed so repeats differ.
		if has_match_seed:
			# DECISION (Bontago-1t5.13): with --match-seed the later loop matches derive their
			# seeds deterministically from it instead of drawing fresh random ones.
			config.rng_seed = _derived_loop_seed(_match_seed_arg(args), main_node._headless_loop_index)
		elif main_node._headless_loop_index > 1 or config.rng_seed < 0:
			config.rng_seed = randi_range(1, 2147483647)
		main_node._headless_loop_seed = config.rng_seed
	else:
		main_node._headless_loop_seed = config.rng_seed
	Match.start_match(config)
	_apply_bot_weight_overrides()
	_begin_bot_record(config)
	_start_headless_bots_diagnostics()


## `--loop-matches`, same "-"-stripping convention as the other flags.
func _has_loop_matches_arg(args: PackedStringArray) -> bool:
	for raw: String in args:
		var text: String = raw
		while text.begins_with("-"):
			text = text.substr(1)
		if text == "loop-matches":
			return true
	return false


## Bontago-8or.21: on END print one compact `HEADLESS_MATCH` summary line and
## restart on the next frame (deferred, so the END emit finishes first; the
## restart goes END -> LOBBY -> LOADING, which tears the old world down).
func _on_headless_loop_state_changed(_from_state: int, to_state: int) -> void:
	if to_state != Match.State.END or main_node._headless_loop_restart_pending:
		return
	print(_headless_match_summary_line())
	main_node._headless_loop_restart_pending = true
	main_node._restart_headless_loop_match.call_deferred()


func _on_headless_single_state_changed(_from_state: int, to_state: int) -> void:
	if to_state == Match.State.END:
		print(_headless_match_summary_line())


func _restart_headless_loop_match() -> void:
	main_node._headless_loop_restart_pending = false
	if not main_node._headless_loop_enabled or not _net_is_hosting() or Match.state() != Match.State.END:
		return
	_start_headless_loop_match(_bots_arg(main_node._headless_loop_args), main_node._headless_loop_args)


## `timed_out` (Bontago-1t5.16): the --seconds cap hit with the match still PLAYING; the line then
## carries winner_team=-1 and a trailing `timeout=1` (tools/bot_h2h.py counts it as a draw).
func _headless_match_summary_line(timed_out: bool = false) -> String:
	var line: String = "HEADLESS_MATCH index=%d mode=%d seed=%d duration=%.1f winner_team=%d placements=%d homes_alive=%d teams=%s" % [
		main_node._headless_loop_index,
		Match.config.game_mode if Match.config != null else 0,
		main_node._headless_loop_seed, _headless_bots_elapsed_s(), -1 if timed_out else Match.winner_team(),
		main_node._headless_bots_placements, _headless_bots_homes_alive(), _headless_slot_teams(),
	]
	return line + " timeout=1" if timed_out else line


## Team id per slot, comma-separated ("0,1,2,..."), so a harness can map candidate seats to teams.
func _headless_slot_teams() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for i: int in range(Match.slot_count()):
		parts.append(str(Match.team_of(i)))
	return ",".join(parts)


## Bontago-d5c.6 review finding 1: true only when Net actually became the
## HOST, unlike Net.is_host() (autoload/Net.gd: "True on the host **and
## offline**"), which cannot tell a genuine offline mode apart from
## --headless-host's own host_game() call having failed to bind. A private
## helper rather than inlining `Net.mode() == Net.Mode.HOST` at the one call
## site above, so a test that needs to force either outcome has exactly one
## seam to reach for.
func _net_is_hosting() -> bool:
	return Net.mode() == Net.Mode.HOST


## `--bots=<n>`, same "-"-stripping/PREFIX convention as _sandbox_player_
## count()/_sandbox_force_special_arg() above. 0 when absent -- see
## _start_headless_bot_match_with_args()'s own "feature off by default" doc.
func _bots_arg(args: PackedStringArray) -> int:
	const PREFIX: String = "bots="
	for raw: String in args:
		var text: String = raw
		while text.begins_with("-"):
			text = text.substr(1)
		if text.begins_with(PREFIX):
			return int(text.substr(PREFIX.length()))
	return 0


## `--seconds=<n>`, same convention. 0.0 (unbounded -- the match runs until a
## real win condition or the process is killed) when absent.
func _seconds_arg(args: PackedStringArray) -> float:
	const PREFIX: String = "seconds="
	for raw: String in args:
		var text: String = raw
		while text.begins_with("-"):
			text = text.substr(1)
		if text.begins_with(PREFIX):
			return float(text.substr(PREFIX.length()))
	return 0.0


## Same "players="-reading loop as _sandbox_player_count(), with a different
## absent-flag default (0, so `maxi(bots, ...)` below reduces to exactly
## `bots` with no --players given -- docs/archive/M5_PLAN.md P5: "every seat a bot"
## is the literal acceptance command's own shape) -- kept separate from
## _sandbox_player_count() rather than reused, since that function's own
## absent-flag default (sandbox_config.default_player_count) is wrong here.
func _headless_bot_players_arg(args: PackedStringArray) -> int:
	const PREFIX: String = "players="
	for raw: String in args:
		var text: String = raw
		while text.begins_with("-"):
			text = text.substr(1)
		if text.begins_with(PREFIX):
			return int(text.substr(PREFIX.length()))
	return 0


## Same lobby-settings-minus-a-few-overrides shape as _build_hot_seat_config()/
## _build_sandbox_config() above: `config.player_count` may be raised past
## `bots` by `--players=<n2>` to leave human seats idle (docs/archive/M5_PLAN.md P5:
## "matching --sandbox's own --players= precedent, but is not required for
## the acceptance criterion"); `config.sandbox` stays false (unlike
## --sandbox's own config) -- this is a real match, real timers/cadence, the
## whole point being that the real feed/territory/win loop survives N
## concurrent bots, not sandbox's relaxed rules.
func _build_headless_bot_config(bots: int, args: PackedStringArray) -> MatchConfig:
	# DECISION (game/Main.gd, Bontago-3k0, deferred from Bontago-keo.19):
	# Net.match_config_override() (set by --match-config=<path>, parsed inside
	# Net's own host branch -- autoload/Net.gd's _apply_command_line_args())
	# takes over `match_config`'s usual role as the duplication source here,
	# extending this function's existing duplicate-then-override shape rather
	# than adding a second, parallel config path. Null (no flag, or a
	# rejected path/type) leaves this exactly as it was before the flag
	# existed.
	var base_config: MatchConfig = main_node.match_config
	if Net.match_config_override() != null:
		base_config = Net.match_config_override()
	var config: MatchConfig = base_config.duplicate(true) as MatchConfig
	config.ai_count = bots
	config.player_count = maxi(bots, _headless_bot_players_arg(args))
	config.hot_seat = false
	config.sandbox = false
	# DECISION (Bontago-mp0.27): headless bot matches have no human to wait for,
	# so they skip the 3-2-1 countdown (harnesses and loops stay fast).
	config.countdown_seconds = 0.0
	# DECISION (Bontago-1t5.3): `--mode=<classic|ctf|elimination|sky>` (or the
	# GameMode integer) picks the headless bot match's mode; absent keeps the
	# config's own mode. resolve_game_mode() still falls back for unselectable ids.
	# DECISION (Bontago-1t5.1): `--goals=<1..5>` overrides goal_flag_count for headless bot matches.
	# Bontago-1pi.107: `--disc-size=<step>` picks the disc-size slider step (0 tiny .. 5 enormous).
	var disc_step: int = _disc_size_arg(args)
	if disc_step >= 0:
		config.disc_size_step = DiscSizeTuning.shared().clamp_step(disc_step)

	var difficulty_override: int = _bot_difficulty_arg(args)
	if difficulty_override >= 0:
		config.ai_difficulty = difficulty_override as MatchConfig.AiDifficulty
		config.slot_ai_difficulties = PackedInt32Array()  # the flag covers every bot slot
	if _has_match_seed_arg(args):
		config.rng_seed = _match_seed_arg(args)

	var goals_override: int = _goals_arg(args)
	if goals_override > 0:
		config.goal_flag_count = clampi(goals_override, MatchConfig.GOAL_FLAG_MIN, MatchConfig.GOAL_FLAG_MAX)
	var mode_override: int = _mode_arg(args)
	if mode_override >= 0:
		config.game_mode = MatchConfig.resolve_game_mode(mode_override)
		config.round_timer_minutes = MatchConfig.clamp_round_timer(config.round_timer_minutes, config.game_mode)
	return config


## `--disc-size=<step>`, -1 when absent.
func _disc_size_arg(args: PackedStringArray) -> int:
	const PREFIX: String = "disc-size="
	for raw: String in args:
		var text: String = raw
		while text.begins_with("-"):
			text = text.substr(1)
		if text.begins_with(PREFIX):
			return int(text.substr(PREFIX.length()))
	return -1


## `--goals=<n>`, 0 when absent.
func _goals_arg(args: PackedStringArray) -> int:
	const PREFIX: String = "goals="
	for raw: String in args:
		var text: String = raw
		while text.begins_with("-"):
			text = text.substr(1)
		if text.begins_with(PREFIX):
			return int(text.substr(PREFIX.length()))
	return 0


## Bontago-1t5.1 diagnostics: per team, the most goals it holds in one group, "tN:k/total".
func _headless_bots_goal_coverage() -> String:
	var raster: TerritoryRaster = Match.raster()
	if raster == null or Match.config == null:
		return "n/a"
	var goals: PackedVector2Array = PlayerSlot.goal_positions_for(Match.config.effective_goal_flag_count(), Match.config.map_def())
	var by_group: Dictionary = {}
	for point: Vector2 in goals:
		var team: int = WinChecker.goal_holder(raster, point, Match._territory._claim_radius())
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


## `--mode=<name|id>`, -1 when absent or unrecognised.
func _mode_arg(args: PackedStringArray) -> int:
	const PREFIX: String = "mode="
	for raw: String in args:
		var text: String = raw
		while text.begins_with("-"):
			text = text.substr(1)
		if not text.begins_with(PREFIX):
			continue
		var value: String = text.substr(PREFIX.length()).to_lower()
		match value:
			"classic":
				return MatchConfig.GameMode.CLASSIC
			"ctf", "capture_the_flag":
				return MatchConfig.GameMode.CAPTURE_THE_FLAG
			"elimination":
				return MatchConfig.GameMode.ELIMINATION
			"sky", "reach_the_sky":
				return MatchConfig.GameMode.REACH_THE_SKY
			"domination":
				return MatchConfig.GameMode.DOMINATION
		if value.is_valid_int():
			var id: int = int(value)
			if MatchConfig.resolve_game_mode(id) != id:
				push_warning("--mode=%s is reserved or unselectable; falling back to %d" % [value, MatchConfig.resolve_game_mode(id)])
			return id
		push_warning("--mode=%s is not a known mode id; keeping the configured mode" % value)
		return -1
	return -1


# --- Headless bot match diagnostics (Bontago-d5c.6 review finding 2) ---------
#
# The literal acceptance command (`--headless-host --bots=8 --seconds=60`) has
# no console to watch, so this prints one `HEADLESS_BOTS` line every
# HEADLESS_BOTS_REPORT_INTERVAL_S and a final one right before the --seconds
# quit, each carrying the wall-clock time since the match began, Match's own
# state name and how many blocks have been placed so far (Events.block_placed
# -- autoload/Events.gd: "a block became a live physics body, either placed by
# a player or auto-dropped when its feed timer ran out", exactly what a bot's
# own placements are). Diagnostics only: nothing here feeds a rule or a test
# assertion about gameplay, only a human (or tools/triage_log.py) reading the
# log. `bots_active` from the brief is omitted -- BotController's own _state
# (game/BotController.gd) has no public accessor and this file does not own
# that script, so reading it here is not "cheaply readable" without editing a
# file outside this package's ownership.

func _start_headless_bots_diagnostics() -> void:
	# Idempotent (Bontago-8or.21): a --loop-matches restart must not double-connect
	# block_placed or leak a second report Timer.
	_stop_headless_bots_diagnostics()
	main_node._headless_bots_start_msec = Time.get_ticks_msec()
	_headless_bots_start_physics_frame = Engine.get_physics_frames()
	main_node._headless_bots_placements = 0
	Events.block_placed.connect(main_node._on_headless_bots_block_placed)
	main_node._headless_bots_report_timer = Timer.new()
	main_node._headless_bots_report_timer.wait_time = Main.HEADLESS_BOTS_REPORT_INTERVAL_S
	main_node._headless_bots_report_timer.autostart = true
	main_node._headless_bots_report_timer.timeout.connect(main_node._on_headless_bots_report_tick)
	main_node.add_child(main_node._headless_bots_report_timer)


## Torn down from _end_match_world() (idempotent: a no-op for every match
## world that never called _start_headless_bots_diagnostics() above, since
## _headless_bots_report_timer stays null and Events.block_placed was never
## connected by this instance).
func _stop_headless_bots_diagnostics() -> void:
	if Events.block_placed.is_connected(main_node._on_headless_bots_block_placed):
		Events.block_placed.disconnect(main_node._on_headless_bots_block_placed)
	if main_node._headless_bots_report_timer != null and is_instance_valid(main_node._headless_bots_report_timer):
		main_node._headless_bots_report_timer.queue_free()
	main_node._headless_bots_report_timer = null


func _on_headless_bots_block_placed(_block: RigidBody3D, _shape_id: StringName) -> void:
	main_node._headless_bots_placements += 1


func _on_headless_bots_report_tick() -> void:
	print(_headless_bots_periodic_line())


## _start_headless_bot_match_with_args()'s own `--seconds=<n>` quit timer,
## above: prints one last line (with the same counters the periodic line
## used) so the acceptance command's log always ends with a placements total,
## even when the process quits between two HEADLESS_BOTS_REPORT_INTERVAL_S
## ticks.
func _on_headless_bots_seconds_elapsed() -> void:
	print(_headless_bots_done_line())
	if Match.state() == Match.State.PLAYING:
		print(_headless_match_summary_line(true))
	_finish_bot_record(-1)
	await Sfx.drain_for_quit()
	main_node.get_tree().quit(0)


func _headless_bots_periodic_line() -> String:
	return "HEADLESS_BOTS t=%.1f wall=%.1f state=%s placements=%d mode=%d homes_alive=%d frontier_gap=%.2f goals=%s" % [
		_headless_bots_elapsed_s(), _headless_bots_wall_s(), _headless_bots_state_name(), main_node._headless_bots_placements,
		Match.config.game_mode if Match.config != null else 0, _headless_bots_homes_alive(),
		_headless_bots_frontier_gap(), _headless_bots_goal_coverage(),
	]


func _headless_bots_done_line() -> String:
	return "HEADLESS_BOTS done t=%.1f wall=%.1f placements=%d mode=%d homes_alive=%d" % [
		_headless_bots_elapsed_s(), _headless_bots_wall_s(), main_node._headless_bots_placements,
		Match.config.game_mode if Match.config != null else 0, _headless_bots_homes_alive(),
	]


# --- Bot decision recording: `--bot-record=<dir>` (Bontago-1t5.11, BT3) -------
#
# docs/BOT_TRAINING_SOAK_PLAN.md: OFF unless the flag is given. One JSONL file per bot per
# match (game/BotDecisionRecorder.gd), rotated per --loop-matches match; the recorder is a
# passive observer attached to every BotController. DECISION: the recorder and its state
# live on this flow object (Main.gd is not part of this package), and END/--seconds close
# the files so footers and truncated outcomes are always written.

var _bot_record_dir: String = ""
var _bot_recorder: BotDecisionRecorder = null
var _bot_record_timeline_started: bool = false


## `--bot-record=<dir>`, "" when absent.
func _bot_record_arg(args: PackedStringArray) -> String:
	const PREFIX: String = "bot-record="
	for raw: String in args:
		var text: String = raw
		while text.begins_with("-"):
			text = text.substr(1)
		if text.begins_with(PREFIX):
			return text.substr(PREFIX.length())
	return ""


func _setup_bot_record(args: PackedStringArray) -> void:
	_bot_record_dir = _bot_record_arg(args)
	if _bot_record_dir.is_empty() or _bot_recorder != null:
		return
	_bot_recorder = BotDecisionRecorder.new()
	main_node.add_child(_bot_recorder)
	if not _bot_recorder.configure(_bot_record_dir):
		# The recorder already printed BOT_RECORD_ERROR; the match runs unrecorded.
		return
	Events.match_state_changed.connect(_on_bot_record_state_changed)


func _begin_bot_record(config: MatchConfig) -> void:
	if _bot_recorder == null or not _bot_recorder.is_enabled():
		return
	var slots: PackedInt32Array = PackedInt32Array()
	var difficulties: Array = []
	for slot_id: int in range(config.player_count - config.ai_count, config.player_count):
		slots.append(slot_id)
		difficulties.append(int(config.ai_difficulty_for_slot(slot_id)))
	for override_slot: int in _bot_weight_tunings:
		_bot_recorder.set_slot_tuning(override_slot, _bot_weight_tunings[override_slot] as BotTuning)
	var map_def: MapDef = config.map_def()
	var header: Dictionary = {
		"seed": config.rng_seed,
		"mode": int(config.game_mode),
		"map_id": String(map_def.id) if map_def != null else "",
		"bot_count": config.ai_count,
		"difficulty": int(config.ai_difficulty),
		"difficulties": difficulties,
		"weight_overrides": _bot_weight_overrides_for_header(),
		"git_revision": BuildVersion.git_revision(),
	}
	_bot_record_timeline_started = false
	_bot_recorder.begin_match(header, slots, main_node._headless_loop_index)


func _on_bot_record_state_changed(_from_state: int, to_state: int) -> void:
	if _bot_recorder == null or not is_instance_valid(_bot_recorder):
		return
	# Controllers are spawned while the world builds; attach (idempotent) on every transition.
	for node: Node in main_node._bot_controllers:
		var bot: BotController = node as BotController
		if bot != null and is_instance_valid(bot):
			bot.set_recorder(_bot_recorder)
	if to_state == Match.State.PLAYING and not _bot_record_timeline_started:
		_bot_record_timeline_started = true
		_bot_recorder.on_tick(0.0)
	elif to_state == Match.State.END:
		_finish_bot_record(Match.winner_team())


func _finish_bot_record(winner_team: int) -> void:
	if _bot_recorder == null:
		return
	_bot_recorder.end_match(winner_team)
	print("BOT_RECORD match=%d %s" % [main_node._headless_loop_index, JSON.stringify(_bot_recorder.stats())])


## Bontago-1t5.4 diagnostics: smallest (distance to a living enemy home minus
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


## DECISION (Bontago-1t5.16): the `t=` / `duration=` fields are GAME time (physics ticks), the same
## clock the --seconds SceneTree timer uses, so `done t=` matches the cap even under an unpaced
## `--fixed-fps 60` run; wall-clock seconds are printed as an extra `wall=` field.
func _headless_bots_elapsed_s() -> float:
	return float(Engine.get_physics_frames() - _headless_bots_start_physics_frame) / float(Engine.physics_ticks_per_second)


func _headless_bots_wall_s() -> float:
	return float(Time.get_ticks_msec() - main_node._headless_bots_start_msec) / 1000.0


## Match.State's own name for Match.state() (e.g. "PLAYING"), read the same
## way an enum-to-string helper would if Match exported one: Dictionary.
## find_key() on the enum itself, since GDScript enums are plain Dictionaries
## under the hood. "UNKNOWN" only if Match.state() is ever a value the enum
## does not declare, which should not be possible.
func _headless_bots_state_name() -> String:
	var key: Variant = Match.State.find_key(Match.state())
	return str(key) if key != null else "UNKNOWN"


# --- Training overrides (Bontago-1t5.13, BT5) ---------------------------------
#
# `--bot-difficulty=<easy|normal|hard|0..2>` sets every bot slot; `--match-seed=<int>` is the first
# match's rng_seed; `--bot-weights=<json file>` [+ `--bot-weights-slots=<csv>`] overrides BotTuning
# weight_* fields for the named bot slots only. DECISION: the weights file is either ONE flat object
# {"weight_x": v, ...} applied to --bot-weights-slots (default: every bot slot; this is what
# tools/bot_h2h.py writes) or a slot map {"3": {"weight_x": v}, ...}. Bad JSON / unknown keys warn
# and the bots keep the shipped weights.

const LOOP_SEED_STRIDE: int = 7919
const LOOP_SEED_MAX: int = 2147483647

var _bot_weight_overrides: Dictionary = {}  # slot_id -> weights Dictionary (raw, for the header)
var _bot_weight_tunings: Dictionary = {}  # slot_id -> BotTuning copy


func _string_arg(args: PackedStringArray, prefix: String) -> String:
	for raw: String in args:
		var text: String = raw
		while text.begins_with("-"):
			text = text.substr(1)
		if text.begins_with(prefix):
			return text.substr(prefix.length())
	return ""


func _has_match_seed_arg(args: PackedStringArray) -> bool:
	return _string_arg(args, "match-seed=").is_valid_int()


## `--match-seed=<int>`, clamped to >= 0 (negative means "random" elsewhere); -1 when absent.
func _match_seed_arg(args: PackedStringArray) -> int:
	var text: String = _string_arg(args, "match-seed=")
	return maxi(int(text), 0) if text.is_valid_int() else -1


## Seed of loop match `index` (1-based) from a base seed: index 1 is the base itself.
func _derived_loop_seed(base_seed: int, index: int) -> int:
	if index <= 1:
		return base_seed
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = base_seed + index * LOOP_SEED_STRIDE
	return rng.randi_range(1, LOOP_SEED_MAX)


## `--bot-difficulty=`, -1 when absent/unknown (unknown values warn).
func _bot_difficulty_arg(args: PackedStringArray) -> int:
	var value: String = _string_arg(args, "bot-difficulty=").to_lower()
	if value.is_empty():
		return -1
	match value:
		"easy", "0":
			return MatchConfig.AiDifficulty.EASY
		"normal", "1":
			return MatchConfig.AiDifficulty.NORMAL
		"hard", "2":
			return MatchConfig.AiDifficulty.HARD
	push_warning("--bot-difficulty=%s is not easy|normal|hard; keeping the configured difficulty" % value)
	return -1


## Parses --bot-weights[/-slots] into _bot_weight_overrides / _bot_weight_tunings. Never fatal.
func _load_bot_weight_overrides(args: PackedStringArray, bots: int) -> void:
	_bot_weight_overrides.clear()
	_bot_weight_tunings.clear()
	var path: String = _string_arg(args, "bot-weights=")
	if path.is_empty():
		return
	var first_slot: int = maxi(bots, _headless_bot_players_arg(args)) - bots
	var bot_slots: PackedInt32Array = PackedInt32Array()
	for slot_id: int in range(first_slot, first_slot + bots):
		bot_slots.append(slot_id)
	var text: String = FileAccess.get_file_as_string(path)
	var parser: JSON = JSON.new()  # not parse_string: that logs an engine error on bad input
	var data: Variant = parser.data if not text.is_empty() and parser.parse(text) == OK else null
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("--bot-weights=%s is missing or not a JSON object; bots keep the shipped weights" % path)
		return
	var table: Dictionary = data as Dictionary
	var by_slot: bool = not table.is_empty()
	for key: Variant in table:
		if typeof(table[key]) != TYPE_DICTIONARY or not String(key).is_valid_int():
			by_slot = false
	if by_slot:
		for key: Variant in table:
			var keyed_slot: int = int(String(key))
			if bot_slots.has(keyed_slot):
				_bot_weight_overrides[keyed_slot] = table[key]
			else:
				push_warning("--bot-weights: slot %d is not a bot slot; ignored" % keyed_slot)
	else:
		var slots_text: String = _string_arg(args, "bot-weights-slots=")
		var targets: PackedInt32Array = bot_slots
		if not slots_text.is_empty():
			targets = PackedInt32Array()
			for part: String in slots_text.split(",", false):
				if part.strip_edges().is_valid_int() and bot_slots.has(int(part)):
					targets.append(int(part))
				else:
					push_warning("--bot-weights-slots: '%s' is not a bot slot; ignored" % part)
		for target_slot: int in targets:
			_bot_weight_overrides[target_slot] = table
	var shipped: BotTuning = load("res://config/bot_tuning.tres") as BotTuning
	for override_slot: int in _bot_weight_overrides:
		_bot_weight_tunings[override_slot] = BotController.tuning_with_weights(shipped, _bot_weight_overrides[override_slot] as Dictionary)


## Installs each named slot's tuning copy on its controller (idempotent; other slots untouched).
func _apply_bot_weight_overrides() -> void:
	if _bot_weight_tunings.is_empty():
		return
	for node: Node in main_node._bot_controllers:
		var bot: BotController = node as BotController
		if bot != null and is_instance_valid(bot) and _bot_weight_tunings.has(bot.bound_slot()):
			bot.set_tuning_override(_bot_weight_tunings[bot.bound_slot()] as BotTuning)


func _bot_weight_overrides_for_header() -> Dictionary:
	var out: Dictionary = {}
	for slot_id: int in _bot_weight_overrides:
		out[str(slot_id)] = _bot_weight_overrides[slot_id]
	return out
