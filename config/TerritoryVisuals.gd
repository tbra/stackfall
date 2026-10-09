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
##
## DECISION (config/TerritoryVisuals.gd, Bontago-mp0.3.2, owner feedback: "the
## disc is just a thin mirror currently ... the mockup has a much thicker
## metallic disc"): darkened from a lit slate-grey toward the mockup's near-
## black graphite/lacquer top -- the previous value, blended with a bright
## uncapped planar mirror (since removed), is what read as "brownish, almost see-through".
##
## DECISION (config/TerritoryVisuals.gd, Bontago-mp0.3.2 review pass 2, owner:
## "flat muddy brown ... mockup is dark cool graphite/black lacquer (~
## #23262c-#2e3138, slightly blue-grey, not brown)"): re-picked as a cool
## blue-grey inside that hex range instead of a near-black neutral -- the
## "muddy brown" was mostly the fresnel-attenuated mirror letting the warm
## sky tint the disc almost unopposed (see mirror_center_fraction/
## mirror_max_luminance below), but a neutral-to-warm base color compounded
## it instead of pushing back cool.
## Bontago-adt.2: swappable texture set for the disc top (config/disc_surfaces/*.tres,
## DiscSurfaceDef). null keeps the flat look. # DECISION: one Resource reference so
## the owner switches sets from one place in the editor.
@export var disc_surface: DiscSurfaceDef = null

@export var disk_base_color: Color = Color(0.18, 0.23, 0.36)
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
##
## DECISION (config/TerritoryVisuals.gd, Bontago-xtq.20, reproduced by
## tools/screenshot_feel8b_disc_glare.gd): back down to a glossy dielectric.
## The mirror-like look came from a planar mirror pass (removed 2026-10-07; the
## disc now relies on the sky and probe reflections), not from metallic: at 0.85 the lit
## albedo -- the territory tint and the mirror image both -- only tinted the
## environment reflection, which is why the mirror barely read and the tint
## was muddy. The sun hot spot itself was the light's specular lobe, now off
## on the disc (shaders/territory.gdshader's render_mode DECISION).
##
## DECISION (config/TerritoryVisuals.gd, Bontago-mp0.3.2, owner feedback:
## "the disc is just a thin mirror currently ... the mockup has a much
## thicker metallic disc"): raised again toward docs/art_mockups/08-cel-
## shaded-home-beacons.png's dark polished graphite/black-lacquer top,
## alongside disk_base_color's own darkening and the new
## mirror_center_fraction/mirror_fresnel_power below, which now do the actual
## work of keeping the straight-down reflection subdued.
##
## DECISION (config/TerritoryVisuals.gd, Bontago-mp0.3.2 review pass 2):
## brought back down -- the built-in env/probe/SSR reflection path this
## drives samples the WorldEnvironment sky directly and, unlike the explicit
## planar mirror below, has no per-pixel block image or luminance cap to keep
## it from reading as a flat, blurred wash of the warm sky ("muddy brown,
## mirror reflections gone"). The crisp block reflection now comes from
## (removed mirror knobs) instead.
@export var disk_metallic: float = 0.16
## DECISION (config/TerritoryVisuals.gd, Bontago-xtq.11): lowered back toward
## glass-smooth, same reference screenshots as disk_metallic above -- the
## reflections in both are soft-edged, not a razor-sharp mirror, so this
## stops short of 0.0.
##
## Bontago-xtq.20: 0.3 -- only the ambient/probe/SSR sheen reads this now
## (direct-light specular is off on the disc), and a slightly softer sheen
## sits under the sharp planar mirror image instead of competing with it.
@export var disk_roughness: float = 0.3
## Radial segments of the disk mesh. High enough that the rim reads as a
## circle rather than a polygon at the camera distances spec 2.5 allows.
@export var disk_mesh_segments: int = 96

## -- Top-surface brushed/plank grain (Bontago-pt.12 part 2, owner: "the
## disc looks close to the mockup but it lacks the texture ... especially
## visible in the mockup where it interacts with the sun (top-right and
## bottom-center)") -- shaders/territory.gdshader's own top_grain_* uniforms,
## a cheap hash-noise NORMAL/ROUGHNESS perturbation on the flat top surface
## only (this package's own game/DiscBody.gd already textures the side
## band/chamfer, a separate mesh/material). Nearly invisible in plain
## diffuse/ambient light by design -- it only visibly breaks up the
## explicit sun-facing sheen (disk_sheen_* above) and the mirror/ambient/
## SSR/probe specular into fine streaks, matching the mockup's plank-like
## grain that "shows up" specifically where the disc catches the sun.
## Amplitude of the NORMAL tilt the grain applies; 0 disables it entirely
## (a perfectly flat normal, exactly the old behavior).
@export var top_grain_strength: float = 0.0
## Spatial frequency, in cycles per meter, of the coarse "plank" bands.
## Lower reads as fewer, wider bands; higher as many narrow ones.
@export var top_grain_scale: float = 0.35
## Multiplier on top_grain_scale for a finer "brushed" ripple layered inside
## each plank band -- the actual frequency of that fine layer is
## top_grain_scale * this value.
@export var top_grain_fine_scale: float = 6.0
## Amplitude of the grain's own small additive nudge to ROUGHNESS (on top of
## disk_roughness above); 0 disables it. Sign-symmetric (the grain height is
## centered on 0), so this only ever varies the reflection's sharpness in
## fine streaks, never dulls or polishes the disc as a whole.
@export var top_grain_roughness_strength: float = 0.0

## Bontago-adt.2: cool sky-coloured fresnel sheen on the disc top, strongest at grazing angles (the far side of the disc), like the mockup's lavender reflection on graphite.
@export var disk_sky_sheen_color: Color = Color(0.65, 0.6, 0.62)
@export var disk_sky_sheen_strength: float = 0.15
@export var disk_sky_sheen_power: float = 8.0

## Bontago-adt.2: flat cool graphite fill on the disc top, added as emission so the disc keeps its cool hue whatever colour the sky ambient is. Darken it (or scale by a night theme) for night.
@export var disk_fill_color: Color = Color(0.3, 0.33, 0.42)

## Bontago-adt.2: scale of the sky ambient diffuse light on the disc top (shaders/territory.gdshader AO). Lower keeps the graphite from borrowing the sunset colour.
@export var disk_ambient_scale: float = 0.6

## Bontago-adt.2: dielectric reflectance F0 of the disc top (SPECULAR built-in; 0.5 = engine default).
@export var disk_specular: float = 0.3

## Bontago-adt.2: edge length (m) of the procedural machined-panel tiles on the disc top.
@export var panel_size_m: float = 6.0

## Constant screen-space width (px) of the panel seams.
@export var panel_seam_width_px: float = 1.0

## How much panel seams darken the albedo (0 = invisible).
@export var panel_seam_strength: float = 0.0

## Per-panel brightness variation (fraction of albedo).
@export var panel_variation: float = 0.0

## Panels smaller than this on screen (px) fade their seams out to avoid moire at distance.
@export var panel_fade_px: float = 12.0

## Flat, light-independent emissive fill of the territory tint (keeps it readable under any sky/night theme).
@export var tint_fill_emission: float = 0.12

## -- Sun-facing sheen / diffuse cooling (Bontago-mp0.3.8, owner: "the disc
## top reads flat maroon-brown, mockup is dark cool graphite/black lacquer
## with a warm gold sheen gradient toward the sun") --------------------------
## Overall energy of the disc top's DIRECT DirectionalLight3D diffuse
## response (shaders/territory.gdshader's own light() function) -- ambient/
## IBL/the planar mirror are untouched by this. < 1 so the sun (tuned for the
## blocks in Main.tscn, out of scope here) doesn't dominate the disc's own
## cool disk_base_color the way Godot's uncapped default diffuse response did.
@export var disk_diffuse_response: float = 0.45
## How much the direct light's own warm colour is desaturated toward its
## luminance before it multiplies the disc's ALBEDO in that same light()
## function -- 1.0 removes the hue entirely (brightness-only shading), 0.0
## leaves it fully warm (Godot's ordinary default).
@export var disk_diffuse_desaturate: float = 0.85
## Color of the sun-facing sheen (docs/art_mockups/08-cel-shaded-home-
## beacons.png: a warm gold sheen on the half of the disc toward the sun).
@export var disk_sheen_color: Color = Color(1.0, 0.78, 0.4)
## Peak strength of the sun-facing sheen; 0 disables it.
##
## DECISION (config/TerritoryVisuals.gd, Bontago-mp0.3.8): 0.35 (this field's
## first-pass value, paired with the old fixed-position gradient) added
## enough EMISSION to wash out a team's own tint entirely on the sun-facing
## half (feedback/overhaul/disc2-r1-player.png: deep red territory near a
## home flag read as flat gold, not "red with a gold sheen") -- the brief's
## own "keep: territory tints" -- lowered. Re-raised somewhat (0.12 -> 0.6)
## after switching to the view-dependent reflect()-based term below (see
## shaders/territory.gdshader's own DECISION): that term is naturally more
## localized (only bright where the disc genuinely mirrors the sun toward
## the camera) than the old always-on half-disc gradient was, so the same
## visible brightness needs a higher peak value.
@export var disk_sheen_strength: float = 0.15
## Shininess exponent shaping the sheen's specular-style falloff (shaders/
## territory.gdshader's own light-reflected-toward-camera dot product raised
## to this power) -- deliberately LOW (a broad, soft lobe) rather than a
## tight mirror-sharp highlight; higher narrows it.
##
## DECISION (config/TerritoryVisuals.gd, Bontago-mp0.3.8 review pass, owner:
## "the sun sheen must be VIEW-DEPENDENT ... reflect the view vector about
## the surface normal and compare with the sun direction, or use the half-
## vector with a low exponent"): replaces the old disk_sheen_softness (a
## smoothstep width for a fixed disk-position gradient, independent of the
## camera) -- that version painted the same half of the disc gold from every
## angle, reading as a flat gold wash or a hard diagonal terminator on any
## framing other than the one it was tuned against (feedback/overhaul/disc2-
## r2-player.png, disc2-r3-overview.png).
@export var disk_sheen_exponent: float = 40.0

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
##
## DECISION (config/TerritoryVisuals.gd, Bontago-mp0.3.2 review pass 2, owner:
## "mockup fills are translucent tints (~25-35%) with crisp luminous boundary
## lines"): lowered from a fairly opaque wash toward that range; the boundary
## itself stays bright via rim_strength/outline_strength below, which this
## field does not touch.
@export var tint_alpha: float = 0.3

## -- Animated outline (spec 2.10: "with an animated outline") ---------------
## Half-width of the outline band around a territory edge, same units as
## edge_softness.
@export var outline_width: float = 0.10
## Pulses per second along the outline.
@export var outline_speed: float = 1.6
## Emission strength of the outline at the peak of its pulse.
##
## DECISION (config/TerritoryVisuals.gd, Bontago-mp0.3.2): raised so the
## raster-fallback outline actually crosses Main.tscn's HDR glow threshold
## (1.1) and reads as a luminous boundary line the way
## docs/art_mockups/08-cel-shaded-home-beacons.png's territory edges do,
## matching rim_strength below (the ordinary analytic path's own equivalent).
@export var outline_strength: float = 1.6
## How much of the pulse is animated; the rest is a constant outline.
@export var outline_pulse_depth: float = 0.12

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
@export var goal_flag_color: Color = Color(0.95, 0.93, 0.85)

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
@export var rim_width: float = 0.12
## Emission strength of the rim at the peak of its pulse.
##
## DECISION (config/TerritoryVisuals.gd, Bontago-mp0.3.2): raised past
## Main.tscn's HDR glow threshold (1.1) so the ordinary analytic path's
## territory boundary blooms slightly, matching
## docs/art_mockups/08-cel-shaded-home-beacons.png's luminous contour lines
## (outline_strength above is the raster-fallback path's own equivalent).
@export var rim_strength: float = 1.8
## How much of the rim's pulse is animated; the rest is a constant glow.
@export var rim_pulse_depth: float = 0.12
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
## Bontago-1pi.11.1: bake the circle field into a texture only when the circle
## set changes (shaders/territory_circle_bake.gdshader) so the disc shader does
## two texture reads per pixel instead of looping circles. Off = the old
## per-pixel loop.
@export var circle_bake_enabled: bool = true
## Bake resolution in texels per metre (6 = 0.17 m texels; edge accuracy is
## sub-centimetre because the baked values are a continuous distance field).
@export_range(1.0, 16.0, 0.5) var circle_bake_texels_per_m: float = 6.0

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
## Bontago-1pi.11.67: a dev/F4 override that forces UPDATE_ALWAYS (six faces every
## frame, ~2.5 ms on a 3060 at 3440x1440) regardless of the graphics preset. Default
## false: the refresh strategy (off / once / interval / always) is now the preset's
## GraphicsPreset.reflection_probe_mode, which game/Skybox.gd applies.
@export var reflection_probe_update_always: bool = false
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

## -- Screen-space ambient occlusion (Bontago-1pi.11.70, experiment for decision
## 1pi.11.68: "SSR off looked dull") -----------------------------------------
##
## Skybox.gd's configure_ssr() also writes these onto the wired Environment.
## Default OFF so the shipped look is unchanged; every tunable below defaults to
## Environment's own engine default. The SSAO quality/half-size level is a project
## setting (rendering/environment/ssao/*) and stays at the engine default.
@export var ssao_enabled: bool = false
## Distance, in meters, in which occluders are searched for.
@export_range(0.01, 16.0, 0.01, "or_greater") var ssao_radius: float = 1.0
## Strength of the occlusion darkening.
@export_range(0.0, 16.0, 0.01, "or_greater") var ssao_intensity: float = 2.0
## Exponent applied to the occlusion; higher darkens the crevices more sharply.
@export_range(0.01, 16.0, 0.01, "or_greater") var ssao_power: float = 1.5
## Extra fine-detail occlusion on small features.
@export_range(0.0, 1.0, 0.01) var ssao_detail: float = 0.5
## Horizon cutoff; higher ignores surfaces nearly parallel to the view.
@export_range(0.0, 1.0, 0.01) var ssao_horizon: float = 0.06
## Edge sharpness; higher reduces blur across depth edges.
@export_range(0.0, 1.0, 0.01) var ssao_sharpness: float = 0.98
## How much SSAO also darkens direct light (0 = ambient only).
@export_range(0.0, 1.0, 0.01) var ssao_light_affect: float = 0.0
## How much SSAO affects the baked/material AO channel.
@export_range(0.0, 1.0, 0.01) var ssao_ao_channel_affect: float = 0.0
