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
