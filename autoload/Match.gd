extends Node
## Match configuration and the host-side state machine (spec 3.7).
##
## Lobby -> Loading -> Countdown(3s) -> Playing -> (SuddenDeath) -> End -> Lobby.
## M2 implements Lobby, Loading, Countdown, Playing and End; SuddenDeath is
## M6.
##
## **This node is the authority.** Spec 3.4: "The host is authoritative, and
## only the host runs physics. Clients send intents. The host checks every
## intent before acting on it." Everything that decides an outcome lives here
## or in core/: the feed timers, the territory solve, the win check, and
## request_place(). Even in M2's hot-seat, where every player is local, the
## controllers do not spawn blocks themselves; they call request_place() and
## wait. M3a then only has to make request_place() reachable over an RPC,
## with no rule code to move.
##
## Signals are emitted on the Events bus rather than declared here, per
## CLAUDE.md's "use a global signal bus to decouple systems".

## Spec 3.7's states.
enum State { LOBBY, LOADING, COUNTDOWN, PLAYING, SUDDEN_DEATH, END }

## Spec 3.7: "Countdown(3s)". A fixed part of the state machine's shape, not a
## lobby setting (spec 2.8's table doesn't list it) — kept as a named constant
## here rather than in a Resource for the same reason
## BlockOrientations.ORIENTATION_COUNT is a const: it isn't tunable, it's the
## architecture (CLAUDE.md's "no magic numbers" targets tunables).
const COUNTDOWN_SECONDS: float = 3.0

## The config the running match was started with. A duplicate of whatever was
## handed to start_match(), never the shared config/match_defaults.tres.
var config: MatchConfig = null

var _physics_tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
var _territory_tuning: TerritoryTuning = preload("res://config/territory_tuning.tres")
var _block_feed_config: BlockFeedConfig = preload("res://config/block_feed.tres")

var _field: Field = null
var _registry: BlockRegistry = null
var _blocks_parent: Node3D = null

var _state: State = State.LOBBY
var _countdown_remaining: float = 0.0
var _countdown_last_whole: int = 0

var _slots: Array[PlayerSlot] = []
var _bags: Array[BlockBag] = []
var _held_shapes: Array[BlockShape] = []
var _feed_time_left: Array[float] = []
var _feed_expired: Array[bool] = []
var _active_slot: int = -1

var _cell_grid: CellGrid = null
var _raster: TerritoryRaster = null
var _solver: TerritorySolver = null
var _win_checker: WinChecker = null
var _last_groups: TerritoryGroups = null
var _solve_accum: float = 0.0


# --- Lifecycle --------------------------------------------------------------

## Hands Match the world it drives. Called once by Main after the scene is
## built, so nothing here ever walks the scene tree looking for its
## collaborators (CLAUDE.md). `registry` is game/BlockRegistry.gd, which
## tracks live blocks and their settled state; `blocks_parent` is where new
## blocks are added.
func register_world(field: Field, registry: Node, blocks_parent: Node3D) -> void:
	_field = field
	_registry = registry as BlockRegistry
	_blocks_parent = blocks_parent


## Lobby -> Loading -> Countdown -> Playing. Builds the player slots, the
## per-slot block bags, the solver, the raster and the win checker from
## `match_config`, then starts the countdown.
func start_match(match_config: MatchConfig) -> void:
	config = match_config.duplicate(true) as MatchConfig
	config.sanitize()
	_set_state(State.LOADING)

	_clear_blocks()
	_build_slots()
	_build_bags()
	_build_territory()
	if _registry != null:
		_registry.configure(_field, config.map_def())
		_registry.reset()

	_set_state(State.COUNTDOWN)
	_countdown_remaining = COUNTDOWN_SECONDS
	_countdown_last_whole = int(ceil(_countdown_remaining))
	Events.countdown_tick.emit(_countdown_last_whole)


## Back to Lobby from anywhere, clearing the field.
func abort_match() -> void:
	var old_state: State = _state
	_clear_blocks()
	_slots.clear()
	_bags.clear()
	_held_shapes.clear()
	_feed_time_left.clear()
	_feed_expired.clear()
	_active_slot = -1
	_cell_grid = null
	_raster = null
	_solver = null
	_win_checker = null
	_last_groups = null
	config = null
	_state = State.LOBBY
	Events.match_state_changed.emit(old_state, State.LOBBY)


func state() -> State:
	return _state


## Seconds left in the countdown, or 0.0 outside State.COUNTDOWN.
func countdown_remaining() -> float:
	return _countdown_remaining if _state == State.COUNTDOWN else 0.0


func _process(delta: float) -> void:
	match _state:
		State.COUNTDOWN:
			_tick_countdown(delta)
		State.PLAYING:
			_tick_feed(delta)
			_tick_territory(delta)
		_:
			pass


func _tick_countdown(delta: float) -> void:
	_countdown_remaining = maxf(_countdown_remaining - delta, 0.0)
	var whole: int = int(ceil(_countdown_remaining))
	if whole < _countdown_last_whole:
		_countdown_last_whole = whole
		Events.countdown_tick.emit(whole)
	if _countdown_remaining <= 0.0:
		_begin_playing()


func _begin_playing() -> void:
	_set_state(State.PLAYING)
	_active_slot = _next_alive_slot(-1)
	for i: int in range(_slots.size()):
		_issue_next_block(i)
		_feed_time_left[i] = config.block_timer
		_feed_expired[i] = false
	if _active_slot != -1:
		Events.turn_changed.emit(_active_slot)


# --- Slots and teams --------------------------------------------------------

func slot_count() -> int:
	return _slots.size()


func slot(slot_id: int) -> PlayerSlot:
	if slot_id < 0 or slot_id >= _slots.size():
		return null
	return _slots[slot_id]


func team_of(slot_id: int) -> int:
	var target: PlayerSlot = slot(slot_id)
	return target.team_id if target != null else -1


## Hot-seat: the slot whose turn it is. Outside hot-seat this is the local
## player's slot, and every slot acts at once.
func active_slot() -> int:
	return _active_slot


## Hot-seat: hands the turn to the next slot. Called after a placement
## resolves, not by input.
func advance_turn() -> void:
	if not config.hot_seat:
		return
	var next_slot: int = _next_alive_slot(_active_slot)
	_active_slot = next_slot
	if next_slot == -1:
		return
	_feed_time_left[next_slot] = config.block_timer
	_feed_expired[next_slot] = false
	Events.turn_changed.emit(next_slot)


func _next_alive_slot(after: int) -> int:
	var count: int = _slots.size()
	if count == 0:
		return -1
	for step: int in range(1, count + 1):
		var candidate: int = (after + step) % count
		if _slots[candidate].home_flag_alive:
			return candidate
	return -1


# --- Block feed (spec 2.4, 3.7) ---------------------------------------------

## The shape `slot_id` is holding right now, or null between blocks.
func held_shape(slot_id: int) -> BlockShape:
	if slot_id < 0 or slot_id >= _held_shapes.size():
		return null
	return _held_shapes[slot_id]


## What the HUD's next-block preview shows for `slot_id`.
func next_shape(slot_id: int) -> BlockShape:
	if slot_id < 0 or slot_id >= _bags.size():
		return null
	var preview: Array[BlockShape] = _bags[slot_id].peek(1)
	return preview[0] if preview.size() > 0 else null


## Seconds left on the slot's block timer (spec 2.8: 3-12 s, default 6).
func feed_time_left(slot_id: int) -> float:
	if slot_id < 0 or slot_id >= _feed_time_left.size():
		return 0.0
	return _feed_time_left[slot_id]


## feed_time_left / config.block_timer, 1 -> 0, for the HUD's timer ring.
func feed_progress(slot_id: int) -> float:
	if config == null or config.block_timer <= 0.0:
		return 0.0
	return clampf(feed_time_left(slot_id) / config.block_timer, 0.0, 1.0)


func _issue_next_block(slot_id: int) -> void:
	var bag: BlockBag = _bags[slot_id]
	var shape: BlockShape = bag.next()
	_held_shapes[slot_id] = shape
	var preview: Array[BlockShape] = bag.peek(1)
	var next_id: StringName = preview[0].id if preview.size() > 0 else &""
	Events.feed_block_issued.emit(slot_id, shape.id if shape != null else &"", next_id)


func _tick_feed(delta: float) -> void:
	if config.hot_seat:
		if _active_slot == -1:
			return
		if not _slots[_active_slot].home_flag_alive:
			advance_turn()
			return
		_feed_time_left[_active_slot] = maxf(_feed_time_left[_active_slot] - delta, 0.0)
		if _feed_time_left[_active_slot] <= 0.0 and not _feed_expired[_active_slot]:
			_feed_expired[_active_slot] = true
			Events.feed_timer_expired.emit(_active_slot)
	else:
		for i: int in range(_slots.size()):
			if not _slots[i].home_flag_alive:
				continue
			_feed_time_left[i] = maxf(_feed_time_left[i] - delta, 0.0)
			if _feed_time_left[i] <= 0.0 and not _feed_expired[i]:
				_feed_expired[i] = true
				Events.feed_timer_expired.emit(i)


# --- The one authoritative entry point (spec 3.4) ---------------------------

## Every placement in the game goes through here, local or remote. `origin` is
## the world position the block's local origin would sit at, `orientation_index`
## the BlockOrientations index and `free_quat` the free rotation layered on it
## (spec 2.5). `auto_drop` is true when the slot's timer ran out rather than
## the player clicking, which is the only case where the host relocates the
## block to the closest valid point instead of rejecting it (spec 2.5).
##
## Returns PlacementRules.REASON_OK on success, otherwise the REASON_* that
## explains the refusal, which is also emitted as Events.placement_rejected.
## A refused *deliberate* placement still spawns the block and throws it off
## the map (spec 2.2); a refused auto-drop that finds no valid point does the
## same.
##
## M3a adds `@rpc("any_peer", "call_remote", "reliable")` to a thin wrapper
## that forwards to this, checks the caller's peer id against the slot, and
## changes nothing else.
func request_place(
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	auto_drop: bool
) -> StringName:
	if _state != State.PLAYING or _field == null or _blocks_parent == null:
		return PlacementRules.REASON_NO_BLOCK
	if slot_id < 0 or slot_id >= _slots.size():
		return PlacementRules.REASON_NO_BLOCK
	var acting_slot: PlayerSlot = _slots[slot_id]
	if not acting_slot.home_flag_alive:
		return PlacementRules.REASON_NO_BLOCK
	if config.hot_seat and slot_id != _active_slot:
		return PlacementRules.REASON_NOT_YOUR_TURN
	var shape: BlockShape = _held_shapes[slot_id]
	if shape == null:
		return PlacementRules.REASON_NO_BLOCK

	var basis: Basis = Basis(free_quat) * BlockOrientations.get_basis(orientation_index)
	var local_origin: Vector3 = _field.to_local(origin)
	var disk_origin: Vector2 = Vector2(local_origin.x, local_origin.z)
	var cube_size: float = _physics_tuning.cube_size

	var footprint: PackedInt32Array = PlacementRules.footprint_cells(
		shape.cells, basis, disk_origin, cube_size, _cell_grid
	)
	var team_id: int = acting_slot.team_id
	var result: PlacementRules.Result = PlacementRules.validate(footprint, _raster, team_id)

	var relocated: Vector2 = PlacementRules.NO_ORIGIN
	if result != PlacementRules.Result.VALID and auto_drop:
		relocated = PlacementRules.closest_valid_origin(
			disk_origin, shape.cells, basis, cube_size, _cell_grid, _raster, team_id, _territory_tuning
		)
	var outcome: Dictionary = _resolve_outcome(result, auto_drop, relocated)
	var reason: StringName = outcome["reason"]
	var final_disk_origin: Vector2 = relocated if outcome["use_relocation"] else disk_origin

	var final_world_origin: Vector3 = _field.to_global(
		Vector3(final_disk_origin.x, local_origin.y, final_disk_origin.y)
	)
	var spawned: Block = _spawn_block(shape, final_world_origin, basis, slot_id)
	if reason != PlacementRules.REASON_OK:
		# Owner decision (docs/M2_PLAN.md, "Invalid release — burn the block"):
		# any release on an invalid spot, deliberate or auto-drop, spawns the
		# block and throws it off the map; the block is still consumed either
		# way (spec 2.2).
		_burn_block(spawned, final_disk_origin)
		Events.placement_rejected.emit(slot_id, reason)

	_consume_and_refeed(slot_id)
	if config.hot_seat:
		advance_turn()

	return reason


## Pure decision step factored out of request_place() so it can be unit-tested
## against manufactured PlacementRules.Result / relocation values without a
## working P1 territory solve (docs/M2_PLAN.md's P2 brief: "use fakes/stubs
## for territory results — the P1 stubs exist and compile"). `initial_result`
## is what validate() said about the desired spot; `relocated` is what
## closest_valid_origin() found (or PlacementRules.NO_ORIGIN), already
## computed by the caller since that search itself needs a real raster.
##
## Returns {"reason": StringName, "use_relocation": bool}: the reason
## request_place() should return, and whether the block should land at
## `relocated` (true) or stay at the original spot and be thrown off the map
## (false, with reason != REASON_OK) — spec 2.2's "burn the block" rule
## (docs/M2_PLAN.md owner decision 2): any release on an invalid spot burns
## the block; auto-drop gets one relocation attempt first.
func _resolve_outcome(
	initial_result: PlacementRules.Result, auto_drop: bool, relocated: Vector2
) -> Dictionary:
	if initial_result == PlacementRules.Result.VALID:
		return {"reason": PlacementRules.REASON_OK, "use_relocation": false}
	if auto_drop and not PlacementRules.is_no_origin(relocated):
		return {"reason": PlacementRules.REASON_OK, "use_relocation": true}
	return {"reason": PlacementRules.reason_for(initial_result), "use_relocation": false}


## Dry run of request_place()'s territory check, for the ghost's valid/red/
## hatched tint (spec 2.5). Costs one footprint build plus one validate, so it
## is safe to call every frame.
func preview_placement(
	slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion
) -> PlacementRules.Result:
	if _state != State.PLAYING or _cell_grid == null or _raster == null or _field == null:
		return PlacementRules.Result.EMPTY
	if slot_id < 0 or slot_id >= _slots.size():
		return PlacementRules.Result.EMPTY
	var shape: BlockShape = _held_shapes[slot_id]
	if shape == null:
		return PlacementRules.Result.EMPTY

	var basis: Basis = Basis(free_quat) * BlockOrientations.get_basis(orientation_index)
	var local_origin: Vector3 = _field.to_local(origin)
	var disk_origin: Vector2 = Vector2(local_origin.x, local_origin.z)
	var footprint: PackedInt32Array = PlacementRules.footprint_cells(
		shape.cells, basis, disk_origin, _physics_tuning.cube_size, _cell_grid
	)
	return PlacementRules.validate(footprint, _raster, _slots[slot_id].team_id)


func _spawn_block(shape: BlockShape, world_origin: Vector3, basis: Basis, slot_id: int) -> Block:
	var block: Block = BlockFactory.build(shape, _physics_tuning, slot_id)
	_blocks_parent.add_child(block)
	block.global_transform = Transform3D(basis, world_origin)
	Events.block_placed.emit(block, shape.id)
	return block


## Spec 2.2: a rejected block "is thrown off the map with a visible reject
## animation". Impulse points radially outward from the disk center, blended
## with an upward component (TerritoryTuning.reject_impulse /
## reject_upward_fraction) so it visibly launches rather than just sliding.
func _burn_block(block: Block, disk_origin: Vector2) -> void:
	if block == null:
		return
	var outward: Vector2 = disk_origin.normalized() if disk_origin.length() > 0.001 else Vector2.RIGHT
	var horizontal_world: Vector3 = (_field.global_transform.basis * Vector3(outward.x, 0.0, outward.y)).normalized()
	var up_fraction: float = clampf(_territory_tuning.reject_upward_fraction, 0.0, 1.0)
	var impulse_dir: Vector3 = horizontal_world * (1.0 - up_fraction) + Vector3.UP * up_fraction
	if impulse_dir.length() > 0.001:
		impulse_dir = impulse_dir.normalized()
	block.apply_central_impulse(impulse_dir * _territory_tuning.reject_impulse)


func _consume_and_refeed(slot_id: int) -> void:
	_issue_next_block(slot_id)
	_feed_time_left[slot_id] = config.block_timer
	_feed_expired[slot_id] = false


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


## Tallest point any of this slot's settled blocks reaches above the disk, in
## meters. Spec 2.10's HUD shows it as a number.
func max_height_for_slot(slot_id: int) -> float:
	return _registry.max_height_for_slot(slot_id) if _registry != null else 0.0


func _build_slots() -> void:
	_slots.clear()
	var map_def: MapDef = config.map_def()
	for i: int in range(config.player_count):
		var color: Color = config.player_colors[i % config.player_colors.size()]
		var home: Vector2 = PlayerSlot.home_position_for(i, config.player_count, map_def)
		_slots.append(PlayerSlot.new(i, config.team_of_slot(i), "Player %d" % (i + 1), color, home))

	_held_shapes.resize(_slots.size())
	_feed_time_left.resize(_slots.size())
	_feed_expired.resize(_slots.size())
	for i: int in range(_slots.size()):
		_held_shapes[i] = null
		_feed_time_left[i] = config.block_timer
		_feed_expired[i] = false


func _build_bags() -> void:
	_bags.clear()
	for i: int in range(_slots.size()):
		# DECISION (autoload/Match.gd): MatchConfig has one rng_seed for the
		# whole match; each slot's bag needs its own seed so slots don't deal
		# identical sequences. Spread deterministically from the match seed
		# with a large odd stride so per-slot seeds don't collide for any
		# player_count in spec 2.8's 2-8 range.
		var seed: int = -1
		if config.rng_seed >= 0:
			seed = config.rng_seed + i * 1000003
		_bags.append(BlockBag.new(_block_feed_config, seed))


func _build_territory() -> void:
	var map_def: MapDef = config.map_def()
	_cell_grid = CellGrid.new(map_def.field_radius, map_def.cell_size)
	_raster = TerritoryRaster.new(_cell_grid, _territory_tuning)
	_raster.reset()
	_solver = TerritorySolver.new(_territory_tuning)
	var goal_positions: PackedVector2Array = PlayerSlot.goal_positions_for(config.goal_flag_count, map_def)
	_win_checker = WinChecker.new(goal_positions, _territory_tuning.capture_hold)
	_last_groups = null
	_solve_accum = 0.0


func _clear_blocks() -> void:
	if _blocks_parent == null:
		return
	for child: Node in _blocks_parent.get_children():
		child.queue_free()


func _tick_territory(delta: float) -> void:
	if _raster == null or _solver == null:
		return
	_solve_accum += delta
	var step: float = 1.0 / maxf(_territory_tuning.solve_hz, 0.001)
	while _solve_accum >= step:
		_solve_accum -= step
		_run_territory_step(step)


func _run_territory_step(delta: float) -> void:
	var circles: Array[InfluenceCircle] = _collect_circles()
	var groups: TerritoryGroups = _solver.solve(circles)
	_last_groups = groups
	_raster.update(circles, groups, delta, config.hole_mode == MatchConfig.HoleMode.PERMANENT)
	_win_checker.update(_raster, delta)

	Events.territory_updated.emit(_raster, groups)

	var opened: PackedInt32Array = _raster.holes_opened()
	var closed: PackedInt32Array = _raster.holes_closed()
	if opened.size() > 0 or closed.size() > 0:
		Events.hole_cells_changed.emit(opened, closed)
		if opened.size() > 0:
			_check_home_flags(opened)

	var shares: PackedFloat32Array = PackedFloat32Array()
	for t: int in range(config.team_count()):
		shares.append(_raster.team_share(t))
	Events.territory_share_changed.emit(shares)

	Events.goal_capture_progress.emit(_win_checker.capturing_team(), _win_checker.capture_progress())

	if _state == State.PLAYING and _win_checker.winner() != WinChecker.NO_TEAM:
		_finish_match(_win_checker.winner())


func _collect_circles() -> Array[InfluenceCircle]:
	var circles: Array[InfluenceCircle] = []
	for slot_item: PlayerSlot in _slots:
		if not slot_item.home_flag_alive:
			continue
		circles.append(
			InfluenceCircle.for_home(slot_item.home_position, slot_item.team_id, slot_item.slot_id, _territory_tuning)
		)
	if _registry != null:
		circles.append_array(_registry.influence_circles(_slots, _territory_tuning, config.map_def()))
	return circles


## Owner decision (docs/M2_PLAN.md, "Home flag lost to a hole"): a hole
## opening under a slot's home flag eliminates it — home_flag_alive goes
## false, its circles unanchor (P1's TerritorySolver drops them next solve
## since they no longer connect to a home circle), it gets no more feed, and
## the win check ignores it. If that leaves one player/team standing, the
## match ends right here.
func _check_home_flags(opened: PackedInt32Array) -> void:
	var opened_set: Dictionary = {}
	for cell: int in opened:
		opened_set[cell] = true

	for slot_item: PlayerSlot in _slots:
		if not slot_item.home_flag_alive:
			continue
		var coords: Vector2i = _cell_grid.world_to_cell(slot_item.home_position)
		if not _cell_grid.in_bounds(coords.x, coords.y):
			continue
		if opened_set.has(_cell_grid.cell_index(coords.x, coords.y)):
			slot_item.home_flag_alive = false
			Events.player_eliminated.emit(slot_item.slot_id, slot_item.team_id)

	_check_last_team_standing()


func _check_last_team_standing() -> void:
	if _state != State.PLAYING:
		return
	var alive_teams: Dictionary = {}
	for slot_item: PlayerSlot in _slots:
		if slot_item.home_flag_alive:
			alive_teams[slot_item.team_id] = true
	if alive_teams.size() == 1:
		_finish_match(alive_teams.keys()[0])


func _finish_match(winning_team: int) -> void:
	_set_state(State.END)
	Events.match_won.emit(winning_team)


func _set_state(new_state: State) -> void:
	var old_state: State = _state
	_state = new_state
	Events.match_state_changed.emit(old_state, new_state)
