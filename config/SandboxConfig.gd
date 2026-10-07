class_name SandboxConfig
extends Resource
## Tunables for the unlisted `godot --path . -- --sandbox` debug entry point
## (Bontago-mv0.8). Nothing here changes match rules — see config/MatchConfig.gd
## for those, config/PhysicsTuning.gd for physics — this only tunes how the
## sandbox scaffold itself behaves (CLAUDE.md: no magic numbers).
##
## Loaded once as config/sandbox.tres, exactly like every other config/*.tres.

## `--sandbox` with no `--players=` starts with this many slots.
## MatchConfig.PLAYER_COUNT_MIN is 2 (spec 2.8); sandbox is the one place a
## config below that floor is allowed (MatchConfig.sandbox), so this can sit
## under it on purpose for solo rules testing.
@export var default_player_count: int = 2

## sandbox_spawn_tower (F7) calls Match.request_place() this many times in a
## row for the active slot, stacked vertically at the ghost's current (x, z) —
## whatever shape the slot is holding at each step, since request_place()
## has no shape override and this package does not touch core/ rule logic
## (game/Sandbox.gd's own DECISION explains why "N cubes" becomes "N of
## whatever's held").
@export var tower_block_count: int = 6

## Vertical gap between each spawned block's center, in meters. A separate
## tunable from PhysicsTuning.cube_size (rather than reading that directly)
## so a sandbox tester can deliberately dial in an overlapping or a loosely
## spaced stack without touching physics tuning that every other mode shares.
@export var tower_spacing: float = 1.05

## ui/SandboxPanel.gd's refresh rate, in Hz. The panel is cheap to poll every
## frame, but reads no better at 60 Hz than at 10, so it accumulates delta
## and only rebuilds its labels this often.
@export var panel_refresh_hz: float = 10.0

## sandbox_slow_motion (F10) sets Engine.time_scale to this while active, and
## back to 1.0 when toggled off, on game/Sandbox.gd's own scene teardown, and
## on sandbox_reset_field -- see that file's own DECISION on why the reset is
## guaranteed rather than left to whoever remembers to toggle the hotkey back
## (Engine.time_scale is process-global, not scoped to one scene, so a leaked
## value here would still be in effect for the next match).
@export var slow_motion_scale: float = 0.25

## Bontago-1pi.70 (gift demo preset, config/sandbox_gift_demo.tres). Every
## opponent slot (all but slot 0) gets a tower of this many blocks dropped at
## its home position when the sandbox starts and after each field reset. 0 = none.
@export var preplaced_tower_blocks: int = 0

## Pre-placed towers are built resting on the disc (lowest block on the surface,
## each block on the one below at its exact stacked height), never dropped, so
## nothing is interpenetrating or falling at spawn. Opponent towers stand this
## far in from their home beacon toward the field centre, in meters, so they
## clear the beacon's collision (socket and crystal) with room to spare.
@export var preplaced_home_offset: float = 4.0

## Spawned towers start asleep (zero velocity) so they stand until something
## hits them.
@export var preplaced_start_asleep: bool = true

## BlockShape id every pre-placed block uses (a stacked tower of cubes).
@export var preplaced_shape_id: StringName = &"cube"

## Tower-topple layout (Bontago-1pi.102). When non-empty this replaces the
## per-opponent towers: one tower per entry, that many cubes tall, in a row
## along the field's x axis centred on the origin, owned round-robin by the
## slots. Mirrors the tower tests (a few heights plus the 30- and 40-block
## acceptance towers).
@export var row_tower_heights: PackedInt32Array = PackedInt32Array()

## Centre-to-centre distance between neighbouring row towers, in meters.
@export var row_tower_spacing: float = 5.0

## Disk-local (x, z) centre of the row, in meters. Kept off the origin: the
## central goal flag's zone (TerritoryTuning.goal_zone_radius) refuses blocks.
@export var row_center: Vector2 = Vector2(0.0, 8.0)

## Gift-testing tweak: when >= 0, overrides MatchConfig.special_frequency
## (0-100) and forces gifts_enabled for the sandbox match. -1 leaves the
## lobby/default value alone.
@export var special_frequency_override: int = -1
