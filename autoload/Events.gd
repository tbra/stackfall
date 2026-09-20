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

## A slot's home flag was lost to a hole opening under it (spec 2.2 is silent
## on this; docs/M2_PLAN.md's owner decision: this eliminates the slot —
## PlayerSlot.home_flag_alive goes false, its circles unanchor, and it gets no
## more feed). Match ends the match itself via match_won if only one
## player/team is left.
signal player_eliminated(slot_id: int, team_id: int)

# --- M3a: session and transport (spec 3.4) ----------------------------------

## Net changed between OFFLINE, HOST and CLIENT. `mode` is a Net.Mode value.
signal net_mode_changed(mode: int)

## A peer finished the build-version handshake and holds a slot. `slot_id` is
## -1 while it is only sitting in the lobby without a seat.
signal net_peer_joined(peer_id: int, slot_id: int, player_name: String)

## A peer disconnected. `reason` is a Net.LeaveReason value. The host decides
## what happens to its slot (docs/M3a_PLAN.md); this is the notification, not
## the decision.
signal net_peer_left(peer_id: int, slot_id: int, reason: int)

## A join attempt failed. `error` is a Net.JoinError value; `detail` is a
## human-readable line for the lobby, never parsed.
signal net_join_failed(error: int, detail: String)

## The host published new lobby settings (spec 3.4: Steam lobbies store match
## settings as lobby data; over ENet the host broadcasts the same Dictionary).
## The payload is MatchConfig.to_dict() plus the roster.
signal net_lobby_data_changed(data: Dictionary)

## The LAN browser's list changed (spec 3.4 "LAN discovery"). Each entry is
## {name, address, port, version, players, max, map}.
signal net_games_discovered(games: Array[Dictionary])

## Ping, snapshot size, interpolation delay and measured loss, refreshed at
## NetConfig.stats_hz. ui/NetDebugOverlay.gd is the only consumer; the shape
## is Net.stats().
signal net_stats_updated(stats: Dictionary)

# --- M3a: replication (spec 3.4) --------------------------------------------

## A client built its frozen copy of a block the host spawned. The local
## equivalent of block_placed for bodies this instance does not simulate:
## emitted only on clients, and always before the first snapshot moves it.
signal block_replicated(block: RigidBody3D, net_id: int)

## A client applied a territory update from the host. Clients never solve
## territory themselves (spec 3.4: only the host runs physics and the rules),
## so this replaces territory_updated on a client. The raster is the client's
## mirror; read it, never mutate it.
signal territory_replicated(raster: TerritoryRaster)

## Another player's ghost moved (spec 3.4: "update_cursor(pos) ... only used to
## show other players' ghosts"). Emitted on every instance for every non-local
## slot, at NetConfig.cursor_hz.
signal remote_cursor_updated(
	slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion
)

# --- M3b: Steam transport (spec 3.4, docs/M3b_PLAN.md P1) -------------------

## Net.init_steam() finished (or the extension isn't installed). `available`
## mirrors Net.steam_available(); `detail` is a human-readable line for the
## menu's notice label, never parsed.
signal net_steam_status_changed(available: bool, detail: String)

## The Steam lobby list changed after Net.refresh_lobby_list(). Each entry is
## {lobby_id, name, players, max, map}, the Steam-side equivalent of
## net_games_discovered.
signal net_steam_lobbies_discovered(lobbies: Array[Dictionary])
