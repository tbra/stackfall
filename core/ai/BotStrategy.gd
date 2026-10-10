class_name BotStrategy
extends RefCounted
## Bot V2 strategy layer (docs/BOT_AI_REDESIGN.md 2.3 step 3, Bontago-1t5.23): picks the
## BotIntent for one piece from a BotWorldView and its BotChains. First match wins:
##   HOLD    every goal / beacon is already own: raise the covering stack, strike a
##           threatening enemy circle (focus_circle)
##   DEFEND  an own key (home in Elimination, goal-covering stack, circle carrying
##           >= defend_downstream_min) is inside an enemy circle's reach + allowance
##   STRIKE  an enemy circle carrying >= strike_downstream_min (or covering a goal)
##           whose base one placement can cover
##   FINISH  the gap to the target <= finish_gap_m: build the tower at the zone edge
##   ANCHOR  the tip stack is low and an enemy circle contests it, or every Nth piece
##   default RACE; mode adapters replace it: Elimination SIEGE on a per-seat target home,
##           Domination AREA, Reach the Sky ANCHOR on the own tallest stack, CTF RACE
##           to the unheld beacons. Classic with several goals targets the goal the mode
##           context names (else the unheld goal with the smallest gap).
## Intents the tier's BotDifficultyProfile.intent_mask disables are skipped; RACE is
## always available. No scene tree, no rng. Stickiness: `memory` (a per-seat Dictionary the
## caller keeps between pieces) holds the last soft intent (RACE / ANCHOR) and its age in own
## placements; the other soft kind cannot replace it for `intent_min_hold_pieces` placements, so
## contest and rhythm anchors do not flip-flop with RACE. Every other intent (HOLD, DEFEND,
## STRIKE, FINISH, SIEGE, AREA) pre-empts at once. A repeated think without a placement (WAIT)
## ages nothing, so the rhythm does not repeat on its own.

const SHIPPED_TUNING: BotStrategyTuning = preload("res://config/bot_strategy_tuning.tres")
## Threat priorities (a higher one wins before downstream counts are compared).
const PRIORITY_KEY: float = 1000.0
const PRIORITY_GOAL: float = 2000.0
const PRIORITY_HOME: float = 3000.0
const NONE: int = -1


## The intent for the held piece. `tuning` defaults to the shipped resource.
static func choose(
	view: BotWorldView, chains: BotChains, profile: BotDifficultyProfile, tuning: BotStrategyTuning = null,
	memory: Dictionary = {}
) -> BotIntent:
	var t: BotStrategyTuning = tuning if tuning != null else SHIPPED_TUNING
	var mask: int = profile.intent_mask
	var spread: bool = BotIntent.is_enabled(mask, BotIntent.Kind.STRIKE)
	var plan: Dictionary = _mode_plan(view, chains, t, spread)
	var target: Vector2 = plan["target"] as Vector2
	var has_target: bool = plan["has_target"] as bool
	var allowance: float = t.threat_allowance_m + profile.threat_lookahead_m
	if plan["hold"] as bool and BotIntent.is_enabled(mask, BotIntent.Kind.HOLD):
		var hold: BotIntent = _make(t, BotIntent.Kind.HOLD, target)
		hold.focus_circle = _goal_threat(view, chains, target, allowance)
		return hold
	if BotIntent.is_enabled(mask, BotIntent.Kind.DEFEND):
		var threat: int = _find_threat(view, chains, t, allowance)
		if threat != NONE:
			return _focused(view, t, BotIntent.Kind.DEFEND, threat)
	if BotIntent.is_enabled(mask, BotIntent.Kind.STRIKE):
		var strike: int = _find_strike(view, chains, t)
		if strike != NONE:
			return _focused(view, t, BotIntent.Kind.STRIKE, strike)
	if (
		BotIntent.is_enabled(mask, BotIntent.Kind.FINISH)
		and plan["finishable"] as bool
		and has_target
		and chains.gap_to(view.team_id, target) <= t.finish_gap_m
	):
		return _make(t, BotIntent.Kind.FINISH, target)
	var default_kind: BotIntent.Kind = plan["default"] as BotIntent.Kind
	if not BotIntent.is_enabled(mask, default_kind):
		default_kind = BotIntent.Kind.RACE
	var base: BotIntent = _make(t, default_kind, target)
	if default_kind == BotIntent.Kind.ANCHOR or not BotIntent.is_enabled(mask, BotIntent.Kind.ANCHOR):
		return base
	var anchor: int = _anchor_circle(view, chains, t, mask, target, has_target)
	var fresh: BotIntent = base
	if anchor != NONE:
		fresh = _make(t, BotIntent.Kind.ANCHOR, Vector2(view.cx[anchor], view.cz[anchor]))
	return _sticky(view, t, memory, fresh, base)


## Applies the base/ANCHOR hold to `fresh` (see the class doc) and records the outcome. `base` is
## the mode's default intent (RACE, SIEGE or AREA) for this piece.
static func _sticky(
	view: BotWorldView, t: BotStrategyTuning, memory: Dictionary, fresh: BotIntent, base: BotIntent
) -> BotIntent:
	var own_count: int = view.indices_of_team(view.team_id).size()
	if memory.is_empty() or own_count == 0:
		memory["kind"] = int(fresh.kind)
		memory["own"] = own_count
		memory["age"] = 0
		memory["anchor_target"] = fresh.target
		return fresh
	if int(memory["own"]) != own_count:
		memory["age"] = int(memory["age"]) + 1
		memory["own"] = own_count
	var held_anchor: bool = int(memory["kind"]) == int(BotIntent.Kind.ANCHOR)
	var fresh_anchor: bool = fresh.kind == BotIntent.Kind.ANCHOR
	var result: BotIntent = fresh
	if held_anchor != fresh_anchor:
		if int(memory["age"]) < t.intent_min_hold_pieces:
			result = _make(t, BotIntent.Kind.ANCHOR, memory["anchor_target"] as Vector2) if held_anchor else base
		else:
			memory["kind"] = int(fresh.kind)
			memory["age"] = 0
	if result.kind == BotIntent.Kind.ANCHOR:
		memory["kind"] = int(BotIntent.Kind.ANCHOR)
		memory["anchor_target"] = result.target
	else:
		memory["kind"] = int(result.kind)
	return result


static func _make(t: BotStrategyTuning, kind: BotIntent.Kind, target: Vector2) -> BotIntent:
	var intent: BotIntent = BotIntent.new()
	intent.kind = kind
	intent.target = target
	intent.weights = t.weights_for(kind).duplicate()
	intent.weights.resize(BotIntent.Term.size())
	return intent


## An intent aimed at enemy circle `focus` (its centre is the target).
static func _focused(view: BotWorldView, t: BotStrategyTuning, kind: BotIntent.Kind, focus: int) -> BotIntent:
	var intent: BotIntent = _make(t, kind, Vector2(view.cx[focus], view.cz[focus]))
	intent.focus_circle = focus
	return intent


## Per-mode plan: {target, has_target, hold, finishable, default (BotIntent.Kind)}.
static func _mode_plan(view: BotWorldView, chains: BotChains, t: BotStrategyTuning, spread: bool) -> Dictionary:
	var plan: Dictionary = {
		"target": view.own_home, "has_target": view.has_home, "hold": false,
		"finishable": false, "default": BotIntent.Kind.RACE,
	}
	match view.mode:
		MatchConfig.GameMode.ELIMINATION:
			var home: int = _elimination_target(view, t, spread)
			if home != NONE:
				plan["target"] = view.enemy_homes[home]
				plan["has_target"] = true
				plan["finishable"] = true
			plan["default"] = BotIntent.Kind.SIEGE
		MatchConfig.GameMode.DOMINATION:
			plan["target"] = _area_target(view)
			plan["has_target"] = true
			plan["default"] = BotIntent.Kind.AREA
		MatchConfig.GameMode.REACH_THE_SKY:
			var goal: BotModeGoal = view.mode_goal
			if goal != null and goal.has_tower:
				plan["target"] = goal.tower_origin
				plan["has_target"] = true
			plan["default"] = BotIntent.Kind.ANCHOR
		MatchConfig.GameMode.CAPTURE_THE_FLAG:
			_plan_beacons(view, chains, plan)
		_:
			_plan_goals(view, chains, plan)
	return plan


## Classic: the unheld goal to race to (the mode context's target for several goals, else the
## smallest gap); HOLD once every goal is own.
static func _plan_goals(view: BotWorldView, chains: BotChains, plan: Dictionary) -> void:
	if view.goals.is_empty():
		return
	var held: Array[bool] = []
	for goal: Vector2 in view.goals:
		held.append(_holder(view, goal) == view.team_id)
	var pick: int = NONE
	var goal_context: BotModeGoal = view.mode_goal
	if goal_context != null and goal_context.is_multi_goal():
		var named: int = goal_context.target_goal_index
		if named >= 0 and named < view.goals.size() and not held[named]:
			pick = named
	if pick == NONE:
		pick = _closest_unheld(view.goals, held, chains, view.team_id)
	plan["has_target"] = true
	plan["finishable"] = true
	if pick == NONE:
		plan["hold"] = true
		plan["target"] = view.goals[0]
		plan["finishable"] = false
	else:
		plan["target"] = view.goals[pick]


## Capture the Flag: RACE to the nearest unheld beacon, HOLD once all are own.
static func _plan_beacons(view: BotWorldView, chains: BotChains, plan: Dictionary) -> void:
	var goal: BotModeGoal = view.mode_goal
	if goal == null or goal.beacon_positions.is_empty():
		return
	var held: Array[bool] = []
	for i: int in range(goal.beacon_positions.size()):
		held.append(i < goal.beacon_held_by_own.size() and goal.beacon_held_by_own[i])
	var pick: int = _closest_unheld(goal.beacon_positions, held, chains, view.team_id)
	plan["has_target"] = true
	if pick == NONE:
		plan["hold"] = true
		plan["target"] = goal.beacon_positions[0]
	else:
		plan["target"] = goal.beacon_positions[pick]


static func _closest_unheld(points: PackedVector2Array, held: Array[bool], chains: BotChains, team: int) -> int:
	var best: int = NONE
	var best_gap: float = INF
	for i: int in range(points.size()):
		if held[i]:
			continue
		var gap: float = chains.gap_to(team, points[i])
		if best == NONE or gap < best_gap:
			best = i
			best_gap = gap
	return best


## Elimination target home for this seat: the nearest enemy home; homes within
## elim_tie_epsilon_m tie to the smallest clockwise angle step around the field centre.
## DECISION: "clockwise" is increasing polar angle in disk-local x/z; the exact sense does
## not matter, only that every seat of a ring uses the same one, so eight bots on equidistant
## seats pick eight distinct homes. Hard only (`spread`, the tier with STRIKE, spec 2.6);
## lower tiers take the plainly nearest home (first index on a tie). NONE when no enemy home lives.
static func _elimination_target(view: BotWorldView, t: BotStrategyTuning, spread: bool) -> int:
	var origin: Vector2 = view.own_home if view.has_home else Vector2.ZERO
	var nearest: float = INF
	for home: Vector2 in view.enemy_homes:
		nearest = minf(nearest, origin.distance_to(home))
	var best: int = NONE
	var best_step: float = INF
	for i: int in range(view.enemy_homes.size()):
		if origin.distance_to(view.enemy_homes[i]) > nearest + (t.elim_tie_epsilon_m if spread else 0.0):
			continue
		var step: float = wrapf(view.enemy_homes[i].angle() - origin.angle(), 0.0, TAU) if spread else 0.0
		if best == NONE or step < best_step:
			best = i
			best_step = step
	return best


## Domination: grow towards the leading team's land when someone else leads, else the field centre.
static func _area_target(view: BotWorldView) -> Vector2:
	var goal: BotModeGoal = view.mode_goal
	if goal == null or goal.own_team_leads or goal.leader_points.is_empty():
		return Vector2.ZERO
	var origin: Vector2 = view.own_home if view.has_home else Vector2.ZERO
	var best: Vector2 = goal.leader_points[0]
	for point: Vector2 in goal.leader_points:
		if origin.distance_squared_to(point) < origin.distance_squared_to(best):
			best = point
	return best


## Team holding the raster cell at `point` (-1 unowned, contested, hole, off-grid).
static func _holder(view: BotWorldView, point: Vector2) -> int:
	if view.raster == null or view.grid == null:
		return NONE
	var cell: Vector2i = view.grid.world_to_cell(point)
	return view.raster.team_at(cell.x, cell.y)


## Enemy circle (home-connected) whose reach plus allowance covers `point`, nearest first; NONE.
static func _goal_threat(view: BotWorldView, chains: BotChains, point: Vector2, allowance: float) -> int:
	var best: int = NONE
	var best_gap: float = INF
	for j: int in range(view.circle_count()):
		if view.cteam[j] == view.team_id or not chains.connected(j):
			continue
		var gap: float = Vector2(view.cx[j], view.cz[j]).distance_to(point) - view.cr[j] - allowance
		if gap <= 0.0 and gap < best_gap:
			best = j
			best_gap = gap
	return best


## The enemy circle most worth answering: it reaches (radius + allowance) the own home
## (Elimination), a goal-covering own stack, or an own circle carrying >= defend_downstream_min.
## NONE when nothing is threatened.
static func _find_threat(
	view: BotWorldView, chains: BotChains, t: BotStrategyTuning, allowance: float
) -> int:
	var own: PackedInt32Array = PackedInt32Array()
	for i: int in view.indices_of_team(view.team_id):
		if chains.connected(i):
			own.append(i)
	var best_focus: int = NONE
	var best_value: float = -INF
	for j: int in range(view.circle_count()):
		if view.cteam[j] == view.team_id or not chains.connected(j):
			continue
		var enemy: Vector2 = Vector2(view.cx[j], view.cz[j])
		var reach: float = view.cr[j] + allowance
		var value: float = -INF
		if view.mode == MatchConfig.GameMode.ELIMINATION and view.has_home and enemy.distance_to(view.own_home) <= reach:
			value = PRIORITY_HOME
		for i: int in own:
			var centre: Vector2 = Vector2(view.cx[i], view.cz[i])
			if enemy.distance_to(centre) > reach:
				continue
			var worth: float = float(chains.downstream(i))
			if _covers_goal(view, centre, view.cr[i]):
				value = maxf(value, PRIORITY_GOAL + worth)
			elif chains.downstream(i) >= t.defend_downstream_min:
				value = maxf(value, PRIORITY_KEY + worth)
		if value > best_value:
			best_value = value
			best_focus = j
	return best_focus


static func _covers_goal(view: BotWorldView, centre: Vector2, radius: float) -> bool:
	for goal: Vector2 in view.goals:
		if centre.distance_to(goal) <= radius:
			return true
	return false


## The best enemy circle to cut: carries >= strike_downstream_min (plus a bonus when its reach
## covers a goal), not already under own cover, with its base within strike_reach_m of the own
## land's edge. NONE when there is none.
static func _find_strike(view: BotWorldView, chains: BotChains, t: BotStrategyTuning) -> int:
	var best: int = NONE
	var best_value: float = -INF
	for j: int in range(view.circle_count()):
		if view.cteam[j] == view.team_id or not chains.connected(j):
			continue
		var centre: Vector2 = Vector2(view.cx[j], view.cz[j])
		var value: float = float(chains.downstream(j))
		if _covers_goal(view, centre, view.cr[j]):
			value += t.strike_goal_bonus
		if value < float(t.strike_downstream_min):
			continue
		var gap: float = chains.gap_to(view.team_id, centre)
		if gap <= 0.0 or gap > t.strike_reach_m:
			continue
		if value > best_value:
			best_value = value
			best = j
	return best


## The tip circle to anchor on when the rhythm or the contest rule calls for a tower, else NONE.
## The contest rule needs DEFEND enabled (DECISION: Easy anchors on its fixed rhythm only,
## the reactive tiers also when an enemy circle contests a low tip).
static func _anchor_circle(
	view: BotWorldView, chains: BotChains, t: BotStrategyTuning, mask: int, target: Vector2, has_target: bool
) -> int:
	if not has_target:
		return NONE
	var tip: int = _tip_circle(view, chains, target)
	if tip == NONE:
		return NONE
	var own_count: int = view.indices_of_team(view.team_id).size()
	if t.anchor_rhythm > 0 and own_count % t.anchor_rhythm == 0:
		return tip
	if not BotIntent.is_enabled(mask, BotIntent.Kind.DEFEND) or view.top_height(tip) >= t.anchor_min_height_m:
		return NONE
	var tip_centre: Vector2 = Vector2(view.cx[tip], view.cz[tip])
	for j: int in range(view.circle_count()):
		if view.cteam[j] == view.team_id or not chains.connected(j):
			continue
		var edge_gap: float = tip_centre.distance_to(Vector2(view.cx[j], view.cz[j])) - view.cr[tip] - view.cr[j]
		if edge_gap <= t.contest_lookahead_m:
			return tip
	return NONE


## The own home-connected circle with the smallest gap to `target` (the frontier tip); NONE
## when the team has none.
static func _tip_circle(view: BotWorldView, chains: BotChains, target: Vector2) -> int:
	var best: int = NONE
	var best_gap: float = INF
	for i: int in view.indices_of_team(view.team_id):
		if not chains.connected(i):
			continue
		var gap: float = Vector2(view.cx[i], view.cz[i]).distance_to(target) - view.cr[i]
		if gap < best_gap:
			best_gap = gap
			best = i
	return best
