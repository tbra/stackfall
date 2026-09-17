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
