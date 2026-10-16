class_name BotSpecialPlanner
extends RefCounted
## Pure (CLAUDE.md "core/ ... no dependence on the scene tree"). Decides what a bot does with a held
## special (spec 1.6, 1.8): place it, or throw it at a target. `plan_v2` reads the world snapshot and
## chain graph; gated by the tier's `uses_defensive_specials` / `uses_offensive_specials` flags.
## `BotSpecialAction.place_target` / `has_place_target` carry a placed special's intended disk-local
## point; `throw_origin` / `throw_velocity` are set only on a genuine `should_throw` action (Bomb).

class BotSpecialAction:
	var should_throw: bool = false
	## Disk-local release point, inside own territory. Only meaningful when
	## should_throw is true.
	var throw_origin: Vector2 = Vector2.ZERO
	## World-space; caller still clamps via request_throw().
	var throw_velocity: Vector3 = Vector3.ZERO
	## Fall back to an ordinary placement candidate.
	var should_place_ordinarily: bool = true
	## True when a placed-special heuristic (Rocket/Volcano/tilt/Jumping Bean/...)
	## recorded an intended disk-local target in `place_target` below -- never
	## true at the same time as `should_throw`.
	var has_place_target: bool = false
	## Disk-local intended placement target, set only when has_place_target.
	var place_target: Vector2 = Vector2.ZERO


## Bot V2 (docs/BOT_AI_REDESIGN.md 2.3 step 7): the per-type effect
## contract (spec 1.6: Rocket does not home, Propeller does not blow sideways,
## Bomb is the only thrown one), but targets read the chain graph instead of enemy circle
## centres. Offensive area specials aim at the enemy circle whose removal costs its team the
## most (BotChains.downstream: a joint or tower base); Paintball at the tallest enemy
## stack; Freeze/Glue at the own goal-covering or most threatened tower; Stackfall at the
## own tip; tilt specials take the farthest own site. A tier with both special flags false
## (Easy) never uses one; offensive types also need uses_offensive_specials. `own_points`
## are the disk-local own-territory sites a placement can really land on (V2 candidates);
## `place_target` snaps to the nearest one. No target in range -> a default
## action (spend it like an ordinary block).
static func plan_v2(
	special_id: StringName,
	view: BotWorldView,
	chains: BotChains,
	profile: BotDifficultyProfile,
	tuning: BotTuning,
	own_points: PackedVector2Array = PackedVector2Array(),
	throw_range_m: float = 0.0,
	black_hole_pull_radius_m: float = 0.0,
	effect_radius_m: float = 0.0
) -> BotSpecialAction:
	var offensive: bool = profile != null and profile.uses_offensive_specials
	var defensive: bool = profile != null and profile.uses_defensive_specials
	if view == null or chains == null or tuning == null or (not offensive and not defensive):
		return BotSpecialAction.new()
	match special_id:
		&"bomb":
			if not offensive:
				return BotSpecialAction.new()
			return _v2_bomb(view, chains, tuning, own_points, throw_range_m)
		&"rocket", &"volcano", &"jumping_bean":
			if not offensive:
				return BotSpecialAction.new()
			var joint: int = _v2_best_joint(view, chains, tuning, tuning.special_v2_reach_m, -1.0)
			return _v2_place_at(view, joint, own_points, _v2_max_offset(tuning, effect_radius_m))
		&"black_hole":
			if not offensive or black_hole_pull_radius_m <= 0.0:
				return BotSpecialAction.new()
			var hole_joint: int = _v2_best_joint(
				view, chains, tuning, tuning.special_v2_reach_m, black_hole_pull_radius_m
			)
			return _v2_place_at(view, hole_joint, own_points, _v2_max_offset(tuning, black_hole_pull_radius_m))
		&"paintball":
			if not offensive:
				return BotSpecialAction.new()
			return _v2_place_at(
				view, _v2_tallest_enemy(view, chains, tuning), own_points, _v2_max_offset(tuning, effect_radius_m)
			)
		&"freeze", &"glue":
			if not defensive:
				return BotSpecialAction.new()
			return _v2_place_at(view, _v2_defended_tower(view, chains, tuning), own_points)
		&"stackfall":
			return _v2_place_at(view, _v2_own_tip(view, chains), own_points)
		&"earthquake", &"anvil", &"propeller":
			return _plan_tilt(view.own_home, own_points)
		_:
			return BotSpecialAction.new()


## Bomb: thrown at the best enemy joint; default action when none qualifies or no own
## release point lands within `special_v2_throw_tolerance_m` of the host's fixed throw range.
static func _v2_bomb(
	view: BotWorldView, chains: BotChains, tuning: BotTuning, own_points: PackedVector2Array, throw_range_m: float
) -> BotSpecialAction:
	var action: BotSpecialAction = BotSpecialAction.new()
	var ranged: bool = throw_range_m > 0.0 and not own_points.is_empty()
	var reach: float = INF if ranged else tuning.special_v2_reach_m
	var joint: int = _v2_best_joint(view, chains, tuning, reach, -1.0)
	if joint < 0:
		return action
	var target: Vector2 = Vector2(view.cx[joint], view.cz[joint])
	var origin: Vector2 = _nearest(own_points, target, view.own_home)
	if ranged:
		var best_error: float = INF
		for point: Vector2 in own_points:
			var error: float = absf(point.distance_to(target) - throw_range_m)
			if error < best_error:
				best_error = error
				origin = point
		if best_error > tuning.special_v2_throw_tolerance_m:
			return action
	var velocity: Vector3 = _ballistic_velocity(origin, target, tuning)
	if velocity == Vector3.ZERO or not velocity.is_finite():
		return action
	action.should_throw = true
	action.throw_origin = origin
	action.throw_velocity = velocity
	action.should_place_ordinarily = false
	return action


## Placement action aimed at circle `index` (default action when index < 0).
static func _v2_place_at(
	view: BotWorldView, index: int, own_points: PackedVector2Array, max_offset_m: float = INF
) -> BotSpecialAction:
	var action: BotSpecialAction = BotSpecialAction.new()
	if index < 0 or index >= view.circle_count():
		return action
	var target: Vector2 = Vector2(view.cx[index], view.cz[index])
	var snapped: Vector2 = _nearest(own_points, target, target)
	if snapped.distance_to(target) > max_offset_m:
		return action
	action.place_target = snapped
	action.has_place_target = true
	action.should_place_ordinarily = true
	return action


## Farthest a placed special may land from its target: its effect radius plus
## `special_v2_effect_margin_m` (INF = uncapped when the caller supplies no radius).
static func _v2_max_offset(tuning: BotTuning, effect_radius_m: float) -> float:
	if effect_radius_m <= 0.0:
		return INF
	return effect_radius_m + tuning.special_v2_effect_margin_m


## The in-reach enemy circle with the highest BotChains.downstream (plus a small height
## tiebreak); -1 when none reaches `special_v2_min_downstream`. With `pull_radius_m` > 0 the
## score also loses `black_hole_own_penalty` per own circle that radius would drag in and
## must stay at or above `black_hole_min_net_score`.
static func _v2_best_joint(
	view: BotWorldView, chains: BotChains, tuning: BotTuning, reach_m: float, pull_radius_m: float
) -> int:
	var best: int = -1
	var best_score: float = -INF
	for i: int in range(view.circle_count()):
		if view.cteam[i] == view.team_id or not chains.connected(i):
			continue
		var centre: Vector2 = Vector2(view.cx[i], view.cz[i])
		if chains.gap_to(view.team_id, centre) > reach_m:
			continue
		var downstream: int = chains.downstream(i)
		if downstream < tuning.special_v2_min_downstream:
			continue
		var score: float = float(downstream)
		if pull_radius_m > 0.0:
			score -= tuning.black_hole_own_penalty * float(_v2_own_within(view, centre, pull_radius_m))
			if score < tuning.black_hole_min_net_score:
				continue
		score += tuning.special_v2_height_tiebreak * view.top_height(i)
		if score > best_score:
			best_score = score
			best = i
	return best


## The in-reach enemy circle with the tallest top (Paintball converts a stack); -1 below
## `special_v2_paintball_min_height_m`.
static func _v2_tallest_enemy(view: BotWorldView, chains: BotChains, tuning: BotTuning) -> int:
	var best: int = -1
	var best_height: float = tuning.special_v2_paintball_min_height_m
	for i: int in range(view.circle_count()):
		if view.cteam[i] == view.team_id or not chains.connected(i):
			continue
		if chains.gap_to(view.team_id, Vector2(view.cx[i], view.cz[i])) > tuning.special_v2_reach_m:
			continue
		var height: float = view.top_height(i)
		if height >= best_height:
			best_height = height
			best = i
	return best


## The own tower Freeze/Glue should protect: the tallest own circle covering a goal; else the
## own circle with the highest downstream that has an enemy circle within
## `special_v2_threat_gap_m` (edge to edge); -1 when neither exists.
static func _v2_defended_tower(view: BotWorldView, chains: BotChains, tuning: BotTuning) -> int:
	var covering: int = -1
	var covering_height: float = -1.0
	var threatened: int = -1
	var threatened_score: float = -INF
	for i: int in range(view.circle_count()):
		if view.cteam[i] != view.team_id or not chains.connected(i):
			continue
		var centre: Vector2 = Vector2(view.cx[i], view.cz[i])
		for goal: Vector2 in view.goals:
			if goal.distance_to(centre) <= view.cr[i] and view.top_height(i) > covering_height:
				covering_height = view.top_height(i)
				covering = i
		if _v2_enemy_edge_gap(view, centre, view.cr[i]) <= tuning.special_v2_threat_gap_m:
			var score: float = float(chains.downstream(i)) + tuning.special_v2_height_tiebreak * view.top_height(i)
			if score > threatened_score:
				threatened_score = score
				threatened = i
	return covering if covering >= 0 else threatened


## The own connected circle closest to a goal (farthest from home when the map has none): the
## tip Stackfall rains around; -1 when the team has no block circle.
static func _v2_own_tip(view: BotWorldView, chains: BotChains) -> int:
	var best: int = -1
	var best_key: float = INF
	for i: int in range(view.circle_count()):
		if view.cteam[i] != view.team_id or not chains.connected(i):
			continue
		var centre: Vector2 = Vector2(view.cx[i], view.cz[i])
		var key: float = -centre.distance_to(view.own_home)
		if not view.goals.is_empty():
			key = INF
			for goal: Vector2 in view.goals:
				key = minf(key, goal.distance_to(centre))
		if key < best_key:
			best_key = key
			best = i
	return best


static func _v2_own_within(view: BotWorldView, centre: Vector2, radius_m: float) -> int:
	var count: int = 0
	for i: int in range(view.circle_count()):
		if view.cteam[i] == view.team_id and centre.distance_to(Vector2(view.cx[i], view.cz[i])) <= radius_m:
			count += 1
	return count


## Smallest edge-to-edge distance from a circle (centre, radius) to any enemy circle or home.
static func _v2_enemy_edge_gap(view: BotWorldView, centre: Vector2, radius_m: float) -> float:
	var best: float = INF
	for i: int in range(view.circle_count()):
		if view.cteam[i] != view.team_id:
			best = minf(best, centre.distance_to(Vector2(view.cx[i], view.cz[i])) - radius_m - view.cr[i])
	for home: Vector2 in view.enemy_homes:
		best = minf(best, centre.distance_to(home) - radius_m - view.territory_tuning.home_radius)
	return best


## Earthquake/Anvil/Propeller (self-triggering tilt effects): placed near the
## disk edge farthest from the bot's own home, for the biggest lever arm on
## the tilt -- approximated, with no field-radius/raster access at this layer,
## as the bot's own territory sample point farthest from `own_home_position`
## (the caller already only reaches this branch when at least one of
## `uses_defensive_specials`/`uses_offensive_specials` is true; see the
## both-false gate in `plan_v2()`).
static func _plan_tilt(
	own_home_position: Vector2,
	own_territory_sample_points: PackedVector2Array
) -> BotSpecialAction:
	var action: BotSpecialAction = BotSpecialAction.new()
	action.place_target = _farthest(own_territory_sample_points, own_home_position, own_home_position)
	action.has_place_target = true
	action.should_place_ordinarily = true
	return action


## A simple, non-time-of-flight-solved launch estimate (spec 1.8 does not
## demand an exact ballistic solve; the deep-dive is `MatchPlacement.
## request_throw()`'s own clamp/validate, the real safety net): aim the
## horizontal component straight at `target`, add a fixed vertical lift ratio
## (`tuning.special_throw_loft_ratio`, the bot's own analogue of
## `SpecialTuning.throw_loft_ratio` -- this planner is never handed a
## `SpecialTuning` instance), then normalise to `tuning.
## special_throw_speed_mps`. Returns `Vector3.ZERO` only when `origin` and
## `target` coincide (no direction to aim) -- callers must treat that as "do
## not throw", never divide by the resulting zero length.
static func _ballistic_velocity(origin: Vector2, target: Vector2, tuning: BotTuning) -> Vector3:
	var delta: Vector2 = target - origin
	var horizontal_dist: float = delta.length()
	if horizontal_dist <= 0.0001:
		return Vector3.ZERO
	var horizontal_dir: Vector2 = delta / horizontal_dist
	var raw: Vector3 = Vector3(horizontal_dir.x, tuning.special_throw_loft_ratio, horizontal_dir.y)
	return raw.normalized() * tuning.special_throw_speed_mps


## Nearest of `centers`/`points` to `target`; `fallback` (never NaN) when the
## array is empty.
static func _nearest(points: PackedVector2Array, target: Vector2, fallback: Vector2) -> Vector2:
	if points.is_empty():
		return fallback
	var best: Vector2 = points[0]
	var best_dist_sq: float = best.distance_squared_to(target)
	for i: int in range(1, points.size()):
		var dist_sq: float = points[i].distance_squared_to(target)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best = points[i]
	return best


## Farthest of `points` from `from`; `fallback` (never NaN) when the array is
## empty.
static func _farthest(points: PackedVector2Array, from: Vector2, fallback: Vector2) -> Vector2:
	if points.is_empty():
		return fallback
	var best: Vector2 = points[0]
	var best_dist_sq: float = best.distance_squared_to(from)
	for i: int in range(1, points.size()):
		var dist_sq: float = points[i].distance_squared_to(from)
		if dist_sq > best_dist_sq:
			best_dist_sq = dist_sq
			best = points[i]
	return best
