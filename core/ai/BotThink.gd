class_name BotThink
extends RefCounted
## Bot V2 (docs/BOT_AI_REDESIGN.md 2.3): one resumable think-cycle for one piece. The
## assembled pipeline, each stage resumable under the caller's microsecond budget:
##   PLAN     BotChains + BotStrategy.choose -> BotIntent                (one chunk)
##   SITES    BotCandidateGen.begin: the targeted TIP / STACK sites       (one chunk)
##   FILL     the uniform FILL draws, fill_chunk_attempts per step        (sliced)
##   STACK    BotStack.analyse_step over the snapshot of the towers (Bontago-1t5.53b; sliced, one unit
##            per body; skipped with no snapshot, which keeps the think exactly as before)
##   PROBE    support ray + one ray per footprint cell, statics -> tip_risk, and the tower's centre
##            of mass margin under the site (`load_margin`, block-supported sites only)
##   RANK     BotEvaluator.proxy on every site, rank_chunk_sites per step, best first
##   MEASURE  BotEvaluator.measure on the top `eval_top_k` (skipped when 0) (per site)
##   PICK     argmax, or a softmax sample from the best `pick_pool`; the origin is
##            re-validated against the live raster (state can move during the think)
## The PLAN and SITES chunks are not sliceable (they are pure rule code, a few ms at 110
## sites); step() checks the budget between chunks. Pure: physics is reached only through
## the `probe` callable the caller supplies.
## Deadline support (Bontago-1t5.37): every unit of work is timed per phase; finished thinks
## feed a process-wide per-unit cost average, from which remaining_work_us() estimates what is
## left (the caller spreads it over the ticks left before its deadline) and step() declines to
## start a unit predicted to overrun its slice. Timing never reaches a decision: how the work is
## sliced does not change what is chosen.

const SHIPPED_TUNING: BotTuning = preload("res://config/bot_tuning.tres")
## BotCandidate.site_kind of a candidate from the retired legacy sampler (kept as the 0 default).
const SITE_LEGACY: int = 0
## Support height recorded for a probe cell with no hit (hole, rim, open air).
const NO_SUPPORT: float = -1.0
## `-- --bot-intent-log` prints one line per decision (smoke diagnostics).
## Floor for the softmax temperature (a 0 would divide by zero).
const MIN_TEMPERATURE: float = 0.001
const INTENT_LOG_ARG: String = "--bot-intent-log"
## Bontago-1t5.37: weight of the newest finished think in the unit-cost and share averages.
## DECISION: a const, not a tuning field: it only shapes the slice schedule, never a decision.
const COST_AVERAGE_WEIGHT: float = 0.25
## Marks an average with no sample yet.
const NO_SAMPLE: float = -1.0

enum DecisionKind { PLACE, WAIT }
enum Phase { PLAN, SITES, FILL, STACK, PROBE, RANK, MEASURE, PICK, DONE }

static var _intent_log: int = -1
## Per-seat BotStrategy stickiness memory (slot id -> Dictionary), kept between pieces.
static var _strategy_memory: Dictionary = {}
## Bontago-1t5.37: microseconds per work unit of each phase (index = Phase; units: PLAN, PICK
## one per think, SITES one per candidate_count, FILL one per draw, PROBE / RANK / MEASURE one
## per site), averaged over the phases finished by every V2 bot in the process: unit costs follow
## the machine and the board, not the seat. NO_SAMPLE until a think has finished that phase.
static var _unit_cost_us: PackedFloat64Array = PackedFloat64Array()
## Bontago-1t5.37: averaged FILL draws and generated sites per candidate_count, for the estimate
## made before SITES / FILL have produced the exact counts.
static var _fill_draw_share: float = NO_SAMPLE
static var _site_share: float = NO_SAMPLE


class Decision:
	extends RefCounted
	var kind: int = DecisionKind.WAIT
	var origin: Vector2 = Vector2.ZERO
	var orientation_index: int = 0
	var intent: int = BotIntent.Kind.RACE
	var terms: PackedFloat32Array = PackedFloat32Array()


## Kept for BotController (it installs its own, possibly overridden, copy): the probe's
## contact tolerance. V2 scoring reads the BotStrategyTuning / BotEvalTuning / BotGenTuning
## resources instead.
var tuning: BotTuning = SHIPPED_TUNING
## Test hooks: null = the shipped resources.
var strategy_tuning: BotStrategyTuning = null
var gen_tuning: BotGenTuning = null
## Optional cheaper probe for the per-bottom-cube rays (they read `hit`, `height` and the optional
## `body` collider id, never `own`); falls back to the step's `probe` when not valid. (Bontago-1t5.30)
var cell_probe: Callable = Callable()

var _view: BotWorldView
var _profile: BotDifficultyProfile
var _rng: RandomNumberGenerator
var _phase: Phase = Phase.PLAN
var _chains: BotChains = null
var _intent: BotIntent = BotIntent.new()
var _candidates: Array[BotCandidate] = []
var _site_job: BotCandidateGen.SiteJob = null
## Next candidate the sliced proxy RANK scores.
var _rank_pos: int = 0
var _probe_index: int = 0
## Bontago-1t5.53b: bodies the sliced STACK phase has analysed so far.
var _stack_pos: int = 0
## Candidate indices ranked best first (proxy, then measured on the head).
var _ranked: PackedInt32Array = PackedInt32Array()
var _scores: PackedFloat32Array = PackedFloat32Array()
var _terms: Array[PackedFloat32Array] = []
var _measure_pos: int = 0
var _best: BotCandidate = null
## Ranked positions in pick order (the chosen one first), for revalidate().
var _pick_order: Array[int] = []
var _decision: Decision = Decision.new()
## Bontago-1t5.37: this think's microseconds and work units per phase (index = Phase).
var _phase_us: PackedInt64Array = PackedInt64Array()
var _phase_units: PackedInt64Array = PackedInt64Array()
## FILL draws made and sites they added in this think.
var _fill_draws: int = 0
var _fill_added: int = 0
## Orientation index -> BotStatics.OrientationInfo of the held piece (built on first use).
var _orientation_infos: Dictionary = {}


func _init(view: BotWorldView, profile: BotDifficultyProfile, rng: RandomNumberGenerator) -> void:
	_view = view
	_profile = profile
	_rng = rng
	_phase_us.resize(Phase.DONE)
	_phase_units.resize(Phase.DONE)


## Advances the think by at most about `budget_usec` microseconds (always at least one unit
## of work, so a zero budget still progresses). `probe(xz: Vector2)` returns
## {hit: bool, height: float, own: bool}. True once the decision is ready.
## Bontago-1t5.37: after the first unit, a unit whose averaged cost would carry the slice past
## `budget_usec` is left for the next step.
func step(budget_usec: int, probe: Callable) -> bool:
	var start_usec: int = Time.get_ticks_usec()
	var progressed: bool = false
	while _phase != Phase.DONE:
		if progressed:
			var elapsed: int = Time.get_ticks_usec() - start_usec
			if elapsed >= budget_usec or float(elapsed) + _next_unit_us() > float(budget_usec):
				return false
		_advance_timed(probe)
		progressed = true
	return true


## Bontago-1t5.37: runs every remaining stage now (the caller's deadline tick). The decision is
## the one any slicing of step() reaches; unlike finish_early() nothing is skipped.
func complete(probe: Callable) -> void:
	while _phase != Phase.DONE:
		_advance_timed(probe)


## Bontago-1t5.37: true once thinks in this process have finished every costly phase this one
## will run (PROBE, RANK and, with eval_top_k, MEASURE), so remaining_work_us() covers the whole
## think (before that it only knows the phases measured so far and is a lower bound).
func has_cost_estimate() -> bool:
	if _unit_cost_us.size() != Phase.DONE:
		return false
	if _unit_cost_us[Phase.PROBE] < 0.0 or _unit_cost_us[Phase.RANK] < 0.0:
		return false
	return _profile.eval_top_k <= 0 or _unit_cost_us[Phase.MEASURE] >= 0.0


## Bontago-1t5.37: estimated microseconds of work left, from the exact counts known so far (FILL
## draws left, sites left to probe / rank / measure) times the averaged unit costs; counts not
## known yet (before SITES / FILL) come from the averaged shares. 0 when done; a phase with no
## cost sample yet (the process's first thinks) counts as free.
func remaining_work_us() -> int:
	if _phase == Phase.DONE:
		return 0
	var total: float = float(maxi(_profile.candidate_count, 0))
	var sites: float = _expected_sites(total)
	var work: float = _unit_us(Phase.PICK)
	if _phase <= Phase.PLAN:
		work += _unit_us(Phase.PLAN)
	if _phase <= Phase.SITES:
		work += _unit_us(Phase.SITES) * total
	if _phase <= Phase.FILL:
		work += _unit_us(Phase.FILL) * _fill_draws_left(total)
	if _phase <= Phase.STACK and _stack_pending():
		work += _unit_us(Phase.STACK) * maxf(float(_view.stack.body_count() - _stack_pos), 0.0)
	if _phase <= Phase.PROBE:
		work += _unit_us(Phase.PROBE) * maxf(sites - float(_probe_index), 0.0)
	if _phase <= Phase.RANK:
		work += _unit_us(Phase.RANK) * maxf(sites - float(_rank_pos), 0.0)
	if _phase <= Phase.MEASURE:
		var top_k: float = minf(float(maxi(_profile.eval_top_k, 0)), sites)
		work += _unit_us(Phase.MEASURE) * maxf(top_k - float(_measure_pos), 0.0)
	return int(work)


## Ends the think now with what is gathered so far (the caller's frame cap): the sites probed
## so far are ranked by proxy and the best valid one is picked.
func finish_early() -> void:
	if _phase == Phase.DONE:
		return
	if _phase == Phase.PLAN or _phase == Phase.SITES or _phase == Phase.FILL:
		if _view.held == null:
			_phase = Phase.DONE
			_wait()
			return
		_plan()
		if _phase != Phase.FILL:
			_make_sites()
		while _phase == Phase.FILL:
			_fill_sites(_site_job.attempts_left())
	if _phase == Phase.STACK:
		_phase = Phase.PROBE
	if _phase == Phase.PROBE:
		_rank_all(_probe_index if _probe_index > 0 else _candidates.size())
	elif _phase == Phase.RANK:
		_rank_all(_candidates.size())
	_pick()


func is_done() -> bool:
	return _phase == Phase.DONE


func decision() -> Decision:
	return _decision


## The chosen candidate (null for WAIT); lets the controller reuse its recorded fields.
func best_candidate() -> BotCandidate:
	return _best


## Every site generated (probed ones carry their probe results).
func candidates() -> Array[BotCandidate]:
	return _candidates


## The strategy's intent for this piece (valid after the PLAN chunk).
func intent() -> BotIntent:
	return _intent


## One unit of work, timed into this think's per-phase totals; a phase that just ended is
## folded into the process-wide averages at once (so the first thinks of a process, which
## overlap, learn from each other before any of them is done).
func _advance_timed(probe: Callable) -> void:
	var phase: int = _phase
	var start_usec: int = Time.get_ticks_usec()
	var units: int = _advance(probe)
	_phase_us[phase] += Time.get_ticks_usec() - start_usec
	_phase_units[phase] += units
	if _phase != phase:
		_record_phase(phase)


## Runs one unit of the current phase; returns the work units it covered (see _unit_cost_us).
func _advance(probe: Callable) -> int:
	match _phase:
		Phase.PLAN:
			if _view.held == null:
				_phase = Phase.DONE
				_wait()
				return 1
			_plan()
			_phase = Phase.SITES
			return 1
		Phase.SITES:
			_make_sites()
			return maxi(_profile.candidate_count, 1)
		Phase.FILL:
			return _fill_sites(_gen().fill_chunk_attempts)
		Phase.STACK:
			return _stack_step()
		Phase.PROBE:
			_probe_one(probe)
			return 1
		Phase.RANK:
			return _rank_slice(_gen().rank_chunk_sites)
		Phase.MEASURE:
			_measure_one()
			return 1
		Phase.PICK:
			_pick()
			return 1
	return 0


## Microseconds per unit of `phase`: the larger of the process-wide average and this think's
## own measurement so far (a costlier-than-usual board shows up at once, so the deadline tick
## is not left with the difference), 0 with neither.
func _unit_us(phase: int) -> float:
	var cost: float = 0.0
	if _unit_cost_us.size() == Phase.DONE:
		cost = maxf(cost, _unit_cost_us[phase])
	if _phase_units[phase] > 0:
		cost = maxf(cost, float(_phase_us[phase]) / float(_phase_units[phase]))
	return cost


## Predicted microseconds of the next _advance() call.
func _next_unit_us() -> float:
	match _phase:
		Phase.SITES:
			return _unit_us(Phase.SITES) * float(maxi(_profile.candidate_count, 1))
		Phase.FILL:
			return _unit_us(Phase.FILL) * float(mini(maxi(_gen().fill_chunk_attempts, 1), _site_job.attempts_left()))
		Phase.STACK:
			return _unit_us(Phase.STACK) * float(maxi(BotEvaluator.stack_tuning.analyse_bodies_per_step, 1))
		Phase.RANK:
			return _unit_us(Phase.RANK) * float(mini(maxi(_gen().rank_chunk_sites, 1), _candidates.size() - _rank_pos))
		Phase.DONE:
			return 0.0
	return _unit_us(_phase)


## Sites the think will end up with: exact once FILL is over, else the sites so far plus the
## draws left at this think's FILL yield, else the averaged share of candidate_count.
func _expected_sites(total: float) -> float:
	if _phase > Phase.FILL:
		return float(_candidates.size())
	if _phase == Phase.FILL and _site_job != null and _fill_draws > 0:
		var yield_rate: float = float(_fill_added) / float(_fill_draws)
		return minf(total, float(_candidates.size()) + yield_rate * float(_site_job.attempts_left()))
	var share: float = _site_share if _site_share >= 0.0 else 1.0
	return clampf(share * total, float(_candidates.size()), total)


## FILL draws still to make: exact during FILL (an upper bound: the fill stops once full), the
## averaged share of candidate_count before it, the generator's ceiling with no sample.
func _fill_draws_left(total: float) -> float:
	if _phase > Phase.FILL:
		return 0.0
	if _phase == Phase.FILL:
		return float(_site_job.attempts_left()) if _site_job != null else 0.0
	if _fill_draw_share >= 0.0:
		return _fill_draw_share * total
	return float(maxi(_gen().fill_attempts_per_site, 1)) * total


## Folds this think's per-unit cost of the finished `phase` into the process-wide averages;
## the end of FILL also folds the FILL-draw and site shares.
func _record_phase(phase: int) -> void:
	if _unit_cost_us.size() != Phase.DONE:
		_unit_cost_us.resize(Phase.DONE)
		_unit_cost_us.fill(NO_SAMPLE)
	if _phase_units[phase] > 0:
		_unit_cost_us[phase] = _averaged(_unit_cost_us[phase], float(_phase_us[phase]) / float(_phase_units[phase]))
	var total: int = _profile.candidate_count
	if phase != Phase.FILL or total <= 0:
		return
	_fill_draw_share = _averaged(_fill_draw_share, float(_fill_draws) / float(total))
	_site_share = _averaged(_site_share, float(_candidates.size()) / float(total))


static func _averaged(average: float, sample: float) -> float:
	return sample if average < 0.0 else lerpf(average, sample, COST_AVERAGE_WEIGHT)


func _plan() -> void:
	if _chains != null:
		return
	_chains = BotChains.build(_view)
	var memory: Dictionary = _strategy_memory.get(_view.slot_id, {}) as Dictionary
	_intent = BotStrategy.choose(_view, _chains, _profile, strategy_tuning, memory)
	_strategy_memory[_view.slot_id] = memory


func _gen() -> BotGenTuning:
	return gen_tuning if gen_tuning != null else BotCandidateGen.SHIPPED_TUNING


## Builds the targeted sites; the uniform FILL then runs in FILL slices (Bontago-1t5.30).
func _make_sites() -> void:
	_site_job = BotCandidateGen.begin(_view, _intent, _profile, _rng, gen_tuning)
	_candidates = _site_job.out
	_probe_index = 0
	_phase = Phase.FILL


## Runs up to `max_attempts` FILL draws; returns the draws made.
func _fill_sites(max_attempts: int) -> int:
	var job: BotCandidateGen.SiteJob = _site_job
	var draws_before: int = job.attempts_left()
	var sites_before: int = _candidates.size()
	var finished: bool = job.fill_step(max_attempts)
	var draws: int = draws_before - job.attempts_left()
	_fill_draws += draws
	_fill_added += _candidates.size() - sites_before
	if finished:
		_site_job = null
		if _candidates.is_empty():
			_phase = Phase.PICK
		else:
			_phase = Phase.STACK if _stack_pending() else Phase.PROBE
	return draws


## True while the view carries a snapshot (Bontago-1t5.53b) whose analysis is not finished.
func _stack_pending() -> bool:
	return _view.stack != null and _view.stack.body_count() > 0 and not _view.stack.is_analysed()


## One slice of the STACK phase: analyse the next bodies; returns the bodies covered.
func _stack_step() -> int:
	var per_step: int = maxi(BotEvaluator.stack_tuning.analyse_bodies_per_step, 1)
	var units: int = clampi(_view.stack.body_count() - _stack_pos, 1, per_step)
	_stack_pos += units
	if _view.stack.analyse_step(per_step, BotEvaluator.stack_tuning):
		_phase = Phase.PROBE
	return units


func _probe_one(probe: Callable) -> void:
	var candidate: BotCandidate = _candidates[_probe_index]
	_probe_index += 1
	var hit: Dictionary = probe.call(candidate.origin) as Dictionary
	candidate.support_height = float(hit.get("height", 0.0))
	candidate.on_top_of_own_stack = bool(hit.get("own", false))
	_fire_cell_probes(candidate, probe)
	candidate.top_height = candidate.support_height + candidate.shape_height
	candidate.tip_risk = _tip_risk(candidate)
	candidate.load_margin = _load_margin(candidate)
	if _probe_index >= _candidates.size():
		_phase = Phase.RANK


## BotStatics.tip_risk of a probed site, each orientation of the held piece described once per
## think (Bontago-1t5.37; same values as BotStatics.tip_risk).
func _tip_risk(candidate: BotCandidate) -> float:
	var info: BotStatics.OrientationInfo = _orientation_info(candidate.orientation_index)
	if info == null:
		return 0.0
	return BotStatics.tip_risk_of(candidate, info, _view.grid, _gen(), _view.cube_size)


## Bontago-1t5.53b: the tower's centre-of-mass headroom under a probed site (BotStack.load_margin), INF
## with no snapshot or no block support. The supports are the blocks under the cubes that rest on the
## highest plane (the one the piece sits on); the piece's centre is its spawn-frame cube mean.
## DECISION: the piece's mass is its cube count times the shipped cube mass (the blocks' own rule).
func _load_margin(candidate: BotCandidate) -> float:
	var stack: BotStack = _view.stack
	if stack == null or not stack.is_analysed():
		return INF
	var info: BotStatics.OrientationInfo = _orientation_info(candidate.orientation_index)
	if info == null:
		return INF
	var supports: PackedInt64Array = PackedInt64Array()
	for i: int in range(candidate.support_bodies.size()):
		var id: int = candidate.support_bodies[i]
		if id < 0 or absf(candidate.cell_support[i] - candidate.support_height) > tuning.stability_contact_tolerance_m:
			continue
		if not supports.has(id):
			supports.append(id)
	if supports.is_empty():
		return INF
	var com_xz: Vector2 = candidate.origin + info.com * _view.cube_size
	var com: Vector3 = Vector3(com_xz.x, candidate.support_height + candidate.shape_height * 0.5, com_xz.y)
	var mass: float = BotWorldView.SHIPPED_PHYSICS_TUNING.cube_mass * float(_view.held.cells.size())
	return stack.load_margin(supports, com, mass)


## The held piece's orientation description (built once per think); null with no held shape.
func _orientation_info(orientation_index: int) -> BotStatics.OrientationInfo:
	var shape: BlockShape = _view.held
	if shape == null or shape.cells.is_empty():
		return null
	var info: BotStatics.OrientationInfo = _orientation_infos.get(orientation_index) as BotStatics.OrientationInfo
	if info == null:
		info = BotStatics.orientation_info(shape, orientation_index, _gen())
		_orientation_infos[orientation_index] = info
	return info


## Bontago-1t5.55.2: one ray under each real bottom cube (BotStatics.contact_probe_points, outermost
## cubes first), capped at the tier's stability_raycast_count. `cell_support` / `support_bodies` are
## parallel to `probe_points` (NO_SUPPORT / -1 for a hole or a miss). The resting plane
## (`support_height`) becomes the highest probed hit, which is where the host lift puts the piece; a
## cube is in contact when it is within stability_contact_tolerance_m of that plane. With no hit
## at all the pivot ray's height stays. DECISION (Bontago-1t5.19): holes are read off the raster's
## hole state; the legacy bot reads the Field's applied-hole mask, which lags the raster.
## DECISION (Bontago-1t5.55.2): a cube beyond the cap is not probed and counts as supported.
func _fire_cell_probes(candidate: BotCandidate, probe: Callable) -> void:
	var info: BotStatics.OrientationInfo = _orientation_info(candidate.orientation_index)
	var points: PackedVector2Array = PackedVector2Array()
	if info != null:
		points = BotStatics.contact_probe_points(candidate, info, _view.cube_size, _profile.stability_raycast_count)
	var count: int = points.size()
	var cell_ray: Callable = cell_probe if cell_probe.is_valid() else probe
	candidate.probe_points = points
	candidate.cell_support.resize(count)
	candidate.support_bodies.resize(count)
	var highest: float = NO_SUPPORT
	var any_hit: bool = false
	for i: int in range(count):
		candidate.cell_support[i] = NO_SUPPORT
		candidate.support_bodies[i] = -1
		if _is_hole_at(points[i]):
			continue
		var cell_hit: Dictionary = cell_ray.call(points[i]) as Dictionary
		if not bool(cell_hit.get("hit", false)):
			continue
		var height: float = float(cell_hit.get("height", 0.0))
		candidate.cell_support[i] = height
		candidate.support_bodies[i] = int(cell_hit.get("body", -1))
		if not any_hit or height > highest:
			highest = height
			any_hit = true
	if any_hit:
		candidate.support_height = highest
	var hits: int = 0
	for i: int in range(count):
		if candidate.cell_support[i] != NO_SUPPORT and absf(candidate.cell_support[i] - candidate.support_height) <= tuning.stability_contact_tolerance_m:
			hits += 1
	candidate.corner_support_hits = hits


func _is_hole_at(point: Vector2) -> bool:
	if _view.raster == null or _view.grid == null:
		return false
	var cell: Vector2i = _view.grid.world_to_cell(point)
	return _view.grid.in_bounds(cell.x, cell.y) and _view.raster.is_hole_index(_view.grid.cell_index(cell.x, cell.y))


## Proxy-scores the next `count` sites; ranks them best first after the last one. Returns the
## sites scored.
func _rank_slice(count: int) -> int:
	_scores.resize(_candidates.size())
	_terms.resize(_candidates.size())
	var first: int = _rank_pos
	var stop: int = mini(_rank_pos + maxi(count, 1), _candidates.size())
	while _rank_pos < stop:
		_score_proxy(_rank_pos)
		_rank_pos += 1
	if _rank_pos >= _candidates.size():
		_finish_rank(_candidates.size())
	return _rank_pos - first


## Proxy-scores sites [0, limit) and ranks them best first (ties keep generation order).
func _rank_all(limit: int) -> void:
	limit = mini(limit, _candidates.size())
	_scores.resize(_candidates.size())
	_terms.resize(_candidates.size())
	for i: int in range(_rank_pos, limit):
		_score_proxy(i)
	_finish_rank(limit)


func _score_proxy(i: int) -> void:
	var terms: PackedFloat32Array = BotEvaluator.proxy_terms(_candidates[i], _view, _intent)
	_terms[i] = terms
	_scores[i] = _site_score(_candidates[i], terms)


func _finish_rank(limit: int) -> void:
	var order: Array[int] = []
	for i: int in range(limit):
		order.append(i)
	order.sort_custom(_better)
	_ranked = PackedInt32Array(order)
	_measure_pos = 0
	_phase = Phase.MEASURE if _profile.eval_top_k > 0 and not _ranked.is_empty() else Phase.PICK


## Intent score plus the gift-claim bonus (Bontago-1t5.25). DECISION: the bonus is added
## outside the intent weight vectors (it is not a BotIntent.Term) so the weights stay 6-wide.
func _site_score(candidate: BotCandidate, terms: PackedFloat32Array) -> float:
	return BotEvaluator.score(terms, _intent) + _gift_bonus(candidate)


## Value of the landed gifts this site's new circle would take: each gift not already inside
## own territory (those claim by themselves) and within the future radius counts once.
## DECISION: every gift is worth the same (its special is only rolled on claim); the tier's
## BotDifficultyProfile.gift_claim_scale scales it (Easy low, 0 = ignores gifts).
func _gift_bonus(candidate: BotCandidate) -> float:
	if _view.gifts.is_empty() or _profile.gift_claim_scale <= 0.0:
		return 0.0
	var tuning_res: BotStrategyTuning = strategy_tuning if strategy_tuning != null else BotStrategy.SHIPPED_TUNING
	var radius: float = BotEvaluator.future_radius(candidate, _view) - tuning_res.gift_claim_margin_m
	var count: int = 0
	for gift: Vector2 in _view.gifts:
		if candidate.origin.distance_to(gift) <= radius and not _gift_is_ours(gift):
			count += 1
	return float(count) * tuning_res.gift_claim_value * _profile.gift_claim_scale


func _gift_is_ours(point: Vector2) -> bool:
	if _view.raster == null or _view.grid == null:
		return false
	var cell: Vector2i = _view.grid.world_to_cell(point)
	if not _view.grid.in_bounds(cell.x, cell.y):
		return false
	return _view.raster.team_at(cell.x, cell.y) == _view.team_id


func _better(a: int, b: int) -> bool:
	if _scores[a] != _scores[b]:
		return _scores[a] > _scores[b]
	return a < b


## Measured terms for the next top-k site; the head is re-ranked once all are measured.
func _measure_one() -> void:
	var top_k: int = mini(_profile.eval_top_k, _ranked.size())
	var index: int = _ranked[_measure_pos]
	var terms: PackedFloat32Array = BotEvaluator.measure(_candidates[index], _view, _chains, _intent)
	_terms[index] = terms
	_scores[index] = _site_score(_candidates[index], terms)
	_measure_pos += 1
	if _measure_pos < top_k:
		return
	var head: Array[int] = []
	for i: int in range(top_k):
		head.append(_ranked[i])
	head.sort_custom(_better)
	for i: int in range(top_k):
		_ranked[i] = head[i]
	_phase = Phase.PICK


## argmax (pick_pool 1) or a softmax draw from the best pick_pool sites; the choice moves to
## the front and the first site that still validates against the live raster wins.
func _pick() -> void:
	_phase = Phase.DONE
	if _ranked.is_empty():
		_wait()
		return
	var pool: int = mini(maxi(_profile.pick_pool, 1), _ranked.size())
	var chosen: int = _sample_pool(pool) if pool > 1 else 0
	_pick_order = [chosen]
	for i: int in range(_ranked.size()):
		if i != chosen:
			_pick_order.append(i)
	if not _take_first_valid():
		_wait()


## Chooses the first site in pick order that still validates against the live raster.
func _take_first_valid() -> bool:
	for position: int in _pick_order:
		var index: int = _ranked[position]
		var candidate: BotCandidate = _candidates[index]
		if (
			_view.raster != null
			and PlacementRules.validate_point(candidate.origin, _view.raster, _view.team_id) != PlacementRules.Result.VALID
		):
			continue
		_best = candidate
		_decision.kind = DecisionKind.PLACE
		_decision.origin = candidate.origin
		_decision.orientation_index = candidate.orientation_index
		_decision.intent = int(_intent.kind)
		_decision.terms = _terms[index]
		_log_decision(candidate, _scores[index])
		return true
	return false


## Re-checks the decision against the live raster (the caller's reaction delay and the think
## itself let state move); falls back to the next best valid site. Returns the site to place,
## or null (and a WAIT decision) when none is valid any more.
func revalidate() -> BotCandidate:
	if _phase != Phase.DONE or _decision.kind != DecisionKind.PLACE:
		return _best
	if not _take_first_valid():
		_wait()
	return _best


## Softmax draw over the best `pool` ranked sites at the tier's pick_temperature.
func _sample_pool(pool: int) -> int:
	var best_score: float = _scores[_ranked[0]]
	var temperature: float = maxf(_profile.pick_temperature, MIN_TEMPERATURE)
	var weights: PackedFloat32Array = PackedFloat32Array()
	var total: float = 0.0
	for i: int in range(pool):
		var w: float = exp((_scores[_ranked[i]] - best_score) / temperature)
		weights.append(w)
		total += w
	var draw: float = _rng.randf() * total
	for i: int in range(pool):
		draw -= weights[i]
		if draw <= 0.0:
			return i
	return pool - 1


func _wait() -> void:
	_best = null
	_decision.kind = DecisionKind.WAIT
	_decision.intent = int(_intent.kind)
	_log_decision(null, 0.0)


func _log_decision(candidate: BotCandidate, score: float) -> void:
	if _intent_log < 0:
		_intent_log = 1 if OS.get_cmdline_user_args().has(INTENT_LOG_ARG) else 0
	if _intent_log == 0:
		return
	var intent_name: String = String(BotIntent.Kind.keys()[int(_intent.kind)])
	if candidate == null:
		print("BOTV2 slot=%d intent=%s WAIT sites=%d" % [_view.slot_id, intent_name, _candidates.size()])
		return
	print("BOTV2 slot=%d intent=%s target=(%.1f,%.1f) focus=%d site=%d at=(%.1f,%.1f) top=%.1f risk=%.2f score=%.2f own=%d" % [
		_view.slot_id, intent_name, _intent.target.x, _intent.target.y, _intent.focus_circle,
		candidate.site_kind, candidate.origin.x, candidate.origin.y, candidate.top_height,
		candidate.tip_risk, score, _view.indices_of_team(_view.team_id).size()
	])
