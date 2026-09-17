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

## The config the running match was started with. A duplicate of whatever was
## handed to start_match(), never the shared config/match_defaults.tres.
var config: MatchConfig = null


@warning_ignore_start("unused_parameter")
# --- Lifecycle --------------------------------------------------------------

## Hands Match the world it drives. Called once by Main after the scene is
## built, so nothing here ever walks the scene tree looking for its
## collaborators (CLAUDE.md). `registry` is game/BlockRegistry.gd, which
## tracks live blocks and their settled state; `blocks_parent` is where new
## blocks are added.
func register_world(field: Field, registry: Node, blocks_parent: Node3D) -> void:
	pass


## Lobby -> Loading -> Countdown -> Playing. Builds the player slots, the
## per-slot block bags, the solver, the raster and the win checker from
## `match_config`, then starts the countdown.
func start_match(match_config: MatchConfig) -> void:
	pass


## Back to Lobby from anywhere, clearing the field.
func abort_match() -> void:
	pass


func state() -> State:
	return State.LOBBY


## Seconds left in the countdown, or 0.0 outside State.COUNTDOWN.
func countdown_remaining() -> float:
	return 0.0


# --- Slots and teams --------------------------------------------------------

func slot_count() -> int:
	return 0


func slot(slot_id: int) -> PlayerSlot:
	return null


func team_of(slot_id: int) -> int:
	return -1


## Hot-seat: the slot whose turn it is. Outside hot-seat this is the local
## player's slot, and every slot acts at once.
func active_slot() -> int:
	return -1


## Hot-seat: hands the turn to the next slot. Called after a placement
## resolves, not by input.
func advance_turn() -> void:
	pass


# --- Block feed (spec 2.4, 3.7) ---------------------------------------------

## The shape `slot_id` is holding right now, or null between blocks.
func held_shape(slot_id: int) -> BlockShape:
	return null


## What the HUD's next-block preview shows for `slot_id`.
func next_shape(slot_id: int) -> BlockShape:
	return null


## Seconds left on the slot's block timer (spec 2.8: 3-12 s, default 6).
func feed_time_left(slot_id: int) -> float:
	return 0.0


## feed_time_left / config.block_timer, 1 -> 0, for the HUD's timer ring.
func feed_progress(slot_id: int) -> float:
	return 0.0


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
	return PlacementRules.REASON_NO_BLOCK


## Dry run of request_place()'s territory check, for the ghost's valid/red/
## hatched tint (spec 2.5). Costs one footprint build plus one validate, so it
## is safe to call every frame.
func preview_placement(
	slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion
) -> PlacementRules.Result:
	return PlacementRules.Result.EMPTY


# --- Territory and the win check (spec 2.2, 2.3, 3.3) -----------------------

## The live raster. Never mutate it from outside Match.
func raster() -> TerritoryRaster:
	return null


## The groups from the last solve, parallel to the raster.
func groups() -> TerritoryGroups:
	return null


func cell_grid() -> CellGrid:
	return null


## Fraction of the disk a team owns, 0..1.
func territory_share(team_id: int) -> float:
	return 0.0


## The winning team, or -1.
func winner_team() -> int:
	return -1


## Tallest point any of this slot's settled blocks reaches above the disk, in
## meters. Spec 2.10's HUD shows it as a number.
func max_height_for_slot(slot_id: int) -> float:
	return 0.0
@warning_ignore_restore("unused_parameter")
