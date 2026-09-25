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
var _win_checker: WinChecker = null
var _last_groups: TerritoryGroups = null
var _solve_accum: float = 0.0

## Bontago-cmc.5: goal no-build discs, cached at _build_territory() (goal
## flags never move) so _run_territory_step() does not rebuild them every
## solve, and so net/MatchNet.gd's replicate_territory() can ship the exact
## same list a client's overlay draws. Parallel arrays: goal_radii is
## currently uniform (TerritoryTuning.goal_zone_radius) but kept per-goal
## because core/net/CircleWire.gd's wire format is already per-goal.
var _goal_positions: PackedVector2Array = PackedVector2Array()
var _goal_radii: PackedFloat32Array = PackedFloat32Array()

## The analytic circle list the last _run_territory_step() built for
## game/TerritoryOverlay.gd (see _update_circle_render()), cached so
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
	return _win_checker.winner() if _win_checker != null else WinChecker.NO_TEAM


func _build_territory() -> void:
	var map_def: MapDef = _match.config.map_def()
	_cell_grid = CellGrid.new(map_def.field_radius, map_def.cell_size, map_def.shape_test())
	_raster = TerritoryRaster.new(_cell_grid, _match._territory_tuning)
	_raster.reset()
	_solver = TerritorySolver.new(_match._territory_tuning)
	var goal_positions: PackedVector2Array = PlayerSlot.goal_positions_for(_match.config.goal_flag_count, map_def)
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
	_win_checker = WinChecker.new(goal_positions, _match._territory_tuning.capture_hold)
	_last_groups = null
	_solve_accum = 0.0

	# Bontago-cmc.5: the same goal list, cached for the analytic shader and
	# the replicated circle wire (see the class-level DECISION on
	# _goal_positions above).
	_goal_positions = goal_positions
	_goal_radii = PackedFloat32Array()
	_goal_radii.resize(goal_positions.size())
	_goal_radii.fill(_match._territory_tuning.goal_zone_radius)


func _tick_territory(delta: float) -> void:
	# Spec 3.4 / docs/M3a_PLAN.md, "Clients never solve territory": on a
	# client every body is frozen, so the settled rule would call the whole
	# field settled instantly and the solve would invent a territory that
	# disagrees with the host's. The mirror raster arrives over the wire
	# instead (see apply_replicated_territory).
	if not _match._is_host():
		return
	if _raster == null or _solver == null:
		return
	_solve_accum += delta
	var step: float = 1.0 / maxf(_match._territory_tuning.solve_hz, 0.001)
	while _solve_accum >= step:
		_solve_accum -= step
		_run_territory_step(step)


func _run_territory_step(delta: float) -> void:
	var circles: Array[InfluenceCircle] = _collect_circles()
	var groups: TerritoryGroups = _solver.solve(circles)
	_last_groups = groups
	var holes_enabled: bool = _match.config.hole_mode != MatchConfig.HoleMode.OFF
	var permanent_holes: bool = _match.config.hole_mode == MatchConfig.HoleMode.PERMANENT
	_raster.update(circles, groups, delta, holes_enabled, permanent_holes)
	_win_checker.update(_raster, delta)
	_update_circle_render(circles, groups)

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
	if holes_enabled:
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

	Events.goal_capture_progress.emit(_win_checker.capturing_team(), _win_checker.capture_progress())

	if _match.state() == MatchAutoload.State.PLAYING and _win_checker.winner() != WinChecker.NO_TEAM:
		_match._lifecycle._finish_match(_win_checker.winner())


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
func _update_circle_render(circles: Array[InfluenceCircle], groups: TerritoryGroups) -> void:
	var entries: Array = []
	for group: int in range(groups.group_count()):
		var team: int = groups.team_of(group)
		for circle_index: int in groups.circles_of(group):
			var circle: InfluenceCircle = circles[circle_index]
			entries.append([team, circle.radius, circle.center.x, circle.center.y])
	entries.sort_custom(
		func(a: Array, b: Array) -> bool:
			if a[0] != b[0]:
				return a[0] < b[0]
			return a[1] > b[1]
	)

	var count: int = entries.size()
	var xs: PackedFloat32Array = PackedFloat32Array()
	var zs: PackedFloat32Array = PackedFloat32Array()
	var radii: PackedFloat32Array = PackedFloat32Array()
	var teams: PackedInt32Array = PackedInt32Array()
	xs.resize(count)
	zs.resize(count)
	radii.resize(count)
	teams.resize(count)
	for i: int in range(count):
		var entry: Array = entries[i]
		teams[i] = entry[0]
		radii[i] = entry[1]
		xs[i] = entry[2]
		zs[i] = entry[3]

	var argmax_mode: bool = _match.config.hole_mode == MatchConfig.HoleMode.OFF
	_circle_xs = xs
	_circle_zs = zs
	_circle_radii = radii
	_circle_teams = teams
	_circle_argmax_mode = argmax_mode

	if _match._field != null:
		_match._field.set_overlay_circles(xs, zs, radii, teams, _goal_positions, _goal_radii, argmax_mode)


## The analytic circle list the last _run_territory_step() built (host
## only), cached so net/MatchNet.gd's replicate_territory() can ship the
## identical list to clients rather than re-deriving it from raw circles a
## client never has (every body there is frozen). See _update_circle_render().
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
	# mirror MatchPlacement.spawn_special_projectile()'s State.PLAYING guard.
	# _finish_match() only sets State.END -- it never tears the raster down or
	# stops a SpecialEffect's physics_tick() -- so a Jumping Bean still hopping
	# after a natural win could otherwise still punch a hole here and, through
	# _check_home_flags() below, eliminate a still-alive slot (even one on the
	# already-decided winning team) after the match is already over.
	if _match.state() != MatchAutoload.State.PLAYING:
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

	if opened.size() > 0:
		Events.hole_cells_changed.emit(opened, PackedInt32Array())
		_check_home_flags(opened)
