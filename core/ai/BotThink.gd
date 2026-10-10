class_name BotThink
extends RefCounted
## Bot V2 (docs/BOT_AI_REDESIGN.md 2.3): one resumable think-cycle for one piece. The
## assembled pipeline, each stage resumable under the caller's microsecond budget:
##   PLAN     BotChains + BotStrategy.choose -> BotIntent                (one chunk)
##   SITES    BotCandidateGen.sites for the intent                       (one chunk)
##   PROBE    support ray + one ray per footprint cell, statics -> tip_risk (per site)
##   RANK     BotEvaluator.proxy on every site, best first
##   MEASURE  BotEvaluator.measure on the top `eval_top_k` (skipped when 0) (per site)
##   PICK     argmax, or a softmax sample from the best `pick_pool`; the origin is
##            re-validated against the live raster (state can move during the think)
## The PLAN and SITES chunks are not sliceable (they are pure rule code, a few ms at 110
## sites); step() checks the budget between chunks. Pure: physics is reached only through
## the `probe` callable the caller supplies.

const SHIPPED_TUNING: BotTuning = preload("res://config/bot_tuning.tres")
## BotCandidate.site_kind of a candidate from the retired legacy sampler (kept as the 0 default).
const SITE_LEGACY: int = 0
## Support height recorded for a probe cell with no hit (hole, rim, open air).
const NO_SUPPORT: float = -1.0
## `-- --bot-intent-log` prints one line per decision (smoke diagnostics).
## Floor for the softmax temperature (a 0 would divide by zero).
const MIN_TEMPERATURE: float = 0.001
const INTENT_LOG_ARG: String = "--bot-intent-log"

enum DecisionKind { PLACE, WAIT }
enum Phase { PLAN, SITES, PROBE, RANK, MEASURE, PICK, DONE }

static var _intent_log: int = -1
## Per-seat BotStrategy stickiness memory (slot id -> Dictionary), kept between pieces.
static var _strategy_memory: Dictionary = {}


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

var _view: BotWorldView
var _profile: BotDifficultyProfile
var _rng: RandomNumberGenerator
var _phase: Phase = Phase.PLAN
var _chains: BotChains = null
var _intent: BotIntent = BotIntent.new()
var _candidates: Array[BotCandidate] = []
var _probe_index: int = 0
## Candidate indices ranked best first (proxy, then measured on the head).
var _ranked: PackedInt32Array = PackedInt32Array()
var _scores: PackedFloat32Array = PackedFloat32Array()
var _terms: Array[PackedFloat32Array] = []
var _measure_pos: int = 0
var _best: BotCandidate = null
## Ranked positions in pick order (the chosen one first), for revalidate().
var _pick_order: Array[int] = []
var _decision: Decision = Decision.new()


func _init(view: BotWorldView, profile: BotDifficultyProfile, rng: RandomNumberGenerator) -> void:
	_view = view
	_profile = profile
	_rng = rng


## Advances the think by at most about `budget_usec` microseconds (always at least one unit
## of work, so a zero budget still progresses). `probe(xz: Vector2)` returns
## {hit: bool, height: float, own: bool}. True once the decision is ready.
func step(budget_usec: int, probe: Callable) -> bool:
	var start_usec: int = Time.get_ticks_usec()
	while _phase != Phase.DONE:
		_advance(probe)
		if _phase != Phase.DONE and Time.get_ticks_usec() - start_usec >= budget_usec:
			return false
	return true


## Ends the think now with what is gathered so far (the caller's frame cap): the sites probed
## so far are ranked by proxy and the best valid one is picked.
func finish_early() -> void:
	if _phase == Phase.DONE:
		return
	if _phase == Phase.PLAN or _phase == Phase.SITES:
		if _view.held == null:
			_phase = Phase.DONE
			_wait()
			return
		_plan()
		_make_sites()
	if _phase == Phase.PROBE:
		_rank(_probe_index if _probe_index > 0 else _candidates.size())
	elif _phase == Phase.RANK:
		_rank(_candidates.size())
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


func _advance(probe: Callable) -> void:
	match _phase:
		Phase.PLAN:
			if _view.held == null:
				_phase = Phase.DONE
				_wait()
				return
			_plan()
			_phase = Phase.SITES
		Phase.SITES:
			_make_sites()
		Phase.PROBE:
			_probe_one(probe)
		Phase.RANK:
			_rank(_candidates.size())
		Phase.MEASURE:
			_measure_one()
		Phase.PICK:
			_pick()
		Phase.DONE:
			pass


func _plan() -> void:
	if _chains != null:
		return
	_chains = BotChains.build(_view)
	var memory: Dictionary = _strategy_memory.get(_view.slot_id, {}) as Dictionary
	_intent = BotStrategy.choose(_view, _chains, _profile, strategy_tuning, memory)
	_strategy_memory[_view.slot_id] = memory


func _make_sites() -> void:
	_candidates = BotCandidateGen.sites(_view, _intent, _profile, _rng, gen_tuning)
	_probe_index = 0
	_phase = Phase.PROBE if not _candidates.is_empty() else Phase.PICK


func _probe_one(probe: Callable) -> void:
	var candidate: BotCandidate = _candidates[_probe_index]
	_probe_index += 1
	var hit: Dictionary = probe.call(candidate.origin) as Dictionary
	candidate.support_height = float(hit.get("height", 0.0))
	candidate.on_top_of_own_stack = bool(hit.get("own", false))
	candidate.top_height = candidate.support_height + candidate.shape_height
	_fire_cell_probes(candidate, probe)
	candidate.tip_risk = BotStatics.tip_risk(candidate, _view.held, _view.grid, gen_tuning, _view.cube_size)
	if _probe_index >= _candidates.size():
		_phase = Phase.RANK


## Per-footprint-cell support heights (NO_SUPPORT for a hole or a miss), capped at the tier's
## stability_raycast_count. DECISION (Bontago-1t5.19): holes are read off the raster's hole
## state; the legacy bot reads the Field's applied-hole mask, which lags the raster.
func _fire_cell_probes(candidate: BotCandidate, probe: Callable) -> void:
	var cells: PackedInt32Array = candidate.footprint_cells
	var count: int = maxi(mini(_profile.stability_raycast_count, cells.size()), 0)
	candidate.cell_support.resize(count)
	var hits: int = 0
	for i: int in range(count):
		candidate.cell_support[i] = NO_SUPPORT
		if _view.raster != null and _view.raster.is_hole_index(cells[i]):
			continue
		var cell_hit: Dictionary = probe.call(_view.grid.index_center(cells[i])) as Dictionary
		if not bool(cell_hit.get("hit", false)):
			continue
		var height: float = float(cell_hit.get("height", 0.0))
		candidate.cell_support[i] = height
		if absf(height - candidate.support_height) <= tuning.stability_contact_tolerance_m:
			hits += 1
	candidate.corner_support_hits = hits


## Proxy-scores sites [0, limit) and ranks them best first (ties keep generation order).
func _rank(limit: int) -> void:
	limit = mini(limit, _candidates.size())
	_scores.resize(_candidates.size())
	_terms.resize(_candidates.size())
	var order: Array[int] = []
	for i: int in range(limit):
		var terms: PackedFloat32Array = BotEvaluator.proxy_terms(_candidates[i], _view, _intent)
		_terms[i] = terms
		_scores[i] = _site_score(_candidates[i], terms)
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
