class_name GhostTuning
extends Resource
## Ghost preview / placement control-feel tunables (spec 2.5) that aren't
## physics-body numbers, so they live apart from PhysicsTuning. M2 package P4
## (docs/M2_PLAN.md) also parks its HUD tunables here rather than inventing a
## second resource just for a couple of floats — CLAUDE.md's "no magic
## numbers" rule cares that every tunable lives in *some* res://config/
## resource, not that each owner gets its own file.

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

## -- Ghost visual base (spec 2.5: shadow + guide line) ----------------------
## Base alpha-blended tint before a per-state color is known (its alpha is
## reused as every state's transparency).
@export var tint_color: Color = Color(0.35, 0.9, 0.55, 0.55)
@export var shadow_color: Color = Color(0.0, 0.0, 0.0, 0.4)
@export var shadow_size: Vector2 = Vector2(1.0, 1.0)
## How far above the hit surface the shadow quad floats, so it doesn't
## z-fight with the disk/block it's projected onto.
@export var shadow_offset: float = 0.01
@export var guide_color: Color = Color(1.0, 1.0, 1.0, 0.6)
## Width/depth of the vertical guide line box (its height is the live
## distance from the hit point to the ghost, computed every frame).
@export var guide_thickness: float = 0.03

## -- Placement validity tint (spec 2.2, 2.5) ---------------------------------
## Red: outside territory, contested, or off the disk.
@export var invalid_tint_color: Color = Color(0.95, 0.15, 0.15, 0.6)
## Hatched pattern tint over a hole.
@export var hole_tint_color: Color = Color(0.95, 0.75, 0.15, 0.65)
## UV tiling density of the procedural hatch pattern across the held shape.
@export var hatch_scale: float = 6.0
## Fraction of each hatch tile that's opaque stripe vs. see-through gap.
@export var hatch_stripe_width: float = 0.5

## -- Reject animation (spec 2.2: "thrown off the map with a visible reject
## animation" — see docs/M2_PLAN.md owner decision 2) ------------------------
@export var reject_flash_color: Color = Color(1.0, 1.0, 1.0, 0.9)
@export var reject_flash_duration: float = 0.12
## Sideways and upward distance the held shape's visual kicks during the
## reject arc; the arc plays on the shape's local offset, not the ghost's
## world position, since PlayerController re-homes that every frame.
@export var reject_arc_sideways: float = 1.2
@export var reject_arc_height: float = 1.5
@export var reject_arc_duration: float = 0.4

## -- Auto-drop visual (spec 2.5: "When the timer runs out, the held block
## drops from its current ghost position") -----------------------------------
@export var auto_drop_flash_color: Color = Color(0.8, 0.85, 1.0, 0.85)
@export var auto_drop_flash_duration: float = 0.18

## -- HUD (ui/HUD.gd) ---------------------------------------------------------
@export var hud_reject_message_duration: float = 1.5
@export var hud_reject_fade_duration: float = 0.5
