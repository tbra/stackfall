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

## -- Field (spec 2.1, 3.5) ---------------------------------------------------
@export var disk_friction: float = 0.9
## Any body below this world Y is freed (spec 2.1).
@export var kill_plane_y: float = -40.0

## -- Ghost preview (spec 2.5) ------------------------------------------------
@export var hover_height: float = 0.3

## -- Sleep (spec 3.5) --------------------------------------------------------
@export var sleep_linear_threshold: float = 0.15
@export var sleep_angular_threshold: float = 0.3
@export var sleep_settle_time: float = 0.5

## -- Jolt solver (spec 3.5) --------------------------------------------------
@export var solver_velocity_iterations: int = 10
@export var solver_position_iterations: int = 4

## -- Gravity (spec 2.8 "Gravity 0.5x-2x") ------------------------------------
@export var gravity_multiplier: float = 1.0
