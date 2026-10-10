class_name BotThink
extends RefCounted
## Bot V2 (docs/BOT_AI_REDESIGN.md 2.3): one resumable think-cycle for one piece.
## P1 runs the LEGACY-EQUIVALENT pipeline (a pure port of BotController's
## uniform-in-territory sampler + BotPlacementScorer.pick_best) so V2 plays from
## day one; P4 swaps in strategy, targeted sites and the evaluator behind the
## same step()/decision() seam. Pure: physics is reached only through the
## `probe` callable the caller supplies.

const SHIPPED_TUNING: BotTuning = preload("res://config/bot_tuning.tres")
## BotCandidate.site_kind of a candidate drawn by the legacy sampler.
const SITE_LEGACY: int = 0
## Support height recorded for a probe cell with no hit (hole, rim, open air).
const NO_SUPPORT: float = -1.0

enum DecisionKind { PLACE, WAIT }


class Decision:
	extends RefCounted
	var kind: int = DecisionKind.WAIT
	var origin: Vector2 = Vector2.ZERO
	var orientation_index: int = 0
	var intent: int = BotIntent.Kind.RACE
	var terms: PackedFloat32Array = PackedFloat32Array()


## BotTuning for the scorer weights and sampler limits; BotController installs its own
## (possibly overridden) copy.
var tuning: BotTuning = SHIPPED_TUNING

var _view: BotWorldView
var _profile: BotDifficultyProfile
var _rng: RandomNumberGenerator
var _candidates: Array[BotCandidate] = []
var _orientations: Array[int] = []
var _started: bool = false
var _done: bool = false
var _best: BotCandidate = null
var _decision: Decision = Decision.new()


func _init(view: BotWorldView, profile: BotDifficultyProfile, rng: RandomNumberGenerator) -> void:
	_view = view
	_profile = profile
	_rng = rng


## Advances the think by at most about `budget_usec` microseconds (always at least one
## candidate, so a zero budget still progresses). `probe(xz: Vector2)` returns
## {hit: bool, height: float, own: bool}. True once the decision is ready.
func step(budget_usec: int, probe: Callable) -> bool:
	if _done:
		return true
	var start_usec: int = Time.get_ticks_usec()
	if not _started:
		_started = true
		if _view.held != null:
			_orientations = BotPlacementScorer.flattest_orientations(_view.held, _profile.candidate_count)
		if _orientations.is_empty():
			_orientations = [0]
	while _candidates.size() < _profile.candidate_count and _view.held != null:
		var orientation_index: int = _orientations[_candidates.size() % _orientations.size()]
		_candidates.append(_generate_one(orientation_index, probe))
		if _candidates.size() < _profile.candidate_count and Time.get_ticks_usec() - start_usec >= budget_usec:
			return false
	_finish()
	return true


## Ends the think now with the candidates gathered so far (the caller's frame cap).
func finish_early() -> void:
	if not _done:
		_finish()


func is_done() -> bool:
	return _done


func decision() -> Decision:
	return _decision


## The chosen candidate (null for WAIT); lets the controller reuse its recorded fields.
func best_candidate() -> BotCandidate:
	return _best


func candidates() -> Array[BotCandidate]:
	return _candidates


func _finish() -> void:
	_done = true
	_best = BotPlacementScorer.pick_best(
		_candidates, _view.raster, _view.grid, _view.team_id, _view.goals,
		_view.enemy_circle_centers(), _view.specials, tuning, _view.field_radius, _view.mode_goal
	)
	if _best == null:
		_decision.kind = DecisionKind.WAIT
		return
	_decision.kind = DecisionKind.PLACE
	_decision.origin = _best.origin
	_decision.orientation_index = _best.orientation_index
	_decision.intent = BotIntent.Kind.RACE


func _generate_one(orientation_index: int, probe: Callable) -> BotCandidate:
	var origin: Vector2 = _sample_territory_point()
	var hit: Dictionary = probe.call(origin) as Dictionary
	var candidate: BotCandidate = BotCandidate.new()
	candidate.origin = origin
	candidate.orientation_index = orientation_index
	candidate.site_kind = SITE_LEGACY
	candidate.support_height = float(hit.get("height", 0.0))
	var basis: Basis = BlockOrientations.get_basis(orientation_index)
	candidate.shape_height = shape_height_cubes(_view.held.cells, basis)
	candidate.top_height = candidate.support_height + candidate.shape_height
	if _view.grid != null:
		candidate.footprint_cells = PlacementRules.footprint_cells(
			_view.held.cells, basis, origin, _view.cube_size, _view.grid
		)
		_fire_stability_probes(candidate, probe)
	candidate.on_top_of_own_stack = bool(hit.get("own", false))
	return candidate


## The oriented shape's height in cube units (a flat pillar is 1, upright 3).
static func shape_height_cubes(cells: Array[Vector3i], basis: Basis) -> float:
	if cells.is_empty():
		return 0.0
	var min_height: float = INF
	var max_height: float = -INF
	for cell: Vector3i in cells:
		var transformed_height: float = round((basis * Vector3(cell)).y)
		min_height = minf(min_height, transformed_height)
		max_height = maxf(max_height, transformed_height)
	return max_height - min_height + 1.0


## Same footprint-cell probes as the legacy bot; also records per-cell support heights
## (NO_SUPPORT for a hole or a miss) in `cell_support` for the later statics.
func _fire_stability_probes(candidate: BotCandidate, probe: Callable) -> void:
	var cells: PackedInt32Array = candidate.footprint_cells
	var count: int = mini(_profile.stability_raycast_count, cells.size())
	if count <= 0:
		return
	var hits: int = 0
	candidate.cell_support.resize(count)
	for i: int in range(count):
		candidate.cell_support[i] = NO_SUPPORT
		# DECISION (Bontago-1t5.19): holes are read off the raster's hole state; the legacy
		# bot reads the Field's applied-hole mask, which lags the raster by the toggle batch.
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


## Port of BotController._sample_territory_point (frontier-biased in Elimination, else
## uniform-in-disk rejection against PlacementRules.validate_point; home fallback).
func _sample_territory_point() -> Vector2:
	var raster: TerritoryRaster = _view.raster
	var radius: float = _view.field_radius
	if raster != null and radius > 0.0:
		var line: PackedVector2Array = _frontier_line()
		if line.size() == 2 and _rng.randf() < tuning.elim_frontier_sample_fraction:
			for _attempt: int in range(tuning.max_territory_sample_attempts):
				var t: float = 1.0 - _rng.randf() * _rng.randf()
				var jitter: Vector2 = Vector2.from_angle(_rng.randf() * TAU) * (_rng.randf() * tuning.elim_frontier_jitter_m)
				var biased_xz: Vector2 = line[0].lerp(line[1], t) + jitter
				if biased_xz.length() <= radius and PlacementRules.validate_point(biased_xz, raster, _view.team_id) == PlacementRules.Result.VALID:
					return biased_xz
		for _attempt: int in range(tuning.max_territory_sample_attempts):
			var angle: float = _rng.randf() * TAU
			var dist: float = sqrt(_rng.randf()) * radius
			var candidate_xz: Vector2 = Vector2(cos(angle), sin(angle)) * dist
			if PlacementRules.validate_point(candidate_xz, raster, _view.team_id) == PlacementRules.Result.VALID:
				return candidate_xz
	return _view.own_home


func _frontier_line() -> PackedVector2Array:
	var goal: BotModeGoal = _view.mode_goal
	if goal == null or goal.mode != MatchConfig.GameMode.ELIMINATION or not goal.has_own_home:
		return PackedVector2Array()
	var index: int = BotPlacementScorer.target_home_index(goal, tuning)
	if index < 0:
		return PackedVector2Array()
	return PackedVector2Array([goal.own_home_position, goal.enemy_home_positions[index]])
