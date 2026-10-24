class_name SunFlareConfig
extends Resource
## Tunables for game/sky/SunFlare.gd's screen-space lens flare. Every number the
## shader (shaders/sky/sun_flare.gdshader) and the driving script read lives here.
##
## DECISION: not wired into ui/debug/TuningPanel.gd, which hardcodes one preload()'d
## var per tunable Resource it exposes; these fields are Resource-only (edit
## config/sky/sun_flare.tres), not live-editable from the in-game F4 panel.

## World-space direction from the field's center toward the sun (normalized).
## # DECISION: keep the original flare axis and scene light rotation. sunset.tres
## rotates panorama sampling to place its painted sun on this axis; moving the
## light instead caused a grazing hotspot. See sunset_clouds.gdshader for the
## measured panorama centre.
@export var sun_direction: Vector3 = Vector3(0.963087, 0.069011, -0.260192)

## Warm tint applied to every flare element (core, rays, ghosts) before
## per-element color/alpha below.
@export var sun_color: Color = Color(1.0, 0.86, 0.62)

## Bright core disc radius/softness, in normalized screen-diagonal units
## (see shaders/sky/sun_flare.gdshader's own doc for the exact unit conversion). The
## painted panorama supplies the sun disc behind all geometry; this is a small
## sparkle on top of it, so it stays low-intensity rather than blowing out the disc.
@export var core_radius: float = 0.022
@export var core_softness: float = 0.5
@export var core_intensity: float = 0.9

## A tight starburst sparkle right on the sun's own screen position -- NOT
## the big god-ray beams (those live in shaders/sky/sunset_clouds.gdshader's
## sky pass, which can sit behind scene geometry for free). ray_length is
## deliberately small (a lens-artifact spike a few percent of the screen
## diagonal), not a long beam.
@export var ray_count: int = 8
@export var ray_length: float = 0.09
## Higher = thinner, sharper rays (an angular falloff exponent).
@export var ray_sharpness: float = 30.0
@export var ray_intensity: float = 0.4

## Ghost ("ghost ring") ghost discs sampled along the sun-to-screen-center
## axis, alternating between sun_color (warm) and ghost_color_b (teal).
## # DECISION: ghost_base_size and ghost_alpha are kept small and non-zero so the
## ghosts stay visible but subtle and none reads as a second sun.
@export var ghost_count: int = 4
## Position of each ghost as a fraction of the way from the sun toward (and
## past) the screen center -- e.g. 0.5 sits halfway to center, 1.3 sits just
## past it on the opposite side.
@export var ghost_positions: PackedFloat32Array = PackedFloat32Array([0.35, 0.65, 1.0, 1.35])
@export var ghost_base_size: float = 0.03
@export var ghost_size_falloff: float = 0.72
@export var ghost_alpha: float = 0.22
## Fraction of the ghost's radius that is ring (0 = solid discs). Solid discs read as
## a second sun when seen from the side, since straight on every ghost collapses onto
## the sun at screen centre; hollow, dim rings read as lens artifacts. The sky-shader
## sun, the scene light and this flare's sun_direction all agree
## (tests/unit/sky/test_sky_themes.gd asserts it).
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
## without touching any other field (used by game/sky/SunFlare.gd to gate the
## effect off on the Low graphics preset).
@export var max_intensity: float = 1.0

@export_group("Occlusion")
## The disc collider is a single-sided trimesh (game/field/Field.gd: faces only up and out of the
## rim), so the one camera-to-sun ray of game/sky/SunFlare.gd passes unhit through the disc seen
## from below or edge-on, so a second ray from the sun back to the camera is cast too (it meets
## the faces from outside) and either hit hides the flare.
## How far from the camera (m, along the sun direction) the reverse ray starts: past the arena and the
## whole play volume, but short enough that a long float-precision ray does not leak between the disc
## quads. Never longer than the forward ray.
@export var reverse_ray_length_m: float = 800.0
## The puffs are shader-drawn instances, not physics bodies, and the flare is
## an additive layer over all 3D, so clouds never hid it. game/sky/CloudSea.gd answers
## sun_ray_cloud_occlusion() from the bounds recorded at build; this scales how much of that
## answer hides the flare (0 = clouds never hide it, 1 = a fully covered sun hides it).
@export_range(0.0, 1.0, 0.01) var cloud_occlusion_strength: float = 1.0
## Seconds between cloud queries (a few hundred bounds tests, no physics); the result feeds
## visibility_lerp_speed's smoothing, so a longer interval never pops. 0 = every frame.
@export var cloud_occlusion_refresh_s: float = 0.1
## Share of a puff's radius, inward from its silhouette, over which its cover fades from full
## to none, so a sun at a cloud's edge dims gradually rather than switching.
@export_range(0.0, 1.0, 0.01) var cloud_edge_softness: float = 0.3
