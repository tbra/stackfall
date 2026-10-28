class_name MatchTerritory
extends RefCounted
## Match's territory build/reset, the 10 Hz solve loop, circle collection and
## render hand-off, goal zones, both elimination-check flavours, and the
## replicated territory mirror.
##
## Split out of autoload/Match.gd; see its header comment for the state machine this territory logic
## serves.

var _match: MatchAutoload = null

var _cell_grid: CellGrid = null
var _raster: TerritoryRaster = null
var _solver: TerritorySolver = null
## The CLASSIC objective's WinChecker (null in other modes). A setter keeps
## the active ClassicObjective pointing at whatever is assigned, so tests and
## bench tools that swap the checker in place still drive the win path.
var _win_checker: WinChecker = null:
	set(value):
		_win_checker = value
		if _objective is ClassicObjective:
			(_objective as ClassicObjective).set_checker(value)
## The active mode objective: fed every solve, owns the win.
var _objective: ModeObjective = null
var _last_groups: TerritoryGroups = null
var _solve_accum: float = 0.0
## Time the solve being applied waited since the previous one (F4: the overlay
## bake shares the staleness cap with it).
var _solve_waited_s: float = 0.0
var _cached_sources: Dictionary = {}
var _cached_circles: Array[InfluenceCircle] = []
var _cached_groups: TerritoryGroups = null
## dirty state. The board is clean when no block event bumped
## the registry revision, the small non-block config signature is unchanged and
## nothing forced a re-solve since the last real solve step.
var _seen_revision: int = -1
var _seen_config: Dictionary = {}
var _force_dirty: bool = true

## The in-flight WorkerThreadPool solve, if any.
## DECISION: one job at a time, applied on the first frame it is seen complete
## (one frame after kickoff at the earliest). While pending the main thread only
## accumulates _solve_accum, so no elapsed time is lost or applied twice.
var _pending: TerritorySolveJob = null
## Solve steps still owed after the pending job's step, and their length.
var _pending_remaining: int = 0
var _pending_step: float = 0.0
## DECISION: private raster the worker fills; adopt_fill() swaps it in (O(1)).
var _shadow_raster: TerritoryRaster = null

## goal no-build discs, cached at _build_territory() (goal
## flags never move) so _run_territory_step() does not rebuild them every
## solve, and so net/match/MatchReplication.send_territory() can ship the exact
## same list a client's overlay draws. Parallel arrays: goal_radii is
## currently uniform (TerritoryTuning.goal_zone_radius) but kept per-goal
## because core/net/CircleWire.gd's wire format is already per-goal.
var _goal_positions: PackedVector2Array = PackedVector2Array()
var _goal_radii: PackedFloat32Array = PackedFloat32Array()

## The analytic circle list the last _run_territory_step() built for
## game/field/TerritoryOverlay.gd (see _apply_circle_render()), cached so
## net/match/MatchReplication.send_territory() can ship the identical list to
## clients without re-deriving it from raw circles a client never has (every
## body is frozen there). Host only; a client's copy lives only in the
## overlay it was handed via apply_replicated_territory().
var _circle_xs: PackedFloat32Array = PackedFloat32Array()
var _circle_zs: PackedFloat32Array = PackedFloat32Array()
var _circle_radii: PackedFloat32Array = PackedFloat32Array()
var _circle_teams: PackedInt32Array = PackedInt32Array()
var _circle_argmax_mode: bool = false


func setup(match_ref: MatchAutoload) -> void:
	_match = match_ref


# --- Territory and the win check (spec 1.5, 2.5) -----------------------

## The live raster. Never mutate it from outside Match.
func raster() -> TerritoryRaster:
	return _raster


func cell_grid() -> CellGrid:
	return _cell_grid


## Fraction of the disk a team owns, 0..1.
func territory_share(team_id: int) -> float:
	return _raster.team_share(team_id) if _raster != null else 0.0


## Soak audit (SOAK_PLAN 6.3). True when the board is not clean (nothing to
## compare), or when an uncached fresh solve's owner bytes equal the live raster's
## owner bytes, ignoring live hole and contested cells. Read-only: no raster,
## cache or revision state changes (the live raster's owner-byte cache is
## refreshed, which is content-neutral). Nothing is compared while a solve is
## pending, a block is awake or the last solve is stale (_is_clean()).
func fresh_solve_matches_live() -> bool:
	if _raster == null or _solver == null or _pending != null or _match._registry == null:
		return true
	if not _match._registry.all_settled() or not _is_clean():
		return true
	var job: TerritorySolveJob = TerritorySolveJob.new()
	job.circles = _collect_circles()
	job.holes_enabled = _match.config.hole_mode != MatchConfig.HoleMode.OFF
	job.solver_tuning = _match._territory_tuning
	job.fill_raster = TerritoryRaster.new(_cell_grid, _match._territory_tuning)
	job.run()
	var live_owners: PackedByteArray = _raster.owner_bytes()
	var fresh_owners: PackedByteArray = job.fill_raster.owner_bytes()
	var live_states: PackedByteArray = _raster.state_bytes()
	var skip_mask: int = TerritoryRaster.STATE_HOLE | TerritoryRaster.STATE_CONTESTED
	if live_owners.size() != fresh_owners.size():
		return false
	if live_owners == fresh_owners:
		return true
	var fresh_states: PackedByteArray = job.fill_raster.state_bytes()
	for index: int in range(live_owners.size()):
		if live_owners[index] != fresh_owners[index] and (live_states[index] | fresh_states[index]) & skip_mask == 0:
			return false
	return true


## The active objective, or null before a match is built.
func objective() -> ModeObjective:
	return _objective


## The winning team, or -1.
func winner_team() -> int:
	return _objective.winner() if _objective != null else WinChecker.NO_TEAM


func _build_territory() -> void:
	cancel_pending()
	# The previous match's influence circles must not be encoded to
	# clients (net/match/MatchReplication.gd) while this one loads and counts down.
	clear_circles()
	var map_def: MapDef = _match.config.map_def()
	_cell_grid = CellGrid.new(map_def.field_radius, map_def.cell_size, map_def.shape_test())
	# A new match (map / goal layout) starts with no cached claim cell lists. The cache is
	# value-keyed, so this frees memory rather than guarding correctness.
	ClaimCells.clear()
	_raster = TerritoryRaster.new(_cell_grid, _match._territory_tuning)
	_raster.reset()
	_solver = TerritorySolver.new(_match._territory_tuning)
	_shadow_raster = null
	if _match._territory_tuning.async_solve_min_circles > 0:
		_shadow_raster = TerritoryRaster.new(_cell_grid, _match._territory_tuning)
	var goal_positions: PackedVector2Array = PlayerSlot.goal_positions_for(_match.config.effective_goal_flag_count(), map_def)
	# DECISION: goal-flag no-build zones stamp under every hole_mode, not just OFF (spec 2.2 "Goal
	# no-build zones": a no-placement disc around each goal; zones block placement, not influence or
	# capture). Zones are static for the match (goal flags never move), so this stamps once, right
	# after reset(), rather than every solve. Under TEMPORARY the capture march therefore runs into
	# the flag's own zone before it can capture, so a capture scenario must march to the zone's rim,
	# not the flag's centre.
	_raster.set_goal_zones(goal_positions, _match._territory_tuning.goal_zone_radius)
	_objective = ModeObjective.create(
		_match.config.game_mode, goal_positions, _match._territory_tuning.capture_hold, _match.config.team_count(),
		_match._territory_tuning.ctf_score_per_beacon_second,
		_match._territory_tuning.ctf_replicate_interval_s,
		_sky_slot_teams(), _match.config.sky_team_sum, _match._territory_tuning.sky_replicate_interval_s,
		_match._territory_tuning.domination_replicate_interval_s,
		SKY_NET_CONFIG.build_height_target_m,
		_match._territory_tuning.home_claim_decay_rate
	)
	_objective.set_claim_radius(_claim_radius())
	_connect_sky_records()
	_win_checker = (_objective as ClassicObjective).checker() if _objective is ClassicObjective else null
	_match._lifecycle.flush_pending_mode_state()
	_last_groups = null
	_solve_accum = 0.0
	_cached_sources.clear()
	_cached_circles.clear()
	_cached_groups = null
	_force_dirty = true

	# The same goal list, cached for the analytic shader and the replicated circle wire (see
	# _goal_positions above, class-level DECISION).
	_goal_positions = goal_positions
	_goal_radii = PackedFloat32Array()
	_goal_radii.resize(goal_positions.size())
	_goal_radii.fill(_match._territory_tuning.goal_zone_radius)


## The capture claim radius -- 0 (flag cell
## only, the rule) unless the toggle is on, then goal_zone_radius times the
## multiplier. The no-build disc and its drawn circle keep the base radius.
##
## DECISION: capture is decided over the cells within this radius around each
## beacon (WinChecker.claim_at): the team owning the most cells claims it, a tie
## or no owning slot leaves it contested/unclaimed. No claim-radius ring is drawn: the
## overlay circle API has no cheap second ring.
func _claim_radius() -> float:
	var qol: QolExperiments = _match.config.qol
	if qol == null or not qol.goal_radius_enabled:
		return 0.0
	return qol.effective_goal_radius(_match._territory_tuning.goal_zone_radius)


func _tick_territory(delta: float) -> void:
	# Spec 2.6: clients never solve territory. On a client every body is frozen, so the settled rule
	# would call the whole field settled instantly and the solve would invent a territory that
	# disagrees with the host's. The mirror raster arrives over the wire instead (see
	# apply_replicated_territory).
	if not _match._is_host():
		# A job pending across a loss of authority must never be applied to a
		# mirror raster later.
		cancel_pending()
		return
	if _raster == null or _solver == null:
		return
	_solve_accum += delta
	if _pending != null:
		# DECISION: apply one frame after kickoff at the
		# earliest, and never kick off again on the apply frame.
		if WorkerThreadPool.is_task_completed(_pending.task_id):
			_complete_pending()
		return
	var step: float = 1.0 / maxf(_match._territory_tuning.solve_hz, 0.001)
	var due_steps: int = int(floorf(_solve_accum / step))
	var holes_on: bool = _match.config.hole_mode != MatchConfig.HoleMode.OFF
	if due_steps > 0 and not holes_on and _is_clean():
		# Nothing that feeds the result changed: only time-based state moves.
		var clean_time: float = float(due_steps) * step
		_solve_accum = maxf(_solve_accum - clean_time, 0.0)
		_advance_clean(clean_time)
		due_steps = 0
	# awake blocks contribute no influence and keep flipping the
	# source signature, so re-solving every 50 ms while a pile tumbles is wasted
	# work. Hold the solve until everything settles, but never longer than
	# solve_defer_max_s (the accumulator is exactly the time since the last
	# solve), so claims, gift sweeps and captures stay bounded-latency.
	if due_steps > 0 and _should_defer_solve():
		due_steps = 0
	if due_steps > 0:
		_solve_waited_s = _solve_accum
		var due_time: float = float(due_steps) * step
		_solve_accum = maxf(_solve_accum - due_time, 0.0)
		# Overlap-mode holes can open, eliminate a home, then close again within a
		# catch-up window. Preserve each timer transition in those modes.
		if holes_on:
			for i: int in range(due_steps):
				if _is_clean():
					_run_clean_hole_step(step)
				elif _step_maybe_async(step, due_steps - i - 1, step, 0):
					break
		else:
			# V2 ownership is independent of elapsed time. An elimination can
			# happen on the first solve, so resolve that step before coalescing
			# the remaining identical body snapshot and advancing capture time.
			var alive_before: int = _alive_home_count()
			var went_async: bool = _step_maybe_async(step, due_steps - 1, step, alive_before)
			if not went_async:
				_continue_v2(due_steps - 1, step, alive_before, _seen_config, false)


## Remaining v2 catch-up after the first step of a tick was applied. `config`
## is the config signature the first step solved against: the rest of the window
## is time-only when nothing but body revisions changed.
## When the config moved (an elimination during apply) the sync step runs.
func _continue_v2(
	remaining: int, step: float, alive_before: int, config: Dictionary, from_async: bool
) -> void:
	if remaining > 0 and _raster != null:
		# After an async apply the registry revision may have advanced during
		# the worker frame; that must not count as dirty for the kickoff snapshot
		# (the next tick re-solves anyway: _seen_revision is the kickoff value).
		var clean: bool = (
			(not _force_dirty and _territory_config_signature() == config) if from_async else _is_clean()
		)
		if clean:
			# The first step consumed every change, so the rest of the
			# catch-up window is time only: no second raster pass, overlay
			# rebuild or territory_updated emission.
			_advance_clean(float(remaining) * step)
		else:
			alive_before = _alive_home_count()
			if from_async:
				# A forced-dirty (punch/shrink) or config-changed re-solve goes
				# back through the worker so the apply frame never runs a full
				# solve; the new job's continuation finishes the loop below.
				if _step_maybe_async(float(remaining) * step, 0, step, alive_before):
					return
			else:
				_run_territory_step(float(remaining) * step)
	# A source-list change on the last solve needs a zero-time redraw,
	# even if the match entered END and will never tick again.
	var alive_after: int = _alive_home_count()
	while alive_after < alive_before:
		alive_before = alive_after
		_run_territory_step(0.0)
		alive_after = _alive_home_count()


## True while the solve may wait: deferral enabled, the staleness cap not yet
## reached, and at least one tracked block is still awake (unsettled).
func _should_defer_solve() -> bool:
	var cap: float = _match._territory_tuning.solve_defer_max_s
	if cap <= 0.0 or _solve_accum >= cap or _match._registry == null:
		return false
	return not _match._registry.all_settled()


## True when nothing that feeds the solve changed since the last real step.
func _is_clean() -> bool:
	if _force_dirty or _last_groups == null:
		return false
	if not _match._territory_cache_enabled or _match._registry == null:
		return false
	_match._registry.set_move_epsilon(_match._territory_tuning.dirty_move_epsilon)
	if _match._registry.territory_revision() != _seen_revision:
		return false
	return _territory_config_signature() == _seen_config


## Time-only work for an unchanged v2 board: the win checker's hold timer and the
## capture-progress event still advance; ownership, overlay and events are as before.
func _advance_clean(delta: float) -> void:
	_objective.update(_raster, delta)
	if _objective is EliminationObjective:
		_tick_home_claims(delta)
	_finish_objective_step()


## Overlap hole modes (temporary/permanent) on an unchanged board: the stamp would reproduce the same
## group/team ids, so only the contest/hole timers advance (by `delta`, exactly as
## update() would) and the hole events, home check and capture hold follow.
func _run_clean_hole_step(delta: float) -> void:
	_raster.advance_time(delta, _match.config.hole_mode == MatchConfig.HoleMode.PERMANENT)
	_objective.update(_raster, delta)
	var opened: PackedInt32Array = _raster.holes_opened()
	var closed: PackedInt32Array = _raster.holes_closed()
	if opened.size() > 0 or closed.size() > 0:
		Events.territory_updated.emit(_raster, _last_groups)
		Events.hole_cells_changed.emit(opened, closed)
		if opened.size() > 0:
			_check_home_flags(opened)
		var shares: PackedFloat32Array = PackedFloat32Array()
		for t: int in range(_match.config.team_count()):
			shares.append(_raster.team_share(t))
		Events.territory_share_changed.emit(shares)
	if _objective is EliminationObjective:
		_tick_home_claims(delta)
	_finish_objective_step()


## After every objective update: capture-ring event, replicated mode state when
## it changed, and the objective's own win (live states only). Only a
## ClassicObjective can win here for now; other modes win through the same
## winner() latch or the round timer (MatchLifecycle._tick_match_timer).
func _finish_objective_step() -> void:
	Events.goal_capture_progress.emit(_objective.capturing_team(), _objective.capture_progress())
	_match._lifecycle.publish_mode_state_if_changed()
	# a sandbox never ends on the goal hold.
	if _match.config.sandbox and _objective is ClassicObjective:
		# The latch is spent: a stale capturer must not decide a later wipe-out, and the hold may restart.
		if _objective.winner() != ModeObjective.NO_TEAM:
			_objective.reset(_match.config.team_count())
		return
	if MatchAutoload.is_live(_match.state()) and _objective.winner() != ModeObjective.NO_TEAM:
		_match._lifecycle._finish_match(_objective.winner())


## The mode goal context bots score against (null when no objective exists). Host-side; reads the
## live objective, raster and registry only.
func bot_mode_goal(slot_id: int) -> BotModeGoal:
	if _objective == null:
		return null
	var goal: BotModeGoal = BotModeGoal.new()
	goal.mode = _objective.mode_id()
	if _objective is ClassicObjective:
		_fill_classic_goals(goal, slot_id, _objective as ClassicObjective)
	if _objective is CaptureFlagObjective:
		var own_team: int = _match.team_of(slot_id)
		goal.beacon_positions = PlayerSlot.goal_positions_for(
			_match.config.effective_goal_flag_count(), _match.config.map_def()
		)
		for point: Vector2 in goal.beacon_positions:
			goal.beacon_held_by_own.append(_raster != null and WinChecker.goal_holder(_raster, point, _claim_radius()) == own_team)
	elif _objective is EliminationObjective:
		# OFF mode flips a home only when an enemy radius beats the home circle.
		goal.no_overlap_mode = _match.config.hole_mode == MatchConfig.HoleMode.OFF
	elif _objective is DominationObjective:
		_fill_domination_goal(goal, _match.team_of(slot_id))
	elif _objective is ReachSkyObjective:
		var registry: BlockRegistry = _match.registry()
		if registry != null:
			var tallest: Dictionary = registry.tallest_settled_for_slot(slot_id)
			if not tallest.is_empty():
				goal.has_tower = true
				goal.tower_origin = tallest["xz"] as Vector2
	return goal


## Reach the Sky's target height is NetConfig.build_height_target_m
## (single source with the network position band).
const SKY_NET_CONFIG: NetConfig = preload("res://config/net/net_config.tres")
## Shipped bot tuning, read for the Domination leader sample cap only.
const BOT_TUNING: BotTuning = preload("res://config/bots/bot_tuning.tres")


## Domination: flags whether `own_team` already leads and, when
## it does not, samples (capped) cells of the first leading team for the bot.
func _fill_domination_goal(goal: BotModeGoal, own_team: int) -> void:
	var leaders: PackedInt32Array = (_objective as DominationObjective).leading_teams()
	goal.own_team_leads = leaders.has(own_team) or leaders.is_empty()
	if goal.own_team_leads or _raster == null:
		return
	var leader: int = leaders[0]
	var grid: CellGrid = _raster.grid()
	var cells: PackedInt32Array = PackedInt32Array()
	for index: int in grid.in_disk_cells():
		var cell: Vector2i = grid.cell_coords(index)
		if _raster.team_at(cell.x, cell.y) == leader:
			cells.append(index)
	var cap: int = maxi(BOT_TUNING.dom_leader_sample_cap, 1)
	var stride: int = maxi(int(ceil(float(cells.size()) / float(cap))), 1)
	for i: int in range(0, cells.size(), stride):
		goal.leader_points.append(grid.index_center(cells[i]))


## classic multi-goal context (left empty for a single goal so
## classic scoring stays exactly as before).
func _fill_classic_goals(goal: BotModeGoal, slot_id: int, classic: ClassicObjective) -> void:
	if _raster == null:
		return
	var positions: PackedVector2Array = PlayerSlot.goal_positions_for(
		_match.config.effective_goal_flag_count(), _match.config.map_def()
	)
	if positions.size() < 2:
		return
	var home: Vector2 = Vector2.ZERO
	var has_home: bool = false
	for slot_item: PlayerSlot in _match._lifecycle._slots:
		if slot_item.slot_id == slot_id and slot_item.home_flag_alive:
			home = slot_item.home_position
			has_home = true
	goal.goal_positions = positions
	var home_group: int = _raster.group_at_point(home) if has_home else -1
	var component_points: PackedVector2Array = PackedVector2Array()
	var grid: CellGrid = _raster.grid()
	if home_group >= 0:
		for index: int in grid.in_disk_cells():
			var cell: Vector2i = grid.cell_coords(index)
			if _raster.group_at(cell.x, cell.y) == home_group:
				component_points.append(grid.index_center(index))
	var in_home_group: Array[bool] = []
	var own_team: int = _match.team_of(slot_id)
	for i: int in positions.size():
		# A goal already latched to our team counts as held, so the bot moves on.
		var latched_own: bool = classic.latched_team(i) == own_team
		in_home_group.append(latched_own or (home_group >= 0 and _raster.group_at_point(positions[i]) == home_group))
	goal.target_goal_index = BotModeGoal.next_goal_index(positions, in_home_group, component_points, home)


## Reach the Sky: team of every slot, index = slot id.
func _sky_slot_teams() -> PackedInt32Array:
	var teams: PackedInt32Array = PackedInt32Array()
	for slot: int in range(_match.config.player_count):
		teams.append(_match.config.team_of_slot(slot))
	return teams


## Host only: feeds each settled block's height to the Reach the Sky objective.
func _connect_sky_records() -> void:
	var registry: BlockRegistry = _match.registry()
	if registry != null and not registry.block_settled.is_connected(_on_block_settled):
		registry.block_settled.connect(_on_block_settled)


func _on_block_settled(owner_slot: int, height: float) -> void:
	if MatchAutoload.is_live(_match.state()):
		_match._stats.record_height(owner_slot, height)
	if _objective is ReachSkyObjective and MatchAutoload.is_live(_match.state()):
		(_objective as ReachSkyObjective).record_height(owner_slot, height)


func _alive_home_count() -> int:
	var count: int = 0
	for slot_item: PlayerSlot in _match._lifecycle._slots:
		if slot_item.home_flag_alive:
			count += 1
	return count


## The synchronous entry point (lifecycle seed, tests, bench): kickoff, solve
## inline on this thread, apply. Finishes any in-flight async job first so two
## steps never interleave.
func _run_territory_step(delta: float) -> void:
	flush_pending()
	var job: TerritorySolveJob = _kickoff(delta)
	job.fill_raster = _raster
	job.solver = _solver
	job.run()
	_apply(job)


## Waits for the in-flight solve and applies it (plus its owed catch-up steps)
## now. No-op when idle. Re-entrant-safe: the pending slot is cleared first.
func flush_pending() -> void:
	if _pending != null:
		_complete_pending()


## Back to the empty state for the next match: no async solve outlives the
## territory it would apply to, and no stale influence circles reach the next
## match's replication. Called by MatchLifecycle's reset.
func reset() -> void:
	cancel_pending()
	_cell_grid = null
	_raster = null
	_solver = null
	_win_checker = null
	_objective = null
	_last_groups = null
	_solve_accum = 0.0
	clear_circles()


## Waits for the in-flight solve and discards it (match build/reset/abort).
func cancel_pending() -> void:
	if _pending == null:
		return
	var job: TerritorySolveJob = _pending
	_pending = null
	_pending_remaining = 0
	WorkerThreadPool.wait_for_task_completion(job.task_id)


## Kicks off one step: async when the board is large enough, otherwise inline.
## Returns true when the step went async (the caller stops; _complete_pending()
## runs the continuation), false when it was already applied here.
func _step_maybe_async(delta: float, remaining: int, step: float, alive_before: int) -> bool:
	var threshold: int = _match._territory_tuning.async_solve_min_circles
	var job: TerritorySolveJob = _kickoff(delta)
	if threshold > 0 and job.circles.size() >= threshold:
		if _shadow_raster == null:
			_shadow_raster = TerritoryRaster.new(_cell_grid, _match._territory_tuning)
		job.alive_before = alive_before
		job.fill_raster = _shadow_raster
		# DECISION: the worker gets a tuning snapshot so a live tuning-panel
		# edit never races the solver; the main thread does not touch the job
		# or the shadow raster until the task is complete.
		job.solver_tuning = _match._territory_tuning.duplicate() as TerritoryTuning
		job.task_id = WorkerThreadPool.add_task(job.run, false, "territory_solve")
		_pending = job
		_pending_remaining = remaining
		_pending_step = step
		return true
	job.fill_raster = _raster
	job.solver = _solver
	job.run()
	_apply(job)
	return false


func _complete_pending() -> void:
	var job: TerritorySolveJob = _pending
	var remaining: int = _pending_remaining
	var step: float = _pending_step
	_pending = null
	_pending_remaining = 0
	WorkerThreadPool.wait_for_task_completion(job.task_id)
	if _raster == null:
		return
	_apply(job)
	if _raster == null:
		return
	if _match.config.hole_mode != MatchConfig.HoleMode.OFF:
		# The remaining catch-up steps replay the same unchanged snapshot. A
		# config change (an elimination during apply) hands the unconsumed time
		# back to the accumulator. Registry revisions after kickoff are ignored
		# on purpose: _seen_revision is the kickoff value, so the next tick
		# re-solves.
		var left: int = remaining
		while left > 0 and _raster != null:
			if _force_dirty or _territory_config_signature() != job.kickoff_config:
				_solve_accum += float(left) * step
				break
			_run_clean_hole_step(step)
			left -= 1
	else:
		_continue_v2(remaining, step, job.alive_before, job.kickoff_config, true)


## Main-thread half of a solve step: every scene read (source signature,
## collect) happens here, so the job is pure data.
func _kickoff(delta: float) -> TerritorySolveJob:
	if _match._registry != null:
		_seen_revision = _match._registry.territory_revision()
	_seen_config = _territory_config_signature()
	_force_dirty = false
	var cache_enabled: bool = _match._territory_cache_enabled
	var job: TerritorySolveJob = TerritorySolveJob.new()
	job.delta = delta
	job.kickoff_config = _seen_config
	job.holes_enabled = _match.config.hole_mode != MatchConfig.HoleMode.OFF
	job.sources = _territory_source_signature() if cache_enabled else {}
	job.cache_hit = cache_enabled and _cached_groups != null and job.sources == _cached_sources
	if job.cache_hit:
		job.circles = _cached_circles
		job.cached_groups = _cached_groups
	else:
		job.circles = _collect_circles()
	return job


## Main-thread half of a solve step, in this order: cache store, groups, raster, objective, overlay,
## events.
func _apply(job: TerritorySolveJob) -> void:
	var groups: TerritoryGroups = job.groups
	var circles: Array[InfluenceCircle] = job.out_circles
	var cache_hit: bool = job.cache_hit
	if _match._territory_cache_enabled and not cache_hit:
		_cached_sources = job.sources
		_cached_circles = circles
		_cached_groups = groups
	_last_groups = groups
	var holes_enabled: bool = job.holes_enabled
	var permanent_holes: bool = _match.config.hole_mode == MatchConfig.HoleMode.PERMANENT
	_raster.adopt_fill(job.fill_raster, job.delta, holes_enabled, permanent_holes)
	_objective.update(_raster, job.delta)
	if not cache_hit:
		_apply_circle_render(job.render)

	Events.territory_updated.emit(_raster, groups)

	# DECISION: overlap modes (TEMPORARY/PERMANENT) keep the hole-under-home-flag trigger below; OFF
	# keeps _check_home_flags_v2()'s argmax-ownership trigger. Spec 2.3 "Home elimination" leaves
	# the overlap-mode trigger [OPEN]. A hole opening under a home flag is a physical event (the
	# floor the flag stands on is gone), the least-invented option until real evidence settles it;
	# it is not claimed to be the original's actual rule.
	if job.holes_enabled:
		var opened: PackedInt32Array = _raster.holes_opened()
		var closed: PackedInt32Array = _raster.holes_closed()
		if opened.size() > 0 or closed.size() > 0:
			Events.hole_cells_changed.emit(opened, closed)
			if opened.size() > 0:
				_check_home_flags(opened)
		if _objective is EliminationObjective:
			_tick_home_claims(job.delta)
	else:
		# Home-flag elimination: v2 has no
		# hole-opened event to drive off, so every step re-reads whether an
		# enemy area has swallowed each living home flag directly.
		_check_home_flags_v2(job.delta)

	var shares: PackedFloat32Array = PackedFloat32Array()
	for t: int in range(_match.config.team_count()):
		shares.append(_raster.team_share(t))
	Events.territory_share_changed.emit(shares)

	_finish_objective_step()


func _territory_config_signature() -> Dictionary:
	var signature: Dictionary = {
		"field": _match._field.global_transform if _match._field != null else Transform3D.IDENTITY,
		"hole_mode": _match.config.hole_mode,
		"influence_base": _match._territory_tuning.influence_base,
		"influence_cap": _match._territory_tuning.influence_max_fraction,
		"home_radius": _match._territory_tuning.home_radius,
		"hash_cell_size": _match._territory_tuning.hash_cell_size,
		"max_circles": _match._territory_tuning.max_circles,
	}
	var visuals: TerritoryVisuals = _match._field.visuals if _match._field != null else null
	if visuals != null:
		# set_circles() also uploads these shader settings and rebuilds bins.
		# A live tuning-panel edit must force one overlay refresh even if every
		# block is stationary.
		signature["visuals"] = [
			visuals.max_shader_circles, visuals.metaball_blend,
			visuals.rim_soft_width, visuals.rim_width, visuals.rim_strength,
			visuals.rim_pulse_depth, visuals.rim_speed, visuals.edge_softness_m,
		]
	for slot_item: PlayerSlot in _match._lifecycle._slots:
		signature["home:%d" % slot_item.slot_id] = [
			slot_item.home_flag_alive, slot_item.home_position, slot_item.team_id
		]
	return signature


## Include every settled block, not just a tower's top: an obscured block can
## slide out from under a cone without moving that top block. Exact transforms
## are deliberately conservative: a false miss costs time, a false hit changes rules.
func _territory_source_signature() -> Dictionary:
	var signature: Dictionary = _territory_config_signature()
	if _match._registry != null:
		for id: Variant in _match._registry._entries.keys():
			var entry: Variant = _match._registry._entries[id]
			if entry.is_settled and is_instance_valid(entry.block):
				signature[id] = [entry.owner_slot, entry.block.global_transform]
	return signature


func _collect_circles() -> Array[InfluenceCircle]:
	var circles: Array[InfluenceCircle] = []
	for slot_item: PlayerSlot in _match._lifecycle._slots:
		if not slot_item.home_flag_alive:
			continue
		circles.append(
			InfluenceCircle.for_home(slot_item.home_position, slot_item.team_id, slot_item.slot_id, _match._territory_tuning)
		)
	if _match._registry != null:
		circles.append_array(_match._registry.influence_circles(_match._lifecycle._slots, _match._territory_tuning, _match.config.map_def()))
	return circles


## Builds the analytic circle list game/field/TerritoryOverlay.gd's shader draws instead of the
## smoothstepped, bilinearly-upscaled 1 m cell raster (so the edge looks smooth): only the
## *home-anchored* circles TerritorySolver kept in a group (never a raw, possibly cut-off circle --
## the raster and the shader must agree on which circles are live territory) survive, already capped
## at TerritoryTuning.max_circles by TerritorySolver's own budget, so this never needs its own
## overflow check (see the
## DECISION in TerritorySolver).
##
## Sorted by team, largest radius first within a team: shaders/
## territory.gdshader's cheap early-out (stop folding a team's circles into
## its coverage value once that team has visibly saturated a pixel) sees
## each team's biggest, most-covering circles first, so it skips the most
## circles for the least visual risk.
func _apply_circle_render(render: Dictionary) -> void:
	var xs: PackedFloat32Array = render["xs"]
	var zs: PackedFloat32Array = render["zs"]
	var radii: PackedFloat32Array = render["radii"]
	var teams: PackedInt32Array = render["teams"]
	var argmax_mode: bool = _match.config.hole_mode == MatchConfig.HoleMode.OFF
	_circle_xs = xs
	_circle_zs = zs
	_circle_radii = radii
	_circle_teams = teams
	_circle_argmax_mode = argmax_mode

	if _match._field != null:
		_match._field.set_overlay_churning(
			_match._registry != null and not _match._registry.all_settled(), _solve_waited_s
		)
		_solve_waited_s = 0.0
		_match._field.set_overlay_circles(xs, zs, radii, teams, _goal_positions, _goal_radii, argmax_mode)


## Drops the cached influence-circle list (only that list; goal
## positions/radii are rebuilt by the next _build_territory()). Called from MatchLifecycle._reset_match_state() (every
## abort/start, host and client) and at the top of _build_territory(); idempotent.
## Does not touch Field's overlay (Main's clear_match_state owns that).
func clear_circles() -> void:
	_circle_xs = PackedFloat32Array()
	_circle_zs = PackedFloat32Array()
	_circle_radii = PackedFloat32Array()
	_circle_teams = PackedInt32Array()
	_circle_argmax_mode = false


## The analytic circle list the last _run_territory_step() built (host
## only), cached so net/match/MatchReplication.send_territory() can ship the
## identical list to clients rather than re-deriving it from raw circles a
## client never has (every body there is frozen). See _apply_circle_render().
func circle_render_arrays() -> Dictionary:
	return {
		"xs": _circle_xs,
		"zs": _circle_zs,
		"radii": _circle_radii,
		"teams": _circle_teams,
		"goal_positions": _goal_positions,
		"goal_radii": _goal_radii,
		"argmax_mode": _circle_argmax_mode,
	}


## Overlap modes: a hole opening under a slot's home flag eliminates it -- home_flag_alive goes
## false, its circles unanchor (TerritorySolver drops them next solve since they no longer connect
## to a home circle), it gets no more feed, and the win check ignores it. If that leaves one
## player/team standing, the match ends right here.
func _check_home_flags(opened: PackedInt32Array) -> void:
	if not _match._is_host():
		return
	if _objective is EliminationObjective:
		# the claim timers run from _tick_home_claims().
		return
	var lost: PackedInt32Array = PackedInt32Array()
	var opened_set: Dictionary = {}
	for cell: int in opened:
		opened_set[cell] = true

	for slot_item: PlayerSlot in _match._lifecycle._slots:
		if not slot_item.home_flag_alive:
			continue
		var coords: Vector2i = _cell_grid.world_to_cell(slot_item.home_position)
		if not _cell_grid.in_bounds(coords.x, coords.y):
			continue
		if opened_set.has(_cell_grid.cell_index(coords.x, coords.y)):
			lost.append(slot_item.slot_id)
	_match._lifecycle.eliminate_slots(lost)


## The v2 counterpart of _check_home_flags(opened) above, run every v2 territory step rather than
## off a hole-opened event, since the default ruleset never opens one. The home circle is always one
## of the anchored circles feeding the field, so under normal play it wins the argmax at its own
## center (kernel value home_radius, distance 0) -- unless an enemy circle is both close enough and
## tall enough to outscore it there. If raster.team_at() at a living slot's home cell answers anyone
## else, that enemy area has swallowed the flag: eliminate it exactly as the overlap-mode trigger
## does, through the one shared eliminate_slots().
func _check_home_flags_v2(delta: float = 0.0) -> void:
	if not _match._is_host():
		return
	if _objective is EliminationObjective:
		_tick_home_claims(delta)
		return
	var lost: PackedInt32Array = PackedInt32Array()
	for slot_item: PlayerSlot in _match._lifecycle._slots:
		if not slot_item.home_flag_alive:
			continue
		var coords: Vector2i = _cell_grid.world_to_cell(slot_item.home_position)
		if not _cell_grid.in_bounds(coords.x, coords.y):
			continue
		var owner_team: int = _raster.team_at(coords.x, coords.y)
		if owner_team != slot_item.team_id:
			lost.append(slot_item.slot_id)
	_match._lifecycle.eliminate_slots(lost)


## Elimination: a home flag is
## knocked out only after the attacker controls it continuously for the claim
## time (TerritoryTuning.capture_hold, shared with the goal beacons). Pressure is
## the same trigger the instant knockout used: v2 (HoleMode.OFF) an enemy-owned
## (or unowned) home cell, the overlap modes a hole at the home cell. The
## claim progress shows through Events.goal_capture_progress (the goal ring).
## When the pressure lapses the claim fades (home_claim_decay_rate).
## `delta` is the time this step covers (0 = re-evaluate only).
func _tick_home_claims(delta: float) -> void:
	if not _match._is_host() or not _objective is EliminationObjective:
		return
	var elimination: EliminationObjective = _objective as EliminationObjective
	var v2: bool = _match.config.hole_mode == MatchConfig.HoleMode.OFF
	var pressure: Dictionary = {}
	for slot_item: PlayerSlot in _match._lifecycle._slots:
		if not slot_item.home_flag_alive:
			continue
		var coords: Vector2i = _cell_grid.world_to_cell(slot_item.home_position)
		if not _cell_grid.in_bounds(coords.x, coords.y):
			continue
		if v2:
			var owner_team: int = _raster.team_at(coords.x, coords.y)
			if owner_team != slot_item.team_id:
				pressure[slot_item.slot_id] = owner_team
		elif _raster.is_hole(coords.x, coords.y):
			pressure[slot_item.slot_id] = ModeObjective.NO_TEAM
	var done: PackedInt32Array = elimination.step_claims(pressure, delta)
	# DECISION: the map is built before the batch is eliminated, so a same-batch teammate of the
	# attacking team still counts as a living attacker (the old per-slot loop did not).
	var attackers: Dictionary = {}
	for slot_id: int in done:
		attackers[slot_id] = _attacker_slot_for(slot_id, elimination.eliminator_team(slot_id))
	_match._lifecycle.eliminate_slots(done, attackers)


## The living slot of `team` nearest `victim`'s home flag (the player credited
## with the knockout), or -1 when the attacker is unknown.
func _attacker_slot_for(victim: int, team: int) -> int:
	if team < 0:
		return -1
	var home: Vector2 = _match._lifecycle._slots[victim].home_position
	var best: int = -1
	var best_dist: float = INF
	for slot_item: PlayerSlot in _match._lifecycle._slots:
		if slot_item.team_id != team or slot_item.slot_id == victim or not slot_item.home_flag_alive:
			continue
		var dist: float = slot_item.home_position.distance_squared_to(home)
		if dist < best_dist:
			best_dist = dist
			best = slot_item.slot_id
	return best


# --- The client's read model (spec 2.6) -------------------------------------

## Writes one territory payload into the mirror raster (see
## TerritoryRaster.apply_replicated_state). Returns the cells whose hole bit
## flipped so MatchNet can re-emit Events.hole_cells_changed and Field opens
## exactly the same holes the host did.
##
## The circle_* / goal_* / argmax_mode arguments are core/net/CircleWire.gd's decoded analytic
## circle list, defaulted empty so a caller that only has the raster payload still mirrors the
## raster exactly; an empty circle list means the overlay falls back to the raster path for that
## frame (game/field/TerritoryOverlay.gd's set_circles(), "circles_valid"), never a crash.
## net/MatchNet.gd's net_territory() is the only real caller that passes a non-empty list.
func apply_replicated_territory(
	cells: PackedInt32Array,
	owners: PackedByteArray,
	states: PackedByteArray,
	full: bool,
	circle_xs: PackedFloat32Array = PackedFloat32Array(),
	circle_zs: PackedFloat32Array = PackedFloat32Array(),
	circle_radii: PackedFloat32Array = PackedFloat32Array(),
	circle_teams: PackedInt32Array = PackedInt32Array(),
	goal_positions: PackedVector2Array = PackedVector2Array(),
	goal_radii: PackedFloat32Array = PackedFloat32Array(),
	argmax_mode: bool = false
) -> void:
	if _raster == null:
		return
	if full:
		_raster.apply_replicated_state(owners, states)
	else:
		_raster.apply_replicated_diff(cells, owners, states)
	# DECISION: an empty circle_xs means "no circle update in this packet", not "clear the overlay's
	# circles": a legitimately empty list should not occur during play (every living team keeps a
	# home circle), so it almost always means a caller that never decoded one. Matching
	# net/MatchNet.gd's raster contract ("ignored, not half-applied"), an update that didn't arrive
	# intact must not blank an overlay that was drawing correctly.
	if _match._field != null and circle_xs.size() > 0:
		_match._field.set_overlay_circles(
			circle_xs, circle_zs, circle_radii, circle_teams, goal_positions, goal_radii, argmax_mode
		)


# --- Special-punched holes -------------------------------------

## A special effect's own hole, independent of territory contest (spec 1.6). `world_pos` is
## disk-local (x, z) metres -- Field.disk_local_from_world()'s convention, the same one CellGrid
## documents -- not a Vector3 world position; a caller (e.g.
## game/gifts/specials/JumpingBeanEffect.gd) converts before calling in.
##
## Host-only, the same guard _tick_territory()/_check_home_flags() use, and a no-op under
## HoleMode.OFF -- enforced here, not trusted to every SpecialEffect caller, so a special cannot
## invent a hole ruleset the lobby turned off. Otherwise force-opens every in-disk cell whose centre
## falls within radius_m of world_pos, then runs the same change-set path _run_territory_step() runs
## for a natural hole: one Events.hole_cells_changed for the whole punch. The cell under each living
## home flag is never punched (the hole opens around it), so a gift cannot eliminate a home; only a
## natural overlap hole does (spec 1.5), which is why no home check runs here.
##
## DECISION: the opened change-set is computed locally from is_hole() before/after each cell, not
## from TerritoryRaster.holes_opened() as _run_territory_step() does. That array is only cleared at
## the top of update() (the periodic solve tick), so between two solves it still holds what the last
## update() opened, already reported once. This call can land in that gap (a Jumping Bean hops on
## its own clock), and reading holes_opened() would re-announce those stale cells. `closed` is
## always empty: force_hole_cell() only opens a cell; closing stays _advance_timers()'s job off the
## solve loop.
func punch_special_hole(world_pos: Vector2, radius_m: float, hole_open_s: float) -> void:
	if not _match._is_host():
		return
	# DECISION: live-play guard (PLAYING or SUDDEN_DEATH via MatchAutoload.is_live()).
	# _finish_match() only sets State.END -- it never tears the raster down or stops a
	# SpecialEffect's physics_tick() -- so a Jumping Bean still hopping after a natural win could
	# otherwise punch a hole here after the match is over.
	if not MatchAutoload.is_live(_match.state()):
		return
	if _match.config.hole_mode == MatchConfig.HoleMode.OFF:
		return
	if _raster == null or _cell_grid == null:
		return
	if radius_m <= 0.0:
		return

	var permanent_holes: bool = _match.config.hole_mode == MatchConfig.HoleMode.PERMANENT
	var opened: PackedInt32Array = PackedInt32Array()

	var res: int = _cell_grid.res
	var cell_size: float = _cell_grid.cell_size
	var half_extent: float = _cell_grid.half_extent
	var radius_squared: float = radius_m * radius_m
	# The cells the home-elimination checks read: under each living home flag.
	var home_cells: Dictionary = {}
	for slot_item: PlayerSlot in _match._lifecycle._slots:
		var home: Vector2i = _cell_grid.world_to_cell(slot_item.home_position)
		if slot_item.home_flag_alive and _cell_grid.in_bounds(home.x, home.y):
			home_cells[_cell_grid.cell_index(home.x, home.y)] = true

	var cy_min: int = maxi(0, ceili((world_pos.y - radius_m + half_extent) / cell_size - 0.5))
	var cy_max: int = mini(res - 1, floori((world_pos.y + radius_m + half_extent) / cell_size - 0.5))

	for cy: int in range(cy_min, cy_max + 1):
		var dz: float = (float(cy) + 0.5) * cell_size - half_extent - world_pos.y
		var remaining: float = radius_squared - dz * dz
		if remaining < 0.0:
			continue
		var half_span: float = sqrt(remaining)
		var cx_min: int = maxi(0, ceili((world_pos.x - half_span + half_extent) / cell_size - 0.5))
		var cx_max: int = mini(res - 1, floori((world_pos.x + half_span + half_extent) / cell_size - 0.5))

		for cx: int in range(cx_min, cx_max + 1):
			if not _cell_grid.is_in_disk(cx, cy) or home_cells.has(_cell_grid.cell_index(cx, cy)):
				continue
			var was_hole: bool = _raster.is_hole(cx, cy)
			_raster.force_hole_cell(cx, cy, hole_open_s, permanent_holes)
			if not was_hole and _raster.is_hole(cx, cy):
				opened.append(_cell_grid.cell_index(cx, cy))

	_force_dirty = true
	if opened.size() > 0:
		Events.hole_cells_changed.emit(opened, PackedInt32Array())

