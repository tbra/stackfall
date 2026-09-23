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
## Bontago-mv0.21 (owner, 2026-09-22, after re-testing against the original
## Bontago): lowered from 0.05 to 0.015 -- the original moves the held block
## much more slowly per pixel of mouse motion than this project's earlier
## default.
@export var block_move_sensitivity: float = 0.015
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

## -- Rotate drag (Bontago-mv0.22, spec 2.5 "Rotate block (hold+drag)"
## [ORIGINAL, owner test 2026-09-22]): distinct from Rotation Mode above --
## that one snaps to the 90 degree grid on purpose (spec 1.7's reported
## drift problem); this one runs GhostPreview.free_quaternion continuously,
## exactly like the original, while rotate_drag (MMB) is held
## (PlayerController._unhandled_input). Safe end-to-end with no wire-format
## change: free_quaternion already travels submit_cursor/submit_place
## unmodified (net/MatchNet.gd) and the host accepts any finite unit
## quaternion, not only the 24-entry table (autoload/match/MatchPlacement.gd
## is_pose_well_formed(), request_place()'s Basis(free_quat) * orientation
## basis composition). ------------------------------------------------------
## Radians of rotation per pixel of mouse motion while rotate_drag is held --
## horizontal motion yaws about world up, vertical motion pitches about the
## camera's current right axis (game/PlayerController.gd's
## _camera_right_axis()). Bontago-mv0.25 (spec 2.5, owner test 2026-09-22:
## "like the RMB orbit but for the block"): both axes now spin continuously
## while the button is held, not yaw alone.
## DECISION (config/GhostTuning.gd): one shared sensitivity for both axes,
## not a second field -- it's one continuous two-axis drag gesture from a
## single input device, and giving the axes different pixel-to-radian scales
## would feel inconsistent for no clear benefit.
@export var rotate_drag_sensitivity: float = 0.008

## -- Hover height (spec 1.5/2.5: "the mouse wheel raises and lowers the
## block") --------------------------------------------------------------------
## Continuous per-second rate for held inputs (PageUp/PageDown keys, gamepad
## RS click/X) -- these are genuinely holdable buttons, unlike the wheel.
@export var hover_manual_adjust_speed: float = 1.0
## Meters applied per discrete wheel notch (InputEventMouseButton wheel
## events are momentary -- one press+release per notch -- so they get one
## fixed step instead of hover_manual_adjust_speed's per-frame rate).
@export var hover_wheel_step: float = 0.4
## Bontago-mv0.17 item 5 (owner feel report: "the block's height changes ONLY
## via the wheel" -- original behaviour): raised from 3 m to clear a tall
## tower, now that the ghost's own height is the disk surface plus this
## manual offset rather than whatever is directly underneath it.
@export var hover_manual_max: float = 30.0

## -- Placement raycast --------------------------------------------------
@export var placement_ray_length: float = 200.0
## Height above the cursor's disk-plane position that the placement raycast
## starts from, so it looks straight down through anything the cursor sits
## under (spec 2.5: placement is a straight-down ray from the ghost).
@export var cursor_ray_height: float = 200.0
## Bontago-mv0.17 item 5: PlayerController's disk-surface probe (the raycast
## that decides the ghost's own height) walks straight down and skips over
## any RigidBody3D (placed block) it hits, so the ghost's height reflects the
## disk itself, never a tower underneath the cursor. This caps how many
## stacked blocks it will skip before giving up and falling back to the flat
## y = 0 plane, so a runaway/adversarial stack can't spin the probe forever.
@export var surface_probe_max_blocks: int = 32

## -- Ghost visual base (spec 2.5; Bontago-mv0.17 item 6 replaced the old
## vertical guide line with the footprint projection below, and Bontago-mv0.25
## removed the drop-shadow blob entirely -- see the footprint section's
## DECISION) -----------------------------------------------------------------
## Base alpha-blended tint before a per-state color is known (its alpha is
## reused as every state's transparency).
@export var tint_color: Color = Color(0.35, 0.9, 0.55, 0.55)

## -- Footprint projection (Bontago-mv0.17 item 6 -- owner feel report:
## replaces the single vertical guide line with the whole footprint, one
## rotated convex polygon per bottom cell of the held shape, projected
## straight down onto whatever is directly beneath it) -----------------------
## DECISION (config/GhostTuning.gd, Bontago-mv0.25, docs/rotation-issue.png):
## the separate drop-shadow quad (shadow_color/shadow_size/shadow_offset) is
## removed rather than kept unused -- the footprint is now the only ground
## marker (owner test 2026-09-22: a rotated block's footprint must show its
## true rotated silhouette, and a second, always-axis-aligned grey square
## underneath it was redundant and visually wrong once the footprint itself
## rotates correctly). Their old field names are gone; nothing else in the
## project reads them (see this package's own grep audit).
## Alpha of each footprint quad's validity tint (valid/invalid/hole/locked
## share the same colours as the held shape's own tint -- see
## GhostPreview._footprint_color_for_state() -- just at this alpha instead of
## each state colour's own baked-in one, since a whole-footprint decal reads
## better a bit more transparent than the held shape itself).
@export var footprint_alpha: float = 0.55
## How far above the landing surface each footprint quad floats, so it
## doesn't z-fight with the disk/block it's projected onto.
@export var footprint_offset: float = 0.01

## -- Projection prism (Bontago-xtq.7, docs/solid-blocks2-issue.png, owner
## test 2026-09-23: "in the original the ghost block projects its whole shape
## downwards to the disc, it's not just a footprint indicator where the
## raycast lands") -- the vertical walls connecting the held shape's own
## underside down to its footprint on the disc, matching the original's own
## translucent silhouette (docs/original_in-game.png). ------------------------
## Alpha of the projection prism's own walls -- deliberately fainter than
## footprint_alpha (the flat decal it stands on): a tall, mostly-empty volume
## marker reads better subtle than a solid wall would.
@export var projection_alpha: float = 0.18
## DECISION (config/GhostTuning.gd, Bontago-xtq.7): true reuses the same
## valid/invalid/hole/locked state colours the footprint and held shape's own
## body already show (see GhostPreview._apply_projection_material()'s own
## DECISION); false always tints the prism with the base tint_color
## regardless of state, kept as a tuning-panel escape hatch for an owner feel
## comparison rather than a field this project expects to ship off.
@export var projection_uses_state_tint: bool = true

## -- Placement validity tint (spec 2.2, 2.5) ---------------------------------
## Shown for every "can't drop here" reason that isn't a hole/goal-zone:
## outside your own territory, contested, or off the disk.
## DECISION (config/GhostTuning.gd, Bontago-mv0.25, owner test 2026-09-22):
## changed from red to the same grey as locked_tint_color -- red read as an
## alarming "you did something wrong" cue, but simply aiming outside your own
## territory while looking for a legal spot is the normal, expected case, not
## an error; grey reads as calmer, plain "can't drop here" feedback, matching
## how the interval-locked state already reads. Left as its own field (not a
## direct reuse of locked_tint_color) so the tuning panel can still split them
## apart later without a second migration.
@export var invalid_tint_color: Color = Color(0.6, 0.6, 0.6, 0.55)
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
## Sideways (+world X) and upward (+world Y) distance the ghost kicks during
## the reject arc. Bontago-mv0.25 (docs/rotation-issue.png): the kick now
## animates a world-space offset added on top of the ghost's own computed
## position every frame (GhostPreview._reject_offset), not the shape visual's
## local offset -- the old local-offset kick rode along with whatever
## rotation the held block currently had, so a pitched/rolled block's "up"
## kick visibly went sideways or backwards. A world-space offset survives
## PlayerController re-homing the ghost's position every frame for the same
## reason the old local-offset trick existed, but no longer depends on the
## block's rotation.
@export var reject_arc_sideways: float = 0.3
@export var reject_arc_height: float = 0.375
@export var reject_arc_duration: float = 0.4

## -- Auto-drop visual (spec 2.5: "When the timer runs out, the held block
## drops from its current ghost position") -----------------------------------
@export var auto_drop_flash_color: Color = Color(0.8, 0.85, 1.0, 0.85)
@export var auto_drop_flash_duration: float = 0.18

## -- HUD (ui/HUD.gd) ---------------------------------------------------------
@export var hud_reject_message_duration: float = 1.5
@export var hud_reject_fade_duration: float = 0.5

## -- Ghost-vs-placed-block collision (Bontago-mv0.23, spec 2.5 "Held-block
## behaviour" [ORIGINAL], owner test 2026-09-22): the held ghost collides with
## already placed blocks -- it cannot pass through a tower -- but it never
## pushes or knocks them; placed blocks are unaffected by the ghost.
## game/PlayerController.gd runs a swept box test every frame against the
## real physics world instead of giving the ghost its own physics body, so a
## placed RigidBody3D is only ever read from, never touched. -----------------
## Master switch (F4 tuning panel): false restores the pre-mv0.23 behaviour
## (the ghost passes through placed blocks) for an owner feel comparison.
@export var ghost_collision_enabled: bool = true
## Meters of gap the swept test keeps between the ghost and a placed block.
## Implemented by inflating the swept box by this much on every side
## (game/PlayerController.gd._sweep_motion()) rather than subtracting it from
## the result, so the gap is exact regardless of sweep direction.
@export var ghost_collision_skin: float = 0.03
## How many non-block colliders (the disk, a future goal-zone body) one
## cell's shape cast will skip past before giving up and calling that cast
## clear -- the shape-cast analogue of surface_probe_max_blocks above, needed
## because this project sets no distinguishing physics layer for a placed
## block (every body defaults to Godot's layer 1; see PlayerController's
## DECISION comment on _cast_one_box()).
@export var collision_probe_max_bodies: int = 8
