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

const SHIPPED_TUNING: BotEvalTuning = preload("res://config/bots/bot_eval_tuning.tres")
## Tests (and the tuning tools) may swap this; it is read-only in play.
static var tuning: BotEvalTuning = SHIPPED_TUNING
## Bontago-1t5.53b: the tower-statics tunables (aim share, tolerance, analysis slice); tests may swap it.
const SHIPPED_STACK_TUNING: BotStackTuning = preload("res://config/bots/bot_stack_tuning.tres")
static var stack_tuning: BotStackTuning = SHIPPED_STACK_TUNING
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
	terms[BotIntent.Term.REACH] = radius - c.origin.distance_to(intent.target) + height_gain(c, view)
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
		terms[BotIntent.Term.HAZARD] = minf(_hazard_from_gap(c, view, nearest_gap) + incoming_special_risk(c, view), 1.0)
	terms[BotIntent.Term.EXPOSURE] = float(mini(threats + _home_threats(c.origin, view), tuning.exposure_cap))
	terms[BotIntent.Term.TIP] = stability_risk(c) + wind_tip(c, view) + breeze_tip(c, view) + rim_risk(c, view)
	terms[BotIntent.Term.WASTE] = 1.0 if inside >= 1.0 else 0.0
	return terms


## Full per-term magnitudes for one site (size BotIntent.Term.size(), indexed by Term).
static func measure(
	c: BotCandidate, view: BotWorldView, chains: BotChains, intent: BotIntent
) -> PackedFloat32Array:
	var terms: PackedFloat32Array = PackedFloat32Array()
	terms.resize(BotIntent.Term.size())
	var radius: float = future_radius(c, view)
	terms[BotIntent.Term.REACH] = _reach(c, view, chains, intent, radius) + height_gain(c, view)
	var fractions: Vector2 = _sample_fractions(c, view, radius)
	var area_m2: float = PI * radius * radius * fractions.x
	terms[BotIntent.Term.AREA] = area_m2 / tuning.area_unit_m2
	terms[BotIntent.Term.WASTE] = fractions.y
	terms[BotIntent.Term.KILL] = _kill(c, view, chains, radius)
	terms[BotIntent.Term.EXPOSURE] = float(_exposure(c, view, chains))
	terms[BotIntent.Term.TIP] = stability_risk(c) + wind_tip(c, view) + breeze_tip(c, view) + rim_risk(c, view)
	terms[BotIntent.Term.HAZARD] = minf(hazard(c, view, chains) + incoming_special_risk(c, view), 1.0)
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


## Bontago-1t5.72.5: TIP risk of the site's statics: topple_penalty when the probed placement is not stable under
## the owner's two centre-of-mass rules (BotStability slack <= 0), else 0. An unevaluated site has slack INF.
## DECISION: binary, no soft headroom band; the required margin already holds the aim error and the tolerance.
static func stability_risk(c: BotCandidate) -> float:
	return tuning.topple_penalty if c.stability_slack <= 0.0 else 0.0


## Bontago-1t5.41: extra TIP risk from the active wind: grows with the weather intensity and
## the wind's height response at the piece's top; exactly 0 in calm weather or without wind.
## Bontago-1t5.46: scaled by 1 + wind_rim_gain * downwind_rim_factor along the Storm heading
## (view.wind_dir), so a site with the rim close downwind scores worse than an upwind one; the
## factor is 0 (the old value, bit for bit) while the heading is unknown.
static func wind_tip(c: BotCandidate, view: BotWorldView) -> float:
	if view.wind_tuning == null or view.weather_intensity <= 0.0 or tuning.wind_tip_weight <= 0.0:
		return 0.0
	var top: float = maxf(c.top_height, c.support_height + c.shape_height)
	var sway: float = tuning.wind_tip_weight * clampf(view.weather_intensity, 0.0, 1.0) * WindField.height_factor(top, view.wind_tuning)
	if sway <= 0.0 or view.wind_dir == Vector2.ZERO:
		return sway
	return sway * (1.0 + tuning.wind_rim_gain * downwind_rim_factor(c.origin, view.wind_dir, view))


## Bontago-1t5.44: risk 0..1 of a site lying in the impact zone of an enemy special in flight: the
## worst zone's linear proximity (1 at the predicted impact point, 0 at radius + incoming_margin_m),
## times incoming_special_weight. Exactly 0 with none in flight.
static func incoming_special_risk(c: BotCandidate, view: BotWorldView) -> float:
	if view.incoming_points.is_empty() or tuning.incoming_special_weight <= 0.0:
		return 0.0
	var worst: float = 0.0
	for i: int in range(view.incoming_points.size()):
		var reach: float = view.incoming_radii[i] + tuning.incoming_margin_m
		if reach <= 0.0:
			continue
		worst = maxf(worst, 1.0 - c.origin.distance_to(view.incoming_points[i]) / reach)
	return clampf(worst, 0.0, 1.0) * tuning.incoming_special_weight


## Bontago-1t5.46: extra TIP risk from the live Breeze gusts. Each gust adds its power times the
## smooth falloff of the piece's distance to the gust centre (the host's BreezeField.falloff), times
## the Breeze height response at the piece's top, times 1 + wind_rim_gain * downwind_rim_factor along
## the gust heading. Distance is 3D: the vertical part is the gap between the gust centre height
## and the piece's [support, top] span (0 when the centre lies inside it), and a site downwind of
## the centre (positive offset along the heading) has that offset shrunk by 1 / (1 + breeze_lee_gain),
## i.e. the sphere reaches further downwind than upwind. Exactly 0 with no gust, a low piece (below
## the Breeze threshold height) or breeze_tip_weight 0; calm and upwind/sheltered sites score as before.
static func breeze_tip(c: BotCandidate, view: BotWorldView) -> float:
	if view.breeze_tuning == null or view.gust_power_values.is_empty() or tuning.breeze_tip_weight <= 0.0:
		return 0.0
	var top: float = maxf(c.top_height, c.support_height + c.shape_height)
	var response: float = WindField.height_factor(top, view.breeze_tuning)
	if response <= 0.0:
		return 0.0
	var bottom: float = minf(c.support_height, top)
	var total: float = 0.0
	for i: int in range(view.gust_power_values.size()):
		var centre: Vector3 = view.gust_center[i]
		var heading: Vector2 = view.gust_heading[i]
		var rel: Vector2 = c.origin - Vector2(centre.x, centre.z)
		var along: float = rel.dot(heading)
		if along > 0.0:
			rel -= heading * (along - along / (1.0 + maxf(tuning.breeze_lee_gain, 0.0)))
		var dy: float = maxf(maxf(bottom - centre.y, centre.y - top), 0.0)
		var distance: float = sqrt(rel.length_squared() + dy * dy)
		var exposure: float = view.gust_power_values[i] * BreezeField.falloff(distance, view.gust_radius[i])
		if exposure > 0.0:
			total += exposure * (1.0 + tuning.wind_rim_gain * downwind_rim_factor(c.origin, heading, view))
	return tuning.breeze_tip_weight * total * response


## Bontago-1t5.46: 0..1 how close `origin` is to the live disc edge measured along `heading` (the way
## the wind shoves a piece): 1 at or beyond the edge, falling linearly to 0 once BotEvalTuning.rim_margin_m
## or more of disc lies downwind. 0 while the heading or the live radius is unknown. Origin only (the
## footprint is not sampled), which keeps it cheap enough for the proxy stage.
static func downwind_rim_factor(origin: Vector2, heading: Vector2, view: BotWorldView) -> float:
	if view.live_radius <= 0.0 or heading == Vector2.ZERO or tuning.rim_margin_m <= 0.0:
		return 0.0
	var along: float = origin.dot(heading)
	var disc: float = along * along - origin.length_squared() + view.live_radius * view.live_radius
	var run: float = sqrt(maxf(disc, 0.0)) - along
	return clampf(1.0 - run / tuning.rim_margin_m, 0.0, 1.0)


## Bontago-1t5.42: fall-off risk near the live disc edge plus the pull towards the surviving
## centre after a shrink (TIP axis). Exactly 0 when the footprint stays rim_margin_m inside the
## disc and no shrink is active, so central placements on a full-size disc score as before.
static func rim_risk(c: BotCandidate, view: BotWorldView) -> float:
	if view.live_radius <= 0.0:
		return 0.0
	var reach: float = c.origin.length()
	# Early-out: when even the farthest possible footprint cell stays rim_margin_m inside the
	# disc (and no shrink bias applies below), the loop cannot change the result.
	var extent: float = view.footprint_extent_m()
	var clear: bool = extent >= 0.0 and reach + extent <= view.live_radius - tuning.rim_margin_m
	if view.grid != null and not clear:
		for index: int in c.footprint_cells:
			reach = maxf(reach, view.grid.index_center(index).length())
	var margin: float = view.live_radius - reach
	var risk: float = 0.0
	if margin < tuning.rim_margin_m and tuning.rim_margin_m > 0.0:
		risk += tuning.rim_weight * clampf(1.0 - margin / tuning.rim_margin_m, 0.0, 1.0)
	if margin < 0.0:
		risk += tuning.rim_outside_penalty
	if view.is_shrunk():
		var shrunk: float = 1.0 - view.live_radius / view.field_radius
		risk += tuning.shrink_centre_weight * shrunk * clampf(c.origin.length() / view.live_radius, 0.0, 1.0)
	return risk


## Bontago-1t5.69: Reach the Sky only (else 0): height_gain_weight times the metres this placement raises the
## column it rests on (top height minus the support height under the site, from the probe), plus
## height_top_area_weight per cube of its top layer (capped). DECISION (review): the baseline is the surface
## the piece lands on, not the tallest own block, so a bar still stands up on a new base beside tall debris.
## Added to the REACH term (the intent's REACH weight scales it); the TIP axis (the statics model's topple penalty)
## still penalises standing up unsound.
static func height_gain(c: BotCandidate, view: BotWorldView) -> float:
	if view.mode != MatchConfig.GameMode.REACH_THE_SKY or tuning.height_gain_weight <= 0.0:
		return 0.0
	var gain: float = maxf(c.top_height - c.support_height, 0.0)
	if gain <= 0.0:
		return 0.0
	return tuning.height_gain_weight * gain + tuning.height_top_area_weight * minf(c.top_area, tuning.height_top_area_cap)


## Radius of the influence circle the placed piece will project.
static func future_radius(c: BotCandidate, view: BotWorldView) -> float:
	var top: float = maxf(c.top_height, c.support_height + c.shape_height)
	return InfluenceCircle.radius_for_height(top, view.territory_tuning, view.field_radius)


## Bontago-1t5.32: dissolve risk (0 safe .. 1 doomed) of the site's base under the overlap-hole
## rule; 0 under HoleMode.OFF, where nothing dissolves. The legacy fill turns every cell that
## home-connected circles of two teams cover CONTESTED, opens a hole there after
## TerritoryTuning.hole_delay, and game/field/HoleDissolver.gd dissolves a disc-level block touching
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
