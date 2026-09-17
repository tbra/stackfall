extends Node
## Global signal bus.
##
## Systems emit and connect here instead of reaching through the scene tree,
## so nothing needs deep node paths like get_node("../../..").
## Signals are added as each milestone needs them; M0 ships the bus empty.

## M1: a block became a live physics body, either placed by a player or
## auto-dropped when its feed timer ran out.
signal block_placed(block: RigidBody3D, shape_id: StringName)

## M1: a block left the simulation (kill plane for now; despawn/body-cap
## reasons arrive later). `reason` is a short machine-readable tag; use the
## REASON_* constants below rather than a string literal so it can't drift.
signal block_removed(block: RigidBody3D, reason: String)

## game/Field.gd: a block fell below tuning.kill_plane_y.
const REASON_KILL_PLANE: StringName = &"kill_plane"

# --- M2: match flow (spec 3.7) ----------------------------------------------

## The host's state machine moved. Both arguments are Match.State values.
signal match_state_changed(from_state: int, to_state: int)

## One second of the 3 s pre-match countdown elapsed; 0 means "go".
signal countdown_tick(seconds_left: int)

## Hot-seat: it is now this slot's turn to hold and place a block.
signal turn_changed(slot_id: int)

## A team met the win condition (spec 2.3). The match state goes to End.
signal match_won(team_id: int)

# --- M2: block feed (spec 2.4, 3.7) -----------------------------------------

## A slot received a new block from the bag. `next_shape_id` is what the HUD
## shows in the next-block preview; it is &"" when the preview is off.
signal feed_block_issued(slot_id: int, shape_id: StringName, next_shape_id: StringName)

## A slot's block timer ran out. The slot's controller answers by calling
## Match.request_place(..., auto_drop = true) from wherever its ghost is;
## Match relocates it to the closest valid point if it has to (spec 2.5).
signal feed_timer_expired(slot_id: int)

## The host refused a placement intent. `reason` is one of the
## PlacementRules.REASON_* constants. The block is thrown off the map
## (spec 2.2) and the client shows a reject effect (spec 3.4).
signal placement_rejected(slot_id: int, reason: StringName)

# --- M2: territory (spec 2.2, 3.3) ------------------------------------------

## The host finished a territory solve, at TerritoryTuning.solve_hz. Carries
## the live raster; receivers read it, never mutate it.
signal territory_updated(raster: TerritoryRaster, groups: TerritoryGroups)

## Per-team share of the disk, 0..1, indexed by team id. HUD only.
signal territory_share_changed(shares: PackedFloat32Array)

## Cells whose hole state flipped in the last solve, as row-major CellGrid
## indices. Field batches the collision toggles and wakes the blocks above
## them (spec 3.3).
signal hole_cells_changed(opened: PackedInt32Array, closed: PackedInt32Array)

## A team is holding every goal flag in one connected territory. `progress`
## runs 0..1 over TerritoryTuning.capture_hold and drives the flag's radial
## ring (spec 2.3). team_id is -1 with progress 0 when a capture breaks.
signal goal_capture_progress(team_id: int, progress: float)
