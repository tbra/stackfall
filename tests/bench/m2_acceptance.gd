extends Node3D
## End-to-end acceptance for M2 (spec Part 4 M2, docs/M2_PLAN.md), driven by
## script with no player and no fakes: the real Match autoload, a real Field
## with real per-cell collision, a real BlockRegistry and real Jolt physics.
## Run headless:
##   godot --headless --path . res://tests/bench/m2_acceptance.tscn
## It prints one M2_ACCEPT line per criterion and exits non-zero if any fails.
##
## The six criteria, lettered as in the M2 integration brief:
##   (a) both players' territory shares grow as they build.
##   (b) where two territories overlap, the contested cells become holes after
##       hole_delay, and a block dropped on a hole cell falls below the disk.
##   (c) a tower whose base is cut off loses its influence: removing a link in
##       the chain drops the owner's territory share.
##   (d) a player whose connected territory holds the goal flag for
##       capture_hold wins, and Match reaches End with the right winner.
##   (e) an invalid release burns the block: it spawns, is thrown off the map,
##       and the next block is fed (docs/M2_PLAN.md owner decision 2).
##   (f) a hole under a home flag eliminates that slot (owner decision 3).
##
## It lives in tests/bench/ rather than tests/unit/ because it is a real-time
## scenario: the GUT suite would grow by the ~60 s of wall clock the physics
## actually takes. Nothing here is a benchmark — the name is the folder's.
##
## **Why it drives the match this way.** The disk is 60 m across and a single
## cube's influence circle is 2.4 m, so making two territories touch means
## laying a chain of blocks between two homes. Each player takes real turns
## through Match.request_place(); the slot that should not build "passes" by
## releasing off the disk, which under owner decision 2 burns its block and
## hands the turn back — the same code path criterion (e) checks.

## Spec 2.8 lobby settings this scenario needs. The small map keeps the chain
## short enough to lay in a minute of wall clock; the rest are defaults.
const MAP_SIZE: MapDef.MapSize = MapDef.MapSize.SMALL
const PLAYER_COUNT: int = 2
## Five goal flags for the scenarios that must NOT end in a capture: a single
## chain of blocks cannot hold all five at once, so the march can cross the
## middle of the disk without accidentally winning. The capture scenario (d)
## uses one goal, in the center.
const GOALS_NO_CAPTURE: int = 5
const GOALS_CAPTURE: int = 1
const RNG_SEED: int = 20260917

## Physics frames to hold a freshly placed block still before it counts as
## settled. PhysicsTuning.sleep_settle_time is 0.5 s; the spare frames cover
## the drop from PLACE_HEIGHT and the solve that follows.
const SETTLE_FRAMES: int = 42
## How far above the disk surface a scripted placement is released, in meters.
## Small enough that the block is at rest almost immediately.
const PLACE_HEIGHT: float = 0.55
## Give up rather than loop forever if the march stops making progress.
const MAX_MARCH_STEPS: int = 60
## How far off the disk a passed turn releases its block, as a multiple of the
## field radius. Far enough that the footprint is empty on any map.
const OFF_DISK_FACTOR: float = 3.0
## An on-disk but un-owned release point for criterion (e), as a fraction of
## the field radius along +z — away from both homes, which sit on the x axis.
const NEUTRAL_SPOT_FRACTION: float = 0.9
## Cubes each player stacks on the head of its chain once the two fronts meet,
## to widen the contested band into a patch of cells.
const FRONT_STACK_HEIGHT: int = 4

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

	await _scenario_growth_holes_and_cutoff()
	await _scenario_home_flag_hole()
	await _scenario_capture_win()
	await _scenario_burned_block()

	print("M2_ACCEPT result=%s failures=%d" % [
		"PASS" if _failures.is_empty() else "FAIL", _failures.size()
	])
	for failure: String in _failures:
		print("M2_ACCEPT failure %s" % failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


# --- Scenarios ---------------------------------------------------------------

## (a) both shares grow, (b) overlap -> contested -> holes -> a block falls
## through, (c) cutting the chain costs the owner its territory.
func _scenario_growth_holes_and_cutoff() -> void:
	await _start_match(GOALS_NO_CAPTURE)

	var share_0_before: float = Match.territory_share(Match.team_of(0))
	var share_1_before: float = Match.territory_share(Match.team_of(1))

	# Both players march toward each other along the line joining their homes,
	# so their fronts meet near the middle of the disk.
	var home_0: Vector2 = Match.slot(0).home_position
	var home_1: Vector2 = Match.slot(1).home_position
	var chain_0: Array[Block] = []
	var chain_1: Array[Block] = []
	await _march_pair(home_0, home_1, chain_0, chain_1)

	var share_0_after: float = Match.territory_share(Match.team_of(0))
	var share_1_after: float = Match.territory_share(Match.team_of(1))
	_check("a", share_0_after > share_0_before and share_1_after > share_1_before,
		"shares p0 %.4f->%.4f p1 %.4f->%.4f blocks %d/%d" % [
			share_0_before, share_0_after, share_1_before, share_1_after,
			chain_0.size(), chain_1.size()
		])

	# (b) The two fronts overlap, so cells in between belong to both teams.
	# Both players now build up at the front, which widens each front circle
	# (r = influence_base + influence_k * h) and so widens the contested band
	# between them into a patch of cells rather than a hairline.
	await _raise_fronts(chain_0, chain_1)

	# TerritoryRaster only opens a hole once contested_time passes hole_delay,
	# so let the solve run over that threshold before looking.
	var contested_before: int = _contested_cell_count()
	await _step(_frames_for_seconds(_tuning.hole_delay) + _frames_for_seconds(2.0 / _tuning.solve_hz))
	var holes: PackedInt32Array = _hole_cells()
	_check("b1", contested_before > 0 and holes.size() > 0,
		"contested_cells=%d hole_cells=%d after hole_delay=%.2fs" % [
			contested_before, holes.size(), _tuning.hole_delay
		])

	# Field applies the hole diff through a backlog capped at
	# max_cell_toggles_per_frame, so wait for it to drain before dropping
	# anything on the hole.
	await _drain_field_backlog()
	var fell_through: bool = false
	if holes.size() > 0:
		fell_through = await _drop_through_hole(holes)
	_check("b2", fell_through,
		"a block dropped on a hole cell must end up below the disk surface")

	# (c) Cut the middle out of player 0's chain: everything past the cut is no
	# longer connected to the home circle, so it stops granting territory.
	var team_0: int = Match.team_of(0)
	var share_before_cut: float = Match.territory_share(team_0)
	var tail: Vector2 = _disk_local(chain_0[chain_0.size() - 1].global_position)
	var owned_before_cut: bool = _owns_point(team_0, tail)
	var removed: int = _cut_chain(chain_0)
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

	await _end_match()


## (f) A hole opening under a home flag eliminates that slot.
func _scenario_home_flag_hole() -> void:
	await _start_match(GOALS_NO_CAPTURE)

	var home_0: Vector2 = Match.slot(0).home_position
	var home_1: Vector2 = Match.slot(1).home_position
	# Player 1 passes every turn, so its territory stays exactly its home
	# circle and player 0 can march all the way up to the edge of it.
	var chain: Array[Block] = []
	await _march_solo(0, home_0, home_1, chain)

	# A single cube's circle stops short of the flag itself. Stacking on the
	# head of the chain grows that circle by influence_k per meter of height
	# until it swallows the home flag's cell, which is what opens the hole.
	var eliminated: bool = await _stack_until_home_flag_falls(0, chain, 1)
	_check("f", eliminated and not Match.slot(1).home_flag_alive,
		"slot 1 home_flag_alive=%s after %d chain blocks" % [
			Match.slot(1).home_flag_alive, chain.size()
		])

	await _end_match()


## (d) Holding the goal flag in one connected territory for capture_hold wins.
func _scenario_capture_win() -> void:
	await _start_match(GOALS_CAPTURE)

	var home_0: Vector2 = Match.slot(0).home_position
	var chain: Array[Block] = []
	# The single goal flag sits at the disk center, so player 0 marches from
	# its home to the middle while player 1 passes.
	await _march_solo(0, home_0, Vector2.ZERO, chain, true)

	var team_0: int = Match.team_of(0)
	var capture_frames: int = _frames_for_seconds(_tuning.capture_hold + 1.0)
	var won: bool = await _step_until(capture_frames, func() -> bool:
		return Match.state() == Match.State.END
	)
	_check("d", won and Match.winner_team() == team_0,
		"state=%d winner=%d expected=%d chain=%d" % [
			Match.state(), Match.winner_team(), team_0, chain.size()
		])

	await _end_match()


## (e) A deliberate release on an invalid spot burns the block: it is spawned,
## thrown off the map, and the next block is fed (owner decision 2).
func _scenario_burned_block() -> void:
	await _start_match(GOALS_NO_CAPTURE)

	var blocks_before: int = _blocks.get_child_count()
	# On the disk but outside either player's territory, so this is a refusal
	# on the territory rule itself rather than an empty footprint.
	var reason: StringName = _release(0, _neutral_spot())
	var spawned_one: bool = _blocks.get_child_count() == blocks_before + 1
	var spawned_id: int = 0
	if spawned_one:
		spawned_id = _blocks.get_child(_blocks.get_child_count() - 1).get_instance_id()
	var refed: bool = Match.held_shape(0) != null
	var tracked_before: int = _registry.tracked_block_count()

	# The reject impulse lands on the next physics step, not on the call.
	await _step(1)
	var launched: bool = false
	if _alive(spawned_id):
		var body: Block = instance_from_id(spawned_id) as Block
		launched = body.linear_velocity.length() > 0.0

	# Thrown clear of the disk, the kill plane frees it and reports it, which
	# is what unregisters it from the BlockRegistry.
	var gone: bool = await _step_until(_frames_for_seconds(15.0), func() -> bool:
		return not _alive(spawned_id)
	)

	_check("e", (
		reason == PlacementRules.REASON_OUTSIDE_TERRITORY
		and spawned_one
		and launched
		and refed
		and gone
		and _registry.tracked_block_count() < tracked_before
	), "reason=%s spawned=%s launched=%s refed=%s killed=%s tracked %d->%d" % [
		reason, spawned_one, launched, refed, gone,
		tracked_before, _registry.tracked_block_count()
	])

	await _end_match()


# --- Match lifecycle ---------------------------------------------------------

func _start_match(goal_count: int) -> void:
	_field = (load("res://game/Field.tscn") as PackedScene).instantiate() as Field
	_field.map_def = MapDef.for_size(MAP_SIZE)
	add_child(_field)
	_blocks = Node3D.new()
	add_child(_blocks)
	_registry = BlockRegistry.new()
	add_child(_registry)

	Match.register_world(_field, _registry, _blocks)
	Match.start_match(_build_config(goal_count))
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


# --- Laying chains of blocks -------------------------------------------------

## Both slots march from their own home toward the other's, alternating turns,
## until neither can place any further. Collects the blocks each one laid.
func _march_pair(home_0: Vector2, home_1: Vector2, chain_0: Array[Block], chain_1: Array[Block]) -> void:
	var front: Array[Vector2] = [home_0, home_1]
	var target: Array[Vector2] = [home_1, home_0]
	# The first step comes off the home circle, which is much wider than a
	# single cube's; after that every front is a cube.
	var reach: Array[float] = [_tuning.home_radius, _tuning.home_radius]
	var chains: Array = [chain_0, chain_1]
	var stalled: Array[bool] = [false, false]
	for _step_index: int in range(MAX_MARCH_STEPS):
		if stalled[0] and stalled[1]:
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


## One slot marches toward `target` while the other passes its turns.
## `stop_at_target` ends the march as soon as the front reaches the target
## rather than when it runs out of room.
func _march_solo(
	slot_id: int, from: Vector2, target: Vector2, chain: Array[Block], stop_at_target: bool = false
) -> void:
	var front: Vector2 = from
	var reach: float = _tuning.home_radius
	for _step_index: int in range(MAX_MARCH_STEPS):
		if Match.state() != Match.State.PLAYING:
			return
		if stop_at_target and _owns_point(Match.team_of(slot_id), target):
			return
		var placed: Block = await _march_one(slot_id, front, reach, target)
		if placed == null:
			return
		chain.append(placed)
		front = _disk_local(placed.global_position)
		reach = _cube_reach()
		if stop_at_target and _owns_point(Match.team_of(slot_id), target):
			return
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
	var cell: float = _field.map_definition().cell_size
	return maxf(reach - _physics.cube_size * 0.5 - cell * 0.5 * sqrt(2.0), 0.0)


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


## Both players stack on the head of their chain, alternating turns, so the
## two front circles grow into each other. A hole one cell wide is barely
## wider than the block itself; a real contested overlap is a patch, and that
## is what criterion (b) needs to drop a block into.
func _raise_fronts(chain_0: Array[Block], chain_1: Array[Block]) -> void:
	var chains: Array = [chain_0, chain_1]
	var heights: Array[float] = [_physics.cube_size, _physics.cube_size]
	for _layer: int in range(FRONT_STACK_HEIGHT):
		for slot_id: int in range(PLAYER_COUNT):
			if Match.state() != Match.State.PLAYING:
				return
			var chain: Array[Block] = chains[slot_id]
			if chain.is_empty():
				continue
			heights[slot_id] += _physics.cube_size
			var head: Vector2 = _disk_local(chain[chain.size() - 1].global_position)
			var spot: Vector3 = _world_point(head, heights[slot_id] + PLACE_HEIGHT)
			_hold_cube(slot_id)
			if Match.preview_placement(slot_id, spot, 0, Quaternion.IDENTITY) != PlacementRules.Result.VALID:
				continue
			if _release(slot_id, spot) != PlacementRules.REASON_OK:
				continue
			await _step(SETTLE_FRAMES)


## Spends a slot's turn without building: releasing off the disk burns the
## block (owner decision 2) and hands the turn on.
func _pass_turn(slot_id: int) -> void:
	if Match.state() != Match.State.PLAYING or not Match.slot(slot_id).home_flag_alive:
		return
	_release(slot_id, _off_disk_point())
	await _step(1)


## Forces the held shape to a cube so the scenario's geometry is the same on
## every run, whatever the bag dealt. It has to run before preview_placement()
## too: the preview validates the *held* shape's footprint, so previewing a
## bar and then releasing a cube would ask about two different shapes.
func _hold_cube(slot_id: int) -> void:
	Match._held_shapes[slot_id] = _cube


## The placement intent Match would get from a player.
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


## Drops a bare block (not a placement — placing on a hole is refused) over a
## hole cell and reports whether it ended up below the disk surface.
func _drop_through_hole(holes: PackedInt32Array) -> bool:
	var grid: CellGrid = Match.raster().grid()
	for index: int in _interior_first(holes, grid):
		if not _field.is_hole_cell(index):
			continue
		var center: Vector2 = grid.index_center(index)
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
## Returns how many were removed.
func _cut_chain(chain: Array[Block]) -> int:
	if chain.size() < 4:
		return 0
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
## point out along +z belongs to neither player.
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
