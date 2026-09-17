class_name GhostTuning
extends Resource
## Ghost preview / placement control-feel tunables (spec 2.5) that aren't
## physics-body numbers, so they live apart from PhysicsTuning.

## -- Gamepad ghost cursor (spec 2.5: "speed scales with camera zoom, with
## acceleration and a small dead zone") ---------------------------------
@export var gamepad_cursor_base_speed: float = 10.0
## The zoom (camera orbit distance) at which base_speed applies; farther out
## moves the cursor faster, closer in moves it slower.
@export var gamepad_cursor_zoom_reference_distance: float = 30.0
@export var gamepad_cursor_acceleration: float = 40.0

## -- Free rotation (spec 2.5: "rotate_free_hold + mouse motion / right
## stick") -----------------------------------------------------------------
## Radians of free rotation per pixel of mouse motion.
@export var free_rotate_mouse_speed: float = 0.01
## Radians per second of free rotation at full gamepad stick deflection.
@export var free_rotate_pad_speed: float = 2.5

## -- Hover height (spec 2.5 "Raise/lower hover") -----------------------------
@export var hover_manual_adjust_speed: float = 1.0
@export var hover_manual_max: float = 3.0

## -- Placement raycast --------------------------------------------------
@export var placement_ray_length: float = 200.0
