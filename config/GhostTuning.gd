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

## Bontago-iry (owner feedback/controller-update.md, "clicking mmb rotates
## the ghost block, seems to follow a set pattern"): total unscaled mouse
## pixels of motion (game/PlayerController.gd's _rotate_drag_motion_px)
## rotate_drag can accumulate while held before the hold counts as a drag
## instead of a tap. Below this, no continuous free rotation is applied at
## all and release fires one BlockOrientations.step_yaw_cw() snap (the same
## fixed 90 degree pattern rotate_snap/rotate_yaw_cw use); at or above it,
## every further frame's motion drives the continuous free rotation as
## before and release does nothing extra. DECISION (config/GhostTuning.gd):
## ~6 px is small enough that a deliberate drag crosses it on the very first
## real mouse-motion event (matching every pre-existing rotate_drag test's
## 20-130 px single-event motions) while a genuine click-with-jitter tap
## stays under it.
@export var rotate_tap_max_motion_px: float = 6.0

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
## Bontago-mv0.34 (owner playtest 2026-09-23, "there's a max height above
## which I can't scroll up or place blocks, there shouldn't be"): raised again
## from 30 m to 60 m -- MapDef.cell_wake_height's own doc comment already
## calls 60 m "tall enough to cover any tower this map can realistically
## carry", the same bound this field needs, so it reuses that figure rather
## than inventing a second one. Not read from MapDef directly: GhostTuning is
## a plain preloaded Resource with no reference to whichever map is live, and
## every shipped map uses the same 60 m cell_wake_height today (no .tres
## overrides it), so a fixed constant here costs nothing in practice while
## keeping this package's scope to its own owned files.
## DECISION (config/GhostTuning.gd, Bontago-mv0.34): capped at 60 m, not the
## wire's own full headroom -- net/MatchNet.gd's _pose_is_acceptable() refuses
## any placement whose Y falls outside NetConfig.pos_min_y..pos_max_y (-48..72
## m, config/net_config.tres), the same band core/net/Quantize.gd's
## pack_position() quantizes into. At the disk surface (y=0) a manual offset
## of 60 m plus PhysicsTuning.hover_height (0.3 m) tops out at 60.3 m, 11.7 m
## under that 72 m ceiling -- comfortably inside the wire's own budget, so
## this package needed no change to NetConfig, Quantize, or MatchNet.gd's
## check (see this package's own report for the full audit). See
## config/tuning_panel_hints.tres's own DECISION for why the F4 slider itself
## is capped below the wire ceiling too, not just this default.
@export var hover_manual_max: float = 60.0

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
## Bontago-xtq.9 (owner test 2026-09-23, "the ghost block should be a bit
## more opaque"): alpha raised from 0.55 to 0.75, matching the other
## valid/state tints below (invalid_tint_color, hole_tint_color,
## locked_tint_color) so every state reads more solid, not just VALID.
@export var tint_color: Color = Color(0.35, 0.9, 0.55, 0.75)

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
## Alpha of each footprint quad's own colour (footprint_base_color blended
## with a faint amount of the current state's own hue -- see
## GhostPreview._footprint_color_for_state()/footprint_hue_strength below).
## Bontago-xtq.10 (owner test 2026-09-23, "the footprint on the disc should
## be almost white"): raised from 0.55 to 0.85 -- a near-white marker needs
## real opacity to actually read as "almost white" rather than a faint grey
## wash of the disc showing through.
@export var footprint_alpha: float = 0.85
## How far above the landing surface each footprint quad floats, so it
## doesn't z-fight with the disk/block it's projected onto.
@export var footprint_offset: float = 0.01
## Bontago-xtq.10 (owner test 2026-09-23, "the footprint on the disc should
## be almost white"): the footprint's own base colour before any state hue is
## blended in -- deliberately near-white (not pure white: a hair of "already
## lit" warmth reads better than a flat, possibly-blown-out RGB(1,1,1) patch
## on a bright disc). See footprint_hue_strength below for how much of the
## current validity state still shows through it.
@export var footprint_base_color: Color = Color(0.95, 0.95, 0.95, 1.0)
## Bontago-xtq.10: how much of the current state's own hue (player colour /
## invalid_tint_color / hole_tint_color / locked_tint_color) is blended into
## footprint_base_color above (GhostPreview._footprint_color_for_state()'s
## own Color.lerp) -- 0 keeps the footprint pure white regardless of state
## (loses the valid/invalid/hole/locked cue entirely), 1 restores the old
## fully state-coloured footprint from before this package. A low default
## keeps the disc marker reading "almost white" (owner's own words) while
## still faintly hinting at validity.
@export var footprint_hue_strength: float = 0.18

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
## Bontago-xtq.10 (owner test 2026-09-23, "the projection colour is right but
## any surface that falls within the projection should be a lot brighter"):
## the prism's own material now blends additively (BaseMaterial3D.
## BLEND_MODE_ADD, GhostPreview._ready()) instead of the usual alpha-over
## compositing, and also emits light of its own (emission_enabled) at this
## multiplier -- both brighten whatever renders behind/inside the column
## instead of just tinting over it, matching the owner's request. Visual
## only: nothing about placement rules reads this prism.
@export var projection_emission_energy: float = 1.5
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
## Bontago-xtq.9: alpha raised from 0.55 to 0.75 alongside tint_color's own
## alpha above (owner test 2026-09-23, "the ghost block should be a bit more
## opaque").
@export var invalid_tint_color: Color = Color(0.6, 0.6, 0.6, 0.75)
## Hatched pattern tint over a hole.
## Bontago-xtq.9: alpha raised from 0.65 to 0.75, same reasoning as
## tint_color/invalid_tint_color above.
@export var hole_tint_color: Color = Color(0.95, 0.75, 0.15, 0.75)
## Bontago-mv0.10 (spec 2.4/2.5 "[ORIGINAL target]" placement cadence): grey,
## the interval-locked state -- this slot released a piece early this
## interval and is only aiming/preparing the next one, which cannot be
## released until the interval boundary. Distinct from invalid_tint_color's
## red on purpose: spec 2.5, "A location-valid ghost does not imply that the
## current interval permits release," so a locked-but-otherwise-valid spot
## must not read as "you're standing somewhere wrong."
## Bontago-xtq.9: alpha raised from 0.55 to 0.75, same reasoning as
## tint_color/invalid_tint_color above.
@export var locked_tint_color: Color = Color(0.6, 0.6, 0.6, 0.75)
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

## -- Post-placement spawn clearance (Bontago-mv0.30, owner test 2026-09-23,
## "when you place a block and the next block loads it gets displaced so it
## doesn't spawn directly within the placed block") ---------------------------
## Extra height (on top of the just-placed shape's own top) game/
## PlayerController.gd's _apply_spawn_clearance() seeds the next ghost's
## manual_hover_offset to, right after Events.feed_block_issued follows this
## controller's own accepted placement -- so the new held shape floats clear
## of the one just spawned instead of rendering inside it. The existing hover
## wheel and ghost-vs-placed-block collision sweep take over normally from
## there. Never applied on the match's very first piece, or after a
## placement that didn't actually spawn anything near the cursor (a refused
## manual release, or an auto-drop burn thrown off the map) -- see that
## function's own DECISION comments.
@export var spawn_clearance: float = 0.15

## -- Throw aim (M4 P2e, docs/M4_P2_PACKAGES.md P2e; spec 2.5 "Throw
## (specials only)") ----------------------------------------------------------
## Ghost tint while game/PlayerController.gd's is_aiming_throw() is true
## (game/GhostPreview.gd's show_throw_hint()) -- distinct from every other
## tint here since it says nothing about where the block would land, only
## that a throw gesture is in progress. Same alpha as tint_color/
## invalid_tint_color/hole_tint_color/locked_tint_color for the same "reads
## more solid" reason those give.
@export var throw_aim_tint_color: Color = Color(1.0, 0.55, 0.15, 0.75)
## How many straight segments game/ThrowArcPreview.gd's ballistic polyline is
## divided into before its own landing cutoff (Bontago-1en.25) can stop it
## early; higher reads smoother but costs more per-frame vertices. Raised
## from 24 to 64 alongside throw_arc_max_time_s's own default increase below,
## so the per-segment time step (throw_arc_max_time_s / this) stays about the
## same as before that change (~0.0625 s/segment) instead of getting coarser.
@export var throw_arc_sample_count: int = 64
## Seconds of flight the arc preview samples out to before giving up. Since
## Bontago-1en.25 the preview normally stops the moment it actually reaches
## the landing surface (game/Field.gd's own surface_y(), or
## throw_arc_floor_below_disc_m under it once the throw has flown past the
## disc's rim) -- this is now only the safety cap for a throw that never
## "lands" at all (no Field wired, or the floor disabled below): a real
## thrown special still flies until it lands or the fuse times out
## (SpecialTuning.fuse_timeout_s et al.), never this value. Raised from 1.5 s
## to 4 s, comfortably past the ~3.6 s hang time SpecialTuning's own
## throw_max_speed (25 m/s) and throw_loft_ratio (1.0, 45 degrees) defaults
## produce, so the cap rarely bites in practice (feedback/throw-arc.png: the
## old 1.5 s cut a hard lofted throw off while it was still rising).
@export var throw_arc_max_time_s: float = 4.0
## Colour of the arc preview polyline (and its optional landing-point marker,
## throw_arc_end_marker_enabled below).
@export var throw_arc_color: Color = Color(1.0, 0.85, 0.3, 0.9)
## World-space width (meters) of the arc preview's ribbon.
@export var throw_arc_width: float = 0.05

## -- Throw arc landing (Bontago-1en.25, feedback/throw-arc.png: "arc leaves
## the screen while rising") -- game/ThrowArcPreview.gd's sample_arc()/
## update_arc() now stop the preview at ground/disc contact instead of always
## sampling out to throw_arc_max_time_s above. ------------------------------
## Height, in meters below game/Field.gd's own surface_y(), the arc keeps
## falling to when its XZ has flown past the disc's own rim (map_def.
## field_radius) -- a flat "there is no ground here" backstop for an off-disc
## throw, rather than letting it fall forever (see throw_arc_floor_enabled
## below to turn this off instead).
@export var throw_arc_floor_below_disc_m: float = 3.0
## Whether an off-disc sample (past the rim) lands on throw_arc_floor_below_
## disc_m at all. False lets an off-disc throw's preview keep falling until
## throw_arc_max_time_s's own safety cap stops it instead, with no landing
## point -- e.g. for a map/tuning combination where "3 m below the disc" would
## still read as floating in the air.
@export var throw_arc_floor_enabled: bool = true
## Whether the arc preview drops a small flat disc marker at its own landing
## point, for extra legibility beyond the polyline simply stopping there.
@export var throw_arc_end_marker_enabled: bool = true
## World-space radius (meters) of the landing-point marker disc above.
@export var throw_arc_end_marker_radius: float = 0.12

## -- Feel round 7 (ghost) --

## Bontago-xtq.13 (owner playtest 2026-09-23, "ghost block should still be
## less transparent -> add a slider for it in the F4 menu"): one alpha shared
## by every ghost state tint (tint_color/invalid_tint_color/hole_tint_color/
## locked_tint_color/throw_aim_tint_color all keep their own RGB --
## game/GhostPreview.gd's _apply_validity_material() now applies this as the
## alpha of whichever colour it picks, rather than each colour's own baked-in
## alpha channel). DECISION (config/GhostTuning.gd, Bontago-xtq.13): kept as
## one new field rather than editing each tint colour's own stored alpha --
## a single slider matches the brief's own "add a slider for it", and every
## existing tint colour's alpha channel becomes dead weight this field
## overrides rather than a second value to keep in sync by hand.
@export var ghost_opacity: float = 0.9

## Bontago-xtq.15 (owner playtest 2026-09-23, "the same white projection that
## shows up on the disk should show up on the blocks as well, just a bit
## fainter"): game/GhostPreview.gd's _block_projection_decal projects this RGB
## (its own alpha channel is ignored, same convention as ghost_opacity above
## overriding every tint colour's own alpha -- see block_projection_alpha)
## downward from the held ghost's own underside onto whatever real block sits
## beneath it, near-white to match footprint_base_color's own disc marker.
@export var block_projection_color: Color = Color(0.95, 0.95, 0.95, 1.0)
## Alpha of the block-projection decal above -- deliberately fainter than
## footprint_alpha's own disc marker (the brief's own "just a bit fainter"),
## since a placed block already has its own lit surface to read through,
## unlike the flat disc.
@export var block_projection_alpha: float = 0.5
## Bontago-xtq.18 attempt 3: the block-projection decal's upper/lower fade
## exponent (Decal.upper_fade/lower_fade: 1 - |height in box| raised to this).
## Tiny by default so the projection stays a crisp full-strength shaft, but
## never 0 -- game/GhostPreview.gd clamps it above zero, since a fade of 0.0
## makes any surface lying exactly on the decal box's top or bottom plane
## render as NaN (black speckle; feedback/owner-noise-footprint.png).
@export var block_projection_edge_fade: float = 0.001
