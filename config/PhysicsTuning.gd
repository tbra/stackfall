class_name PhysicsTuning
extends Resource
## Every tunable number M1's physics needs (spec 2.4, 3.5). CLAUDE.md: "No
## magic numbers... every tunable value belongs in a Resource under
## res://config/". Loaded once as config/physics_tuning.tres and shared by
## BlockFactory, Field, and the benchmark scenes.

## -- Block bodies (spec 2.4) ------------------------------------------------
## Cube edge length in meters.
@export var cube_size: float = 1.0
## Shrink each cube's collision box by this much so neighboring blocks don't
## jam against each other.
@export var cube_margin: float = 0.02
## Mass per cube; a shape's total mass is cube count * cube_mass.
@export var cube_mass: float = 1.0
## Block physics material.
@export var block_friction: float = 0.8
@export var block_bounce: float = 0.05
## DECISION (config/PhysicsTuning.gd): spec 2.4 doesn't specify body damping,
## so blocks use Godot's project-default 0.1 and nothing more. Damping is
## deliberately NOT used to hold towers up.
##
## An earlier M1 revision set both of these to 4.0 because a 40-cube column
## would otherwise lean over and collapse. That was treating the symptom. The
## cause was Jolt's velocity solver running too few iterations to distribute
## the support force through a 40-contact chain (see the long comment on
## velocity_steps in tools/bootstrap_project.gd). The leftover per-block
## velocity kept the stack above Jolt's sleep threshold, and above roughly 15
## blocks it fed a lean that grew at the free inverted-pendulum rate until the
## tower fell. Damping of 4.0 did not stabilise that - it just slowed the
## topple by about 7x, which was enough for Jolt to put the tower to sleep
## before it fell over.
##
## The price was game feel. Spec 1.6 says the original's appeal was "a real
## sense of weight and balance", and linear damping of 4.0 caps a falling
## block at g/damp = 2.5 m/s, so blocks floated down like feathers. With the
## solver fixed, the 40-cube benchmark passes at zero damping (max top drift
## 24 mm, asleep at 0.52 s), so 0.1 here is insurance, not structure: it caps
## terminal velocity at 98 m/s, i.e. free fall for anything this game drops.
##
## 2026-09-22 (Bontago-ddz): that 24 mm / 0.52 s result was reproducible only
## by luck of body creation order until Jolt's body-pair contact cache
## distance threshold was tightened (tools/bootstrap_project.gd); with it the
## tower is 8/8 clean at every tested offset. Damping was never the variable.
##
## Worth knowing either way: Jolt sleeps a whole connected island together,
## not body by body, so one vibrating block near the top of a tower keeps
## every block below it awake too. These are also NOT the same numbers as the
## sleep_linear/angular_threshold fields below, which describe spec 2.2's
## settled-block/influence rule and aren't engine settings.
## See tests/unit/test_tower_placement.gd and tests/bench/bench_tower.gd.
@export var block_linear_damp: float = 0.1
@export var block_angular_damp: float = 0.1

## -- Field (spec 2.1, 3.5) ---------------------------------------------------
@export var disk_friction: float = 0.9
## Any body below this world Y is freed (spec 2.1).
@export var kill_plane_y: float = -40.0

## -- Ghost preview (spec 2.5) ------------------------------------------------
@export var hover_height: float = 0.3

## -- Settled-block rule (spec 2.2: "A block counts as settled when its
## linear speed is below 0.15 m/s and its angular speed below 0.3 rad/s for
## 0.5 s"). Used from M2 onward for territory influence, not by anything in
## M1 yet, but the numbers belong here rather than hard-coded later. ---------
@export var sleep_linear_threshold: float = 0.15
@export var sleep_angular_threshold: float = 0.3
@export var sleep_settle_time: float = 0.5

## -- Gravity (spec 2.8 "Gravity 0.5x-2x") ------------------------------------
@export var gravity_multiplier: float = 1.0

## -- Rebound damping (Bontago-xtq.17, owner playtest 2026-09-23: "heavier and
## more bouncy, but a dropped block shouldn't just bounce straight up
## again") --------------------------------------------------------------------
## DECISION (config/PhysicsTuning.gd): block_bounce (the PhysicsMaterial
## restitution above) is Jolt's only source of "bounciness", and Jolt applies
## restitution along the whole contact-normal impulse -- a block landing flat
## gets that restitution straight back as vertical velocity ("bounces
## straight up again"), while a corner/edge hit already scatters some of it
## sideways into tumble. Raising block_bounce for a livelier corner/edge hit
## therefore also raises the flat-drop's straight-up rebound; there is no
## separate Jolt knob for "restitution, but not on the vertical axis". So
## this field damps only the vertical (world Y) component of a block's own
## post-solve velocity, only on the one physics step a bounce actually
## happens (game/Block._integrate_forces(), host-only since a client's
## synced blocks are frozen and never integrate) -- horizontal and angular
## velocity, and every step that isn't a fresh bounce, are untouched, so
## block_bounce still gives lateral/tumbling liveliness. 1.0 is a pass-
## through multiplier (state.linear_velocity.y * 1.0 is exact under
## IEEE754), so this field defaults to 1.0 and every existing preset/test's
## behavior is byte-identical until a preset sets it below 1. See
## config/physics_presets/*.tres for the shipped presets and
## game/Block._damp_rebound() for the pure scaling rule this field feeds.
@export var rebound_damping: float = 1.0

## -- Stable-block freeze (spec 3.5 "Stable-block optimization" [NEW],
## docs/M8_PLAN.md P5) ---------------------------------------------------------
## DECISION (config/PhysicsTuning.gd): spec 3.5 gives this rule's own number
## directly ("asleep for more than 20 s") -- no fidelity-table ambiguity to
## resolve, unlike some of this file's other fields. 20.0 also matches the
## Freeze special's own duration (spec 2.9's table: "static for 20 s"), which
## keeps "how long is a block frozen for" one number in the player's head
## across both the optimization and the special, even though they arrive at
## it through unrelated code paths (game/StableBlockManager.gd vs. a future
## FreezeEffect). A block resets this timer (and un-freezes if already
## frozen) the instant it wakes, per spec 3.5's "goes back to normal the
## moment any impulse, tilt, or change in the cells under it happens".
@export var stable_freeze_delay_s: float = 20.0
## DECISION (config/PhysicsTuning.gd): docs/M8_PLAN.md's own P5 section
## suggested reusing a bare internal accumulator instead of a tunable here,
## since spec 3.5 names no interval of its own -- but this project's own "no
## magic numbers" rule (CLAUDE.md) is stricter than that suggestion, so this
## stays a real field rather than a hard-coded constant inside
## game/StableBlockManager.gd. 0.5 s: cheap enough at a few hundred live
## blocks (this only reads Block.sleeping and, rarely, flips freeze_mode --
## nothing like the ~5-7 ms/step contact_monitor cost this file's rebound-
## damping section above already documents) and coarse enough that the
## 20 s freeze delay's own precision doesn't need anything tighter.
@export var stable_freeze_scan_interval_s: float = 0.5
