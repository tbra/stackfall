class_name TerritoryVisuals
extends Resource
## Every tunable number the territory overlay, its shader and the flags use
## (spec 1.10, 2.5).
##
## These are presentation numbers only: nothing here may change a rule.
## TerritoryTuning holds the rule numbers, MapDef the geometry, and this
## resource how the result looks.
##
## Loaded once as config/territory/territory_visuals.tres.

## -- Disk surface -----------------------------------------------------------
## The disk's own color where no team owns the ground.
##
## DECISION: a dark graphite/lacquer top; a bright base blended with the reflections
## read as brownish and see-through.
##
## DECISION: a cool blue-grey rather than a near-black neutral: a neutral-to-warm
## base lets the warm sky tint the fresnel-attenuated mirror almost unopposed.
## Surface definition for the disc top (config/territory/disc_surfaces/*.tres,
## DiscSurfaceDef). null keeps the flat look. # DECISION: one Resource reference so
## the owner switches surfaces from one place in the editor.
@export var disc_surface: DiscSurfaceDef = null

@export var disk_base_color: Color = Color(0.18, 0.23, 0.36)
## Metallic response; drives the shader's SPECULAR/METALLIC-visible reflection of
## the sky.
##
## DECISION: a glossy dielectric, not a high metallic: at high metallic the lit
## albedo (the territory tint and the mirror image both) only tinted the environment
## reflection, so the mirror barely read and the tint was muddy.
##
## DECISION: the disc is opaque, so a resting block does not look reflected in the
## surface under it.
##
## DECISION: the sun hot spot is the light's specular lobe, which is off on the disc
## (see shaders/territory/territory.gdshader's render_mode DECISION).
##
## DECISION: the crisp block reflection comes from the reflection probe and SSR, not
## from this value.
##
## DECISION: kept low because the built-in env/probe/SSR path samples the sky
## directly and turns into a flat warm wash if metallic is raised.
@export var disk_metallic: float = 0.16
## DECISION: low but short of 0.0, so reflections are soft-edged rather than a
## razor-sharp mirror. Only the ambient/probe/SSR sheen reads this (direct-light
## specular is off on the disc).
@export var disk_roughness: float = 0.3
## Radial segments of the disk mesh. High enough that the rim reads as a
## circle rather than a polygon at the camera distances spec 1.3 allows.
@export var disk_mesh_segments: int = 96

## -- Top-surface brushed/plank grain: shaders/territory/territory.gdshader's own
## top_grain_* uniforms, a cheap hash-noise NORMAL/ROUGHNESS perturbation on the
## flat top surface only (game/field/ArenaMesh.gd textures the side band/chamfer, a
## separate mesh/material). Nearly invisible in plain diffuse/ambient light by
## design: it only breaks up the explicit sun-facing sheen (disk_sheen_*) and the
## ambient/SSR/probe specular into fine streaks.
## Amplitude of the NORMAL tilt the grain applies; 0 disables it entirely
## (a perfectly flat normal).
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

## Cool sky-coloured fresnel sheen on the disc top, strongest at grazing angles (the far side of the disc).
@export var disk_sky_sheen_color: Color = Color(0.65, 0.6, 0.62)
@export var disk_sky_sheen_strength: float = 0.15
@export var disk_sky_sheen_power: float = 8.0

## Flat cool graphite fill on the disc top, added as emission so the disc keeps its cool hue whatever colour the sky ambient is. Darken it (or scale by a night theme) for night.
@export var disk_fill_color: Color = Color(0.3, 0.33, 0.42)

## Scale of the sky ambient diffuse light on the disc top (shaders/territory/territory.gdshader AO). Lower keeps the graphite from borrowing the sunset colour.
@export var disk_ambient_scale: float = 0.6

## Dielectric reflectance F0 of the disc top (SPECULAR built-in; 0.5 = engine default).
@export var disk_specular: float = 0.3

## Edge length (m) of the procedural machined-panel tiles on the disc top.
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

## -- Sun-facing sheen / diffuse cooling: a cool graphite top with a warm gold sheen
## gradient toward the sun ---------------------------------------------------
## Overall energy of the disc top's DIRECT DirectionalLight3D diffuse
## response (shaders/territory/territory.gdshader's own light() function) -- ambient/
## IBL are untouched by this. < 1 so the sun (tuned for the blocks in Main.tscn)
## doesn't dominate the disc's own cool disk_base_color the way Godot's uncapped
## default diffuse response did.
@export var disk_diffuse_response: float = 0.45
## How much the direct light's own warm colour is desaturated toward its
## luminance before it multiplies the disc's ALBEDO in that same light()
## function -- 1.0 removes the hue entirely (brightness-only shading), 0.0
## leaves it fully warm (Godot's ordinary default).
@export var disk_diffuse_desaturate: float = 0.85
## Color of the sun-facing sheen (a warm gold sheen on the half of the disc toward the sun).
@export var disk_sheen_color: Color = Color(1.0, 0.78, 0.4)
## Peak strength of the sun-facing sheen; 0 disables it.
##
## DECISION: a low peak, because a higher one adds enough EMISSION to wash out a
## team's own tint on the sun-facing half (deep red territory near a home flag read
## as flat gold). The view-dependent reflect()-based term (see shaders/territory/
## territory.gdshader's own DECISION) is localized to where the disc genuinely
## mirrors the sun toward the camera, so a modest value is visible.
@export var disk_sheen_strength: float = 0.15
## Shininess exponent shaping the sheen's specular-style falloff (shaders/
## territory.gdshader's own light-reflected-toward-camera dot product raised
## to this power) -- deliberately LOW (a broad, soft lobe) rather than a
## tight mirror-sharp highlight; higher narrows it.
##
## DECISION: the sheen is view-dependent (the view vector reflected about the
## surface normal, compared with the sun direction) rather than a fixed gradient
## across the disc, which painted the same half gold from every camera angle as a
## flat wash or hard diagonal terminator.
@export var disk_sheen_exponent: float = 40.0

## DECISION: the disk is opaque, not translucent, so there are no disk-opacity
## tunables.

## -- Territory tint (spec 1.10: "a soft tint in their color") ---------------
## Half-width of the smoothstep applied to the bilinear owning-slot edge, in owning-slot
## units (the texture's R channel counts teams, so 1.0 is one whole team
## step). Larger is blurrier. Only the raster (fallback) path
## (shaders/territory/territory.gdshader's `circles_valid == false` branch) reads
## this -- see edge_softness_m right below for the analytic path's own
## equivalent, which is what ordinary play actually renders.
@export var edge_softness: float = 0.4
## Half-width, in meters, of the smoothstep applied to the analytic path's
## ownership TINT (shaders/territory/territory.gdshader's circle_path(), the ordinary
## rendering path whenever circle_count doesn't overflow
## max_shader_circles). Spec 1.10: the edge of the area is crisp.
##
## DECISION: split out of rim_soft_width below, because the tint's coverage
## smoothstep and the glow's coverage gate are different effects (spec 1.10 lists
## "a soft tint" and "an animated outline" separately), and blurring the tint by as
## much as the glow (0.25 m) read as a blurry ownership boundary. 0.03 m is as
## crisp as a still screenshot can tell from a hard edge; a literal one-pixel
## transition (0) can alias/shimmer at a shallow camera angle.
@export var edge_softness_m: float = 0.03
## How much of the owner color is mixed over the disk at full coverage.
##
## DECISION: a translucent tint (~25-35%) with a crisp luminous boundary; the
## boundary itself stays bright via rim_strength/outline_strength, which this field
## does not touch.
@export var tint_alpha: float = 0.3

## -- Animated outline (spec 1.10: "with an animated outline") ---------------
## Half-width of the outline band around a territory edge, same units as
## edge_softness.
@export var outline_width: float = 0.10
## Pulses per second along the outline.
@export var outline_speed: float = 1.6
## Emission strength of the outline at the peak of its pulse.
##
## DECISION: raised so the raster-fallback outline crosses Main.tscn's HDR glow
## threshold (1.1) and reads as a luminous boundary line, matching rim_strength
## below (the ordinary analytic path's own equivalent).
@export var outline_strength: float = 1.6
## How much of the pulse is animated; the rest is a constant outline.
@export var outline_pulse_depth: float = 0.12

## -- Contested cells (spec 1.10: "Contested areas shimmer") -----------------
@export var contested_color: Color = Color(1.0, 0.95, 0.75)
## Shimmer cycles per second.
@export var contested_shimmer_rate: float = 5.0
## Spatial frequency of the shimmer's travelling bands, in cycles across the
## whole disk.
@export var contested_shimmer_scale: float = 24.0
@export var contested_shimmer_strength: float = 0.4

## -- Holes (spec 1.10: "Hole edges glow", 3.3: the shader discards holes) ---
@export var hole_rim_color: Color = Color(1.0, 0.45, 0.12)
## Width of the glowing rim just outside a hole, in hole-mask units.
@export var hole_rim_width: float = 0.35
@export var hole_rim_glow: float = 2.5

## -- Flags (spec 1.5) --------------------------------------------------
@export var goal_flag_color: Color = Color(0.95, 0.93, 0.85)

## -- Goal capture ring (spec 1.5: "A radial progress ring appears on each
## goal flag while someone is capturing it") --------------------------------
## Outer radius of the ring lying on the disk around a goal flag.
@export var capture_ring_radius: float = 2.2
@export var capture_ring_thickness: float = 0.45
## Height above the disk surface, so the ring never z-fights the disk.
@export var capture_ring_lift: float = 0.06
## Segments in the full circle; the drawn arc uses a proportional share.
@export var capture_ring_segments: int = 64
@export var capture_ring_emission: float = 1.8

## -- Analytic circle rendering ---------------------------------------------------
## game/field/TerritoryOverlay.gd feeds the shader the home-anchored circle list
## itself (disk-local x/z/radius/team, one texel per circle) alongside the cell
## raster, so the territory border is the analytic union of real circles instead of
## a smoothstepped, bilinearly-upscaled 1 m cell grid, which can only look like a
## blurred grid (game/field/TerritoryOverlay.gd's class doc explains why). These
## fields are separate from edge_softness/outline_* above: those drive the *raster
## fallback* path (shaders/territory/territory.gdshader's `circles_valid == false`
## branch, taken when the circle list overflows max_shader_circles), which has only
## the bilinear owning-slot ramp and so no meaning of "meters from the analytic
## boundary".
##
## Half-width, in meters, of the smoothstep applied to a team's analytic
## coverage value (radius - distance to the nearest/union-blended circle of
## that team). Larger reads blurrier.
@export var rim_soft_width: float = 0.25
## Half-width, in meters, of the bright rim band drawn just inside a
## territory's analytic edge.
@export var rim_width: float = 0.12
## Emission strength of the rim at the peak of its pulse.
##
## DECISION: raised past Main.tscn's HDR glow threshold (1.1) so the ordinary
## analytic path's territory boundary blooms slightly (outline_strength above is
## the raster-fallback path's own equivalent).
@export var rim_strength: float = 1.8
## How much of the rim's pulse is animated; the rest is a constant glow.
@export var rim_pulse_depth: float = 0.12
## Pulses per second along the rim.
@export var rim_speed: float = 1.6
## Smooth-min/-max blend radius, in meters, used when two overlapping
## same-team circles are combined into one team coverage value (the
## "metaballs" look). 0 disables blending (a plain union,
## still smooth-edged, just with a visible seam angle where two circles of
## different radii meet).
@export var metaball_blend: float = 0.3
## Circles the shader actually loops per pixel before falling back to the
## raster path for that frame. Defaults to
## TerritoryTuning.max_circles; lower this on weaker GPUs without touching
## the solver's own cap.
@export var max_shader_circles: int = 400
## Bake the circle field into a texture only when the circle
## set changes (shaders/territory/territory_circle_bake.gdshader) so the disc shader does
## two texture reads per pixel instead of looping circles. Off = per-pixel loop.
@export var circle_bake_enabled: bool = true
## Bake resolution in texels per metre (6 = 0.17 m texels; edge accuracy is
## sub-centimetre because the baked values are a continuous distance field).
@export_range(1.0, 16.0, 0.5) var circle_bake_texels_per_m: float = 6.0

## -- Reflections (spec 1.10: an opaque, mirror-like polished surface with sky
## reflections via the Environment sky and a reflection probe for nearby blocks) --
##
## Main.tscn's Environment reflects its Sky (background_mode == BG_SKY,
## reflected_light_source at its default REFLECTION_SOURCE_BG). Forward+ never
## reflects dynamic scene geometry (the placed blocks) without a ReflectionProbe or
## screen-space reflections, and a flat metallic disk with only the sky's smooth
## gradient in it reads as a dull tint, not a mirror. game/sky/Skybox.gd builds a
## ReflectionProbe from these fields (see its class doc for why the box is sized
## once, for the largest map, rather than resized per active MapDef).
@export var reflection_probe_enabled: bool = true
## A dev/F4 override that forces UPDATE_ALWAYS (six faces every
## frame, ~2.5 ms on a 3060 at 3440x1440) regardless of the graphics preset. Default
## false: the refresh strategy (off / once / interval / always) is the preset's
## GraphicsPreset.reflection_probe_mode, which game/sky/Skybox.gd applies.
@export var reflection_probe_update_always: bool = false
## Extra meters of box half-width beyond MapDef.RADIUS_LARGE (spec 1.9's
## largest map size), so one static probe box covers every map without
## resizing itself per match. DECISION: a fixed box sized for the largest map,
## because game/main/Main.gd is the integrator's file and Field.gd's `map_def`
## export is not reassigned per match at runtime today (only tools/*.gd screenshot
## scripts override it). Revisit if Field.map_def becomes per-match again.
@export var reflection_probe_margin_m: float = 15.0
## Full box height of the reflection probe, in meters, so it also captures a
## tall stack of blocks above the disk, not just the sky at grazing angles.
@export var reflection_probe_height_m: float = 40.0

## -- Screen-space reflections -----------------------------------------------------
##
## The ReflectionProbe above only samples a static/periodic cubemap snapshot of the
## scene, blurred by distance from the probe's own origin -- from the follow
## camera's shallow angle it reads as a faint tint, not a legible mirror image of a
## specific block. SSR marches the actual depth/color buffer per pixel instead, so a
## block on screen shows up in the disk's reflection at roughly its true screen
## position. game/sky/Skybox.gd's configure_ssr() writes these onto the wired
## Environment each time refresh_from_visuals() runs (boot, and every live F4 edit),
## mirroring configure_reflection_probe()'s no-op-when-unwired contract. Kept
## alongside the probe: SSR can only reflect what is already rendered on screen, so
## it still needs the probe's cubemap for anything off-screen or behind the camera.
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

## -- Screen-space ambient occlusion -----------------------------------------------
##
## Skybox.gd's configure_ssr() also writes these onto the wired Environment.
## Default OFF; every tunable below defaults to
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
