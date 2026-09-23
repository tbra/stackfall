extends Node3D
## End-to-end acceptance for the reconciled M2 rules (spec Part 4 M2's "Current
## rule acceptance", "Decisions made -- current target", and "Rule acceptance
## scenarios"): overlap holes as the default, goal-flag no-build zones in
## every mode, one-raycast point placement, the fixed placement-window cadence
## with an early-release lock, and continuous territory updates. Driven by
## script with no player and no fakes: the real Match autoload, a real Field
## with real per-cell collision, a real BlockRegistry and real Jolt physics.
## Run headless:
##   godot --headless --path . res://tests/bench/m2_acceptance.tscn
## It prints one M2_ACCEPT line per criterion and exits non-zero if any fails.
##
## **Harness note, not a rule claim.** Criteria (a)-(f) run with
## `MatchConfig.hot_seat = true`. That is a single-process scripting
## convenience -- it serializes two "concurrent" players' turns so one script
## can drive both deterministically -- not evidence about turn-taking (spec
## Part 4 M2: "the original hot-seat build was a test harness... A separate
## hot-seat/turn-based test mode must not become normal play"). Criterion (g)
## specifically needs the fixed-interval release-lock cadence, which
## `autoload/Match.gd`'s `_consume_and_refeed()` deliberately exempts hot-seat
## from (hot-seat's strict alternation already means no slot can act twice in
## a row, so there is nothing for the lock to prevent) -- so (g) runs with
## `hot_seat = false` instead, driving `Match.request_place()` directly for
## both slots the way `net/MatchNet.gd` and a real `PlayerController` would,
## with no scene-tree consumer of its own.
##
## The eight criteria, lettered as in the acceptance brief:
##   (a) both players' territory shares grow as they build.
##   (b) where two territories overlap, the contested cells become holes after
##       hole_delay, and a block dropped on a hole cell falls below the disk.
##   (c) a tower whose base is cut off loses its influence: removing a link in
##       the chain drops the owner's territory share.
##   (d) a player whose connected territory holds the goal flag's base for
##       capture_hold wins, approaching from outside the goal's no-build zone
##       and covering the flag with reach rather than by placing inside the
##       zone; a placement attempt inside the zone is refused with
##       REASON_GOAL_ZONE (scenario 4), and the win fires only after the hold.
##   (e) a deliberate release on an invalid spot is refused outright: nothing
##       spawns or is consumed, and the same still-held piece places
##       correctly right after (spec 2.5 "Held-block behaviour"/"Expiry and
##       invalid actions", Bontago-mv0.24, owner test 2026-09-22).
##   (f) a hole under a home flag eliminates that slot (owner decision 3).
##   (g) the placement cadence (spec 2.4): an early release locks the slot's
##       next piece until the interval boundary, a second release before then
##       is refused, the lock lifts at the boundary without forcing anything,
##       and an untouched piece auto-drops at expiry (Events.feed_timer_expired).
##   (h) continuous update (scenario 2): toppling a tower with no placement at
##       all drops its owner's share within a couple of solve ticks.
##
## It lives in tests/bench/ rather than tests/unit/ because it is a real-time
## scenario: the GUT suite would grow by the wall clock the physics actually
## takes. Nothing here is a benchmark -- the name is the folder's.
##
## **Why it routes the march around the goal.** SPEC.md 2.2's goal no-build
## zone (`TerritoryTuning.goal_zone_radius`) now stamps under every hole_mode,
## not just the old v2-only default, and MapDef's one-goal layout puts that
## goal at the disk centre -- exactly where a straight chain between two
## antipodal homes on a round map has to cross. Marching straight down that
## line either refuses every placement in the zone (stalling the fronts before
## they can meet, scenarios b/c/f) or, worse, could let a tall tower's reach
## cover the lone goal by accident (scenarios a/b/c, which must NOT end in a
## capture). So (a)-(c) and (f) aim their marches at a meeting point offset in
## +z from the straight home-to-home line, far enough out that neither the
## goal's no-build zone nor any front's tallest possible reach ever comes near
## the goal position -- see `_goal_avoidance_clearance()` and
## `_meeting_point()` for the derivation. (d) is the mirror image: it
## deliberately approaches along the direct line, stopping just outside the
## zone and stacking height there so the tower's *reach* -- not its physical
## position -- covers the flag base.

## Spec 2.8 lobby settings this scenario needs. The small map keeps every
## chain short enough to lay in well under a minute of wall clock each; the
## rest are defaults.
const MAP_SIZE: MapDef.MapSize = MapDef.MapSize.SMALL
const PLAYER_COUNT: int = 2
## One goal, at the disk centre (MapDef.goal_flag_positions(1) == [ZERO]), for
## every scenario. (a)-(c) and (f) route their marches around it (see the
## file header); (d) marches straight at it and stops outside its zone; (e)
## and (g) do not care where it is.
const GOAL_COUNT: int = 1
const RNG_SEED: int = 20260917

## Physics frames to hold a freshly placed block still before it counts as
## settled. PhysicsTuning.sleep_settle_time is 0.5 s; the spare frames cover
## the drop from PLACE_HEIGHT and the solve that follows.
const SETTLE_FRAMES: int = 42
## How far above the target resting spot a scripted placement's spawn point
## sits, in meters. Small enough that the block is at rest almost immediately
## (SETTLE_FRAMES covers the drop).
##
## Bontago-mv0.17 item 3 (owner feel report: "the ghost/body pivot is the
## block's middle" -- see config/blocks/BlockShape.gd's bottom_center()):
## request_place()'s `origin`/`spot.y` used to be the shape's geometric
## *centre*, so 0.55 m meant "the block's bottom sits ~0.06 m above the
## target" (0.55 minus half a cube, ~0.49 m with PhysicsTuning's default
## cube_size 1.0 / cube_margin 0.02). Now `origin` is the shape's own
## bottom-centre, so this constant *is* that release gap directly -- 0.06 m
## reproduces the exact same physical drop this harness always used,
## unchanged by the pivot move. Left at the old 0.55 this became a ~0.55 m
## fall instead of ~0.06 m, energetic enough to perturb the multi-layer
## stacking criteria (d)/(f) (extra bounce before a tall stack's next layer
## settles) without making any single-block criterion wrong outright -- a
## harness height assumption to fix, not a rule bug (see the two failures
## this replaced in the M2 acceptance log).
const PLACE_HEIGHT: float = 0.06
## Give up rather than loop forever if a march stops making progress.
const MAX_MARCH_STEPS: int = 60
## How far off the disk a passed turn releases its block, as a multiple of the
## field radius. Far enough that the footprint is empty on any map.
const OFF_DISK_FACTOR: float = 3.0
## An on-disk but un-owned release point for criterion (e), as a fraction of
## the field radius along +z -- away from both homes, which sit on the x axis,
## and far outside the lone central goal's zone.
const NEUTRAL_SPOT_FRACTION: float = 0.9
## Cubes each player stacks on the head of its chain once the two fronts meet
## (scenario b), to widen the contested band into a patch of cells.
const FRONT_STACK_HEIGHT: int = 4
## Cubes in (h)'s dedicated, isolated tower -- enough that its own reach
## (influence_base + influence_k * height) clears home_radius with a solid
## margin, so there is a cell only that tower (and not the permanent home
## circle) can be seen to own.
const TOPPLE_TOWER_LAYERS: int = 2

var _tuning: TerritoryTuning = preload("res://config/territory_tuning.tres")
var _physics: PhysicsTuning = preload("res://config/physics_tuning.tres")
var _cube: BlockShape = preload("res://config/blocks/cube.tres")

var _field: Field = null
var _blocks: Node3D = null
var _registry: BlockRegistry = null
var _failures: Array[String] = []


func _ready() -> void:
	print("M2_ACCEPT start map=%d players=%d" % [MAP_SIZE, PLAYER_COUNT])
	Match.set_process(false)

	await _scenario_growth_holes_cutoff_and_topple()
	await _scenario_home_flag_hole()
	await _scenario_capture_win()
	await _scenario_burned_block()
	await _scenario_cadence_lock()

	print("M2_ACCEPT result=%s failures=%d" % [
		"PASS" if _failures.is_empty() else "FAIL", _failures.size()
	])
	for failure: String in _failures:
		print("M2_ACCEPT failure %s" % failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


# --- Scenarios ---------------------------------------------------------------

## (a) both shares grow, (b) overlap -> contested -> holes -> a block falls
## through, (c) cutting the chain costs the owner its territory, (h) toppling
## the other chain's head (no placement at all) drops its owner's territory
## too, promptly.
func _scenario_growth_holes_cutoff_and_topple() -> void:
	await _start_match(GOAL_COUNT)

	var home_0: Vector2 = Match.slot(0).home_position
	var home_1: Vector2 = Match.slot(1).home_position

	# (h) needs a tower to topple later that was never at risk of falling
	# through (b)'s own hole: build a short, isolated stack in player 1's own
	# territory, offset in -z from its home -- the opposite side from the
	# meeting point below, which is offset in +z -- so it can never be
	# confused with, or undermined by, anything the rest of this scenario
	# does. Slot 0 passes first so slot 1 can act (hot-seat's strict
	# alternation), then hands the turn back to slot 0 for the march below.
	await _pass_turn(0)
	var topple_chain: Array[Block] = []
	var topple_base: Vector2 = await _build_isolated_tower(
		1, 0, home_1, TOPPLE_TOWER_LAYERS, topple_chain
	)

	var share_0_before: float = Match.territory_share(Match.team_of(0))
	var share_1_before: float = Match.territory_share(Match.team_of(1))

	# Both players march toward a shared meeting point offset from the straight
	# home-to-home line, so their fronts meet without ever nearing the lone
	# central goal (see the file header).
	var clearance: float = _goal_avoidance_clearance()
	var meeting: Vector2 = _meeting_point(home_0.x, clearance)
	var chain_0: Array[Block] = []
	var chain_1: Array[Block] = []
	await _march_pair(home_0, home_1, meeting, chain_0, chain_1)

	# Snapshotted now, before anything can fall through a hole: the base of
	# each chain sits exactly at the contested meeting point (see below), so
	# `chain_N[-1]` itself is exactly the block at risk of losing its own
	# floor once (b) opens a hole there. Every later position check reads
	# these plain Vector2s instead of a Block's .global_position, so a chain
	# base that later falls through its own hole can never crash a later
	# criterion (an owner-retained requirement, not a bug this test should
	# paper over: two fronts built directly on top of the exact cell where
	# their circles first met can legitimately hole out from under themselves).
	var points_0: Array[Vector2] = []
	for block: Block in chain_0:
		points_0.append(_disk_local(block.global_position))
	var points_1: Array[Vector2] = []
	for block: Block in chain_1:
		points_1.append(_disk_local(block.global_position))

	var share_0_after: float = Match.territory_share(Match.team_of(0))
	var share_1_after: float = Match.territory_share(Match.team_of(1))
	_check("a", share_0_after > share_0_before and share_1_after > share_1_before,
		"shares p0 %.4f->%.4f p1 %.4f->%.4f blocks %d/%d meeting=%s clearance=%.2f" % [
			share_0_before, share_0_after, share_1_before, share_1_after,
			chain_0.size(), chain_1.size(), meeting, clearance
		])

	# (b) The two fronts overlap, so cells in between belong to both teams.
	# Both players now build up at the front, which widens each front circle
	# (r = influence_base + influence_k * h) and so widens the contested band
	# between them into a patch of cells rather than a hairline.
	var peak_contested: Array[int] = [0]
	await _raise_fronts(chain_0, chain_1, peak_contested)
	peak_contested[0] = maxi(peak_contested[0], _contested_cell_count())

	# TerritoryRaster only opens a hole once contested_time passes hole_delay,
	# so let the solve run over that threshold before looking.
	await _step(_frames_for_seconds(_tuning.hole_delay) + _frames_for_seconds(2.0 / _tuning.solve_hz))
	var holes: PackedInt32Array = _hole_cells()
	_check("b1", peak_contested[0] > 0 and holes.size() > 0,
		"peak_contested_cells=%d hole_cells=%d after hole_delay=%.2fs" % [
			peak_contested[0], holes.size(), _tuning.hole_delay
		])

	# Field applies the hole diff through a backlog capped at
	# max_cell_toggles_per_frame, so wait for it to drain before dropping
	# anything on the hole.
	await _drain_field_backlog()
	# The two towers' own footprints (points_0/points_1's last entry) are
	# exactly where a hole is most likely, but they are occupied by real
	# blocks -- excluded so the dropped test block actually falls through open
	# ground rather than resting on (or crashing on a freed reference to) a
	# tower that is still standing, or that fell through moments earlier.
	var occupied: Array[Vector2] = [points_0[points_0.size() - 1], points_1[points_1.size() - 1]]
	var fell_through: bool = false
	if holes.size() > 0:
		fell_through = await _drop_through_hole(holes, occupied)
	_check("b2", fell_through,
		"a block dropped on a hole cell must end up below the disk surface")

	# (c) Cut the middle out of player 0's chain: everything past the cut is no
	# longer connected to the home circle, so it stops granting territory. The
	# tail point checked is the first surviving element past the cut, not the
	# chain's extreme tip: the tip is the contested meeting point itself,
	# which (b) may already have holed out on its own by now, before any cut.
	var team_0: int = Match.team_of(0)
	var share_before_cut: float = Match.territory_share(team_0)
	var cut: Dictionary = _cut_chain(chain_0)
	var removed: int = cut["removed"]
	var tail: Vector2 = points_0[cut["tail_index"]]
	var owned_before_cut: bool = _owns_point(team_0, tail)
	await _step(_frames_for_seconds(3.0 / _tuning.solve_hz))
	var share_after_cut: float = Match.territory_share(team_0)
	_check("c", (
		removed > 0
		and owned_before_cut
		and share_after_cut < share_before_cut
		and not _owns_point(team_0, tail)
	), "removed %d of %d chain blocks, share %.4f->%.4f, tail cell owned %s->%s" % [
		removed, chain_0.size(), share_before_cut, share_after_cut,
		owned_before_cut, _owns_point(team_0, tail)
	])

	# (h) Continuous update, no placement at all (SPEC.md acceptance scenario
	# 2): topple all of the isolated tower built at the very start of this
	# scenario -- untouched by anything since -- by freeing its blocks the way
	# the kill plane does, and confirm the territory solve drops player 1's
	# share and that cell's ownership within a couple of solve ticks, with no
	# request_place() call anywhere in between. The checked cell is at the
	# tower's own reach, beyond home_radius, where only the tower's own circle
	# (not the permanent home circle) can be covering it -- otherwise removing
	# the tower could never flip that cell's ownership at all.
	var team_1: int = Match.team_of(1)
	var share_before_topple: float = Match.territory_share(team_1)
	var topple_reach: float = _tuning.influence_base + _tuning.influence_k * (
		_physics.cube_size * float(TOPPLE_TOWER_LAYERS)
	)
	var topple_point: Vector2 = topple_base + Vector2(0.0, -1.0) * (topple_reach - _corner_margin())
	var owned_before_topple: bool = _owns_point(team_1, topple_point)
	var toppled: int = _topple_tail(topple_chain, topple_chain.size())
	await _step(_frames_for_seconds(2.0 / _tuning.solve_hz) + 1)
	var share_after_topple: float = Match.territory_share(team_1)
	_check("h", (
		toppled > 0
		and owned_before_topple
		and share_after_topple < share_before_topple
		and not _owns_point(team_1, topple_point)
	), "toppled %d/%d, share %.4f->%.4f, tower's own reach cell owned %s->%s (no placement in between)" % [
		toppled, topple_chain.size(), share_before_topple, share_after_topple,
		owned_before_topple, _owns_point(team_1, topple_point)
	])

	await _end_match()


## (f) A hole opening under a home flag eliminates that slot.
func _scenario_home_flag_hole() -> void:
	await _start_match(GOAL_COUNT)

	var home_0: Vector2 = Match.slot(0).home_position
	var home_1: Vector2 = Match.slot(1).home_position
	# The same clearance as (a)-(c): reusing it (rather than the smaller goal-
	# zone-only margin that would suffice for this scenario's own single-cube
	# march) keeps the detour's shape -- and so this scenario's approach
	# angle into home_1 -- identical to the run this was validated against.
	var clearance: float = _goal_avoidance_clearance()
	var meeting: Vector2 = _meeting_point(home_0.x, clearance)
	# Player 1 passes every turn, so its territory stays exactly its home
	# circle and player 0 can march all the way up to the edge of it. The
	# route detours through `meeting` first so the approach never nears the
	# lone central goal (see the file header); it rejoins the direct line to
	# home_1 well away from the centre.
	var chain: Array[Block] = []
	await _march_solo_route(0, [meeting, home_1], chain)

	# A single cube's circle stops short of the flag itself. Stacking on the
	# head of the chain grows that circle by influence_k per meter of height
	# until it swallows the home flag's cell, which is what opens the hole.
	var eliminated: bool = await _stack_until_home_flag_falls(0, chain, 1)
	_check("f", eliminated and not Match.slot(1).home_flag_alive,
		"slot 1 home_flag_alive=%s after %d chain blocks (meeting=%s)" % [
			Match.slot(1).home_flag_alive, chain.size(), meeting
		])

	await _end_match()


## (d) Holding the goal flag's base in one connected territory for
## capture_hold wins -- from outside the goal's no-build zone, covering it
## with reach rather than placing inside it (scenario 4); a placement inside
## the zone is refused with REASON_GOAL_ZONE regardless.
func _scenario_capture_win() -> void:
	await _start_match(GOAL_COUNT)

	var home_0: Vector2 = Match.slot(0).home_position
	var goal: Vector2 = Vector2.ZERO
	var team_0: int = Match.team_of(0)
	var stop_distance: float = _zone_edge_stop_distance()

	# March straight at the goal -- there is only one, so this cannot cross
	# another goal's zone -- but never closer than stop_distance, which is
	# just outside goal_zone_radius.
	var chain: Array[Block] = []
	await _march_to_distance(0, home_0, goal, stop_distance, chain)

	var reached_edge: bool = not chain.is_empty()
	var head: Vector2 = _disk_local(chain[chain.size() - 1].global_position) if reached_edge else home_0
	var edge_distance: float = head.distance_to(goal)

	# A point well inside the zone, on the same side the chain approached
	# from, must be refused for the reason the zone exists -- even though nothing
	# stops this player's territory reaching past it (scenario 4).
	_hold_cube(0)
	var inside_zone_point: Vector2 = goal + (head - goal).normalized() * (_tuning.goal_zone_radius * 0.5)
	var inside_zone_result: PlacementRules.Result = Match.preview_placement(
		0, _world_point(inside_zone_point, PLACE_HEIGHT), 0, Quaternion.IDENTITY
	)

	# Stack height on the last block outside the zone until this team's
	# uncontested reach (influence_base + influence_k * h) covers the flag
	# base -- never by moving the block itself any closer.
	var covered: bool = await _stack_until_goal_covered(0, head, goal, team_0, chain)
	var covered_before_hold: bool = Match.state() != Match.State.END

	var capture_frames: int = _frames_for_seconds(_tuning.capture_hold + 1.0)
	var won: bool = await _step_until(capture_frames, func() -> bool:
		return Match.state() == Match.State.END
	)

	_check("d", (
		reached_edge
		and edge_distance >= _tuning.goal_zone_radius
		and inside_zone_result == PlacementRules.Result.GOAL_ZONE
		and covered
		and covered_before_hold
		and won and Match.winner_team() == team_0
	), (
		"edge_distance=%.2f (zone=%.2f) inside_zone_result=%d covered=%s "
		+ "won_before_hold=%s state=%d winner=%d expected=%d chain=%d"
	) % [
		edge_distance, _tuning.goal_zone_radius, inside_zone_result, covered,
		not covered_before_hold, Match.state(), Match.winner_team(), team_0, chain.size()
	])

	await _end_match()


## (e) A deliberate (manual, non-auto_drop) release on an invalid spot is
## refused outright: nothing spawns, nothing is consumed, and the same piece
## is still there to place correctly afterward.
##
## DECISION (tests/bench/m2_acceptance.gd, Bontago-p0a): rewritten from the
## old "burns the block: it is spawned, thrown off the map, and the next
## block is fed (docs/M2_PLAN.md owner decision 2)" expectation, which
## Bontago-mv0.24 (owner test 2026-09-22) superseded for exactly this case --
## SPEC.md 2.5 "Held-block behaviour": "A drop outside the player's own
## territory is refused (the block stays in hand; no drop, feedback only)",
## and "Expiry and invalid actions": "An invalid manual click does not drop
## and does not consume the piece: the game refuses it and the block stays
## in hand... Failed clicks never advance the cadence." That change predates
## this test's own last rewrite (Bontago-cmc.6, 2026-09-21) by a day, which
## is why this scenario went stale rather than ever having been broken by
## it. autoload/match/MatchPlacement.gd's request_place() now returns before
## spawning anything at all on this path (auto_drop == false and reason !=
## REASON_OK) -- the burn/throw path this used to exercise is only reachable
## with auto_drop == true (the timer-expiry case), which criterion (g)
## already covers via its own auto-drop check.
func _scenario_burned_block() -> void:
	await _start_match(GOAL_COUNT)

	var blocks_before: int = _blocks.get_child_count()
	var tracked_before: int = _registry.tracked_block_count()
	# Force the held shape to _cube *before* snapshotting it: _release() below
	# does this too (every release forces a cube for deterministic geometry --
	# see _hold_cube()'s own comment), so capturing the bag's own random deal
	# here instead would make held_before != held_after look like a burn even
	# though nothing was actually consumed.
	_hold_cube(0)
	var held_before: BlockShape = Match.held_shape(0)
	var feed_seq_before: int = Match.feed_seq(0)

	# On the disk but outside either player's territory, so this is a refusal
	# on the territory rule itself rather than an empty footprint.
	var reason: StringName = _release(0, _neutral_spot())
	var spawned_none: bool = _blocks.get_child_count() == blocks_before
	var still_held: bool = Match.held_shape(0) == held_before
	var seq_unmoved: bool = Match.feed_seq(0) == feed_seq_before
	var tracked_unmoved: bool = _registry.tracked_block_count() == tracked_before

	# Nothing was consumed, so the same slot may simply try again -- this
	# time at a spot inside its own home circle, which must succeed and
	# actually spawn the still-held piece.
	var retry_reason: StringName = _release(0, _world_point(Match.slot(0).home_position, PLACE_HEIGHT))
	var retry_spawned: bool = _blocks.get_child_count() == blocks_before + 1

	_check("e", (
		reason == PlacementRules.REASON_OUTSIDE_TERRITORY
		and spawned_none
		and still_held
		and seq_unmoved
		and tracked_unmoved
		and retry_reason == PlacementRules.REASON_OK
		and retry_spawned
	), "reason=%s spawned_none=%s still_held=%s seq_unmoved=%s tracked_unmoved=%s retry_reason=%s retry_spawned=%s" % [
		reason, spawned_none, still_held, seq_unmoved, tracked_unmoved, retry_reason, retry_spawned
	])

	await _end_match()


## (g) Spec 2.4's fixed placement-window cadence: an early release locks the
## slot's next piece until the interval boundary; a second release before then
## is refused; the boundary unlocks it without forcing anything (this slot's
## piece was already spent); a slot that never releases at all gets its piece
## forced out at expiry (Events.feed_timer_expired), which this harness drives
## through Match.request_place(auto_drop = true) exactly as
## game/PlayerController.gd's own _on_feed_timer_expired() does -- nothing here
## has a scene-tree consumer of that signal, so the test plays that part
## itself. Needs hot_seat = false: see the file header for why hot-seat is
## exempt from this lock entirely.
func _scenario_cadence_lock() -> void:
	await _start_match_configured(_build_realtime_config(GOAL_COUNT))

	var expired_slots: Array[int] = []
	var on_expired: Callable = func(slot_id: int) -> void:
		expired_slots.append(slot_id)
	Events.feed_timer_expired.connect(on_expired)

	var locked_slot: int = 0
	var expiring_slot: int = 1
	var spot: Vector3 = _world_point(Match.slot(locked_slot).home_position, PLACE_HEIGHT)

	var locked_before: bool = Match.is_release_locked(locked_slot)
	var blocks_before_first: int = _blocks.get_child_count()
	var first_reason: StringName = _release(locked_slot, spot)
	var blocks_after_first: int = _blocks.get_child_count()
	var locked_after_release: bool = Match.is_release_locked(locked_slot)

	# Same interval, same slot, a second deliberate release: refused, and
	# nothing is spawned for it (autoload/Match.gd's request_place() refuses
	# before it ever spawns anything for this case).
	var second_reason: StringName = _release(locked_slot, spot)
	var blocks_after_second: int = _blocks.get_child_count()

	# Slot `expiring_slot` never places anything, so its own interval runs out
	# untouched while `locked_slot` waits out the same boundary.
	var boundary_frames: int = _frames_for_seconds(Match.config.block_timer) + 2
	await _step_until(boundary_frames, func() -> bool:
		return not Match.is_release_locked(locked_slot) and expired_slots.has(expiring_slot)
	)
	var locked_at_boundary: bool = Match.is_release_locked(locked_slot)
	var locked_slot_falsely_expired: bool = expired_slots.has(locked_slot)
	var expiring_slot_expired: bool = expired_slots.has(expiring_slot)

	# The lock lifted; the same slot may release again in the new interval.
	var third_reason: StringName = _release(locked_slot, spot)
	var blocks_after_third: int = _blocks.get_child_count()

	# The untouched slot's piece is still unspent: force it out, from its own
	# last known ghost position (there is none, since this harness never moved
	# one -- Match.default_ghost_origin() is exactly that fallback).
	var blocks_before_auto: int = _blocks.get_child_count()
	var auto_reason: StringName = PlacementRules.REASON_NO_BLOCK
	if expiring_slot_expired:
		auto_reason = Match.request_place(
			expiring_slot, Match.default_ghost_origin(expiring_slot), 0, Quaternion.IDENTITY, true
		)
	var blocks_after_auto: int = _blocks.get_child_count()

	Events.feed_timer_expired.disconnect(on_expired)

	_check("g", (
		not locked_before
		and first_reason == PlacementRules.REASON_OK
		and blocks_after_first == blocks_before_first + 1
		and locked_after_release
		and second_reason == PlacementRules.REASON_NO_BLOCK
		and blocks_after_second == blocks_after_first
		and not locked_at_boundary
		and not locked_slot_falsely_expired
		and expiring_slot_expired
		and third_reason == PlacementRules.REASON_OK
		and blocks_after_third == blocks_after_second + 1
		and auto_reason == PlacementRules.REASON_OK
		and blocks_after_auto == blocks_before_auto + 1
	), (
		"locked_before=%s first=%s(+%d) locked_after=%s second=%s(+%d) "
		+ "locked_at_boundary=%s slot0_expired=%s slot1_expired=%s "
		+ "third=%s(+%d) auto=%s(+%d)"
	) % [
		locked_before, first_reason, blocks_after_first - blocks_before_first,
		locked_after_release, second_reason, blocks_after_second - blocks_after_first,
		locked_at_boundary, locked_slot_falsely_expired, expiring_slot_expired,
		third_reason, blocks_after_third - blocks_after_second,
		auto_reason, blocks_after_auto - blocks_before_auto
	])

	await _end_match()


# --- Match lifecycle ---------------------------------------------------------

func _start_match(goal_count: int) -> void:
	await _start_match_configured(_build_config(goal_count))


func _start_match_configured(config: MatchConfig) -> void:
	_field = (load("res://game/Field.tscn") as PackedScene).instantiate() as Field
	_field.map_def = MapDef.for_size(MAP_SIZE)
	add_child(_field)
	_blocks = Node3D.new()
	add_child(_blocks)
	_registry = BlockRegistry.new()
	add_child(_registry)

	Match.register_world(_field, _registry, _blocks)
	Match.start_match(config)
	_field.place_flags(PLAYER_COUNT, Match.config.player_colors, Match.config.goal_flag_count)
	_field.set_overlay_source(Match.raster(), Match.config.player_colors)
	await _step(_frames_for_seconds(Match.COUNTDOWN_SECONDS) + 2)


func _end_match() -> void:
	Match.abort_match()
	_field.queue_free()
	_blocks.queue_free()
	_registry.queue_free()
	_field = null
	_blocks = null
	_registry = null
	await get_tree().process_frame


func _build_config(goal_count: int) -> MatchConfig:
	var config: MatchConfig = (load("res://config/match_defaults.tres") as MatchConfig).duplicate(true)
	config.map_size = MAP_SIZE
	config.player_count = PLAYER_COUNT
	config.hot_seat = true
	config.goal_flag_count = goal_count
	config.rng_seed = RNG_SEED
	# The scenario drives every placement itself, so the feed timer must not
	# auto-drop a block behind its back. block_timer is clamped to
	# BLOCK_TIMER_MAX by sanitize(), which is far longer than a scenario runs.
	config.block_timer = MatchConfig.BLOCK_TIMER_MAX
	return config


## (g) needs the real fixed-interval cadence, which only runs outside
## hot-seat (see the file header) -- and needs to actually finish waiting out
## an interval, so block_timer is the lobby's *shortest* legal window rather
## than its longest.
func _build_realtime_config(goal_count: int) -> MatchConfig:
	var config: MatchConfig = (load("res://config/match_defaults.tres") as MatchConfig).duplicate(true)
	config.map_size = MAP_SIZE
	config.player_count = PLAYER_COUNT
	config.hot_seat = false
	config.goal_flag_count = goal_count
	config.rng_seed = RNG_SEED
	config.block_timer = MatchConfig.BLOCK_TIMER_MIN
	return config


# --- Laying chains of blocks -------------------------------------------------

## Both slots march from their own home toward `meeting`, alternating turns,
## until neither can place any further. Collects the blocks each one laid.
func _march_pair(
	home_0: Vector2, home_1: Vector2, meeting: Vector2, chain_0: Array[Block], chain_1: Array[Block]
) -> void:
	var front: Array[Vector2] = [home_0, home_1]
	var target: Array[Vector2] = [meeting, meeting]
	# The first step comes off the home circle, which is much wider than a
	# single cube's; after that every front is a cube.
	var reach: Array[float] = [_tuning.home_radius, _tuning.home_radius]
	var chains: Array = [chain_0, chain_1]
	var stalled: Array[bool] = [false, false]
	# Stop deliberately once the two fronts are this close, rather than
	# letting them march until a placement is naturally refused as CONTESTED:
	# a single cube's own circle already covers a same-height opponent cube
	# within cube_reach() of it, so marching until refusal would leave the two
	# base cells already mutually contested, with no room for _raise_fronts()
	# to grow either circle at all before its own base point is refused too
	# (every raise targets that same base cell). _meeting_stop_gap() instead
	# leaves a gap comfortably wider than the fully-raised reach, so every
	# _raise_fronts() layer validates deterministically and neither base ever
	# risks becoming contested (and later holed) under its own tower -- only
	# the ground between the two towers does, which is what (b) needs.
	var stop_gap: float = _meeting_stop_gap()
	for _step_index: int in range(MAX_MARCH_STEPS):
		if stalled[0] and stalled[1]:
			return
		if front[0].distance_to(front[1]) <= stop_gap:
			return
		for slot_id: int in range(PLAYER_COUNT):
			if Match.state() != Match.State.PLAYING:
				return
			if stalled[slot_id]:
				await _pass_turn(slot_id)
				continue
			var placed: Block = await _march_one(
				slot_id, front[slot_id], reach[slot_id], target[slot_id]
			)
			if placed == null:
				stalled[slot_id] = true
				continue
			front[slot_id] = _disk_local(placed.global_position)
			reach[slot_id] = _cube_reach()
			var chain: Array[Block] = chains[slot_id]
			chain.append(placed)
			if front[0].distance_to(front[1]) <= stop_gap:
				return


## Marches `slot_id` from its own home through each point of `route` in turn,
## alternating with every other living slot passing its own turn (hot-seat
## alternates strict turns, so "passing" is how an uninvolved slot spends its
## own window without building). Stops the moment a step is refused (stalled),
## a waypoint budget runs out, or the match ends -- whichever comes first,
## leaving `chain` with whatever it managed to place.
func _march_solo_route(slot_id: int, route: Array[Vector2], chain: Array[Block]) -> void:
	var front: Vector2 = Match.slot(slot_id).home_position
	var reach: float = _tuning.home_radius
	for waypoint: Vector2 in route:
		for _step_index: int in range(MAX_MARCH_STEPS):
			if Match.state() != Match.State.PLAYING:
				return
			if front.distance_to(waypoint) <= _physics.cube_size * 0.5:
				break
			var placed: Block = await _march_one(slot_id, front, reach, waypoint)
			if placed == null:
				return
			chain.append(placed)
			front = _disk_local(placed.global_position)
			reach = _cube_reach()
			for other: int in range(PLAYER_COUNT):
				if other != slot_id and Match.slot(other).home_flag_alive:
					await _pass_turn(other)


## Marches `slot_id` from `home` straight at `goal`, one cube at a time, never
## stepping closer than `stop_distance` -- (d)'s "approach from outside the
## zone" (scenario 4): the block's own placement point must clear the goal's
## no-build zone, even though its eventual *reach* is meant to cover the flag.
func _march_to_distance(
	slot_id: int, home: Vector2, goal: Vector2, stop_distance: float, chain: Array[Block]
) -> void:
	var front: Vector2 = home
	var reach: float = _tuning.home_radius
	for _step_index: int in range(MAX_MARCH_STEPS):
		if Match.state() != Match.State.PLAYING:
			return
		var to_goal: Vector2 = goal - front
		var remaining: float = to_goal.length() - stop_distance
		if remaining <= _physics.cube_size * 0.5:
			return
		var target: Vector2 = front + to_goal.normalized() * remaining
		var placed: Block = await _march_one(slot_id, front, reach, target)
		if placed == null:
			return
		chain.append(placed)
		front = _disk_local(placed.global_position)
		reach = _cube_reach()
		for other: int in range(PLAYER_COUNT):
			if other != slot_id:
				await _pass_turn(other)


## Places one cube as far toward `target` as the front circle of radius
## `reach` allows, backing off if the first try is refused. Returns the block,
## or null when no step forward is valid any more.
func _march_one(slot_id: int, front: Vector2, reach: float, target: Vector2) -> Block:
	var to_target: Vector2 = target - front
	if to_target.length() < 0.001:
		return null
	var direction: Vector2 = to_target.normalized()
	var step: float = minf(_safe_step(reach), to_target.length())
	_hold_cube(slot_id)
	while step > _physics.cube_size * 0.5:
		var spot: Vector2 = front + direction * step
		if Match.preview_placement(
			slot_id, _world_point(spot, PLACE_HEIGHT), 0, Quaternion.IDENTITY
		) == PlacementRules.Result.VALID:
			var before: int = _blocks.get_child_count()
			var reason: StringName = _release(slot_id, _world_point(spot, PLACE_HEIGHT))
			if reason == PlacementRules.REASON_OK and _blocks.get_child_count() > before:
				var placed: Block = _blocks.get_child(_blocks.get_child_count() - 1) as Block
				await _step(SETTLE_FRAMES)
				return placed
			return null
		step -= _physics.cube_size * 0.5
	return null


## A block's influence circle when it is sitting on the disk (spec 2.2:
## r = influence_base + influence_k * h, h being its highest point).
func _cube_reach() -> float:
	return _tuning.influence_base + _tuning.influence_k * _physics.cube_size


## The furthest a cube may step from the center of a circle of radius `reach`
## and still land wholly inside it. The raster owns a cell when its *center*
## is in the circle, so the worst case is the far corner cell of the
## footprint: half a cube plus half a cell diagonal.
func _safe_step(reach: float) -> float:
	return maxf(reach - _physics.cube_size * 0.5 - _corner_margin(), 0.0)


## Half a cell's diagonal: the same corner-rounding slack _safe_step() budgets
## against, reused wherever a point needs a hard guarantee of landing outside
## (or inside) a circle regardless of which cell it rounds to.
func _corner_margin() -> float:
	var cell: float = _field.map_definition().cell_size
	return cell * 0.5 * sqrt(2.0)


## The tallest any front in scenarios (a)-(c) ever grows (spec 2.2's
## r = influence_base + influence_k * h), after _raise_fronts() stacks
## FRONT_STACK_HEIGHT extra layers on the first cube. This is the largest
## radius any single circle in those scenarios can ever have.
func _max_front_reach() -> float:
	var stacked_height: float = _physics.cube_size * float(1 + FRONT_STACK_HEIGHT)
	return _tuning.influence_base + _tuning.influence_k * stacked_height


## _march_pair()'s stopping gap: the fully-raised reach (_max_front_reach())
## plus one more cube_reach() of slack, so that neither base ever becomes
## contested (and thus at risk of being holed out from under itself) while
## _raise_fronts() grows both fronts to their full height -- only the ground
## between the two towers ends up contested, deterministically, on every run.
## The margin is a full cube_reach() rather than a single march step because
## the last step or two toward the meeting point can be as large as a fresh
## circle's own reach (see _march_one()/_safe_step()), so a margin smaller
## than that could still be crossed in one step.
func _meeting_stop_gap() -> float:
	return _max_front_reach() + _cube_reach()


## Distance from the lone central goal that keeps every circle in (a)-(c) and
## (f) from ever reaching it, whether by physically standing in its zone or by
## a tall tower's reach alone: the tallest front's own worst-case reach, plus
## a corner's worth of slack.
func _goal_avoidance_clearance() -> float:
	return _max_front_reach() + _corner_margin()


## The meeting point M = (0, y) on the perpendicular bisector of two homes at
## (+-home_x, 0) whose closest approach to the origin is exactly `clearance`.
## The line from (home_x, 0) to (0, y) has distance home_x * y /
## sqrt(home_x^2 + y^2) from the origin (standard point-to-line distance);
## solving that for y gives this formula. Both homes are equidistant from M by
## construction (they are mirror images through the origin), so aiming both
## fronts at the same M in _march_pair() makes them converge symmetrically.
func _meeting_point(home_x: float, clearance: float) -> Vector2:
	var h: float = absf(home_x)
	var denom: float = sqrt(maxf(h * h - clearance * clearance, 0.001))
	return Vector2(0.0, clearance * h / denom)


## (d): a placement point must clear the goal's no-build zone by at least a
## corner's worth of slack, the same margin _safe_step() uses to keep a step
## unambiguously inside a circle rather than merely on its rounding edge.
func _zone_edge_stop_distance() -> float:
	return _tuning.goal_zone_radius + _corner_margin()


## Does `team` own the cell under this disk-local point right now?
func _owns_point(team: int, point: Vector2) -> bool:
	var grid: CellGrid = Match.raster().grid()
	var coords: Vector2i = grid.world_to_cell(point)
	if not grid.in_bounds(coords.x, coords.y):
		return false
	return Match.raster().team_at(coords.x, coords.y) == team


## Stacks cubes on top of the chain's head until the growing influence circle
## swallows `victim_slot`'s home cell and the hole underneath it takes the flag.
func _stack_until_home_flag_falls(slot_id: int, chain: Array[Block], victim_slot: int) -> bool:
	if chain.is_empty():
		return false
	var head: Vector2 = _disk_local(chain[chain.size() - 1].global_position)
	var height: float = _physics.cube_size
	for _i: int in range(MAX_MARCH_STEPS):
		if Match.state() != Match.State.PLAYING:
			return not Match.slot(victim_slot).home_flag_alive
		height += _physics.cube_size
		var spot: Vector3 = _world_point(head, height + PLACE_HEIGHT)
		_hold_cube(slot_id)
		if Match.preview_placement(slot_id, spot, 0, Quaternion.IDENTITY) != PlacementRules.Result.VALID:
			return not Match.slot(victim_slot).home_flag_alive
		if _release(slot_id, spot) != PlacementRules.REASON_OK:
			return not Match.slot(victim_slot).home_flag_alive
		await _step(SETTLE_FRAMES)
		if not Match.slot(victim_slot).home_flag_alive:
			return true
		for other: int in range(PLAYER_COUNT):
			if other != slot_id and Match.slot(other).home_flag_alive:
				await _pass_turn(other)
		# Give the contested cells time to cross hole_delay before the next
		# block goes on, so the stack does not overshoot the elimination.
		await _step(_frames_for_seconds(_tuning.hole_delay))
		if not Match.slot(victim_slot).home_flag_alive:
			return true
	return not Match.slot(victim_slot).home_flag_alive


## (d): stacks cubes on top of the chain's head, directly above the same
## disk-local point (never moving closer to the zone), until `team`'s
## influence circle there is wide enough to cover `goal` -- reach, not
## position, closes the distance the march deliberately left short.
func _stack_until_goal_covered(
	slot_id: int, head: Vector2, goal: Vector2, team: int, chain: Array[Block]
) -> bool:
	if chain.is_empty():
		return false
	if _owns_point(team, goal):
		return true
	var height: float = _physics.cube_size
	for _i: int in range(MAX_MARCH_STEPS):
		if Match.state() != Match.State.PLAYING:
			return _owns_point(team, goal)
		height += _physics.cube_size
		var spot: Vector3 = _world_point(head, height + PLACE_HEIGHT)
		_hold_cube(slot_id)
		if Match.preview_placement(slot_id, spot, 0, Quaternion.IDENTITY) != PlacementRules.Result.VALID:
			return _owns_point(team, goal)
		if _release(slot_id, spot) != PlacementRules.REASON_OK:
			return _owns_point(team, goal)
		await _step(SETTLE_FRAMES)
		if _owns_point(team, goal):
			return true
		for other: int in range(PLAYER_COUNT):
			if other != slot_id and Match.slot(other).home_flag_alive:
				await _pass_turn(other)
	return _owns_point(team, goal)


## Both players stack on the head of their chain, alternating turns, so the
## two front circles grow into each other. A hole one cell wide is barely
## wider than the block itself; a real contested overlap is a patch, and that
## is what criterion (b) needs to drop a block into. _march_pair() stops the
## march with enough of a gap left that the first layer or two here still
## validates before the bases' own growing reach makes each other's cell
## CONTESTED; once that happens every further layer is skipped -- explicitly
## passing the turn in that case too, since a skipped placement never calls
## Match.request_place() and so never advances hot-seat's turn on its own
## (unlike a placement that spawns and burns, which does).
##
## `peak_contested[0]` comes back holding the largest contested-cell count
## seen at any point while raising -- not just whatever is left once this
## returns. hole_delay (0.75 s by default) is short next to the several
## SETTLE_FRAMES waits this takes, so some or all of the contested band can
## already have finished converting into holes by the time the last layer
## settles; reading contested_before only after the fact would then racily
## report 0 depending on exactly how many layers validated before the bases
## made each other CONTESTED, which is not the thing criterion (b) is meant
## to check.
func _raise_fronts(chain_0: Array[Block], chain_1: Array[Block], peak_contested: Array[int]) -> void:
	var chains: Array = [chain_0, chain_1]
	var heights: Array[float] = [_physics.cube_size, _physics.cube_size]
	for _layer: int in range(FRONT_STACK_HEIGHT):
		for slot_id: int in range(PLAYER_COUNT):
			if Match.state() != Match.State.PLAYING:
				return
			var chain: Array[Block] = chains[slot_id]
			if chain.is_empty():
				await _pass_turn(slot_id)
				continue
			heights[slot_id] += _physics.cube_size
			var head: Vector2 = _disk_local(chain[chain.size() - 1].global_position)
			var spot: Vector3 = _world_point(head, heights[slot_id] + PLACE_HEIGHT)
			_hold_cube(slot_id)
			if Match.preview_placement(slot_id, spot, 0, Quaternion.IDENTITY) != PlacementRules.Result.VALID:
				await _pass_turn(slot_id)
				peak_contested[0] = maxi(peak_contested[0], _contested_cell_count())
				continue
			if _release(slot_id, spot) != PlacementRules.REASON_OK:
				continue
			await _step(SETTLE_FRAMES)
			peak_contested[0] = maxi(peak_contested[0], _contested_cell_count())


## (h): builds `layers` cubes stacked directly above a point just inside
## `slot_id`'s own home circle, offset in -z from `home` -- the opposite side
## from every other march in this file, which goes +z -- so this tower can
## never be contested by, or confused with, anything else the scenario does.
## Alternates with `other_slot` passing so hot-seat's strict turn order still
## lets `slot_id` place every layer; hot-seat auto-advances the turn to
## `other_slot` after `slot_id`'s own last placement, and this does not pass
## `other_slot` again after the final layer, so the active slot is
## `other_slot` when this returns. Returns the tower's base point
## (disk-local), for the caller to derive a reach-only ownership check from.
func _build_isolated_tower(
	slot_id: int, other_slot: int, home: Vector2, layers: int, chain: Array[Block]
) -> Vector2:
	var direction: Vector2 = Vector2(0.0, -1.0)
	var base: Vector2 = home + direction * _safe_step(_tuning.home_radius)
	var height: float = _physics.cube_size
	for i: int in range(layers):
		var spot: Vector3 = _world_point(base, height + PLACE_HEIGHT)
		_hold_cube(slot_id)
		if Match.preview_placement(slot_id, spot, 0, Quaternion.IDENTITY) == PlacementRules.Result.VALID:
			var before: int = _blocks.get_child_count()
			if _release(slot_id, spot) == PlacementRules.REASON_OK and _blocks.get_child_count() > before:
				await _step(SETTLE_FRAMES)
				chain.append(_blocks.get_child(_blocks.get_child_count() - 1) as Block)
		height += _physics.cube_size
		if i < layers - 1:
			await _pass_turn(other_slot)
	return base


## Spends a slot's turn without building, and hands the turn on.
##
## DECISION (tests/bench/m2_acceptance.gd, Bontago-p0a): must call
## request_place() with auto_drop = true, not _release()'s manual
## (auto_drop = false) path. Bontago-mv0.24 (owner test 2026-09-22, SPEC.md
## 2.5 "Held-block behaviour"/"Expiry and invalid actions") changed a
## *manual* release on an invalid spot from "spawns, burns, and hands the
## turn on" (the old docs/M2_PLAN.md owner decision 2 this comment used to
## cite) to "refused outright: nothing spawns, nothing is consumed, feed_seq
## does not move" -- autoload/match/MatchPlacement.gd's request_place()
## returns before ever reaching _consume_and_refeed()/advance_turn() on that
## path now. An off-disk _release() (auto_drop = false) therefore no longer
## advances hot-seat's turn at all, which silently wedged every march that
## alternates real placements with a passed turn (_march_pair(),
## _march_solo_route(), _march_to_distance(), _build_isolated_tower(): a
## stuck active_slot() turns every next real release into
## REASON_NOT_YOUR_TURN, which _march_one() treats as "no further step
## possible" -- Bontago-p0a's (d)/(f)/(h) failures, each stalled at exactly
## the chain length reached right before this function's first call).
## auto_drop = true still burns an off-disk release (spec 2.5's forced-
## release case keeps "nowhere valid to land -> spawn and throw it off the
## map"), and unlike the manual path it always reaches
## _consume_and_refeed()/advance_turn(), which is what a harness-only "pass"
## actually needs -- a real player's timer expiry is the only other caller
## that ever sets auto_drop = true, so this exercises exactly that code path,
## not a bench-only shortcut.
func _pass_turn(slot_id: int) -> void:
	if Match.state() != Match.State.PLAYING or not Match.slot(slot_id).home_flag_alive:
		return
	_hold_cube(slot_id)
	Match.request_place(slot_id, _off_disk_point(), 0, Quaternion.IDENTITY, true)
	await _step(1)


## Forces the held shape to a cube so the scenario's geometry is the same on
## every run, whatever the bag dealt. It has to run before preview_placement()
## too: the preview validates the *held* shape's footprint, so previewing a
## bar and then releasing a cube would ask about two different shapes.
func _hold_cube(slot_id: int) -> void:
	Match._held_shapes[slot_id] = _cube


## The deliberate (auto_drop = false) placement intent Match would get from a
## player's own click -- an invalid spot here is refused outright, not
## burned (see _pass_turn()'s DECISION above for the auto_drop = true path
## this is not).
func _release(slot_id: int, world_origin: Vector3) -> StringName:
	_hold_cube(slot_id)
	return Match.request_place(slot_id, world_origin, 0, Quaternion.IDENTITY, false)


# --- Holes -------------------------------------------------------------------

func _contested_cell_count() -> int:
	var raster: TerritoryRaster = Match.raster()
	var grid: CellGrid = raster.grid()
	var count: int = 0
	for index: int in grid.in_disk_cells():
		var coords: Vector2i = grid.cell_coords(index)
		if raster.is_contested(coords.x, coords.y):
			count += 1
	return count


func _hole_cells() -> PackedInt32Array:
	var raster: TerritoryRaster = Match.raster()
	var cells: PackedInt32Array = PackedInt32Array()
	for index: int in raster.grid().in_disk_cells():
		if raster.is_hole_index(index):
			cells.append(index)
	return cells


## Field batches its collision toggles, so nothing may be dropped on a hole
## until the backlog is empty.
func _drain_field_backlog() -> void:
	for _i: int in range(MAX_MARCH_STEPS * 10):
		if _field.pending_toggle_count() == 0:
			return
		await _step(1)


## Drops a bare block (not a placement -- placing on a hole is refused) over a
## hole cell and reports whether it ended up below the disk surface. Skips any
## candidate cell within a cube's width of `occupied` (the two towers' own
## footprints), which may still have a real block resting on it -- or may not,
## if that tower's own floor gave way first, but either way it is not the open
## ground this check needs.
func _drop_through_hole(holes: PackedInt32Array, occupied: Array[Vector2]) -> bool:
	var grid: CellGrid = Match.raster().grid()
	var clearance: float = _physics.cube_size
	for index: int in _interior_first(holes, grid):
		if not _field.is_hole_cell(index):
			continue
		var center: Vector2 = grid.index_center(index)
		var too_close: bool = false
		for point: Vector2 in occupied:
			if center.distance_to(point) < clearance:
				too_close = true
				break
		if too_close:
			continue
		var block: Block = BlockFactory.build(_cube, _physics, -1)
		_blocks.add_child(block)
		block.global_position = _world_point(center, PLACE_HEIGHT)
		var block_id: int = block.get_instance_id()
		var floor_y: float = _field.surface_y() - _physics.cube_size
		var fell: bool = await _step_until(_frames_for_seconds(4.0), func() -> bool:
			if not _alive(block_id):
				return true
			var body: Node3D = instance_from_id(block_id) as Node3D
			return body.global_position.y < floor_y
		)
		if _alive(block_id):
			(instance_from_id(block_id) as Node).queue_free()
		if fell:
			return true
	return false


## Removes a run of blocks from the middle of a chain, wide enough that the
## survivors on either side of the gap no longer overlap. Anything less and
## the chain simply closes up: two cubes 1.2 m apart still touch through a
## 2.4 m circle, so a one-block gap proves nothing about the cut-off rule.
## Returns {"removed": int, "tail_index": int}: how many were removed, and the
## index of the first surviving element past the cut -- the caller's own
## "definitely cut off, definitely not the contested chain tip" reference
## point, since the tip itself is the meeting point criterion (b) may already
## have holed out on its own.
func _cut_chain(chain: Array[Block]) -> Dictionary:
	if chain.size() < 4:
		return {"removed": 0, "tail_index": chain.size() - 1}
	var cut_from: int = maxi(int(chain.size() / 3.0), 1)
	var anchor: Vector2 = _disk_local(chain[cut_from - 1].global_position)
	var cut_to: int = cut_from
	while cut_to < chain.size() - 2:
		var beyond: Vector2 = _disk_local(chain[cut_to + 1].global_position)
		if anchor.distance_to(beyond) > 2.0 * _cube_reach():
			break
		cut_to += 1
	var removed: int = 0
	for i: int in range(cut_from, cut_to + 1):
		if _remove_block(chain[i]):
			removed += 1
	return {"removed": removed, "tail_index": cut_to + 1}


## Removes the last `count` blocks of `chain` the way physics toppling it off
## a stack would leave it: gone from the next solve, with no placement call
## involved at all. Returns how many were removed. Used only by criterion
## (h), which passes chain.size() to topple the whole thing.
func _topple_tail(chain: Array[Block], count: int) -> int:
	var removed: int = 0
	var start: int = maxi(chain.size() - count, 0)
	for i: int in range(chain.size() - 1, start - 1, -1):
		if _remove_block(chain[i]):
			removed += 1
	return removed


## Hole cells whose four neighbours are holes too, then the rest. A lone open
## cell is only cell_size wide and its neighbours' collision boxes overhang it
## by MapDef.cell_overlap / 2 (see the DECISION there), so a block can bridge
## it; a block over the inside of a patch has nothing to rest on.
func _interior_first(holes: PackedInt32Array, grid: CellGrid) -> PackedInt32Array:
	var is_hole: Dictionary = {}
	for index: int in holes:
		is_hole[index] = true
	var interior: PackedInt32Array = PackedInt32Array()
	var edge: PackedInt32Array = PackedInt32Array()
	for index: int in holes:
		var coords: Vector2i = grid.cell_coords(index)
		var surrounded: bool = true
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbour: Vector2i = coords + step
			if not grid.in_bounds(neighbour.x, neighbour.y):
				surrounded = false
				break
			if not is_hole.has(grid.cell_index(neighbour.x, neighbour.y)):
				surrounded = false
				break
		if surrounded:
			interior.append(index)
		else:
			edge.append(index)
	interior.append_array(edge)
	return interior


## Frees a block the way the kill plane does, so the BlockRegistry stops
## counting its influence.
func _remove_block(block: Block) -> bool:
	if not is_instance_valid(block):
		return false
	Events.block_removed.emit(block, String(Events.REASON_KILL_PLANE))
	block.queue_free()
	return true


# --- Stepping ----------------------------------------------------------------

## One physics frame plus the Match tick that would have run alongside it.
## Match's own _process is switched off so the two can never double-count.
func _step(frames: int) -> void:
	var delta: float = 1.0 / float(Engine.physics_ticks_per_second)
	for _i: int in range(frames):
		await get_tree().physics_frame
		Match._process(delta)


## Steps until `predicate` is true or the frame budget runs out.
func _step_until(frames: int, predicate: Callable) -> bool:
	var delta: float = 1.0 / float(Engine.physics_ticks_per_second)
	for _i: int in range(frames):
		if bool(predicate.call()):
			return true
		await get_tree().physics_frame
		Match._process(delta)
	return bool(predicate.call())


func _frames_for_seconds(seconds: float) -> int:
	return int(ceil(seconds * float(Engine.physics_ticks_per_second)))


# --- Geometry ----------------------------------------------------------------

func _world_point(disk_local: Vector2, height: float) -> Vector3:
	return _field.world_from_disk_local(disk_local, height)


func _disk_local(world: Vector3) -> Vector2:
	return _field.disk_local_from_world(world)


func _off_disk_point() -> Vector3:
	var radius: float = _field.map_definition().field_radius * OFF_DISK_FACTOR
	return _world_point(Vector2(radius, 0.0), PLACE_HEIGHT)


## On the disk, but nobody's territory: the homes sit on the x axis, so a
## point out along +z belongs to neither player, well clear of the lone
## central goal's zone.
func _neutral_spot() -> Vector3:
	var radius: float = _field.map_definition().field_radius * NEUTRAL_SPOT_FRACTION
	return _world_point(Vector2(0.0, radius), PLACE_HEIGHT)


## Whether an object id still refers to a live object. Capturing the object
## itself in a lambda breaks once physics frees it ("Lambda capture was
## freed"), so every wait-for-it-to-die check goes through the id.
func _alive(object_id: int) -> bool:
	return object_id != 0 and is_instance_id_valid(object_id)


# --- Reporting ---------------------------------------------------------------

func _check(criterion: String, passed: bool, detail: String) -> void:
	print("M2_ACCEPT (%s) %s %s" % [criterion, "PASS" if passed else "FAIL", detail])
	if not passed:
		_failures.append("(%s) %s" % [criterion, detail])
