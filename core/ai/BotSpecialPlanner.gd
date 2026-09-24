class_name BotSpecialPlanner
extends RefCounted
## Pure (CLAUDE.md "core/ ... no dependence on the scene tree"). Decides what
## a bot does with a held special (spec 2.6, 2.9) -- place it, or throw it at
## a target.
##
## docs/M5_PLAN.md P3 (Bontago-d5c.4): per-type heuristics keyed on
## `held_special_id`, gated by the acting difficulty's own
## `uses_defensive_specials`/`uses_offensive_specials` flags
## (`tuning.profile_for(difficulty)`, spec 2.9 "Difficulty:... whether the bot
## uses defensive specials"). `plan()`'s own signature and `BotSpecialAction`'s
## own field list are frozen from P1 (docs/M5_PLAN.md's dispatch brief); this
## package rewrites only the function bodies below.
##
## # DECISION (core/ai/BotSpecialPlanner.gd, Bontago-d5c.9, supersedes the
## earlier throw_origin-parking DECISION): `BotSpecialAction` now carries its
## own disk-local `place_target`/`has_place_target` pair, distinct from
## `throw_origin` (read by `game/BotController.gd._send_throw()` only when
## `should_throw` is true). Every placed-special heuristic below (Rocket,
## Volcano, Earthquake/Anvil/Propeller, Jumping Bean -- anything that sets
## `should_place_ordinarily = true` with intent) sets `has_place_target = true`
## and `place_target` to the intended disk-local point; `throw_origin` is only
## ever set on a genuine `should_throw = true` action (Bomb). This package
## still must not touch `game/BotController.gd` or `core/ai/
## BotPlacementScorer.gd` itself, so at the time this package landed
## `has_place_target`/`place_target` were inert (`_send_best_placement()`
## ignored this planner's output and used its own already-generated candidate
## list) but observable/testable at this layer and forward-compatible.
##
## UPDATE (Bontago-d5c.8, M5 P3b-ii): `game/BotController.gd._tick_acting()`
## now reads `has_place_target`/`place_target` and, when set, sends whichever
## already-generated candidate lands nearest `place_target`
## (`_send_best_placement(place_target_override)`) instead of
## `BotPlacementScorer.pick_best()`'s general-purpose scoring -- this comment-
## only edit (Bontago-d5c.10) corrects the paragraph above, which this
## package's own file ownership does not let it touch again; the code below
## is unchanged.

class BotSpecialAction:
	var should_throw: bool = false
	## Disk-local release point, inside own territory. Only meaningful when
	## should_throw is true.
	var throw_origin: Vector2 = Vector2.ZERO
	## World-space; caller still clamps via request_throw().
	var throw_velocity: Vector3 = Vector3.ZERO
	## Fall back to an ordinary placement candidate.
	var should_place_ordinarily: bool = true
	## True when a placed-special heuristic (Rocket/Volcano/tilt/Jumping Bean)
	## recorded an intended disk-local target in `place_target` below -- never
	## true at the same time as `should_throw`.
	var has_place_target: bool = false
	## Disk-local intended placement target, set only when has_place_target.
	var place_target: Vector2 = Vector2.ZERO


## Per-type heuristics (spec 2.9: "do not aim a Rocket as if it homes or a
## Propeller as if it blows sideways"; spec 2.6's own effect table). An EASY
## bot (both flags false on `tuning.profile_for(difficulty)`) never uses any
## special with intent, regardless of `held_special_id` -- the same safe
## default P1 already shipped, applied uniformly instead of per-type.
static func plan(
	held_special_id: StringName,
	own_home_position: Vector2,
	own_territory_sample_points: PackedVector2Array,
	enemy_circle_centers: PackedVector2Array,
	active_special_positions: PackedVector2Array,
	difficulty: MatchConfig.AiDifficulty,
	tuning: BotTuning
) -> BotSpecialAction:
	var profile: BotDifficultyProfile = tuning.profile_for(difficulty)
	var offensive: bool = profile != null and profile.uses_offensive_specials
	var defensive: bool = profile != null and profile.uses_defensive_specials
	if not offensive and not defensive:
		return BotSpecialAction.new()

	match held_special_id:
		&"rocket":
			# DECISION (Bontago-d5c.9): spec 2.9's difficulty axis is defensive
			# special use; offensive use (aiming/targeting a special with
			# intent, even a placed one like Rocket) is gated on the Hard
			# tier's uses_offensive_specials -- a defensive-only (NORMAL)
			# profile places a held Rocket like an ordinary block instead of
			# aiming it at a cluster.
			if not offensive:
				return BotSpecialAction.new()
			return _plan_rocket(own_home_position, own_territory_sample_points, enemy_circle_centers, tuning)
		&"bomb":
			# Same DECISION as Rocket above: throwing a Bomb at a target is
			# offensive special use, gated on uses_offensive_specials.
			if not offensive:
				return BotSpecialAction.new()
			return _plan_bomb(own_home_position, own_territory_sample_points, enemy_circle_centers, tuning)
		&"volcano":
			return _plan_volcano(
				own_home_position, own_territory_sample_points, enemy_circle_centers, offensive, defensive, tuning
			)
		&"earthquake", &"anvil", &"propeller":
			return _plan_tilt(own_home_position, own_territory_sample_points)
		&"jumping_bean":
			return _plan_jumping_bean(own_home_position, own_territory_sample_points, enemy_circle_centers, offensive)
		_:
			# Any unrecognized id (a future M8 special -- Magnet/Freeze/Glue/
			# Gravity well -- or the roster empty): never crash, spend it like
			# an ordinary block.
			return BotSpecialAction.new()


## Rocket (spec 2.6: launches upward on activation, no homing, explodes on
## fuel-out): a thrown/aimed launch would imply a homing target it doesn't
## have -- placed instead, near the densest enemy cluster, `should_throw`
## always false.
static func _plan_rocket(
	own_home_position: Vector2,
	own_territory_sample_points: PackedVector2Array,
	enemy_circle_centers: PackedVector2Array,
	tuning: BotTuning
) -> BotSpecialAction:
	var action: BotSpecialAction = BotSpecialAction.new()
	if enemy_circle_centers.is_empty():
		return action
	var cluster: Vector2 = _densest_cluster_center(enemy_circle_centers, tuning.risk_enemy_territory_radius_m)
	action.place_target = _nearest(own_territory_sample_points, cluster, own_home_position)
	action.has_place_target = true
	action.should_throw = false
	action.should_place_ordinarily = true
	return action


## Bomb/DaBomb (impact-activated, no proximity trigger by the landed code):
## thrown at the nearest/densest enemy cluster, since an impact is what
## activates it. `throw_origin` is the bot's own territory point nearest that
## cluster; `throw_velocity` is a ballistic estimate (see `_ballistic_
## velocity()`) capped by `tuning.special_throw_speed_mps` -- deliberately
## under `SpecialTuning.throw_max_speed`'s own default (25 m/s); the actual
## hard clamp still lives in `MatchPlacement.request_throw()`.
static func _plan_bomb(
	own_home_position: Vector2,
	own_territory_sample_points: PackedVector2Array,
	enemy_circle_centers: PackedVector2Array,
	tuning: BotTuning
) -> BotSpecialAction:
	var action: BotSpecialAction = BotSpecialAction.new()
	if enemy_circle_centers.is_empty():
		return action
	var cluster: Vector2 = _densest_cluster_center(enemy_circle_centers, tuning.risk_enemy_territory_radius_m)
	var origin: Vector2 = _nearest(own_territory_sample_points, cluster, own_home_position)
	var velocity: Vector3 = _ballistic_velocity(origin, cluster, tuning)
	if velocity == Vector3.ZERO or not velocity.is_finite():
		# Degenerate only when origin and cluster coincide exactly (no
		# direction to aim); fall back to spending it like an ordinary block
		# rather than throwing nowhere.
		return action
	action.should_throw = true
	action.throw_origin = origin
	action.throw_velocity = velocity
	action.should_place_ordinarily = false
	return action


## Volcano (self-erupting, no target needed, never thrown -- an eruption
## doesn't benefit from a throw's flight time): placed defensively near the
## bot's own border nearest any single enemy (a proxy for "most contested"
## without raster access at this layer -- see the file-level DECISION) when
## `uses_defensive_specials`, else offensively near the densest enemy cluster
## when `uses_offensive_specials`.
static func _plan_volcano(
	own_home_position: Vector2,
	own_territory_sample_points: PackedVector2Array,
	enemy_circle_centers: PackedVector2Array,
	offensive: bool,
	defensive: bool,
	tuning: BotTuning
) -> BotSpecialAction:
	var action: BotSpecialAction = BotSpecialAction.new()
	if enemy_circle_centers.is_empty():
		return action
	if defensive:
		var nearest_enemy: Vector2 = _nearest(enemy_circle_centers, own_home_position, own_home_position)
		action.place_target = _nearest(own_territory_sample_points, nearest_enemy, own_home_position)
		action.has_place_target = true
		action.should_place_ordinarily = true
		return action
	if offensive:
		var cluster: Vector2 = _densest_cluster_center(enemy_circle_centers, tuning.risk_enemy_territory_radius_m)
		action.place_target = _nearest(own_territory_sample_points, cluster, own_home_position)
		action.has_place_target = true
		action.should_place_ordinarily = true
		return action
	return action


## Earthquake/Anvil/Propeller (self-triggering tilt effects): placed near the
## disk edge farthest from the bot's own home, for the biggest lever arm on
## the tilt -- approximated, with no field-radius/raster access at this layer,
## as the bot's own territory sample point farthest from `own_home_position`
## (the caller already only reaches this branch when at least one of
## `uses_defensive_specials`/`uses_offensive_specials` is true; see the
## both-false EASY gate in `plan()`).
static func _plan_tilt(
	own_home_position: Vector2,
	own_territory_sample_points: PackedVector2Array
) -> BotSpecialAction:
	var action: BotSpecialAction = BotSpecialAction.new()
	action.place_target = _farthest(own_territory_sample_points, own_home_position, own_home_position)
	action.has_place_target = true
	action.should_place_ordinarily = true
	return action


## Jumping Bean (hops, punches holes -- a rules consequence, docs/
## M4_SPECIALS_PACKAGES.md "Open question 2"): placed near the bot's own
## territory edge nearest an enemy's home flag, only when
## `uses_offensive_specials` (its hop-hole threatens a home flag like a
## natural hole -- an offensive use, not a defensive one).
static func _plan_jumping_bean(
	own_home_position: Vector2,
	own_territory_sample_points: PackedVector2Array,
	enemy_circle_centers: PackedVector2Array,
	offensive: bool
) -> BotSpecialAction:
	var action: BotSpecialAction = BotSpecialAction.new()
	if not offensive or enemy_circle_centers.is_empty():
		return action
	var enemy_home: Vector2 = _nearest(enemy_circle_centers, own_home_position, own_home_position)
	action.place_target = _nearest(own_territory_sample_points, enemy_home, own_home_position)
	action.has_place_target = true
	action.should_place_ordinarily = true
	return action


## A simple, non-time-of-flight-solved launch estimate (spec 2.9 does not
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


## The entry in `centers` with the most other entries (itself included)
## within `radius` -- a plain O(n^2) density count, fine at the small n this
## planner ever sees (one point per opposing slot, spec 2.9's 2-8 players).
## Ties keep the earliest index, so the result is deterministic for a fixed
## input order (unit-testable without relying on iteration order elsewhere).
## Assumes `centers` is non-empty; every call site above already checked.
static func _densest_cluster_center(centers: PackedVector2Array, radius: float) -> Vector2:
	var radius_sq: float = radius * radius
	var best_index: int = 0
	var best_count: int = 0
	for i: int in range(centers.size()):
		var count: int = 0
		for j: int in range(centers.size()):
			if centers[i].distance_squared_to(centers[j]) <= radius_sq:
				count += 1
		if count > best_count:
			best_count = count
			best_index = i
	return centers[best_index]
