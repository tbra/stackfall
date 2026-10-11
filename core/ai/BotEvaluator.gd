class_name BotEvaluator
extends RefCounted
## Bot V2 (docs/BOT_AI_REDESIGN.md 2.3 step 6, Bontago-1t5.22): scores a placement
## site on the BotIntent.Term axes. proxy() is the cheap stage run on every site;
## measure() is the costlier stage (64-sample territory read, chain cuts) run on the
## top-k by proxy. Pure: reads a BotWorldView, BotChains and a BotCandidate only.
##
## Term units (raw magnitudes, higher = more of that thing; penalties are applied
## by score()): REACH metres, AREA in BotEvalTuning.area_unit_m2 units, KILL circles
## lost by the enemy, EXPOSURE threatening-circle count, TIP risk 0..1, WASTE 0..1,
## HAZARD dissolve risk 0..1 (Bontago-1t5.32, see hazard()).
## score() adds REACH/AREA/KILL and subtracts EXPOSURE/TIP/WASTE/HAZARD, each times the
## intent weight.
##
## The future circle is centred on the candidate origin with radius
## InfluenceCircle.radius_for_height(top height) (cone half-angle 40 deg).

const SHIPPED_TUNING: BotEvalTuning = preload("res://config/bot_eval_tuning.tres")
## Tests (and the tuning tools) may swap this; it is read-only in play.
static var tuning: BotEvalTuning = SHIPPED_TUNING
## Sunflower spiral step, pi * (3 - sqrt(5)) radians.
const GOLDEN_ANGLE: float = 2.39996323


## Cheap score for ranking every site: weighted terms that need no raster read and
## no chains. REACH is the negated new gap (r - distance to target), KILL the number
## of enemy circles under the new circle (0 in HoleMode.OFF), AREA a containment estimate.
static func proxy(c: BotCandidate, view: BotWorldView, intent: BotIntent) -> float:
	return score(proxy_terms(c, view, intent), intent)


## The proxy's per-term magnitudes (size BotIntent.Term.size()).
static func proxy_terms(c: BotCandidate, view: BotWorldView, intent: BotIntent) -> PackedFloat32Array:
	var terms: PackedFloat32Array = PackedFloat32Array()
	terms.resize(BotIntent.Term.size())
	var radius: float = future_radius(c, view)
	terms[BotIntent.Term.REACH] = radius - c.origin.distance_to(intent.target)
	var inside: float = _own_overlap_fraction(c.origin, radius, view)
	terms[BotIntent.Term.AREA] = PI * radius * radius * (1.0 - inside) / tuning.area_unit_m2
	var covered: int = 0
	var threats: int = 0
	var margin: float = tuning.kill_margin_m
	var nearest_gap: float = INF
	for j: int in range(view.circle_count()):
		if view.cteam[j] == view.team_id:
			continue
		var d: float = c.origin.distance_to(Vector2(view.cx[j], view.cz[j]))
		if d <= radius + margin:
			covered += 1
		if d <= view.cr[j] + tuning.exposure_allowance_m:
			threats += 1
		if not _strikes_first(d, radius, view.cr[j]):
			nearest_gap = minf(nearest_gap, d - view.cr[j])
	if not _kill_disabled(view):
		terms[BotIntent.Term.KILL] = float(covered)
		terms[BotIntent.Term.HAZARD] = _hazard_from_gap(c, view, nearest_gap)
	terms[BotIntent.Term.EXPOSURE] = float(mini(threats + _home_threats(c.origin, view), tuning.exposure_cap))
	terms[BotIntent.Term.TIP] = c.tip_risk
	terms[BotIntent.Term.WASTE] = 1.0 if inside >= 1.0 else 0.0
	return terms


## Full per-term magnitudes for one site (size BotIntent.Term.size(), indexed by Term).
static func measure(
	c: BotCandidate, view: BotWorldView, chains: BotChains, intent: BotIntent
) -> PackedFloat32Array:
	var terms: PackedFloat32Array = PackedFloat32Array()
	terms.resize(BotIntent.Term.size())
	var radius: float = future_radius(c, view)
	terms[BotIntent.Term.REACH] = _reach(c, view, chains, intent, radius)
	var fractions: Vector2 = _sample_fractions(c, view, radius)
	var area_m2: float = PI * radius * radius * fractions.x
	terms[BotIntent.Term.AREA] = area_m2 / tuning.area_unit_m2
	terms[BotIntent.Term.WASTE] = fractions.y
	terms[BotIntent.Term.KILL] = _kill(c, view, chains, radius)
	terms[BotIntent.Term.EXPOSURE] = float(_exposure(c, view, chains))
	terms[BotIntent.Term.TIP] = c.tip_risk
	terms[BotIntent.Term.HAZARD] = hazard(c, view, chains)
	return terms


## Weighted sum of `terms` under the intent weights (penalty terms subtract).
static func score(terms: PackedFloat32Array, intent: BotIntent) -> float:
	var total: float = 0.0
	for t: int in range(mini(terms.size(), intent.weights.size())):
		var signed: float = terms[t]
		if (
			t == BotIntent.Term.EXPOSURE or t == BotIntent.Term.TIP or t == BotIntent.Term.WASTE
			or t == BotIntent.Term.HAZARD
		):
			signed = -signed
		total += signed * intent.weights[t]
	return total


## Radius of the influence circle the placed piece will project.
static func future_radius(c: BotCandidate, view: BotWorldView) -> float:
	var top: float = maxf(c.top_height, c.support_height + c.shape_height)
	return InfluenceCircle.radius_for_height(top, view.territory_tuning, view.field_radius)


## Bontago-1t5.32: dissolve risk (0 safe .. 1 doomed) of the site's base under the overlap-hole
## rule; 0 under HoleMode.OFF, where nothing dissolves. The legacy fill turns every cell that
## home-connected circles of two teams cover CONTESTED, opens a hole there after
## TerritoryTuning.hole_delay, and game/HoleDissolver.gd dissolves a disc-level block touching
## the hole together with everything stacked on it. A block's own circle always covers its
## footprint, so the piece is lost as soon as an enemy circle covers any footprint cell:
##   1     a footprint cell is already enemy-held, contested or a hole (a raster read);
##   else  the look-ahead: an enemy block circle whose edge lies within hazard_lookahead() of
##         the base can grow over it with one placement (bots place on a shared cadence, so the
##         enemy's next piece can land before this one's circle keeps it out), graded linearly
##         from 1 at the circle's edge to 0 at the look-ahead distance.
## `chains` null (the proxy) counts every enemy circle, otherwise home-connected ones only.
## DECISION (Bontago-1t5.32): one placement of look-ahead, graded linearly, nearest enemy edge
## only (not a per-circle sum): the 4-bot measurements showed the nearest circle decides. An
## enemy circle whose base the new circle covers from outside it is struck first (it dissolves
## before its next placement can grow it) and is skipped. Home
## circles never grow, so they add no look-ahead (a base inside one is doomed by the footprint
## read; Elimination SIEGE still has to build next to the target home).
static func hazard(c: BotCandidate, view: BotWorldView, chains: BotChains) -> float:
	if _kill_disabled(view):
		return 0.0
	var radius: float = future_radius(c, view)
	var nearest_gap: float = INF
	for j: int in range(view.circle_count()):
		if view.cteam[j] == view.team_id or (chains != null and not chains.connected(j)):
			continue
		var d: float = c.origin.distance_to(Vector2(view.cx[j], view.cz[j]))
		if not _strikes_first(d, radius, view.cr[j]):
			nearest_gap = minf(nearest_gap, d - view.cr[j])
	return _hazard_from_gap(c, view, nearest_gap)


## True when the new circle (`radius`) covers an enemy base `d` metres away (within
## kill_margin_m, as KILL counts it) while the base lies outside that enemy circle (`enemy_r`):
## the enemy block dissolves before it can grow over the site, so it adds no look-ahead.
static func _strikes_first(d: float, radius: float, enemy_r: float) -> bool:
	return d <= radius + tuning.kill_margin_m and d > enemy_r


## How far beyond its edge one enemy placement can push an enemy circle: the radius of a
## fresh piece of BotEvalTuning.hazard_lookahead_height_m (the future_radius model).
static func hazard_lookahead(view: BotWorldView) -> float:
	return InfluenceCircle.radius_for_height(
		tuning.hazard_lookahead_height_m, view.territory_tuning, view.field_radius
	)


## hazard() given the smallest (distance - radius) over the enemy block circles; the footprint
## read is added here.
static func _hazard_from_gap(c: BotCandidate, view: BotWorldView, nearest_gap: float) -> float:
	if _footprint_doomed(c, view):
		return 1.0
	var lookahead: float = hazard_lookahead(view)
	if lookahead <= 0.0 or is_inf(nearest_gap):
		return 0.0
	return clampf(1.0 - nearest_gap / lookahead, 0.0, 1.0)


## True when a footprint cell (the origin cell when none were computed) is held by another
## team, contested or a hole: the new circle makes it contested and the piece dissolves.
static func _footprint_doomed(c: BotCandidate, view: BotWorldView) -> bool:
	if view.raster == null or view.grid == null:
		return false
	var grid: CellGrid = view.grid
	var cells: PackedInt32Array = c.footprint_cells
	if cells.is_empty():
		var origin_cell: Vector2i = grid.world_to_cell(c.origin)
		if not grid.in_bounds(origin_cell.x, origin_cell.y):
			return false
		cells = PackedInt32Array([grid.cell_index(origin_cell.x, origin_cell.y)])
	for index: int in cells:
		var xy: Vector2i = grid.cell_coords(index)
		var team: int = view.raster.team_at(xy.x, xy.y)
		if team == view.team_id:
			continue
		if team >= 0 or view.raster.is_hole_index(index) or view.raster.is_contested(xy.x, xy.y):
			return true
	return false


## Under HoleMode.OFF circles never destroy each other (only a larger kernel takes a
## cell), so there is no kill term. DECISION: home or goal cover is not counted there
## either.
static func _kill_disabled(view: BotWorldView) -> bool:
	return view.mode_goal != null and view.mode_goal.no_overlap_mode


static func _reach(
	c: BotCandidate, view: BotWorldView, chains: BotChains, intent: BotIntent, radius: float
) -> float:
	var gap_before: float = chains.gap_to(view.team_id, intent.target)
	if is_inf(gap_before):
		return 0.0
	var gap_after: float = minf(gap_before, c.origin.distance_to(intent.target) - radius)
	return gap_before - gap_after


## Circles the enemy loses when the new circle covers their bases, plus home and
## held-goal cover.
static func _kill(c: BotCandidate, view: BotWorldView, chains: BotChains, radius: float) -> float:
	if _kill_disabled(view):
		return 0.0
	var reach: float = radius + tuning.kill_margin_m
	var own_circles: PackedInt32Array = view.indices_of_team(view.team_id)
	var covered: PackedInt32Array = PackedInt32Array()
	for j: int in range(view.circle_count()):
		if view.cteam[j] == view.team_id or not chains.connected(j):
			continue
		var centre: Vector2 = Vector2(view.cx[j], view.cz[j])
		if c.origin.distance_to(centre) > reach:
			continue
		if not _already_covered_by(own_circles, centre, view):
			covered.append(j)
	var total: float = float(chains.cut_loss(covered))
	for home: Vector2 in view.enemy_homes:
		if c.origin.distance_to(home) <= reach:
			total += tuning.kill_home_value
	for goal: Vector2 in view.goals:
		if c.origin.distance_to(goal) > radius:
			continue
		var holder: int = _holder(view, goal)
		if holder != -1 and holder != view.team_id:
			total += tuning.kill_goal_value
	return total


## True when an own circle already reaches `centre` (it is contested already).
static func _already_covered_by(own: PackedInt32Array, centre: Vector2, view: BotWorldView) -> bool:
	var margin: float = tuning.kill_margin_m
	for i: int in own:
		if centre.distance_to(Vector2(view.cx[i], view.cz[i])) <= view.cr[i] + margin:
			return true
	if view.has_home:
		return centre.distance_to(view.own_home) <= view.territory_tuning.home_radius + margin
	return false


## Enemy circles (home-connected ones only) and homes whose reach plus allowance
## contains the base.
static func _exposure(c: BotCandidate, view: BotWorldView, chains: BotChains) -> int:
	var threats: int = _home_threats(c.origin, view)
	for j: int in range(view.circle_count()):
		if view.cteam[j] == view.team_id or not chains.connected(j):
			continue
		var d: float = c.origin.distance_to(Vector2(view.cx[j], view.cz[j]))
		if d <= view.cr[j] + tuning.exposure_allowance_m:
			threats += 1
	return mini(threats, tuning.exposure_cap)


static func _home_threats(origin: Vector2, view: BotWorldView) -> int:
	var reach: float = view.territory_tuning.home_radius + tuning.exposure_allowance_m
	var threats: int = 0
	for home: Vector2 in view.enemy_homes:
		if origin.distance_to(home) <= reach:
			threats += 1
	return threats


## Rough fraction (0..1) of the new circle already inside one own circle.
static func _own_overlap_fraction(origin: Vector2, radius: float, view: BotWorldView) -> float:
	var best: float = 0.0
	for i: int in view.indices_of_team(view.team_id):
		best = maxf(best, _overlap_fraction(origin, radius, Vector2(view.cx[i], view.cz[i]), view.cr[i]))
	if view.has_home:
		best = maxf(best, _overlap_fraction(origin, radius, view.own_home, view.territory_tuning.home_radius))
	return best


static func _overlap_fraction(origin: Vector2, radius: float, centre: Vector2, other: float) -> float:
	var d: float = origin.distance_to(centre)
	if d + radius <= other:
		return 1.0
	if d >= other + radius or radius <= 0.0:
		return 0.0
	return clampf((other + radius - d) / (2.0 * radius), 0.0, 1.0)


## Team holding the raster cell at `point`: -1 unowned, contested, hole, off-grid
## or no raster.
static func _holder(view: BotWorldView, point: Vector2) -> int:
	if view.raster == null or view.grid == null:
		return -1
	var cell: Vector2i = view.grid.world_to_cell(point)
	return view.raster.team_at(cell.x, cell.y)


## (gain fraction, own fraction) over `area_samples` sunflower points of the new circle.
## Legacy fill: a gain is an unowned, uncontested, non-hole in-disk cell. HoleMode.OFF
## (argmax fill): a gain is any non-own cell where the new kernel (radius - distance)
## beats every enemy kernel there. Own fraction is the share of cells already own.
static func _sample_fractions(c: BotCandidate, view: BotWorldView, radius: float) -> Vector2:
	var samples: int = maxi(tuning.area_samples, 1)
	if view.raster == null or view.grid == null:
		var inside: float = _own_overlap_fraction(c.origin, radius, view)
		return Vector2(1.0 - inside, inside)
	var argmax_mode: bool = _kill_disabled(view)
	var rivals: PackedInt32Array = PackedInt32Array()
	if argmax_mode:
		for j: int in range(view.circle_count()):
			if view.cteam[j] == view.team_id:
				continue
			var reach: float = radius + view.cr[j]
			if c.origin.distance_squared_to(Vector2(view.cx[j], view.cz[j])) < reach * reach:
				rivals.append(j)
	var gains: int = 0
	var owned: int = 0
	var grid: CellGrid = view.grid
	var dirs: PackedVector2Array = _sample_dirs(samples)
	var scales: PackedFloat64Array = _sample_scales(samples)
	for k: int in range(samples):
		var offset: float = radius * scales[k]
		var point: Vector2 = c.origin + dirs[k] * offset
		# Inlined CellGrid.world_to_cell (identical arithmetic; 64 calls per measured site).
		var cell: Vector2i = Vector2i(
			floori((point.x + grid.half_extent) / grid.cell_size),
			floori((point.y + grid.half_extent) / grid.cell_size)
		)
		if not grid.in_bounds(cell.x, cell.y) or not grid.is_in_disk(cell.x, cell.y):
			continue
		var team: int = view.raster.team_at(cell.x, cell.y)
		if team == view.team_id:
			owned += 1
		elif argmax_mode:
			if radius - offset > _best_enemy_kernel(point, rivals, view):
				gains += 1
		elif (
			team == -1
			and not view.raster.is_contested(cell.x, cell.y)
			and not view.raster.is_hole(cell.x, cell.y)
		):
			gains += 1
	return Vector2(float(gains) / float(samples), float(owned) / float(samples))


## Unit directions and radial scales of the `samples`-point sunflower spiral (Bontago-1t5.30:
## computed once per sample count; the same values the per-call cos/sin/sqrt produced).
static var _spiral_dirs: Dictionary = {}
static var _spiral_scales: Dictionary = {}


static func _sample_dirs(samples: int) -> PackedVector2Array:
	if not _spiral_dirs.has(samples):
		_build_spiral(samples)
	return _spiral_dirs[samples] as PackedVector2Array


static func _sample_scales(samples: int) -> PackedFloat64Array:
	if not _spiral_scales.has(samples):
		_build_spiral(samples)
	return _spiral_scales[samples] as PackedFloat64Array


static func _build_spiral(samples: int) -> void:
	var dirs: PackedVector2Array = PackedVector2Array()
	var scales: PackedFloat64Array = PackedFloat64Array()
	for k: int in range(samples):
		var angle: float = float(k) * GOLDEN_ANGLE
		dirs.append(Vector2(cos(angle), sin(angle)))
		scales.append(sqrt((float(k) + 0.5) / float(samples)))
	_spiral_dirs[samples] = dirs
	_spiral_scales[samples] = scales


static func _best_enemy_kernel(point: Vector2, rivals: PackedInt32Array, view: BotWorldView) -> float:
	var best: float = -INF
	for j: int in rivals:
		best = maxf(best, view.cr[j] - point.distance_to(Vector2(view.cx[j], view.cz[j])))
	for home: Vector2 in view.enemy_homes:
		best = maxf(best, view.territory_tuning.home_radius - point.distance_to(home))
	return best
