class_name GhostTuning
extends Resource
## Ghost preview / placement control-feel tunables (spec 1.4) that aren't
## physics-body numbers, so they live apart from PhysicsTuning.

## Meters the cursor moves per pixel of camera-relative mouse motion. Mouse and
## gamepad drive the same world-space cursor (spec 1.3: the mouse positions the
## block) and the camera follows it.
@export var block_move_sensitivity: float = 0.05
## Base left-stick cursor speed, scaled by camera zoom (see
## gamepad_cursor_zoom_reference_distance). The Options "Stick speed" setting
## multiplies this.
@export var gamepad_cursor_base_speed: float = 36.0
## The zoom (camera orbit distance) at which base_speed applies; farther out
## moves the cursor faster, closer in moves it slower.
@export var gamepad_cursor_zoom_reference_distance: float = 30.0
@export var gamepad_cursor_acceleration: float = 40.0

## Rotation mode (movement inputs turn the held block on the same 90 degree snap
## table rotate_yaw/pitch/roll use, driven continuously; see
## PlayerController._accumulate_rotation_drag()). "Drag units" of camera-relative
## mouse motion per pixel; a full unit (after sensitivity scaling) snaps one
## 90 degree step. 1/120 means ~120px per step.
@export var block_rotation_sensitivity: float = 1.0 / 120.0
## Drag units per second of left-stick deflection while rotation_mode is
## held at full stick (~1 step every 0.4 s).
@export var pad_rotation_speed: float = 2.5

## Radians of rotation per pixel of mouse motion while rotate_drag (MMB) is held:
## horizontal motion yaws about world up, vertical motion pitches about the
## camera's right axis (PlayerController._camera_right_axis()). Free rotation,
## unlike Rotation Mode's snap grid; free_quaternion already travels
## submit_cursor/submit_place and the host accepts any finite unit quaternion.
## DECISION: one shared sensitivity for both axes; it is one two-axis drag gesture
## from one device, so different pixel-to-radian scales would feel inconsistent.
@export var rotate_drag_sensitivity: float = 0.008

## Total unscaled mouse pixels rotate_drag may move while held and still count as
## a tap, not a drag. Below it no free rotation is applied and release fires one
## BlockOrientations.step_yaw_cw() snap; at or above it motion drives the free
## rotation and release does nothing extra.
## DECISION: ~6 px, so a deliberate drag crosses it on its first mouse-motion
## event while a click with jitter stays under it (existing rotate_drag tests use
## 20-130 px single-event motions).
@export var rotate_tap_max_motion_px: float = 6.0

## Radians per second at full left-stick deflection while rotate_drag_pad (RT) is
## held: continuous free rotation like the mouse drag (X yaws about world up, Y
## pitches about the camera's right axis), not the 90 degree snap grid.
@export var pad_free_rotation_speed: float = 2.0

## Continuous per-second hover rate for held inputs (PageUp/PageDown, gamepad RS
## click/X); wheel notches use hover_wheel_step instead.
## DECISION: only the base rate scales with hover_wheel_step; the hold ramp below
## is separate, so a held input ramps by the same amount per second from a
## faster start.
@export var hover_manual_adjust_speed: float = 1.5
## A held raise/lower starts at hover_manual_adjust_speed and accelerates by this
## many m/s every second it stays held, so a held input is not capped at
## block_timer * base speed of height before the feed timer auto-drops the block.
@export var hover_hold_acceleration: float = 14.0
## Top speed (m/s) of the held-input ramp. Releasing the input resets the ramp, so
## a short tap still moves at hover_manual_adjust_speed for fine control.
@export var hover_hold_max_speed: float = 24.0
## Meters applied per discrete wheel notch (wheel events are momentary, so they
## get one fixed step instead of a per-frame rate). The default wheel action
## adjusts block hover height, not camera zoom.
@export var hover_wheel_step: float = 0.6
## Continuous wheel scrolling accelerates: the step multiplier rises linearly from
## 1 to hover_wheel_max_multiplier over this many seconds of scrolling with no
## pause longer than hover_wheel_gap_seconds.
@export var hover_wheel_ramp_seconds: float = 1.5
## Top multiplier applied to hover_wheel_step while scrolling continuously.
@export var hover_wheel_max_multiplier: float = 4.0
## Pause (s) between notches that ends a scroll and resets the ramp.
@export var hover_wheel_gap_seconds: float = 0.25
## Optional extra designer cap (m) on the manual hover offset. The effective
## ceiling is the wire band: PlayerController._hover_offset_ceiling() stops the
## ghost origin hover_ceiling_margin below NetConfig.pos_max_y, the band
## core/net/Quantize.gd can replicate and net/MatchNet.gd accepts (~147.7 m of
## offset on a flat disk). The default sits above anything the band allows, so it
## never fires on its own.
## DECISION: the default sits above the wire band instead of mirroring it, so the
## band, not this field, stays the real limit.
## DECISION: the F4 slider range (0-200 m) matches the default, so lowering it is
## purely a designer choice.
@export var hover_manual_max: float = 200.0
## Meters kept between the held ghost's origin and NetConfig.pos_max_y, so a
## pose at the very top of the raise still quantizes inside the wire band
## (a released block also gains a little height from physics settling).
@export var hover_ceiling_margin: float = 2.0

## Length of the downward placement raycast, meters.
@export var placement_ray_length: float = 200.0
## Height above the cursor's disk-plane position that the placement raycast
## starts from, so it looks straight down through anything the cursor sits
## under (spec 1.4: placement is a straight-down ray from the ghost).
@export var cursor_ray_height: float = 200.0
## PlayerController's disk-surface probe (the raycast that decides the ghost's own
## height) walks straight down and skips any placed RigidBody3D, so the ghost
## height reflects the disk, never a tower under the cursor. This caps how many
## stacked blocks it skips before falling back to the flat y = 0 plane, so a
## runaway stack can't spin the probe forever.
@export var surface_probe_max_blocks: int = 32

## Base alpha-blended tint before a per-state color is known (its alpha is
## reused as every state's transparency).
@export var tint_color: Color = Color(0.35, 0.9, 0.55, 0.75)

## DECISION: no separate drop-shadow quad; the footprint (one rotated convex
## polygon per bottom cell of the held shape, projected straight down) is the only
## ground marker, since an axis-aligned grey square under a rotated block's
## footprint was redundant and wrong.
## Alpha of each footprint quad's own colour (footprint_base_color blended
## with a faint amount of the current state's own hue -- see
## GhostPreview._footprint_color_for_state()/footprint_hue_strength below).
## Near-opaque so the near-white marker reads as white rather than a faint wash
## of the disc.
@export var footprint_alpha: float = 0.85
## How far above the landing surface each footprint quad floats, so it
## doesn't z-fight with the disk/block it's projected onto.
@export var footprint_offset: float = 0.01
## The footprint's base colour before any state hue is blended in: near-white
## rather than pure white, which can blow out on a bright disc. See
## footprint_hue_strength.
@export var footprint_base_color: Color = Color(0.95, 0.95, 0.95, 1.0)
## How much of the current state's hue (player colour / invalid / hole / locked
## tint) is blended into footprint_base_color (GhostPreview.
## _footprint_color_for_state()). 0 keeps the footprint white regardless of state;
## 1 is fully state-coloured. A low default keeps it near white while hinting at
## validity.
@export var footprint_hue_strength: float = 0.18

## Alpha of the projection prism: the vertical walls connecting the held shape's
## underside down to its footprint on the disc. Deliberately fainter than
## footprint_alpha (the flat decal it stands on): a tall, mostly-empty volume
## marker reads better subtle.
@export var projection_alpha: float = 0.18
## Emission energy of the projection prism, whose material blends additively
## (BLEND_MODE_ADD, GhostPreview._ready()) so it brightens surfaces inside the
## column instead of tinting over them. Visual only: placement rules never read
## it.
@export var projection_emission_energy: float = 1.5
## DECISION: true reuses the valid/invalid/hole/locked state colours the footprint
## and held shape show (see GhostPreview._apply_projection_material()'s own
## DECISION); false
## always tints the prism with tint_color, kept as a tuning-panel escape hatch for
## feel comparison.
@export var projection_uses_state_tint: bool = true

## Shown for every "can't drop here" reason that isn't a hole/goal-zone: outside
## your own territory, contested, or off the disk (spec 1.5, 1.4).
## DECISION: grey like locked_tint_color, not red; aiming outside your territory
## while looking for a legal spot is normal, not an error. Its own field so the
## tuning panel can split the two apart.
@export var invalid_tint_color: Color = Color(0.6, 0.6, 0.6, 0.75)
## Hatched pattern tint over a hole.
@export var hole_tint_color: Color = Color(0.95, 0.75, 0.15, 0.75)
## Interval-locked state (spec 1.4): this slot released a piece early this
## interval and cannot release until the boundary. Spec 1.4, "A location-valid
## ghost does not imply that the current interval permits release," so a
## locked-but-valid spot must not read as "you're standing somewhere wrong".
@export var locked_tint_color: Color = Color(0.6, 0.6, 0.6, 0.75)
## UV tiling density of the procedural hatch pattern across the held shape.
@export var hatch_scale: float = 6.0
## Fraction of each hatch tile that's opaque stripe vs. see-through gap.
@export var hatch_stripe_width: float = 0.5

## Flash colour of the reject animation (spec 1.5: thrown off the map with a visible reject animation).
@export var reject_flash_color: Color = Color(1.0, 1.0, 1.0, 0.9)
@export var reject_flash_duration: float = 0.12
## Sideways (+world X) and upward (+world Y) distance the ghost kicks during the
## reject arc. A world-space offset added to the ghost's computed position every
## frame (GhostPreview._reject_offset), so it survives PlayerController re-homing
## the ghost and does not depend on the block's rotation.
@export var reject_arc_sideways: float = 0.3
@export var reject_arc_height: float = 0.375
@export var reject_arc_duration: float = 0.4

## Flash colour when the feed timer auto-drops the held block (spec 1.4).
@export var auto_drop_flash_color: Color = Color(0.8, 0.85, 1.0, 0.85)
@export var auto_drop_flash_duration: float = 0.18

## Seconds the HUD shows the placement-rejected message (ui/hud/HUD.gd).
@export var hud_reject_message_duration: float = 1.5
@export var hud_reject_fade_duration: float = 0.5
## Seconds the HUD shows the "relocated" message. An auto-drop after a refused
## spot lands at PlacementRules.closest_valid_point(), often a couple of metres
## away, and needs acknowledgement distinct from the earlier reject message.
## ui/HUD.show_relocated() uses these two durations like the reject pair above.
@export var hud_relocated_message_duration: float = 1.5
@export var hud_relocated_fade_duration: float = 0.5

## Master switch (F4 tuning panel) for ghost-vs-placed-block collision (spec 1.4
## held-block behaviour): the held ghost cannot pass through a tower but never
## pushes placed blocks. PlayerController runs a swept box test against the real
## physics world rather than giving the ghost a body. false lets the ghost pass
## through placed blocks.
@export var ghost_collision_enabled: bool = true
## Meters of gap the swept test keeps between the ghost and a placed block.
## Implemented by inflating the swept box by this much on every side
## (game/player/PlayerController.gd._sweep_motion()) rather than subtracting it from
## the result, so the gap is exact regardless of sweep direction.
@export var ghost_collision_skin: float = 0.03
## How many non-block colliders (the disk, a future goal-zone body) one
## cell's shape cast will skip past before giving up and calling that cast
## clear -- the shape-cast analogue of surface_probe_max_blocks above, needed
## because this project sets no distinguishing physics layer for a placed
## block (every body defaults to Godot's layer 1; see PlayerController's
## DECISION comment on _cast_one_box()).
@export var collision_probe_max_bodies: int = 8

## Extra height (on top of the just-placed shape's own top) that PlayerController.
## _apply_spawn_clearance() seeds the next ghost's manual_hover_offset to after
## Events.feed_block_issued follows this controller's own accepted placement, so
## the new shape floats clear of the one just spawned. The hover wheel and ghost
## collision sweep take over from there. Never applied on the first piece, or
## after a placement that spawned nothing near the cursor (a refused release, or
## an auto-drop burn thrown off the map); see that function's own DECISION comments.
@export var spawn_clearance: float = 0.02
## The raise is searched upward in steps of this size (then bisected) until the new piece no longer overlaps a placed block.
@export var spawn_clearance_step: float = 0.25
## Upper bound on one spawn's clearance raise, metres.
@export var spawn_clearance_max_raise: float = 20.0
## Bisection refinements inside the last step (precision = step / 2^n).
@export var spawn_clearance_bisect_steps: int = 5
## Metres per second the raise decays back to the player's own hover once the
## lower pose is clear.
@export var spawn_clearance_decay_speed: float = 2.0
## Longest wait, seconds, for the block a new piece loads inside to come to rest
## before the spawn clearance decides whether to raise it. A block that falls
## clear never raises it.
@export var spawn_clearance_settle_timeout_s: float = 2.5

## Master switch for the spawn-clearance raise above: it raises only when the new
## piece overlaps a placed block, by the minimal amount, and the camera follows.
@export var spawn_clearance_enabled: bool = true

## The match's first piece is held at the owner's home flag, where the home beacon
## socket + crystal (~2.2 m) would swallow it: the beacon sits on a collision
## layer the placement ray and spawn-clearance query never see
## (Field.PLACEMENT_QUERY_MASK), and clearance never runs for the first piece. So
## the first held piece is raised until its lowest point sits this many metres
## above BeaconVisualTuning.beacon_top_height(). The raise is dropped once the
## player takes over the hover height or the first accepted placement issues the
## next piece. The rule itself lives in home_spawn_clear_hover() (see its DECISION).
@export var home_spawn_beacon_margin: float = 1.25
## Metres the first block starts back from the home beacon, horizontally away from the field centre (the side the home camera sits on).
@export var home_spawn_back_offset: float = 2.0

## How many straight segments ThrowArcPreview's ballistic polyline is divided
## into before its landing cutoff can stop it early; higher is smoother but costs
## more vertices. Keep throw_arc_max_time_s / this near 0.0625 s so segments
## don't get coarse.
@export var throw_arc_sample_count: int = 64
## Seconds of flight the arc preview samples out to: the safety cap for a throw
## that never lands (no Field wired, or the floor disabled below). Normally the
## preview stops at the landing surface (Field.surface_y(), or
## throw_arc_floor_below_disc_m once past the rim). A real thrown special flies
## until it lands or the fuse times out, never this value. Set past the ~3.6 s
## hang time of SpecialTuning's throw_max_speed (25 m/s) and throw_loft_ratio
## (1.0, 45 degrees) so the cap rarely bites.
@export var throw_arc_max_time_s: float = 4.0
## Colour of the arc preview polyline (and its optional landing-point marker,
## throw_arc_end_marker_enabled below).
@export var throw_arc_color: Color = Color(1.0, 0.85, 0.3, 0.9)
## World-space width (meters) of the arc preview's ribbon.
@export var throw_arc_width: float = 0.05

## Height, in meters below game/field/Field.gd's own surface_y(), the arc keeps
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
## Whether the arc preview draws a flat landing-zone ring at its own landing
## point, for extra legibility beyond the polyline simply stopping there.
@export var throw_arc_end_marker_enabled: bool = true
## Outer radius (meters) of the landing-zone ring above.
@export var throw_arc_end_marker_radius: float = 1.5
## Radial width (meters) of the landing-zone ring's band, measured inward from its outer radius.
@export var throw_arc_end_marker_width: float = 0.08
## Meters the ring floats along the landing surface normal, so it never z-fights the surface.
@export var throw_arc_end_marker_lift: float = 0.02
## Segments around the landing-zone ring (higher reads rounder).
@export var throw_arc_end_marker_segments: int = 48

## One alpha shared by every ghost state tint (tint_color, invalid/hole/locked/
## throw_aim tints keep their own RGB); GhostPreview._apply_validity_material()
## applies this instead of each colour's own alpha channel.
## DECISION: one new field rather than editing each tint's stored alpha, so a
## single F4 slider covers every state; the tints' alpha channels are overridden,
## not a second value to keep in sync.
@export var ghost_opacity: float = 0.9

## RGB of the decal GhostPreview._block_projection_decal projects downward from
## the held ghost's underside onto the real block beneath it (its alpha is
## ignored; see block_projection_alpha). Near-white to match
## footprint_base_color.
@export var block_projection_color: Color = Color(0.95, 0.95, 0.95, 1.0)
## Alpha of the block-projection decal: fainter than footprint_alpha since a
## placed block has its own lit surface to read through, unlike the flat disc.
@export var block_projection_alpha: float = 0.5
## The block-projection decal's upper/lower fade exponent (Decal.upper_fade/lower_fade: 1 - |height in box| raised to this).
## Tiny by default so the projection stays a crisp full-strength shaft, but
## never 0 -- game/player/GhostPreview.gd clamps it above zero, since a fade of 0.0
## makes any surface lying exactly on the decal box's top or bottom plane
## render as NaN (black speckle).
@export var block_projection_edge_fade: float = 0.001
## Decal.normal_fade of the block-projection decal. The decal projects straight
## down, so without this a block beside or inside the ghost's column gets its
## VERTICAL faces painted too; faces turned away from the projection are faded
## out. 0 disables, higher fades more steeply.
@export var block_projection_normal_fade: float = 0.5

## Emission multiplier of the steady rim glow: a fresnel rim in the ghost's tint
## colour, presentation only (GhostPreview.gd, shaders/blocks/
## ghost_cell_grid.gdshader). It pulses rapidly shortly before the forced drop.
@export var glow_strength: float = 1.0
## Fresnel exponent: higher keeps the glow on the silhouette edge, lower spreads
## it over the whole face.
@export var glow_rim_power: float = 1.5
## Seconds before the forced (timer) drop at which the glow starts pulsing.
@export var glow_warning_lead_seconds: float = 1.0
## Pulse rate (Hz) when the warning begins, ramping linearly to the end rate at
## the moment of the drop.
@export var glow_pulse_start_hz: float = 3.0
@export var glow_pulse_end_hz: float = 10.0
## Glow multiplier reached at the peak of each warning pulse (1 = no pulse).
@export var glow_pulse_peak_multiplier: float = 4.0


## Height above the disc surface at which a first block's lowest point must sit to
## clear the home beacon: the beacon's top plus home_spawn_beacon_margin. The ONE
## rule behind both the player's first hover (PlayerController.
## _seed_home_spawn_raise()) and the host's no-cursor AFK auto-drop origin
## (net/MatchNet.gd _on_feed_timer_expired() via home_spawn_pivot_height()).
## DECISION: lives here, not on Match: both callers already hold a GhostTuning
## and a BeaconVisualTuning, and it is pure (no scene tree).
func home_spawn_clear_hover(beacon_visuals: BeaconVisualTuning) -> float:
	return beacon_visuals.beacon_top_height() + home_spawn_beacon_margin


## home_spawn_clear_hover() expressed as the origin height the host spawns an
## unrotated block at (what MatchNet's no-cursor fallback sends). A block's origin
## is the bottom-face pivot of its lowest cells (BlockShape.bottom_center()), and
## its lowest collision point sits cube_margin / 2 above that pivot
## (GhostPreview._rotated_bottom_offset()), so the pivot goes that much lower.
## Shape-independent: every shape's lowest cells put the pivot on their bottom face.
func home_spawn_pivot_height(beacon_visuals: BeaconVisualTuning, physics_tuning: PhysicsTuning) -> float:
	return home_spawn_clear_hover(beacon_visuals) - physics_tuning.cube_margin * 0.5


## A home flag's field-local position moved home_spawn_back_offset metres horizontally away from the field centre (unchanged at the centre).
## metres horizontally away from the field centre (unchanged at the centre).
func home_spawn_back_position(local_home: Vector3) -> Vector3:
	var away: Vector3 = Vector3(local_home.x, 0.0, local_home.z)
	if away.length() < 0.0001:
		return local_home
	return local_home + away.normalized() * home_spawn_back_offset
