class_name MatchTerritory
extends RefCounted
## Match's territory build/reset, the 10 Hz solve loop, circle collection and
## render hand-off, goal zones, both elimination-check flavours, and the
## replicated territory mirror.
##
## Split out of autoload/Match.gd (pure refactor: no behaviour change). See
## that file's own header comment for the state machine this territory logic
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
## The active mode objective (Bontago-22y.11): fed every solve, owns the win.
var _objective: ModeObjective = null
var _last_groups: TerritoryGroups = null
var _solve_accum: float = 0.0
## Time the solve being applied waited since the previous one (F4: the overlay
## bake shares the staleness cap with it).
var _solve_waited_s: float = 0.0
## Sandbox diagnostics: measured on the real live path, not the one-shot
## comparison. The most recent process tick may contain multiple solve steps.
var _sandbox_tick_ms: float = 0.0
var _sandbox_tick_steps: int = 0
var _sandbox_step_ms: Dictionary = {}
var _sandbox_cache_hits: int = 0
var _cached_sources: Dictionary = {}
var _cached_circles: Array[InfluenceCircle] = []
var _cached_groups: TerritoryGroups = null
## Bontago-1pi.11.10: dirty state. The board is clean when no block event bumped
## the registry revision, the small non-block config signature is unchanged and
## nobody called mark_dirty() since the last real solve step.
var _seen_revision: int = -1
var _seen_config: Dictionary = {}
var _force_dirty: bool = true
var _clean_skips: int = 0
var _solve_steps: int = 0

## Bontago-1pi.11.28 (P-ASYNC): the in-flight WorkerThreadPool solve, if any.
## DECISION: one job at a time, applied on the first frame it is seen complete
## (one frame after kickoff at the earliest). While pending the main thread only
## accumulates _solve_accum, so no elapsed time is lost or applied twice.
var _pending: TerritorySolveJob = null
## Solve steps still owed after the pending job's step, and their length.
var _pending_remaining: int = 0
var _pending_step: float = 0.0
## DECISION: private raster the worker fills; adopt_fill() swaps it in (O(1)).
var _shadow_raster: TerritoryRaster = null

## Bontago-cmc.5: goal no-build discs, cached at _build_territory() (goal
## flags never move) so _run_territory_step() does not rebuild them every
## solve, and so net/MatchNet.gd's replicate_territory() can ship the exact
## same list a client's overlay draws. Parallel arrays: goal_radii is
## currently uniform (TerritoryTuning.goal_zone_radius) but kept per-goal
## because core/net/CircleWire.gd's wire format is already per-goal.
var _goal_positions: PackedVector2Array = PackedVector2Array()
var _goal_radii: PackedFloat32Array = PackedFloat32Array()

## The analytic circle list the last _run_territory_step() built for
## game/TerritoryOverlay.gd (see _apply_circle_render()), cached so
## net/MatchNet.gd's replicate_territory() can ship the identical list to
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


# --- Territory and the win check (spec 2.2, 2.3, 3.3) -----------------------

## The live raster. Never mutate it from outside Match.
func raster() -> TerritoryRaster:
	return _raster


## The groups from the last solve, parallel to the raster.
func groups() -> TerritoryGroups:
	return _last_groups


func cell_grid() -> CellGrid:
	return _cell_grid


## Fraction of the disk a team owns, 0..1.
func territory_share(team_id: int) -> float:
	return _raster.team_share(team_id) if _raster != null else 0.0


## The winning team, or -1.
func winner_team() -> int:
	return _objective.winner() if _objective != null else WinChecker.NO_TEAM


func _build_territory() -> void:
	cancel_pending()
	# Bontago-1pi.46 (G3): the previous match's influence circles must not be encoded to
	# clients (net/MatchNet.gd _encode_circles) while this one loads and counts down.
	clear_circles()
	var map_def: MapDef = _match.config.map_def()
	_cell_grid = CellGrid.new(map_def.field_radius, map_def.cell_size, map_def.shape_test())
	# Bontago-1pi.18.11: a new match (map / goal layout) starts with no cached claim
	# cell lists. The cache is value-keyed, so this frees memory rather than guarding
	# correctness.
	ClaimCells.clear()
	_raster = TerritoryRaster.new(_cell_grid, _match._territory_tuning)
	_raster.reset()
	_solver = TerritorySolver.new(_match._territory_tuning)
	_shadow_raster = null
	if _match._territory_tuning.async_solve_min_circles > 0:
		_shadow_raster = TerritoryRaster.new(_cell_grid, _match._territory_tuning)
	var goal_positions: PackedVector2Array = PlayerSlot.goal_positions_for(_match.config.effective_goal_flag_count(), map_def)
	# DECISION (autoload/Match.gd, Bontago-cmc.7): goal-flag no-build zones now
	# stamp under every hole_mode, not just OFF. SPEC.md's 2026-09-20 audit,
	# 2.2 "Goal no-build zones [OWNER, original unverified]": "keep the earlier
	# requirement for a no-placement disc around each goal... Zones block
	# placement, not influence or capture" -- an owner-retained requirement the
	# audit did not withdraw, unlike v2's OFF default. Zones are static for the
	# match (goal flags never move) so this stamps once, right after reset(),
	# rather than every solve. This makes m2_acceptance's scenario (d) (a
	# capture at the exact flag position) fail under TEMPORARY, since the
	# march now runs into the flag's own zone before it can capture --
	# Bontago-cmc.6, not this ticket, owns rewriting that scenario to march to
	# the zone's rim instead of the flag's centre point.
	_raster.set_goal_zones(goal_positions, _match._territory_tuning.goal_zone_radius)
	_objective = ModeObjective.create(
		_match.config.game_mode, goal_positions, _match._territory_tuning.capture_hold, _match.config.team_count(),
		_match._territory_tuning.ctf_score_per_beacon_second,
		_match._territory_tuning.ctf_replicate_interval_s,
		_sky_slot_teams(), _match.config.sky_team_sum, _match._territory_tuning.sky_replicate_interval_s,
		_match._territory_tuning.domination_replicate_interval_s
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
	_sandbox_cache_hits = 0
	_force_dirty = true

	# Bontago-cmc.5: the same goal list, cached for the analytic shader and
	# the replicated circle wire (see the class-level DECISION on
	# _goal_positions above).
	_goal_positions = goal_positions
	_goal_radii = PackedFloat32Array()
	_goal_radii.resize(goal_positions.size())
	_goal_radii.fill(_match._territory_tuning.goal_zone_radius)


## Bontago-1pi.18.1 (QoL experiment 3): the capture claim radius -- 0 (flag cell
## only, the rule) unless the toggle is on, then goal_zone_radius times the
## multiplier. The no-build disc and its drawn circle keep the base radius.
##
## DECISION: capture is decided over the cells within this radius around each
## beacon (WinChecker.claim_at): the team owning the most cells claims it, a tie
## or no owner leaves it contested/unclaimed. No claim-radius ring is drawn: the
## overlay circle API has no cheap second ring.
func _claim_radius() -> float:
	var qol: QolExperiments = _match.config.qol
	if qol == null or not qol.goal_radius_enabled:
		return 0.0
	return qol.effective_goal_radius(_match._territory_tuning.goal_zone_radius)


func _tick_territory(delta: float) -> void:
	# Spec 3.4 / docs/M3a_PLAN.md, "Clients never solve territory": on a
	# client every body is frozen, so the settled rule would call the whole
	# field settled instantly and the solve would invent a territory that
	# disagrees with the host's. The mirror raster arrives over the wire
	# instead (see apply_replicated_territory).
	if not _match._is_host():
		# A job pending across a loss of authority must never be applied to a
		# mirror raster later (Bontago-1pi.11.28).
		cancel_pending()
		return
	if _raster == null or _solver == null:
		return
	var profile_enabled: bool = _match._sandbox_territory_profile_enabled
	var tick_start: int = Time.get_ticks_usec() if profile_enabled else 0
	if profile_enabled:
		_sandbox_tick_steps = 0
	_solve_accum += delta
	if _pending != null:
		# DECISION (Bontago-1pi.11.28): apply one frame after kickoff at the
		# earliest, and never kick off again on the apply frame.
		if WorkerThreadPool.is_task_completed(_pending.task_id):
			_complete_pending()
		if profile_enabled:
			_sandbox_tick_ms = float(Time.get_ticks_usec() - tick_start) / 1000.0
		return
	var step: float = 1.0 / maxf(_match._territory_tuning.solve_hz, 0.001)
	var due_steps: int = int(floorf(_solve_accum / step))
	var legacy: bool = _match.config.hole_mode != MatchConfig.HoleMode.OFF
	if due_steps > 0 and not legacy and _is_clean():
		# Nothing that feeds the result changed: only time-based state moves.
		var clean_time: float = float(due_steps) * step
		_solve_accum = maxf(_solve_accum - clean_time, 0.0)
		_advance_clean(clean_time)
		due_steps = 0
	# Bontago-na5: awake blocks contribute no influence and keep flipping the
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
		# Legacy holes can open, eliminate a home, then close again within a
		# catch-up window. Preserve each timer transition in those modes.
		if legacy:
			for i: int in range(due_steps):
				if _is_clean():
					_run_clean_legacy_step(step)
				elif _step_maybe_async(step, due_steps - i - 1, step, 0):
					if profile_enabled:
						_sandbox_tick_steps += 1
					break
				if profile_enabled:
					_sandbox_tick_steps += 1
		else:
			# V2 ownership is independent of elapsed time. An elimination can
			# happen on the first solve, so resolve that step before coalescing
			# the remaining identical body snapshot and advancing capture time.
			var alive_before: int = _alive_home_count()
			var went_async: bool = _step_maybe_async(step, due_steps - 1, step, alive_before)
			if profile_enabled:
				_sandbox_tick_steps += 1
			if not went_async:
				_continue_v2(due_steps - 1, step, alive_before, _seen_config, false)
	if profile_enabled:
		_sandbox_tick_ms = float(Time.get_ticks_usec() - tick_start) / 1000.0


## Remaining v2 catch-up after the first step of a tick was applied. `config`
## is the config signature the first step solved against: the rest of the window
## is time-only when nothing but body revisions changed (Bontago-1pi.11.29).
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
			# rebuild or territory_updated emission (Bontago-1pi.11.29).
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
			if _match._sandbox_territory_profile_enabled:
				_sandbox_tick_steps += 1
	# A source-list change on the last solve needs a zero-time redraw,
	# even if the match entered END and will never tick again.
	var alive_after: int = _alive_home_count()
	while alive_after < alive_before:
		alive_before = alive_after
		_run_territory_step(0.0)
		if _match._sandbox_territory_profile_enabled:
			_sandbox_tick_steps += 1
		alive_after = _alive_home_count()


## True while the solve may wait: deferral enabled, the staleness cap not yet
## reached, and at least one tracked block is still awake (unsettled).
func _should_defer_solve() -> bool:
	var cap: float = _match._territory_tuning.solve_defer_max_s
	if cap <= 0.0 or _solve_accum >= cap or _match._registry == null:
		return false
	return not _match._registry.all_settled()


## Forces the next due tick to re-solve (external raster edits, tests).
func mark_dirty() -> void:
	_force_dirty = true


func clean_skip_count() -> int:
	return _clean_skips


func solve_step_count() -> int:
	return _solve_steps


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
	_clean_skips += 1
	_objective.update(_raster, delta)
	_finish_objective_step()


## Legacy hole modes on an unchanged board: the stamp would reproduce the same
## group/team ids, so only the contest/hole timers advance (by `delta`, exactly as
## update() would) and the hole events, home check and capture hold follow.
func _run_clean_legacy_step(delta: float) -> void:
	_clean_skips += 1
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
	_finish_objective_step()


## After every objective update: capture-ring event, replicated mode state when
## it changed, and the objective's own win (live states only). Only a
## ClassicObjective can win here for now; other modes win through the same
## winner() latch or the round timer (MatchLifecycle._tick_match_timer).
func _finish_objective_step() -> void:
	Events.goal_capture_progress.emit(_objective.capturing_team(), _objective.capture_progress())
	_match._lifecycle.publish_mode_state_if_changed()
	# Bontago-6fc.2: a sandbox never ends on the goal hold.
	if _match.config.sandbox and _objective is ClassicObjective:
		return
	if MatchAutoload.is_live(_match.state()) and _objective.winner() != ModeObjective.NO_TEAM:
		_match._lifecycle._finish_match(_objective.winner())


## Bontago-1t5.3: the mode goal context bots score against (null in Classic,
## so classic scoring is untouched). Host-side; reads the live
## objective, raster and registry only.
func bot_mode_goal(slot_id: int) -> BotModeGoal:
	if _objective == null:
		return null
	var goal: BotModeGoal = BotModeGoal.new()
	goal.mode = _objective.mode_id()
	if _objective is ClassicObjective:
		_fill_classic_goals(goal, slot_id)
	if _objective is CaptureFlagObjective:
		var own_team: int = _match.team_of(slot_id)
		goal.beacon_score_rate = _match._territory_tuning.ctf_score_per_beacon_second
		goal.beacon_positions = PlayerSlot.goal_positions_for(
			_match.config.effective_goal_flag_count(), _match.config.map_def()
		)
		for point: Vector2 in goal.beacon_positions:
			goal.beacon_held_by_own.append(_raster != null and WinChecker.goal_holder(_raster, point, _claim_radius()) == own_team)
	elif _objective is EliminationObjective:
		var own_team_e: int = _match.team_of(slot_id)
		# Bontago-1t5.4: OFF mode flips a home only when an enemy radius beats the home circle.
		goal.no_overlap_mode = _match.config.hole_mode == MatchConfig.HoleMode.OFF
		goal.home_radius = _match._territory_tuning.home_radius
		for slot_item: PlayerSlot in _match._lifecycle._slots:
			if not slot_item.home_flag_alive:
				continue
			if slot_item.slot_id == slot_id:
				goal.has_own_home = true
				goal.own_home_position = slot_item.home_position
			elif slot_item.team_id != own_team_e:
				goal.enemy_home_positions.append(slot_item.home_position)
				goal.enemy_home_shares.append(_raster.team_share(slot_item.team_id) if _raster != null else 0.0)
	elif _objective is DominationObjective:
		_fill_domination_goal(goal, _match.team_of(slot_id))
	elif _objective is ReachSkyObjective:
		var registry: BlockRegistry = _match.registry()
		if registry != null:
			var tallest: Dictionary = registry.tallest_settled_for_slot(slot_id)
			if not tallest.is_empty():
				goal.has_tower = true
				goal.tower_origin = tallest["xz"] as Vector2
				goal.tower_height = float(tallest["height"])
	return goal


## Shipped bot tuning, read for the Domination leader sample cap only.
const BOT_TUNING: BotTuning = preload("res://config/bot_tuning.tres")


## Domination (Bontago-1pi.25.1): flags whether `own_team` already leads and, when
## it does not, samples (capped) cells of the first leading team for the scorer.
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


## Bontago-1t5.1: classic multi-goal context (left empty for a single goal so
## classic scoring stays exactly as before).
func _fill_classic_goals(goal: BotModeGoal, slot_id: int) -> void:
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
	if has_home:
		goal.home_group = _raster.group_at_point(home)
	var grid: CellGrid = _raster.grid()
	if goal.home_group >= 0:
		for index: int in grid.in_disk_cells():
			var cell: Vector2i = grid.cell_coords(index)
			if _raster.group_at(cell.x, cell.y) == goal.home_group:
				goal.component_points.append(grid.index_center(index))
	for point: Vector2 in positions:
		goal.goal_in_home_group.append(goal.home_group >= 0 and _raster.group_at_point(point) == goal.home_group)
	goal.target_goal_index = BotPlacementScorer.next_goal_index(positions, goal.goal_in_home_group, goal.component_points, home)


## Reach the Sky (Bontago-22y.9): team of every slot, index = slot id.
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
		_match._stats.record_height(owner_slot, height)  # Bontago-1pi.72.2
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


## True when an async solve is in flight (no result applied yet).
func solve_pending() -> bool:
	return _pending != null


## Waits for the in-flight solve and applies it (plus its owed catch-up steps)
## now. No-op when idle. Re-entrant-safe: the pending slot is cleared first.
func flush_pending() -> void:
	if _pending != null:
		_complete_pending()


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
			_run_clean_legacy_step(step)
			if _match._sandbox_territory_profile_enabled:
				_sandbox_tick_steps += 1
			left -= 1
	else:
		_continue_v2(remaining, step, job.alive_before, job.kickoff_config, true)


## Main-thread half of a solve step: every scene read (source signature,
## collect, cone heights) happens here, so the job is pure data.
func _kickoff(delta: float) -> TerritorySolveJob:
	_solve_steps += 1
	if _match._registry != null:
		_seen_revision = _match._registry.territory_revision()
	_seen_config = _territory_config_signature()
	_force_dirty = false
	var profile_enabled: bool = _match._sandbox_territory_profile_enabled
	var t0: int = Time.get_ticks_usec() if profile_enabled else 0
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
		_sandbox_cache_hits += 1
	else:
		job.circles = _collect_circles()
		# Bontago-1pi.11.45: a field/registry freed by scene teardown can still be
		# referenced here for one step; never pass a freed object to the typed call.
		if _match._sandbox_territory_mode == MatchAutoload.SANDBOX_TERRITORY_CONE \
				and is_instance_valid(_match._field) and is_instance_valid(_match._registry):
			var measured: Dictionary = SandboxConeAdapter.measure_heights(
				job.circles, _match._field, _match._registry, _match._sandbox_cone_height_source
			)
			if not measured.has("error"):
				job.cone_enabled = true
				job.heights = measured["heights"]
				job.cone_angle = _match._sandbox_cone_angle
				job.cone_base_mode = _match._sandbox_cone_base_mode
				job.cone_base_radius = _match._territory_tuning.influence_base
				job.cone_max_radius = (
					_match._territory_tuning.influence_max_fraction * _match.config.map_def().field_radius
				)
	if profile_enabled:
		job.step_ms = {"t0": t0, "t1": Time.get_ticks_usec()}
	return job


## Main-thread half of a solve step, in the exact order the old single-pass
## step used: cache store, groups, raster, objective, overlay, events.
func _apply(job: TerritorySolveJob) -> void:
	var profile_enabled: bool = _match._sandbox_territory_profile_enabled
	var t2: int = Time.get_ticks_usec() if profile_enabled else 0
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
	var t3: int = Time.get_ticks_usec() if profile_enabled else 0
	_objective.update(_raster, job.delta)
	if not cache_hit:
		_apply_circle_render(job.render)
	var t4: int = Time.get_ticks_usec() if profile_enabled else 0

	Events.territory_updated.emit(_raster, groups)

	# DECISION (autoload/Match.gd, Bontago-cmc.7): overlap modes (TEMPORARY/
	# PERMANENT) keep the existing hole-under-home-flag trigger below
	# unchanged; OFF keeps _check_home_flags_v2()'s argmax-ownership trigger.
	# SPEC.md's 2026-09-20 audit leaves the overlap-mode trigger explicitly
	# [OPEN] (2.3 "Home elimination": "the persistent home circle prevents
	# enemy ownership at its center; resolve the trigger before implementation
	# ... Until resolved, do not claim default-mode elimination complies
	# merely because v2 elimination tests pass"). This keeps the pre-existing,
	# already-tested M2 trigger rather than inventing a new one: a hole
	# opening under a home flag is a physical event (the floor the flag stands
	# on is gone), which is at least as defensible as any other untested
	# guess, and it is what shipped before this ticket. It is NOT claimed to
	# be the original's actual rule -- that stays unverified -- only the
	# least-invented option available until real evidence settles it.
	if job.holes_enabled:
		var opened: PackedInt32Array = _raster.holes_opened()
		var closed: PackedInt32Array = _raster.holes_closed()
		if opened.size() > 0 or closed.size() > 0:
			Events.hole_cells_changed.emit(opened, closed)
			if opened.size() > 0:
				_check_home_flags(opened)
	else:
		# docs/TERRITORY_V2_PLAN.md, "Home-flag elimination": v2 has no
		# hole-opened event to drive off, so every step re-reads whether an
		# enemy area has swallowed each living home flag directly.
		_check_home_flags_v2()

	var shares: PackedFloat32Array = PackedFloat32Array()
	for t: int in range(_match.config.team_count()):
		shares.append(_raster.team_share(t))
	Events.territory_share_changed.emit(shares)

	_finish_objective_step()
	if profile_enabled:
		var t5: int = Time.get_ticks_usec()
		var t0: int = int(job.step_ms.get("t0", t2))
		var t1: int = int(job.step_ms.get("t1", t2))
		_sandbox_step_ms = {
			"collect": float(t1 - t0) / 1000.0,
			"solve": float(job.worker_usec) / 1000.0,
			"raster": float(t3 - t2) / 1000.0,
			"overlay": float(t4 - t3) / 1000.0,
			"other": float(t5 - t4) / 1000.0,
			"worker": float(job.worker_usec) / 1000.0,
			"total": float(t5 - t0) / 1000.0,
		}


func sandbox_profile() -> Dictionary:
	return {"tick_ms": _sandbox_tick_ms, "steps": _sandbox_tick_steps, "step_ms": _sandbox_step_ms, "cache_hits": _sandbox_cache_hits}


## Include every settled block, not just a tower's top: an obscured block can
## slide out from under a cone without moving that top block. Exact transforms
## are deliberately conservative: a false miss costs time, a false hit changes rules.
func _territory_config_signature() -> Dictionary:
	var signature: Dictionary = {
		"field": _match._field.global_transform if _match._field != null else Transform3D.IDENTITY,
		"mode": _match._sandbox_territory_mode,
		"angle": _match._sandbox_cone_angle,
		"height_source": _match._sandbox_cone_height_source,
		"base_mode": _match._sandbox_cone_base_mode,
		"hole_mode": _match.config.hole_mode,
		"influence_base": _match._territory_tuning.influence_base,
		"influence_k": _match._territory_tuning.influence_k,
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


## Bontago-cmc.5 (owner requirement: "should look smooth"). Builds the
## analytic circle list game/TerritoryOverlay.gd's shader draws instead of
## the smoothstepped, bilinearly-upscaled 1 m cell raster: only the
## *home-anchored* circles TerritorySolver kept in a group (never a raw,
## possibly cut-off circle — the raster and the shader must agree on which
## circles are live territory) survive, already capped at
## TerritoryTuning.max_circles by TerritorySolver's own budget (see the
## DECISION there), so this never needs its own overflow check.
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


## Bontago-1pi.46 (G3): drops the cached influence-circle list (only that list; goal
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
## only), cached so net/MatchNet.gd's replicate_territory() can ship the
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


## Owner decision (docs/M2_PLAN.md, "Home flag lost to a hole"): a hole
## opening under a slot's home flag eliminates it — home_flag_alive goes
## false, its circles unanchor (P1's TerritorySolver drops them next solve
## since they no longer connect to a home circle), it gets no more feed, and
## the win check ignores it. If that leaves one player/team standing, the
## match ends right here.
func _check_home_flags(opened: PackedInt32Array) -> void:
	if not _match._is_host():
		return
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
			_match._lifecycle._eliminate_slot(slot_item.slot_id)

	_match._lifecycle._check_last_team_standing()


## docs/TERRITORY_V2_PLAN.md, "Home-flag elimination (kept behavior, new
## trigger)": the v2 counterpart of _check_home_flags(opened) above, run every
## v2 territory step rather than off a hole-opened event, since the default
## ruleset never opens one. The home circle is always one of the anchored
## circles feeding the field, so under normal play it always wins the argmax
## at its own center (kernel value home_radius, distance 0) -- unless an
## enemy circle is both close enough and tall enough to outscore it there. If
## raster.team_at() at a living slot's home cell answers anyone else, that
## enemy area has swallowed the flag: eliminate it exactly as the legacy
## trigger does, through the one shared _eliminate_slot().
func _check_home_flags_v2() -> void:
	if not _match._is_host():
		return
	for slot_item: PlayerSlot in _match._lifecycle._slots:
		if not slot_item.home_flag_alive:
			continue
		var coords: Vector2i = _cell_grid.world_to_cell(slot_item.home_position)
		if not _cell_grid.in_bounds(coords.x, coords.y):
			continue
		var owner_team: int = _raster.team_at(coords.x, coords.y)
		if owner_team != slot_item.team_id:
			_match._lifecycle._eliminate_slot(slot_item.slot_id)

	_match._lifecycle._check_last_team_standing()


# --- The client's read model (spec 3.4) -------------------------------------

## Writes one territory payload into the mirror raster (see
## TerritoryRaster.apply_replicated_state). Returns the cells whose hole bit
## flipped so MatchNet can re-emit Events.hole_cells_changed and Field opens
## exactly the same holes the host did.
##
## Bontago-cmc.5: the circle_* / goal_* / argmax_mode arguments are
## core/net/CircleWire.gd's decoded analytic circle list, defaulted empty so
## every pre-existing call site (this file's own tests, a stale client build
## that only ever sent the raster payload) still compiles and still mirrors
## the raster exactly as before -- an empty circle list just means the
## overlay falls back to the raster path for that frame
## (game/TerritoryOverlay.gd's set_circles(), "circles_valid"), never a
## crash. net/MatchNet.gd's net_territory() is the only real caller that
## passes a non-empty list.
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
	# DECISION (autoload/Match.gd): an empty circle_xs is treated as "no
	# circle update in this packet" rather than "clear the overlay's
	# circles" -- a legitimately empty circle list should not occur during
	# play (every living team keeps a home circle), so an empty array here
	# almost always means a caller that never decoded one (an old test, a
	# malformed circle_payload net_territory() dropped). Matching net/
	# MatchNet.gd's raster payload contract ("ignored, not half-applied"): a
	# circle update that didn't arrive intact must not blank a client's
	# overlay that was previously drawing correctly.
	if _match._field != null and circle_xs.size() > 0:
		_match._field.set_overlay_circles(
			circle_xs, circle_zs, circle_radii, circle_teams, goal_positions, goal_radii, argmax_mode
		)


# --- Special-punched holes (M4 P5-HOLE) -------------------------------------

## A special effect's own hole, independent of territory contest (spec 2.6).
## `world_pos` is disk-local (x, z) metres -- Field.disk_local_from_world()'s
## convention, the same one CellGrid documents -- not a Vector3 world
## position; a caller (e.g. game/specials/JumpingBeanEffect.gd) converts
## before calling in.
##
## Host-only, the same guard _tick_territory()/_check_home_flags() use, and a
## no-op under HoleMode.OFF -- owner decision Bontago-z4h: enforced here, not
## trusted to every SpecialEffect caller, so a special cannot invent a hole
## ruleset the lobby turned off. Otherwise force-opens every in-disk cell
## whose centre falls within radius_m of world_pos, then runs the same
## change-set path _run_territory_step() runs for a natural hole: one
## Events.hole_cells_changed for the whole punch, then _check_home_flags(opened)
## -- Bontago-3td (owner question 2, M4_SPECIALS_PACKAGES.md orchestrator
## decision 2): a special-punched hole eliminates a home flag exactly like a
## natural one, shipped as the default while that question is open.
##
## DECISION (autoload/match/MatchTerritory.gd, Bontago-1en.20): the opened
## change-set is computed locally from is_hole() before/after each cell,
## rather than by reading TerritoryRaster.holes_opened() the way
## _run_territory_step() does. That array is only cleared at the top of
## update() -- a periodic 10 Hz solve tick, not this call -- so between two
## solves it still holds whatever the *last* update() opened, already
## reported once by _run_territory_step(). This call can land in that gap
## (a Jumping Bean hops on its own clock, not the solve's), and reading
## holes_opened() then would re-announce those stale cells as newly opened.
## `closed` is always empty here: force_hole_cell() only ever opens a cell
## immediately, never closes one -- closing stays _advance_timers()'s job,
## later, off the existing solve loop.
func punch_special_hole(world_pos: Vector2, radius_m: float, hole_open_s: float) -> void:
	if not _match._is_host():
		return
	# DECISION (autoload/match/MatchTerritory.gd, Bontago-1en.20 review):
	# live-play guard (Bontago-1pi.85.8: PLAYING or SUDDEN_DEATH via
	# MatchAutoload.is_live(), like placement since Bontago-1pi.87).
	# _finish_match() only sets State.END -- it never tears the raster down or
	# stops a SpecialEffect's physics_tick() -- so a Jumping Bean still hopping
	# after a natural win could otherwise still punch a hole here and, through
	# _check_home_flags() below, eliminate a still-alive slot (even one on the
	# already-decided winning team) after the match is already over.
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
			if not _cell_grid.is_in_disk(cx, cy):
				continue
			var was_hole: bool = _raster.is_hole(cx, cy)
			_raster.force_hole_cell(cx, cy, hole_open_s, permanent_holes)
			if not was_hole:
				opened.append(_cell_grid.cell_index(cx, cy))

	_force_dirty = true
	if opened.size() > 0:
		Events.hole_cells_changed.emit(opened, PackedInt32Array())
		_check_home_flags(opened)


# --- Sudden death disk shrink (spec 2.8, M6 A3) ------------------------------

## Spec 2.8: "The disk's edge crumbles inward by 1 m every 10 s." Called by
## MatchLifecycle._tick_sudden_death() with the current shrink radius (field
## radius minus however many 1 m steps have elapsed); punches every currently
## solid (not already a hole), still-in-disk cell whose center now falls
## outside `radius_m` as a **permanent** hole -- regardless of the match's own
## hole_mode, since a shrunk cell must never reopen.
##
## DECISION (autoload/match/MatchTerritory.gd, M6 A3): shrinking is expressed
## entirely in the existing hole vocabulary (TerritoryRaster.force_hole_cell(),
## the same mechanism punch_special_hole() above already proves for Jumping
## Bean) rather than resizing CellGrid/rebuilding Field's trimesh -- A0
## established that a whole-disk operation, not something to run every 10 s.
## game/Field.gd needs no new code at all for sudden death: it already reacts
## to set_hole_cells()/wakes bodies above a newly-opened cell exactly as it
## does for a natural overlap hole.
##
## Monotonic by construction: a cell already a hole (`_raster.is_hole()` true)
## is skipped, so calling this again -- even with a *larger* radius than a
## previous call, which should never happen since the caller only ever shrinks
## -- can never reopen a cell this function already punched; it can only ever
## punch more.
func shrink_to_radius(radius_m: float) -> void:
	if not _match._is_host():
		return
	if _raster == null or _cell_grid == null:
		return

	var opened: PackedInt32Array = PackedInt32Array()
	for index: int in _cell_grid.in_disk_cells():
		var coords: Vector2i = _cell_grid.cell_coords(index)
		if _raster.is_hole(coords.x, coords.y):
			continue
		if _cell_grid.index_center(index).length() <= radius_m:
			continue
		_raster.force_hole_cell(coords.x, coords.y, 0.0, true)
		opened.append(index)

	_force_dirty = true
	if opened.size() > 0:
		Events.hole_cells_changed.emit(opened, PackedInt32Array())
		_check_home_flags(opened)
