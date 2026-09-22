class_name MatchAutoload
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
##
## Bontago-split.1 (pure refactor, no behaviour change): the state machine's
## rules used to all live directly on this Node. They now live in four
## RefCounted controllers under res://autoload/match/ -- MatchFeed (bags,
## held/next shapes, feed_seq, interval timers, the replicated feed mirror),
## MatchPlacement (request_place, pose validation, spawn/burn), MatchTerritory
## (territory build/solve, circles, elimination checks, the replicated
## territory mirror) and MatchLifecycle (the state machine itself, slots/
## teams, disconnect grace, hot-seat turns) -- each wired to this node via
## setup(self) in _ready() so none of them ever walks the scene tree to find
## it. This file keeps every existing public method (and the private/debug
## seams tests reach) as a one-line forward to whichever controller now owns
## the logic, so nothing outside autoload/match/ had to change.
##
## DECISION (autoload/Match.gd, Bontago-split.1): the class_name is
## `MatchAutoload`, not `Match` -- Godot 4.7 refuses `class_name Match` outright
## ("Class 'Match' hides an autoload singleton") since project.godot's
## [autoload] section already binds the global identifier `Match` to this
## script's singleton instance. `MatchAutoload` is the type every controller's
## `_match: MatchAutoload` field and `setup(match: MatchAutoload)` uses to stay
## statically typed (CLAUDE.md's "static typing everywhere"); the global name
## `Match` is untouched and still resolves to the autoload singleton
## everywhere it always has, so every existing `Match.foo()` call site outside
## this package is unaffected.

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

## Bontago-split.1: the four controllers this file forwards to. Built and
## wired in _ready() rather than at field-declaration time, so each one's
## setup(self) can hand back a fully-constructed Match reference.
var _feed: MatchFeed = null
var _placement: MatchPlacement = null
var _territory: MatchTerritory = null
var _lifecycle: MatchLifecycle = null


func _ready() -> void:
	_feed = MatchFeed.new()
	_placement = MatchPlacement.new()
	_territory = MatchTerritory.new()
	_lifecycle = MatchLifecycle.new()
	_feed.setup(self)
	_placement.setup(self)
	_territory.setup(self)
	_lifecycle.setup(self)


# --- Test/debug seams (Bontago-split.1) --------------------------------------
#
# tests/ and tools/ reach several of these directly (by grep of
# `Match\._` and `Match\.debug_`): _held_shapes (index-assigned), _raster and
# _solver (read, then a method called on the returned object), _territory_
# tuning (unchanged -- see above, never moved off Match), and the private
# methods below. Each forwards to the controller that now owns the field or
# method, and — since Array/Object are reference types in GDScript — an
# index-assignment through a get-only property still mutates the controller's
# own storage, exactly as before the split.

var _held_shapes: Array[BlockShape]:
	get:
		return _feed._held_shapes
	set(value):
		_feed._held_shapes = value

var _raster: TerritoryRaster:
	get: return _territory._raster

var _solver: TerritorySolver:
	get: return _territory._solver


func _resolve_outcome(initial_result: PlacementRules.Result, auto_drop: bool, relocated: Vector2) -> Dictionary:
	return _placement._resolve_outcome(initial_result, auto_drop, relocated)


func _finish_match(winning_team: int) -> void:
	_lifecycle._finish_match(winning_team)


func _check_home_flags(opened: PackedInt32Array) -> void:
	_territory._check_home_flags(opened)


func _check_home_flags_v2() -> void:
	_territory._check_home_flags_v2()


func _collect_circles() -> Array[InfluenceCircle]:
	return _territory._collect_circles()


func _run_territory_step(delta: float) -> void:
	_territory._run_territory_step(delta)


func debug_unlock_slot(slot_id: int) -> void:
	_feed.debug_unlock_slot(slot_id)


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


func start_match(match_config: MatchConfig) -> void:
	_lifecycle.start_match(match_config)


func abort_match() -> void:
	_lifecycle.abort_match()


func state() -> State:
	return _lifecycle.state()


## Seconds left in the countdown, or 0.0 outside State.COUNTDOWN.
func countdown_remaining() -> float:
	return _lifecycle.countdown_remaining()


## Spec 3.4: "The host is authoritative ... only the host runs physics." Every
## clock that decides something — the countdown, the feed timers and their
## auto-drops, the 10 Hz territory solve, the win check and the disconnect
## grace — runs here and only on the host. A client's copy of Match is a
## read model: it holds the slots, the config and a mirror raster so its HUD
## and its ghost's territory tint are right, and it is driven entirely by
## net/MatchNet.gd's replicated events.
func _process(delta: float) -> void:
	if not _is_host():
		_feed._tick_client_display(delta)
		return
	match _lifecycle._state:
		State.COUNTDOWN:
			_lifecycle._tick_countdown(delta)
		State.PLAYING:
			_lifecycle._tick_disconnect_grace(delta)
			_feed._tick_feed(delta)
			_territory._tick_territory(delta)
		_:
			pass


# --- Slots and teams --------------------------------------------------------

func slot_count() -> int:
	return _lifecycle.slot_count()


func slot(slot_id: int) -> PlayerSlot:
	return _lifecycle.slot(slot_id)


func team_of(slot_id: int) -> int:
	return _lifecycle.team_of(slot_id)


## Hot-seat: the slot whose turn it is. Outside hot-seat this is the local
## player's slot, and every slot acts at once.
func active_slot() -> int:
	return _lifecycle.active_slot()


## Hot-seat: hands the turn to the next slot. Called after a placement
## resolves, not by input.
func advance_turn() -> void:
	_lifecycle.advance_turn()


# --- Block feed (spec 2.4, 3.7) ---------------------------------------------

## The shape `slot_id` is holding right now, or null between blocks.
func held_shape(slot_id: int) -> BlockShape:
	return _feed.held_shape(slot_id)


## What the HUD's next-block preview shows for `slot_id`.
func next_shape(slot_id: int) -> BlockShape:
	return _feed.next_shape(slot_id)


## Seconds left on the slot's block timer (spec 2.8: 3-12 s, default 6).
func feed_time_left(slot_id: int) -> float:
	return _feed.feed_time_left(slot_id)


## feed_time_left / config.block_timer, 1 -> 0, for the HUD's timer ring.
func feed_progress(slot_id: int) -> float:
	return _feed.feed_progress(slot_id)


## Whether _tick_feed() is currently decrementing timers (Bontago-mv0.8:
## true for every real match). ui/SandboxPanel.gd shows this as the timer's
## "running"/"paused" state.
func feed_timer_enabled() -> bool:
	return _feed.feed_timer_enabled()


## game/Sandbox.gd's sandbox_toggle_timer hotkey. A no-op call outside
## sandbox is harmless (every real match starts true and nothing else in the
## shipped game ever calls this), but nothing stops a caller from flipping it
## — this file does not gate it on config.sandbox, the same way
## set_process(false) in the test harness is trusted rather than re-checked.
func set_feed_timer_enabled(enabled: bool) -> void:
	_feed.set_feed_timer_enabled(enabled)


# --- The one authoritative entry point (spec 3.4) ---------------------------

## Every placement in the game goes through here, local or remote. See
## autoload/match/MatchPlacement.gd's request_place() for the full contract
## (origin/orientation/free_quat/auto_drop/feed_seq, burn-on-reject, the M3a
## RPC wrapping and the -1 feed_seq sentinel for trusted local callers).
func request_place(
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	auto_drop: bool,
	feed_seq: int = -1
) -> StringName:
	return _placement.request_place(slot_id, origin, orientation_index, free_quat, auto_drop, feed_seq)


## Whether a pose can be evaluated at all. See MatchPlacement.is_pose_well_formed().
func is_pose_well_formed(origin: Vector3, orientation_index: int, free_quat: Quaternion) -> bool:
	return _placement.is_pose_well_formed(origin, orientation_index, free_quat)


## Dry run of request_place()'s territory check, for the ghost's valid/red/
## hatched tint (spec 2.5). See MatchPlacement.preview_placement().
func preview_placement(
	slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion
) -> PlacementRules.Result:
	return _placement.preview_placement(slot_id, origin, orientation_index, free_quat)


## Blocks this instance has spawned since the match started. The M3a
## acceptance harness asserts this equals the sum of accepted intents plus
## auto-drops (docs/M3a_PLAN.md).
func blocks_spawned() -> int:
	return _placement.blocks_spawned()


## The value an intent for `slot_id` must quote to be accepted right now. It
## advances on every consumed block, so exactly one intent can spend any one
## held block (docs/M3a_PLAN.md, "Never duplicated, never lost").
func feed_seq(slot_id: int) -> int:
	return _feed.feed_seq(slot_id)


## Bontago-mv0.10 (spec 2.4 "[ORIGINAL target]" cadence): whether `slot_id`'s
## currently held piece may be released right now. See MatchFeed.is_release_locked().
func is_release_locked(slot_id: int) -> bool:
	return _feed.is_release_locked(slot_id)


## Where a slot's block goes when its timer expires and the host has never
## heard a cursor from it. See MatchPlacement.default_ghost_origin().
func default_ghost_origin(slot_id: int) -> Vector3:
	return _placement.default_ghost_origin(slot_id)


# --- Disconnects (docs/M3a_PLAN.md question 2) ------------------------------

func on_peer_left(slot_id: int) -> void:
	_lifecycle.on_peer_left(slot_id)


func on_peer_rejoined(slot_id: int) -> void:
	_lifecycle.on_peer_rejoined(slot_id)


## Seconds left before `slot_id` is eliminated for being gone, or -1 when its
## peer is connected. The lobby and the HUD read this; nothing else.
func disconnect_grace_left(slot_id: int) -> float:
	return _lifecycle.disconnect_grace_left(slot_id)


# --- Territory and the win check (spec 2.2, 2.3, 3.3) -----------------------

## The live raster. Never mutate it from outside Match.
func raster() -> TerritoryRaster:
	return _territory.raster()


## The groups from the last solve, parallel to the raster.
func groups() -> TerritoryGroups:
	return _territory.groups()


func cell_grid() -> CellGrid:
	return _territory.cell_grid()


## Fraction of the disk a team owns, 0..1.
func territory_share(team_id: int) -> float:
	return _territory.territory_share(team_id)


## The winning team, or -1.
func winner_team() -> int:
	return _territory.winner_team()


## Tallest point any of this slot's settled blocks reaches above the disk, in
## meters. Spec 2.10's HUD shows it as a number.
func max_height_for_slot(slot_id: int) -> float:
	return _registry.max_height_for_slot(slot_id) if _registry != null else 0.0


## The analytic circle list the last territory step built (host only),
## cached so net/MatchNet.gd's replicate_territory() can ship the identical
## list to clients. See MatchTerritory.circle_render_arrays().
func circle_render_arrays() -> Dictionary:
	return _territory.circle_render_arrays()


## core/net/CircleWire.gd's quantization bounds for this match's map. Host
## (encoding, net/MatchNet.gd's replicate_territory()) and client (decoding,
## the same file's net_territory()) must use the identical numbers, so this
## is the one place both read them from — the same MatchConfig/NetConfig/
## TerritoryTuning resources a version-matched build already shares.
func circle_wire_xz_bound() -> float:
	return _net_config.position_bounds(config.map_def()).size.x * 0.5


func circle_wire_radius_max() -> float:
	return _territory_tuning.influence_max_fraction * config.map_def().field_radius


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
	_lifecycle.apply_replicated_state_change(new_state)


func apply_replicated_countdown(seconds_left: int) -> void:
	_lifecycle.apply_replicated_countdown(seconds_left)


## The host issued `slot_id` a block. See MatchFeed.apply_replicated_feed()
## for the full contract (host_feed_seq/host_feed_time_left/host_is_locked).
func apply_replicated_feed(
	slot_id: int,
	shape_id: StringName,
	next_shape_id: StringName,
	host_feed_seq: int,
	host_feed_time_left: float = -1.0,
	host_is_locked: bool = false
) -> void:
	_feed.apply_replicated_feed(slot_id, shape_id, next_shape_id, host_feed_seq, host_feed_time_left, host_is_locked)


func apply_replicated_turn(slot_id: int) -> void:
	_lifecycle.apply_replicated_turn(slot_id)


func apply_replicated_elimination(slot_id: int) -> void:
	_lifecycle.apply_replicated_elimination(slot_id)


## Writes one territory payload into the mirror raster. See
## MatchTerritory.apply_replicated_territory() for the full contract
## (circle_*/goal_*/argmax_mode defaults for pre-existing call sites).
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
	_territory.apply_replicated_territory(
		cells, owners, states, full,
		circle_xs, circle_zs, circle_radii, circle_teams,
		goal_positions, goal_radii, argmax_mode
	)
