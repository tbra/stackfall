class_name GhostTuning
extends Resource
## Ghost preview / placement control-feel tunables (spec 2.5) that aren't
## physics-body numbers, so they live apart from PhysicsTuning. M2 package P4
## (docs/M2_PLAN.md) also parks its HUD tunables here rather than inventing a
## second resource just for a couple of floats — CLAUDE.md's "no magic
## numbers" rule cares that every tunable lives in *some* res://config/
## resource, not that each owner gets its own file.

## -- Ghost cursor movement (Bontago-mv0.14: original-style block-locked
## controls — "the mouse positions the block", spec 1.5/2.5). Both mouse and
## gamepad drive the same world-space cursor (PlayerController._cursor); the
## camera follows it (CameraRig.follow_block), it no longer follows a
## screen-space raycast. ------------------------------------------------
## Meters the cursor moves per pixel of camera-relative mouse motion.
@export var block_move_sensitivity: float = 0.05
@export var gamepad_cursor_base_speed: float = 10.0
## The zoom (camera orbit distance) at which base_speed applies; farther out
## moves the cursor faster, closer in moves it slower.
@export var gamepad_cursor_zoom_reference_distance: float = 30.0
@export var gamepad_cursor_acceleration: float = 40.0

## -- Rotation mode (Bontago-mv0.14: original's "hold Rotation Mode ->
## movement inputs change the orientation of the block", spec 1.5/2.5).
## Replaces the old free/quaternion-drift rotation (spec 1.7: drift was a
## reported original problem) with the same 90 degree snap table
## rotate_yaw/pitch/roll already use, driven continuously instead of one tap
## per press. See PlayerController._accumulate_rotation_drag(). ---------------
## "Drag units" of camera-relative mouse motion per pixel; a full unit (after
## sensitivity scaling) snaps one 90 degree step. 1/120 means ~120px per step.
@export var block_rotation_sensitivity: float = 1.0 / 120.0
## Drag units per second of left-stick deflection while rotation_mode is
## held at full stick (~1 step every 0.4 s).
@export var pad_rotation_speed: float = 2.5

## -- Hover height (spec 1.5/2.5: "the mouse wheel raises and lowers the
## block") --------------------------------------------------------------------
## Continuous per-second rate for held inputs (PageUp/PageDown keys, gamepad
## RS click/X) -- these are genuinely holdable buttons, unlike the wheel.
@export var hover_manual_adjust_speed: float = 1.0
## Meters applied per discrete wheel notch (InputEventMouseButton wheel
## events are momentary -- one press+release per notch -- so they get one
## fixed step instead of hover_manual_adjust_speed's per-frame rate).
@export var hover_wheel_step: float = 0.4
@export var hover_manual_max: float = 3.0

## -- Placement raycast --------------------------------------------------
@export var placement_ray_length: float = 200.0
## Height above the cursor's disk-plane position that the placement raycast
## starts from, so it looks straight down through anything the cursor sits
## under (spec 2.5: placement is a straight-down ray from the ghost).
@export var cursor_ray_height: float = 200.0

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
## Bontago-mv0.10 (spec 2.4/2.5 "[ORIGINAL target]" placement cadence): grey,
## the interval-locked state -- this slot released a piece early this
## interval and is only aiming/preparing the next one, which cannot be
## released until the interval boundary. Distinct from invalid_tint_color's
## red on purpose: spec 2.5, "A location-valid ghost does not imply that the
## current interval permits release," so a locked-but-otherwise-valid spot
## must not read as "you're standing somewhere wrong."
@export var locked_tint_color: Color = Color(0.6, 0.6, 0.6, 0.55)
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
