class_name TerritoryVisuals
extends Resource
## Every tunable number the territory overlay, its shader and the flags use
## (spec 2.10, 3.3). CLAUDE.md: "No magic numbers... every tunable value
## belongs in a Resource under res://config/".
##
## These are presentation numbers only: nothing here may change a rule.
## TerritoryTuning holds the rule numbers, MapDef the geometry, and this
## resource how the result looks. M2 asks only for a readable soft tint, an
## outline, a shimmer and a hole; the full look of spec 2.10 is M7.
##
## Loaded once as config/territory_visuals.tres.

## -- Disk surface -----------------------------------------------------------
## The disk's own color where no team owns the ground.
@export var disk_base_color: Color = Color(0.68, 0.70, 0.74)
## Bontago-xtq.4 (owner, 2026-09-22: "a bit transparent and reflective"):
## retuned from 0.1 toward a metallic response; drives the shader's
## SPECULAR/METALLIC-visible reflection of ProceduralSky.
##
## DECISION (config/TerritoryVisuals.gd, Bontago-xtq.6, owner 2026-09-23:
## "the bottom reflects what's on top... also it reflects whatever light
## source you've put in"): brought back down from 0.6 to 0.2 -- at the time
## combined with disk_roughness's old 0.1, the disk read as a near-mirror,
## which made a resting block look reflected in the surface under it and the
## DirectionalLight3D's specular highlight read as a hot mirror spot. Interim
## fix per the owner's note ("we'll work more on the design in m7").
##
## DECISION (config/TerritoryVisuals.gd, Bontago-xtq.11, owner 2026-09-23:
## "I think the disc is a mirror-like surface and not glass, so it should be
## reflective but not transparent"): raised back to a high value against
## docs/original_single-block.png and docs/original_stacked-tower.png (an
## opaque orange disk with a soft, slightly blurred reflection of the sky and
## the tower standing on it, not a sharp mirror and not a diffuse matte
## surface). The disk being genuinely opaque now (not blending its reflection
## over whatever sits below it, see the DECISION further down) is what
## removes the earlier "hot mirror spot"/reflected-block complaint, so
## metallic can go back up without reintroducing it.
@export var disk_metallic: float = 0.85
## DECISION (config/TerritoryVisuals.gd, Bontago-xtq.11): lowered back toward
## glass-smooth, same reference screenshots as disk_metallic above -- the
## reflections in both are soft-edged, not a razor-sharp mirror, so this
## stops short of 0.0.
@export var disk_roughness: float = 0.18
## Radial segments of the disk mesh. High enough that the rim reads as a
## circle rather than a polygon at the camera distances spec 2.5 allows.
@export var disk_mesh_segments: int = 96

## DECISION (config/TerritoryVisuals.gd, Bontago-xtq.11, owner 2026-09-23:
## "the disc is a mirror-like surface and not glass ... reflective but not
## transparent"): the two disk-opacity tunables that used to live here were
## removed -- the disk is opaque now, not translucent.

## -- Territory tint (spec 2.10: "a soft tint in their color") ---------------
## Half-width of the smoothstep applied to the bilinear owner edge, in owner
## units (the texture's R channel counts teams, so 1.0 is one whole team
## step). Larger is blurrier. Only the raster (fallback) path
## (shaders/territory.gdshader's `circles_valid == false` branch) reads
## this -- see edge_softness_m right below for the analytic path's own
## equivalent, which is what ordinary play actually renders.
@export var edge_softness: float = 0.4
## Half-width, in meters, of the smoothstep applied to the analytic path's
## ownership TINT (shaders/territory.gdshader's circle_path(), the ordinary
## rendering path whenever circle_count doesn't overflow
## max_shader_circles). Spec 2.10, updated Bontago-xtq.14 (owner: "the edge
## of the area is a bit blurry, sharpen it", reference docs/original_hover-
## preview.png's hard-edged look).
##
## DECISION (config/TerritoryVisuals.gd, Bontago-xtq.14): split out of
## rim_soft_width below, which the tint's coverage smoothstep and the rim
## glow's own coverage gate used to share -- the two are different effects
## (spec 2.10 lists them separately: "a soft tint" vs. "an animated
## outline"), and blurring the tint by as much as the glow (0.25 m) is what
## read as the ownership boundary itself being blurry rather than crisp.
## rim_soft_width/rim_width/rim_strength/rim_pulse_depth/rim_speed below are
## unchanged and still shape only the glow band. Default (0.03 m == 3 cm) is
## "as crisp as a still screenshot can tell apart from a hard edge" without
## going all the way to 0 (legal, but a literal one-pixel-wide transition can
## alias/shimmer at a shallow camera angle where many world meters map to
## one screen pixel).
@export var edge_softness_m: float = 0.03
## How much of the owner color is mixed over the disk at full coverage.
@export var tint_alpha: float = 0.55

## -- Animated outline (spec 2.10: "with an animated outline") ---------------
## Half-width of the outline band around a territory edge, same units as
## edge_softness.
@export var outline_width: float = 0.16
## Pulses per second along the outline.
@export var outline_speed: float = 1.6
## Emission strength of the outline at the peak of its pulse.
@export var outline_strength: float = 1.4
## How much of the pulse is animated; the rest is a constant outline.
@export var outline_pulse_depth: float = 0.45

## -- Contested cells (spec 2.10: "Contested areas shimmer") -----------------
@export var contested_color: Color = Color(1.0, 0.95, 0.75)
## Shimmer cycles per second.
@export var contested_shimmer_rate: float = 5.0
## Spatial frequency of the shimmer's travelling bands, in cycles across the
## whole disk.
@export var contested_shimmer_scale: float = 24.0
@export var contested_shimmer_strength: float = 0.4

## -- Holes (spec 2.10: "Hole edges glow", 3.3: the shader discards holes) ---
@export var hole_rim_color: Color = Color(1.0, 0.45, 0.12)
## Width of the glowing rim just outside a hole, in hole-mask units.
@export var hole_rim_width: float = 0.35
@export var hole_rim_glow: float = 2.5

## -- Flags (spec 2.2, 2.3) --------------------------------------------------
@export var flag_pole_height: float = 3.2
@export var flag_pole_radius: float = 0.09
@export var flag_pole_color: Color = Color(0.85, 0.86, 0.88)
## Width and height of the banner at the top of the pole.
@export var flag_banner_size: Vector2 = Vector2(1.6, 0.9)
## How much the goal flag's banner is scaled up from a home flag's.
@export var goal_flag_scale: float = 1.35
@export var goal_flag_color: Color = Color(0.95, 0.93, 0.85)
## Emission strength of a flag's banner, so owners read at a glance.
@export var flag_emission: float = 0.6

## -- Goal capture ring (spec 2.3: "A radial progress ring appears on each
## goal flag while someone is capturing it") --------------------------------
## Outer radius of the ring lying on the disk around a goal flag.
@export var capture_ring_radius: float = 2.2
@export var capture_ring_thickness: float = 0.45
## Height above the disk surface, so the ring never z-fights the disk.
@export var capture_ring_lift: float = 0.06
## Segments in the full circle; the drawn arc uses a proportional share.
@export var capture_ring_segments: int = 64
@export var capture_ring_emission: float = 1.8

## -- Analytic circle rendering (Bontago-cmc.5, owner requirement: "should
## look smooth... some kind of metaballs system") ----------------------------
## game/TerritoryOverlay.gd now feeds the shader the home-anchored circle
## list itself (disk-local x/z/radius/team, one texel per circle) alongside
## the cell raster, so the territory border is the analytic union of real
## circles instead of a smoothstepped, bilinearly-upscaled 1 m cell grid —
## the grid can only ever look like a blurred grid, never a curve
## (game/TerritoryOverlay.gd's class doc explains why). These fields are
## deliberately separate from edge_softness/outline_* above: those still
## drive the *raster fallback* path (shaders/territory.gdshader's
## `circles_valid == false` branch, taken when the circle list overflows
## max_shader_circles), which has no continuous distance field to feather —
## only the bilinear owner ramp — so it cannot share this path's meaning of
## "meters from the analytic boundary".
##
## Half-width, in meters, of the smoothstep applied to a team's analytic
## coverage value (radius - distance to the nearest/union-blended circle of
## that team). Larger reads blurrier.
@export var rim_soft_width: float = 0.25
## Half-width, in meters, of the bright rim band drawn just inside a
## territory's analytic edge (docs/ORIGINAL_BONTAGO_NOTES.md: "a bright
## border around the rim of the shaded area").
@export var rim_width: float = 0.35
## Emission strength of the rim at the peak of its pulse.
@export var rim_strength: float = 1.4
## How much of the rim's pulse is animated; the rest is a constant glow.
@export var rim_pulse_depth: float = 0.45
## Pulses per second along the rim.
@export var rim_speed: float = 1.6
## Smooth-min/-max blend radius, in meters, used when two overlapping
## same-team circles are combined into one team coverage value — the
## "metaballs" look the owner asked for. 0 disables blending (a plain union,
## still smooth-edged, just with a visible seam angle where two circles of
## different radii meet).
@export var metaball_blend: float = 0.3
## Circles the shader actually loops per pixel before falling back to the
## raster path for that frame (docs, "Bounded cost"). Defaults to
## TerritoryTuning.max_circles; lower this on weaker GPUs without touching
## the solver's own cap.
@export var max_shader_circles: int = 400

## -- Reflections (spec 2.10, updated 2026-09-23: "Opaque, mirror-like
## polished surface ... with sky reflections via the Environment sky and a
## reflection probe for nearby blocks") ---------------------------------------
##
## Bontago-xtq.12 (owner playtest: "isn't very reflective, like at all"):
## disk_metallic/disk_roughness above were already correct (TerritoryOverlay.
## refresh_visual_uniforms() does push them to the shader every time), and
## Main.tscn's Environment already reflects its Sky (background_mode ==
## BG_SKY, reflected_light_source left at its default REFLECTION_SOURCE_BG,
## which samples the same Sky the background shows). What was missing is
## something to reflect: Forward+ never reflects dynamic scene geometry (the
## placed blocks) without a ReflectionProbe or screen-space reflections — a
## flat metallic disk with only the sky's own smooth gradient in it reads as
## a dull tint, not a mirror, exactly the report. game/Skybox.gd now builds a
## ReflectionProbe from these fields (see its class doc for why the box is
## sized once, for the largest map, rather than resized per active MapDef).
@export var reflection_probe_enabled: bool = true
## UPDATE_ALWAYS recomputes the probe's cubemap every frame, so a block that
## lands after boot still shows up in the disk's reflection (accurate, more
## GPU cost); UPDATE_ONCE captures a single snapshot at boot and never again
## (cheap, but every block placed afterward is invisible in the reflection
## until the scene reloads).
##
## DECISION (config/TerritoryVisuals.gd, Bontago-xtq.12): default true.
## tools/screenshot_xtq11_disk_opaque.gd's --reflection-mode=once/always
## comparison in a windowed run with several placed blocks measured well
## under a millisecond of extra frame time for ALWAYS over ONCE at this
## scene's scale (one small disk, a handful of blocks) — see the package
## report for the numbers — and a stale reflection would look like a new
## bug (blocks players just placed missing from the mirror) worse than the
## small, currently unmeasurable-in-practice cost of recomputing every frame.
@export var reflection_probe_update_always: bool = true
## Extra meters of box half-width beyond MapDef.RADIUS_LARGE (spec 2.8's
## largest map size), so one static probe box covers every map without
## resizing itself per match. DECISION (config/TerritoryVisuals.gd,
## Bontago-xtq.12): game/Main.gd is integrator-owned (its own class doc:
## "the one file nobody but the integrator owns"), so a per-match MapDef ->
## probe resize call is out of this package's file ownership; Field.gd's own
## `map_def` export is not actually reassigned per match at runtime today
## either (only tools/*.gd screenshot scripts override it directly), so a
## fixed box sized for the largest map is not a regression against current
## behavior. Revisit alongside any future fix that makes Field.map_def
## per-match again.
@export var reflection_probe_margin_m: float = 15.0
## Full box height of the reflection probe, in meters, so it also captures a
## tall stack of blocks above the disk, not just the sky at grazing angles.
@export var reflection_probe_height_m: float = 40.0

## -- Screen-space reflections (Bontago-xtq.12 step 2, owner: "the disc
## isn't very reflective, like at all?") -------------------------------------
##
## The ReflectionProbe above (step 1) only ever samples a static/periodic
## cubemap snapshot of the scene, blurred by distance from the probe's own
## origin -- from the follow camera's shallow angle it reads as a faint tint,
## not a legible mirror image of a specific block. SSR marches the actual
## depth/color buffer per pixel instead, so a block that is currently on
## screen shows up in the disk's reflection at roughly its true screen
## position, not just contributing to one blurred cubemap texel. game/
## Skybox.gd's configure_ssr() writes these onto the wired Environment each
## time refresh_from_visuals() runs (boot, and every live F4 edit), mirroring
## configure_reflection_probe()'s own no-op-when-unwired contract. Kept
## alongside the probe (not a replacement for it): SSR can only ever reflect
## what is already rendered on screen, so it still needs the probe's cubemap
## for anything off-screen or behind the camera.
@export var ssr_enabled: bool = true
## Ray-march steps per pixel; Environment's own engine default. Higher finds
## thinner/further occluders at more GPU cost.
@export var ssr_max_steps: int = 64
## Meters of ray travel over which a reflection fades in from nothing, so a
## reflection does not pop in sharply right at the reflective surface.
@export var ssr_fade_in: float = 0.15
## Meters of ray travel over which a reflection fades out toward the probe/
## sky fallback, so a long ray does not cut off sharply once it runs out of
## on-screen depth to march against.
@export var ssr_fade_out: float = 2.0
## Depth-buffer tolerance, in meters, for a marched ray to count as hitting a
## surface; Environment's own engine default.
@export var ssr_depth_tolerance: float = 0.2

## -- Planar mirror (Bontago-xtq.12 step 2) -----------------------------------
##
## game/DiscMirror.gd renders a second camera, mirrored about the disk's own
## plane, into a SubViewport; shaders/territory.gdshader blends that
## viewport's texture over the disk wherever SSR/the probe leave off, so a
## block standing on the disk shows up as a true, per-pixel mirror image
## regardless of screen-space or cubemap-snapshot limits. Wired the same way
## reflection_probe_enabled is: read once at boot and again on every
## refresh_from_visuals() (F4 live edit), never per-match.
@export var mirror_enabled: bool = true
## How much of the disk's reflection comes from the planar mirror texture
## versus the plain metallic/probe/SSR response above; 0 disables the blend
## even if mirror_enabled leaves the viewport itself rendering.
@export var mirror_strength: float = 0.85
## SubViewport size as a fraction of the main viewport's own size. Below 1.0
## trades reflection sharpness for the cost of rendering the whole scene a
## second time every frame.
@export var mirror_resolution_scale: float = 0.5
## Bontago-xtq.20 (owner, 2026-09-23 20:12: "the main light source is
## glaringly visible in the disc reflection"): caps the mirror-sampled
## color's luminance (hue-preserving) before shaders/territory.gdshader mixes
## it into ALBEDO -- see that shader's own uniform doc for why a raw sun disc
## / specular hot spot reads far worse mixed directly into the disk's albedo
## than it would rendered normally, and why a luminance clamp (not disabling
## the light's specular scene-wide, which the mirror SubViewport cannot do
## selectively -- see game/DiscMirror.gd's class doc on own_world_3d) is the
## fix. Pushed onto the shader by game/DiscMirror.gd's _process() through
## TerritoryOverlay's own public material() accessor -- not through
## game/TerritoryOverlay.gd's set_mirror_texture() (that file is out of this
## package's ownership; see DiscMirror.gd's own DECISION comment on this).
@export var mirror_max_luminance: float = 1.35
