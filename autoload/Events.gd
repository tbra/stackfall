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
