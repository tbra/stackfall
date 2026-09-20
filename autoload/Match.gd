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

## Bontago-mv0.1.11, revised Bontago-mv0.2.6 (independent-review finding C):
## how far inside Field's kill-plane box a burned block's spawn point is kept,
## as a fraction of the box's half-extent. _burn_block() then adds an outward
## impulse (TerritoryTuning.reject_impulse / reject_upward_fraction) before
## the body falls through kill_plane_y, so the clamp must leave enough slack
## for that impulse's own horizontal travel, not just spawn the body inside
## the box.
##
## DECISION (autoload/Match.gd, Bontago-mv0.2.6): 0.9 left only
## `field_radius` (30-60 m across the shipped maps) of slack to the box edge.
## reject_impulse=30 on a mass-1 block with reject_upward_fraction=0.35 gives
## a horizontal launch speed of impulse * (1 - up_fraction) / sqrt((1 -
## up_fraction)^2 + up_fraction^2) ~= 26 m/s and enough hang time falling to
## kill_plane_y (-40) to travel roughly field_radius*2 outward -- more than
## the old margin's slack, so a maximally clamped hostile burn could exit the
## box footprint before it ever reached kill_plane_y and free-fall forever
## (see this file's own request_place() comment on the leaked-RigidBody3D
## failure this clamp exists to prevent). Halving the margin to 0.5 (clamp
## radius = half the box half-extent) makes the reserved slack equal to the
## clamp radius itself (>= 150 m on the smallest map), comfortably above the
## worst-case impulse travel above, without touching _burn_block()'s impulse
## for a legitimate near-disk burn (docs/M2_PLAN.md owner decision 2) --
## proven by tests/unit/test_match_flow.gd's
## test_repro_burn_clamp_margin_lets_a_maximally_clamped_burn_escape_the_kill_plane.
const _BURN_CLAMP_MARGIN: float = 0.5

## The config the running match was started with. A duplicate of whatever was
## handed to start_match(), never the shared config/match_defaults.tres.
var config: MatchConfig = null

var _physics_tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
var _territory_tuning: TerritoryTuning = preload("res://config/territory_tuning.tres")
var _block_feed_config: BlockFeedConfig = preload("res://config/block_feed.tres")
var _net_config: NetConfig = preload("res://config/net_config.tres")

## DECISION (autoload/Match.gd): Net is a plain autoload, and GUT cannot
## double one (see game/PlayerController.gd's matching DECISION), so every
## host gate below reads through this seam instead of naming `Net` directly.
## null means "the real Net", which is what every shipped build uses; a test
## injects a double with set_net_provider(). Net.is_host() is true offline
## too, so `if not _is_host(): return` changes nothing about M2's hot-seat.
var _net_provider: Variant = null

## Set by net/MatchNet.gd in its own _ready(). Match never calls rpc() and
## never names MatchNet as a global (the integrator registers that autoload
## after this one), so replication is a hook the membrane installs on itself:
## null means "not networked", which is exactly the M2 and single-player case.
var _replicator: Variant = null

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

## Spec 3.4 / docs/M3a_PLAN.md, "Never duplicated, never lost": one counter
## per slot, advanced every time the slot's held block is consumed. An intent
## carries the value its sender last saw; the host refuses one that is no
## longer current, so a replayed, doubled or raced intent is a no-op instead
## of silently spending the next block.
var _feed_seq: Array[int] = []

## Slots whose peer has vanished and whose NetConfig.disconnect_grace is still
## running: the feed is stopped and the timer is not ticking, but the slot is
## still alive and its towers still hold territory. Parallel to _slots;
## negative means "connected".
var _disconnect_grace_left: Array[float] = []

## Blocks _spawn_block() has built since the match started. The acceptance
## harness asserts blocks_spawned() == sum(intents_accepted) + auto_drops
## across the session (docs/M3a_PLAN.md, "Proving placements are never
## duplicated or lost").
var _blocks_spawned: int = 0

## Lazily built id -> BlockShape index, used only by the client read model.
var _shapes_by_id: Dictionary = {}

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
	if _registry != null:
		# Spec 3.4: only the host simulates. A client's registry must not hand
		# out net_ids of its own — the host's are the only ones that mean
		# anything — and must not run the settled rule over frozen bodies.
		_registry.set_host_authority(_is_host())


## The BlockRegistry and the node new blocks are added under, for
## net/MatchNet.gd's replicated spawns. Nothing else should reach for these:
## rules go through request_place().
func registry() -> BlockRegistry:
	return _registry


func blocks_parent() -> Node3D:
	return _blocks_parent


func field() -> Field:
	return _field


## Test seam for the Net autoload (see _net_provider). Passing null restores
## the real Net.
func set_net_provider(provider: Variant) -> void:
	_net_provider = provider


## Installed by net/MatchNet.gd. `replicator` must answer replicate_spawn(),
## replicate_match_event() and replicate_match_start(); null turns replication
## off, which is the single-player and unit-test case.
func set_replicator(replicator: Variant) -> void:
	_replicator = replicator


## net/MatchNet.gd, or null in a build with no networking. This is how a
## scene node reaches the membrane without naming an autoload the integrator
## registers after this one — and without a get_node("/root/...") path
## (CLAUDE.md).
func replicator() -> Variant:
	return _replicator


## True on the host **and offline** (Net.is_host()'s contract), so every gate
## written against it leaves M2's single-PC behaviour exactly as it was.
func _is_host() -> bool:
	if _net_provider != null:
		return bool(_net_provider.is_host())
	return Net.is_host()


## Lobby -> Loading -> Countdown -> Playing. Builds the player slots, the
## per-slot block bags, the solver, the raster and the win checker from
## `match_config`, then starts the countdown.
##
## Legal from **any** state, on the host and on a client alike (a client's
## copy is called by net/MatchNet.gd's net_match_start with whatever state
## its mirror was left in). A start from anything but LOBBY first goes back
## through the lobby -- abort_match(), which emits (old -> LOBBY) so every
## consumer tears the previous match down -- so the transition consumers see
## for a genuine start is always exactly LOBBY -> LOADING (spec 3.7's
## `End -> Lobby -> Loading`), never PLAYING -> LOADING. A start from LOBBY
## still resets every per-match scalar silently: a client mirror sits in
## LOBBY with the previous match's slots and feed state after the host's
## replicated LOBBY change, and nothing of that may leak into the new match.
##
## **LOADING is emitted only once the world model is complete.** Main builds
## the match world synchronously inside that emit -- Field.set_overlay_source
## (Match.raster()), Field.place_flags(config), SnapshotSync.begin_match
## (Match.registry(), config.map_def()) -- so the raster, the slots and the
## configured registry must all exist before the signal goes out; emitting
## first and building afterwards handed those consumers a null raster (Beads
## Bontago-mv0.1.9). Nothing in the build reads _state, so building while
## still LOBBY costs nothing.
func start_match(match_config: MatchConfig) -> void:
	# DECISION (autoload/Match.gd): a repeated or stale start is handled here
	# rather than by every caller (the Lobby, net_match_start, the tests, a
	# future rematch button): Match owns its state machine, so it is Match
	# that guarantees the sequence consumers can rely on.
	if _state != State.LOBBY:
		abort_match()
	else:
		_reset_match_state()

	config = match_config.duplicate(true) as MatchConfig
	config.sanitize()

	_clear_blocks()
	_build_slots()
	_build_bags()
	_build_territory()
	_blocks_spawned = 0
	if _registry != null:
		_registry.set_host_authority(_is_host())
		_registry.configure(_field, config.map_def())
		_registry.reset()

	_set_state(State.LOADING)

	_set_state(State.COUNTDOWN)
	_countdown_remaining = COUNTDOWN_SECONDS
	_countdown_last_whole = int(ceil(_countdown_remaining))
	Events.countdown_tick.emit(_countdown_last_whole)


## Back to Lobby from anywhere, clearing the field. Emits (old -> LOBBY) even
## from LOBBY itself: callers that want silence check state() first
## (game/Main.gd does), and the emit is what tells every consumer -- Main's
## world, RemoteCursors, MatchNet's start flag -- that the match is over.
func abort_match() -> void:
	var old_state: State = _state
	_reset_match_state()
	_state = State.LOBBY
	Events.match_state_changed.emit(old_state, State.LOBBY)


## Everything one match owns, back to the empty state: blocks, slots, bags,
## feed and grace timers, the territory objects and the config. Shared by
## abort_match() and start_match() so neither can forget a field the other
## resets. Leaves _state alone -- the two callers differ only in what they
## emit about it.
func _reset_match_state() -> void:
	_clear_blocks()
	_slots.clear()
	_bags.clear()
	_held_shapes.clear()
	_feed_time_left.clear()
	_feed_expired.clear()
	_feed_seq.clear()
	_disconnect_grace_left.clear()
	_blocks_spawned = 0
	_active_slot = -1
	_countdown_remaining = 0.0
	_countdown_last_whole = 0
	_cell_grid = null
	_raster = null
	_solver = null
	_win_checker = null
	_last_groups = null
	_solve_accum = 0.0
	config = null


func state() -> State:
	return _state


## Seconds left in the countdown, or 0.0 outside State.COUNTDOWN.
func countdown_remaining() -> float:
	return _countdown_remaining if _state == State.COUNTDOWN else 0.0


## Spec 3.4: "The host is authoritative ... only the host runs physics." Every
## clock that decides something — the countdown, the feed timers and their
## auto-drops, the 10 Hz territory solve, the win check and the disconnect
## grace — runs here and only on the host. A client's copy of Match is a
## read model: it holds the slots, the config and a mirror raster so its HUD
## and its ghost's territory tint are right, and it is driven entirely by
## net/MatchNet.gd's replicated events.
func _process(delta: float) -> void:
	if not _is_host():
		_tick_client_display(delta)
		return
	match _state:
		State.COUNTDOWN:
			_tick_countdown(delta)
		State.PLAYING:
			_tick_disconnect_grace(delta)
			_tick_feed(delta)
			_tick_territory(delta)
		_:
			pass


## DECISION (autoload/Match.gd): docs/M3a_PLAN.md says a client runs "no feed
## tick", meaning it decides nothing — but with no local decrement at all the
## HUD's timer ring would sit frozen between the host's 1-per-block feed
## events, which reads as a bug. So a client counts the same timers down for
## display only: it never emits feed_timer_expired, never issues a block and
## never touches the bag, and every replicated feed event resets the timer to
## the host's value, so it cannot drift. Nothing here can duplicate or lose a
## placement, which is what the gate above exists to guarantee.
func _tick_client_display(delta: float) -> void:
	if _state != State.PLAYING or config == null:
		return
	for i: int in range(_feed_time_left.size()):
		if not _slots[i].home_flag_alive:
			continue
		_feed_time_left[i] = maxf(_feed_time_left[i] - delta, 0.0)


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
	# The home circles exist from the first frame of play (spec 2.2), so the
	# raster must too: without this seeding solve the first 1/solve_hz second
	# of the match has an empty raster and every placement — even one right on
	# your own home flag — reads OUTSIDE_TERRITORY. delta is 0.0 so no
	# contested time accrues and no hole can open on the seeding step.
	if _raster != null and _solver != null:
		_run_territory_step(0.0)


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
	if not _is_host():
		return
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
		# Owner decision (docs/M3a_PLAN.md question 1): per-player concurrent
		# timers, spec 3.7's default ("Each player has a feed timer"). Every
		# slot's timer runs at once and several blocks may land in the same
		# second; nothing here serialises them.
		for i: int in range(_slots.size()):
			if not _slots[i].home_flag_alive:
				continue
			if _disconnect_grace_left[i] >= 0.0:
				# The peer vanished: its feed stops the moment it does
				# (docs/M3a_PLAN.md, "Disconnects and the in-flight held
				# block") so a player who reconnects inside the grace period
				# has not been auto-dropped a tower's worth of blocks.
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
## M3a wraps this in net/MatchNet.gd's `@rpc("any_peer", "call_remote",
## "reliable")` intent, which checks the caller's peer id against `slot_id`
## and changes nothing else. `feed_seq` is the value of feed_seq(slot_id) the
## caller last saw; -1 means "don't check", which is what every M2 call site
## passes by omitting it. A value that is not current means the intent is a
## replay, a double click inside one round trip, or a race with an auto-drop,
## and is refused with REASON_NO_BLOCK — the whole of docs/M3a_PLAN.md's
## "Never duplicated, never lost" defence (1).
##
## The -1 sentinel is a courtesy for **trusted local callers only**: the M2
## controllers, the host's own timer and the tests. It never arrives here from
## the wire — net/MatchNet.gd refuses any negative remote feed_seq before
## calling in — because a client that could quote -1 would opt out of defence
## (1) altogether.
##
## A pose that cannot be evaluated at all (a non-finite origin, a free
## quaternion that is not a finite unit rotation, or an orientation index
## outside BlockOrientations' table) is refused with REASON_NO_BLOCK before
## anything is touched. That is not a rule — the ghost can never produce such
## a pose — but the authority's own guard against corrupt or hostile input
## (spec 3.4: "The host checks every intent before acting on it"); MatchNet
## refuses the same poses at the wire so they are normally never seen here.
func request_place(
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	auto_drop: bool,
	feed_seq: int = -1
) -> StringName:
	# Spec 3.4: the host decides every placement. A client that somehow got
	# here locally must not spawn anything; it waits for the host's spawn.
	if not _is_host():
		return PlacementRules.REASON_NO_BLOCK
	if _state != State.PLAYING or _field == null or _blocks_parent == null:
		return PlacementRules.REASON_NO_BLOCK
	if slot_id < 0 or slot_id >= _slots.size():
		return PlacementRules.REASON_NO_BLOCK
	if feed_seq >= 0 and feed_seq != _feed_seq[slot_id]:
		return PlacementRules.REASON_NO_BLOCK
	var acting_slot: PlayerSlot = _slots[slot_id]
	if not acting_slot.home_flag_alive:
		return PlacementRules.REASON_NO_BLOCK
	if config.hot_seat and slot_id != _active_slot:
		return PlacementRules.REASON_NOT_YOUR_TURN
	var shape: BlockShape = _held_shapes[slot_id]
	if shape == null:
		return PlacementRules.REASON_NO_BLOCK
	if not is_pose_well_formed(origin, orientation_index, free_quat):
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
	if reason != PlacementRules.REASON_OK:
		# Bontago-mv0.1.11: this is the burn path (docs/M2_PLAN.md owner
		# decision 2 below) and disk_origin is whatever the caller asked
		# for -- for a remote intent, a finite-but-arbitrary point (spec 3.4:
		# "The host checks every intent before acting on it"; is_pose_well_
		# formed() above only refuses non-finite poses, not far-off-disk
		# ones, since the ghost itself can produce those close to the edge).
		# Left unclamped, a block spawns and is thrown from that raw point,
		# lands outside Field's kill plane, and free-falls forever: a leaked
		# RigidBody3D plus permanent snapshot traffic for it (Field.gd's
		# _build_kill_plane, not owned here, sizes the box at
		# map_def.field_radius * Field.KILL_PLANE_RADIUS_FACTOR).
		final_disk_origin = _clamp_disk_origin_for_burn(final_disk_origin)

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


## Whether a pose can be evaluated at all: a finite origin, a free quaternion
## that is a finite unit rotation (Basis(q) of anything else is a scaled or
## NaN matrix, and the footprint built from it is garbage), and an orientation
## index inside BlockOrientations' 24-entry table (get_basis() does not check;
## see BlockOrientations.is_valid_index). Pure and cheap, so request_place()
## and preview_placement() both call it on every pose. Height is deliberately
## not judged here: the allowed band is a wire concern (what a snapshot can
## carry) and lives at net/MatchNet.gd's boundary, so that the host's own
## ghost — exact by construction — is never second-guessed.
func is_pose_well_formed(origin: Vector3, orientation_index: int, free_quat: Quaternion) -> bool:
	if not origin.is_finite():
		return false
	if not free_quat.is_finite() or not free_quat.is_normalized():
		return false
	return BlockOrientations.is_valid_index(orientation_index)


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
	if not is_pose_well_formed(origin, orientation_index, free_quat):
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
	# block_placed is what makes BlockRegistry allocate the net_id, so the
	# replication below has to come after it: the reliable spawn RPC must
	# carry the same id the (unreliable) snapshots will address the body by.
	Events.block_placed.emit(block, shape.id)
	_blocks_spawned += 1
	if _replicator != null:
		_replicator.replicate_spawn(block, block.net_id)
	return block


## Blocks this instance has spawned since the match started. The M3a
## acceptance harness asserts this equals the sum of accepted intents plus
## auto-drops (docs/M3a_PLAN.md).
func blocks_spawned() -> int:
	return _blocks_spawned


## Keeps a burn's disk-local spawn point (x/z only, in Field's local space)
## inside Field's kill plane, so a body that gets thrown off never free-falls
## past it (Bontago-mv0.1.11). Preserves direction and only shortens the
## vector, so an on-disk or near-disk burn (the overwhelming common case) is
## returned unchanged -- this only ever fires for the far-off-disk case a
## hostile or buggy client can still produce.
##
## DECISION (autoload/Match.gd): the safe radius is derived from Field's own
## KILL_PLANE_RADIUS_FACTOR constant (the one _build_kill_plane() already
## uses to size the box) times this match's own map_def.field_radius, rather
## than a new literal or MapDef tunable here, so Match's clamp and Field's
## box can never drift apart. Field.gd is not owned by this package; if that
## constant ever needs to become a per-map tunable, MapDef is the right home
## for it and both Field._build_kill_plane() and this function should read
## it from there instead (follow-up, not done here).
func _clamp_disk_origin_for_burn(disk_origin: Vector2) -> Vector2:
	if _field == null or _field.map_def == null:
		return disk_origin
	var half_extent: float = (
		_field.map_def.field_radius * Field.KILL_PLANE_RADIUS_FACTOR * 0.5 * _BURN_CLAMP_MARGIN
	)
	return disk_origin.limit_length(half_extent)


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
	# The sequence advances before the new block is issued, so the
	# feed_block_issued that tells the owner "you have a block" already
	# carries the sequence its next intent must quote.
	_feed_seq[slot_id] += 1
	_issue_next_block(slot_id)
	_feed_time_left[slot_id] = config.block_timer
	_feed_expired[slot_id] = false


## The value an intent for `slot_id` must quote to be accepted right now. It
## advances on every consumed block, so exactly one intent can spend any one
## held block (docs/M3a_PLAN.md, "Never duplicated, never lost").
func feed_seq(slot_id: int) -> int:
	if slot_id < 0 or slot_id >= _feed_seq.size():
		return -1
	return _feed_seq[slot_id]


## Where a slot's block goes when its timer expires and the host has never
## heard a cursor from it — a peer that has not moved its ghost once. Spec
## 2.5's auto-drop [ORIGINAL] drops "from its current ghost position", and
## with no ghost known the slot's own home flag is the honest stand-in;
## PlacementRules.closest_valid_origin() relocates from there as usual.
func default_ghost_origin(slot_id: int) -> Vector3:
	var target: PlayerSlot = slot(slot_id)
	if target == null or _field == null:
		return Vector3.ZERO
	return _field.to_global(Vector3(target.home_position.x, 0.0, target.home_position.y))


# --- Disconnects (docs/M3a_PLAN.md question 2) ------------------------------

## Host only. The peer holding `slot_id` vanished: stop its feed at once and
## start NetConfig.disconnect_grace. If it has not come back by then the slot
## is eliminated exactly as a lost home flag does it — home_flag_alive goes
## false, Events.player_eliminated fires, its towers unanchor and lose their
## influence on the next solve, and the match ends if one player or team is
## left standing.
##
## Its held block needs no cleanup: a held block is a ghost, drawn only on its
## owner's screen and held here as a BlockShape, so there is nothing in the
## physics world to tidy. An intent already in flight is refused by
## net/MatchNet.gd's peer check, its sender no longer holding a slot.
func on_peer_left(slot_id: int) -> void:
	if not _is_host():
		return
	if slot_id < 0 or slot_id >= _slots.size():
		return
	if not _slots[slot_id].home_flag_alive:
		return
	_disconnect_grace_left[slot_id] = maxf(_net_config.disconnect_grace, 0.0)


## Host only. The peer came back inside the grace period: resume its feed with
## a full block timer, so it is not auto-dropped the instant it reconnects.
func on_peer_rejoined(slot_id: int) -> void:
	if not _is_host():
		return
	if slot_id < 0 or slot_id >= _disconnect_grace_left.size():
		return
	if _disconnect_grace_left[slot_id] < 0.0:
		return
	_disconnect_grace_left[slot_id] = -1.0
	if config != null:
		_feed_time_left[slot_id] = config.block_timer
		_feed_expired[slot_id] = false


## Seconds left before `slot_id` is eliminated for being gone, or -1 when its
## peer is connected. The lobby and the HUD read this; nothing else.
func disconnect_grace_left(slot_id: int) -> float:
	if slot_id < 0 or slot_id >= _disconnect_grace_left.size():
		return -1.0
	return _disconnect_grace_left[slot_id]


func _tick_disconnect_grace(delta: float) -> void:
	for i: int in range(_disconnect_grace_left.size()):
		if _disconnect_grace_left[i] < 0.0:
			continue
		_disconnect_grace_left[i] -= delta
		if _disconnect_grace_left[i] > 0.0:
			continue
		_disconnect_grace_left[i] = -1.0
		_eliminate_slot(i)


## The one elimination path, shared by a home flag lost to a hole (spec 2.2)
## and by a peer that never came back (docs/M3a_PLAN.md question 2), so the
## two cannot drift apart.
func _eliminate_slot(slot_id: int) -> void:
	var target: PlayerSlot = _slots[slot_id]
	if not target.home_flag_alive:
		return
	target.home_flag_alive = false
	Events.player_eliminated.emit(target.slot_id, target.team_id)
	_check_last_team_standing()


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
	_feed_seq.resize(_slots.size())
	_disconnect_grace_left.resize(_slots.size())
	for i: int in range(_slots.size()):
		_held_shapes[i] = null
		_feed_time_left[i] = config.block_timer
		_feed_expired[i] = false
		_feed_seq[i] = 0
		_disconnect_grace_left[i] = -1.0


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
	# Spec 3.4 / docs/M3a_PLAN.md, "Clients never solve territory": on a
	# client every body is frozen, so the settled rule would call the whole
	# field settled instantly and the solve would invent a territory that
	# disagrees with the host's. The mirror raster arrives over the wire
	# instead (see apply_replicated_territory).
	if not _is_host():
		return
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
	if not _is_host():
		return
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
			_eliminate_slot(slot_item.slot_id)

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


# --- The client's read model (spec 3.4) -------------------------------------
#
# Everything below is called only by net/MatchNet.gd, only on a client, and
# decides nothing: it writes the host's answers into this instance's copy of
# the match so the HUD, the ghost tint and the block feed preview are right.
# Each one is idempotent, because a reliable channel can still deliver a state
# the client already reached on its own.

## Mirrors the host's state machine. Re-emits match_state_changed only on a
## real change, so a client that already moved itself (the countdown it ran
## locally, say) does not emit twice.
func apply_replicated_state_change(new_state: int) -> void:
	if _state == new_state:
		return
	_set_state(new_state as State)


func apply_replicated_countdown(seconds_left: int) -> void:
	_countdown_remaining = float(seconds_left)
	_countdown_last_whole = seconds_left


## The host issued `slot_id` a block. Sets the held shape the ghost and the
## HUD read, resets the slot's display timer — which is what keeps the
## client's timer ring honest without a feed tick of its own — and takes the
## host's feed sequence verbatim.
##
## `host_feed_seq` is copied rather than counted up to, because the two ends
## do not start level: the host's first block comes from _begin_playing(),
## which issues without consuming, while a client never runs that at all. A
## client that counted its own would quote a sequence one ahead for the rest
## of the match and have every intent refused.
func apply_replicated_feed(
	slot_id: int, shape_id: StringName, _next_shape_id: StringName, host_feed_seq: int
) -> void:
	if slot_id < 0 or slot_id >= _held_shapes.size():
		return
	_held_shapes[slot_id] = _shape_by_id(shape_id)
	if host_feed_seq >= 0:
		_feed_seq[slot_id] = host_feed_seq
	if config != null:
		_feed_time_left[slot_id] = config.block_timer
	_feed_expired[slot_id] = false


func apply_replicated_turn(slot_id: int) -> void:
	_active_slot = slot_id


func apply_replicated_elimination(slot_id: int) -> void:
	var target: PlayerSlot = slot(slot_id)
	if target != null:
		target.home_flag_alive = false


## Writes one territory payload into the mirror raster (see
## TerritoryRaster.apply_replicated_state). Returns the cells whose hole bit
## flipped so MatchNet can re-emit Events.hole_cells_changed and Field opens
## exactly the same holes the host did.
func apply_replicated_territory(
	cells: PackedInt32Array, owners: PackedByteArray, states: PackedByteArray, full: bool
) -> void:
	if _raster == null:
		return
	if full:
		_raster.apply_replicated_state(owners, states)
	else:
		_raster.apply_replicated_diff(cells, owners, states)


## BlockShape.load_all_shapes() scans a directory, so the index is built once
## and only on the instance that needs it: a client, resolving the shape ids
## the host's feed events name.
func _shape_by_id(shape_id: StringName) -> BlockShape:
	if shape_id == &"":
		return null
	if _shapes_by_id.is_empty():
		for shape: BlockShape in BlockShape.load_all_shapes():
			_shapes_by_id[shape.id] = shape
	return _shapes_by_id.get(shape_id) as BlockShape
