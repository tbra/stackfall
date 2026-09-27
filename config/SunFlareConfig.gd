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
## # DECISION (config/SunFlareConfig.gd, Bontago-mp0.3.4): measured from the
## painted sun disc in the sunset panorama texture itself
## (assets/sky/sunset-clouds-v1.png, sampled at its brightest pixel,
## ~(0.708, 0.478) in equirectangular UV), NOT derived from
## Main.tscn's DirectionalLight3D rotation_degrees (-45, -30, 0) -- that
## light's own implied sun position (converted through the same
## shaders/sunset_clouds.gdshader panorama-UV formula the sky shader uses)
## lands at uv (0.083, 0.25), high in the sky and nowhere near the low,
## right-of-center sun actually painted in the texture the player sees. The
## two were never meant to agree (the DirectionalLight3D only drives
## shading/shadow direction, spec's presentation layer never promised its
## rotation would match a painted sky's own sun), and this package's brief
## explicitly says to align the flare with the painted sun when they
## disagree. See vfx/SunFlare.gd's class doc for how this direction is
## turned into a screen position every frame.
@export var sun_direction: Vector3 = Vector3(0.963087, 0.069011, -0.260192)

## Warm tint applied to every flare element (core, rays, ghosts) before
## per-element color/alpha below.
@export var sun_color: Color = Color(1.0, 0.86, 0.62)

## Bright core disc radius/softness, in normalized screen-diagonal units
## (see vfx/sun_flare.gdshader's own doc for the exact unit conversion). Fix
## round (owner: "reduce the hard white clipped look"): the sky shader
## (shaders/sunset_clouds.gdshader) now draws the actual warm sun disc/halo
## behind all geometry; this is only a small, additive-blended sparkle on
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
@export var ghost_count: int = 4
## Position of each ghost as a fraction of the way from the sun toward (and
## past) the screen center -- e.g. 0.5 sits halfway to center, 1.3 sits just
## past it on the opposite side.
@export var ghost_positions: PackedFloat32Array = PackedFloat32Array([0.35, 0.65, 1.0, 1.35])
@export var ghost_base_size: float = 0.045
@export var ghost_size_falloff: float = 0.72
@export var ghost_alpha: float = 0.5
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
