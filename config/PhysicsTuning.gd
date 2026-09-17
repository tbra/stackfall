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
## DECISION (config/PhysicsTuning.gd): spec 2.4 doesn't specify body damping.
## A perfectly aligned single-file column of unit cubes (the M1 acceptance
## criterion's 30-block tower, and the 40-block bench_tower) turned out to be
## a very lightly damped system: with Godot/Jolt's project-default 0.1
## linear/angular damping it develops a slow bending oscillation that grows
## over several seconds until the tower topples, even with extra Jolt solver
## iterations (see tools/bootstrap_project.gd's velocity_steps/position_steps
## comment). Explicit per-block damping fixes it. Also worth knowing: Jolt
## sleeps a whole connected stack together, not body by body, so one lightly
## vibrating block near the top of a tall tower can keep every block below it
## awake too — that drove the damping value up further than the drift alone
## would have suggested. Found empirically against Jolt's actual sleep
## threshold (physics/jolt_physics_3d/simulation/sleep_velocity_threshold,
## 0.03 m/s by default) rather than the sleep_linear/angular_threshold fields
## below, which describe the settled-block/influence rule from spec 2.2 and
## aren't Jolt engine settings. See tests/unit/test_tower_placement.gd.
@export var block_linear_damp: float = 4.0
@export var block_angular_damp: float = 4.0

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
