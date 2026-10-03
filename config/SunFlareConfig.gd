class_name SunFlareConfig
extends Resource
## Tunables for vfx/SunFlare.gd's screen-space lens flare (Bontago-mp0.3.4,
## "Graphics pass 2" -- owner feedback feedback/graphics_feedback.md: "lens
## flare from the sun"). Every number the shader (vfx/sun_flare.gdshader)
## and the driving script read lives here, following the same "no magic
## numbers" pattern config/CameraShakeConfig.gd already uses for
## game/CameraRig.gd.
##
## # DECISION (config/SunFlareConfig.gd, Bontago-mp0.3.4): this Resource is
## not yet wired into ui/TuningPanel.gd -- that file is out of this package's
## owned-file scope (CLAUDE.md pause-point discipline: do not touch another
## worker's owned files) and TuningPanel.gd hardcodes one `preload()`'d var
## per tunable Resource it exposes (no generic auto-discovery), so adding
## this file's section there needs a follow-up in that file itself. Flagged
## to the orchestrator in this package's handback; until that lands, these
## fields are Resource-only (edit config/sun_flare.tres directly), not
## live-editable from the in-game F4 panel.

## World-space direction from the field's center toward the sun (normalized).
## # DECISION (Bontago-1pi.1 v2): preserve the original flare axis and scene
## light rotation. sunset.tres rotates panorama sampling to place its painted
## sun on this axis; changing the light instead caused a grazing hotspot and
## moved the sun away from the default home view. See sunset_clouds.gdshader
## for the measured panorama centre and tools/capture_pt1_sun_sweep.gd for QA.
@export var sun_direction: Vector3 = Vector3(0.963087, 0.069011, -0.260192)

## Warm tint applied to every flare element (core, rays, ghosts) before
## per-element color/alpha below.
@export var sun_color: Color = Color(1.0, 0.86, 0.62)

## Bright core disc radius/softness, in normalized screen-diagonal units
## (see vfx/sun_flare.gdshader's own doc for the exact unit conversion). Fix
## round (owner: "reduce the hard white clipped look"): the painted panorama
## supplies the sun disc behind all geometry; this is a small sparkle on
## top of it, so it stays low-intensity rather than re-blowing-out the disc.
@export var core_radius: float = 0.022
@export var core_softness: float = 0.5
@export var core_intensity: float = 0.9

## A tight starburst sparkle right on the sun's own screen position -- NOT
## the big god-ray beams (those moved into shaders/sunset_clouds.gdshader's
## own sky pass, per the owner's fix-round feedback: they need to sit behind
## scene geometry, which only the sky pass can do for free). ray_length is
## deliberately small (a lens-artifact spike a few percent of the screen
## diagonal), not a long beam.
@export var ray_count: int = 8
@export var ray_length: float = 0.09
## Higher = thinner, sharper rays (an angular falloff exponent).
@export var ray_sharpness: float = 30.0
@export var ray_intensity: float = 0.4

## Ghost ("ghost ring") ghost discs sampled along the sun-to-screen-center
## axis, alternating between sun_color (warm) and ghost_color_b (teal) --
## fix round (owner: "make them visible but subtle, like a camera flare").
## # DECISION (config/SunFlareConfig.gd, Bontago-1pi.1): ghost_base_size and
## ghost_alpha both trimmed down from this fix round's own earlier values
## (0.06/0.65 before) -- this package's brief asks for ghost discs subtle
## enough that none of them reads as a second sun on its own; now that
## sun_direction actually points at the bright painted disc (see that
## field's own DECISION), a same-size-as-before ghost sitting a third of the
## way toward screen center read as too close in brightness/size to a small
## second sun in the feedback/pt-sun-before-* probe images. Kept non-zero
## (still "visible but subtle" per the owner's own fix-round wording above),
## not zeroed.
@export var ghost_count: int = 4
## Position of each ghost as a fraction of the way from the sun toward (and
## past) the screen center -- e.g. 0.5 sits halfway to center, 1.3 sits just
## past it on the opposite side.
@export var ghost_positions: PackedFloat32Array = PackedFloat32Array([0.35, 0.65, 1.0, 1.35])
@export var ghost_base_size: float = 0.03
@export var ghost_size_falloff: float = 0.72
@export var ghost_alpha: float = 0.22
## Bontago-t8x.3 (owner 2026-10-01: "from an angle it looks like there are 2
## suns"): ROOT CAUSE -- the first ghost sits ghost_positions[0] of the way from
## the sun to screen centre as a solid sun-coloured disc. Straight on the sun is
## at centre so every ghost collapses onto it; from the side the ghost separates
## and reads as a second sun. Ghosts are now hollow rings (this fraction of the
## ghost's radius is ring; 0 restores solid discs) and dimmer, so they read as
## lens artifacts. The sky-shader sun, the scene light and this flare's
## sun_direction all agree (tests/unit/test_sky_themes.gd asserts it).
@export var ghost_ring_width: float = 0.3
@export var ghost_color_b: Color = Color(0.35, 0.78, 0.72)

## Screen-space (0..1, with margin allowed to go slightly negative/above 1)
## fade band width near the viewport edge -- the flare fades out smoothly
## rather than popping off/on as the sun crosses the frame edge.
@export var edge_fade_margin: float = 0.18

## Minimum dot(camera_forward, sun_direction) for the sun to be considered
## "roughly ahead of the camera" at all -- below this the flare is fully
## faded regardless of screen position (an unprojected point behind the
## camera can still land inside the 0..1 screen rect after
## Camera3D.unproject_position(), so this guards that case).
@export var min_facing_dot: float = 0.05

## How fast (per second) the computed visibility (facing + edge fade +
## occlusion) is allowed to change -- smooths out a one-frame flicker as a
## block or the disc's own geometry momentarily occludes the sun's raycast
## test, rather than popping the flare fully on/off every frame.
@export var visibility_lerp_speed: float = 6.0

## Overall multiplier on the whole effect -- 0 turns the flare off entirely
## without touching any other field (used by vfx/SunFlare.gd to gate the
## effect off on the Low graphics preset).
@export var max_intensity: float = 1.0

@export_group("Occlusion (Bontago-mp0.95)")
## Owner playtest 2026-10-03: "sun is visible through the clouds and arena". ROOT CAUSE 1:
## the disc collider is a single-sided trimesh (game/Field.gd: faces only up and out of the
## rim), so the one camera-to-sun ray of vfx/SunFlare.gd passes unhit through the disc seen
## from below or edge-on. With this on, a second ray from the sun back to the camera is cast
## too (it meets the faces from outside) and either hit hides the flare. Off restores the
## single forward ray (for A/B captures).
@export var reverse_ray_enabled: bool = true
## How far from the camera (m, along the sun direction) the reverse ray starts: past the arena and the
## whole play volume, but short enough that a long float-precision ray does not leak between the disc
## quads. Never longer than the forward ray.
@export var reverse_ray_length_m: float = 800.0
## ROOT CAUSE 2: the puffs are shader-drawn instances, not physics bodies, and the flare is
## an additive layer over all 3D, so clouds never hid it. vfx/CloudSea.gd answers
## sun_ray_cloud_occlusion() from the bounds recorded at build; this scales how much of that
## answer hides the flare (0 = clouds never hide it, 1 = a fully covered sun hides it).
@export_range(0.0, 1.0, 0.01) var cloud_occlusion_strength: float = 1.0
## Seconds between cloud queries (a few hundred bounds tests, no physics); the result feeds
## visibility_lerp_speed's smoothing, so a longer interval never pops. 0 = every frame.
@export var cloud_occlusion_refresh_s: float = 0.1
## Share of a puff's radius, inward from its silhouette, over which its cover fades from full
## to none, so a sun at a cloud's edge dims gradually rather than switching.
@export_range(0.0, 1.0, 0.01) var cloud_edge_softness: float = 0.3
