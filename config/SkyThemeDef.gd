class_name SkyThemeDef
extends Resource
## A named sky/ground/fog colour palette applied onto the fallback
## ProceduralSkyMaterial and the shared Environment's fog fields whenever no
## textured six-face set is loaded (game/Skybox.gd's `fallback_active == true`
## -- see Skybox.apply_theme()).
##
## M7 P3 (Bontago-xtq.28) ships exactly one instance,
## config/sky_themes/sunset.tres, tuned against docs/art_mockups/
## 04-sunset-signal.png and 07-sunset-signal-cel-shaded.png. M8 follow-up
## (do not build now, per docs/M7_PLAN.md's P3 package): dawn/storm/night
## instances, plus a theme-selection row in ui/TuningPanel.gd (parallel to its
## existing Skybox six-face-set dropdown, `_build_skybox_row()`) once there is
## more than one instance for the owner to choose between -- a single theme
## needs no picker of its own.

## ProceduralSkyMaterial.sky_top_color / sky_horizon_color -- the upper
## hemisphere's zenith and near-horizon colour.
@export var sky_top_color: Color = Color(0.161, 0.2, 0.333)
@export var sky_horizon_color: Color = Color(0.98, 0.64, 0.38)

## ProceduralSkyMaterial.ground_bottom_color / ground_horizon_color -- the
## lower hemisphere (this map floats above a cloud deck, so "ground" here
## reads as clouds seen from above in shade, not terrain).
@export var ground_bottom_color: Color = Color(0.118, 0.098, 0.137)
@export var ground_horizon_color: Color = Color(0.847, 0.514, 0.333)

## Design range (degrees) a future per-theme sun animation could draw from --
## apply_theme() always writes `y` (the wider/softer glow edge) onto
## ProceduralSkyMaterial.sun_angle_max, since that material only exposes one
## float, not a min/max pair. See Skybox.apply_theme()'s own DECISION.
@export var sun_angle_min_max: Vector2 = Vector2(8.0, 20.0)

## Environment.fog_light_color / fog_density -- the ambient haze tint/
## thickness, also reused by Skybox's FogVolume cloud-deck FogMaterial so the
## depth fog and the volumetric deck read as one coherent colour instead of
## two independently tuned effects.
@export var fog_color: Color = Color(0.93, 0.58, 0.4)
@export var fog_density: float = 0.015

## Environment.fog_sky_affect -- how much the basic depth fog tints the
## rendered sky background itself (0 == sky renders untouched past
## fog_depth_end, 1 == the engine's own default, which fully replaces the sky
## with flat fog_light_color). Bontago-xtq.28's rejected candidate never set
## this, so it silently sat at the engine default of 1.0 and masked the
## ProceduralSkyMaterial's orange-horizon/blue-zenith gradient behind a flat
## haze regardless of fog_density. Kept at 0.0 here so the sunset gradient at
## the horizon stays visible; a future stormier theme could raise it.
@export var fog_sky_affect: float = 0.0

## Environment.volumetric_fog_density/volumetric_fog_albedo -- the global
## ambient volumetric-fog density/tint the render server applies across the
## *entire view frustum*, independent of any FogVolume box placed inside it.
## Bontago-xtq.28 fix round 2 (decisive finding): this field defaults to 0.05
## on a fresh Environment and Skybox.apply_theme()'s previous candidate never
## wrote it, so every shot showed a uniform grey haze over the whole frame
## regardless of where _spawn_fog_volume()'s cloud-deck FogVolume box was
## centred -- a FogVolume only ever *adds* extra density inside its own bounds
## on top of this ambient floor; it cannot subtract it back out elsewhere.
## Kept low here (not 0.0, so the ambient volumetric pass still contributes a
## faint atmospheric depth cue at range) so the cloud-deck FogVolume, not this
## global floor, is what reads as the visible sunset haze band.
@export var volumetric_fog_density: float = 0.003
@export var volumetric_fog_albedo: Color = Color(0.93, 0.58, 0.4)

## Skybox._spawn_fog_volume()'s FogVolume box (the "cloud deck" the disk
## floats above): world-space size and the y-height of its centre. World y ==
## 0 is the floating disk's top surface (see game/Skybox.gd's
## PROBE_GROUND_CLEARANCE_M doc); NetConfig.pos_max_y == 72.0 is the highest a
## stacked block may legally sit. Bontago-xtq.28's rejected candidate centred
## this box at y 40 (spanning y 10..70), which swallowed the entire play
## volume and the gameplay camera in fog. Centring it well below the disk
## instead (top edge at y -10, i.e. at least 10 m of clearance under the
## disk's underside) keeps the whole 0..72 m stacking volume fog-free while
## still reading as a cloud layer the island floats above.
@export var cloud_deck_size_m: Vector3 = Vector3(800.0, 60.0, 800.0)
@export var cloud_deck_height_m: float = -40.0
