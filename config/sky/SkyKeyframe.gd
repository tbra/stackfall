class_name SkyKeyframe
extends Resource
## One day-palette keyframe of the sky cycle (plain data). Key 0 of SkyCycleDef.day_keyframes is
## the base palette; every later key is mixed in by its phase window, so the palette is a
## smoothstep blend between keys. Evaluated by core/sky/SkyEvaluator.gd; no logic lives here.

## Weight toward this key is smoothstep(x, y, phase) * (1 - smoothstep(z, w, phase)); key 0 is the base and ignores it.
@export var phase_window: Vector4 = Vector4.ZERO
## Environment fog colour of this key.
@export var fog_color: Color = Color.WHITE
## Global volumetric fog tint.
@export var volumetric_fog_albedo: Color = Color.WHITE
## Sun light colour.
@export var light_color: Color = Color.WHITE
## Sky gradient colour at the zenith.
@export var proc_zenith_color: Color = Color.WHITE
## Sky gradient colour at mid height.
@export var proc_mid_color: Color = Color.WHITE
## Sky gradient colour at the horizon.
@export var proc_horizon_color: Color = Color.WHITE
## Colour of the horizon glow band.
@export var proc_horizon_glow_color: Color = Color.WHITE
## Cloud-sea colour under the horizon, near edge.
@export var proc_sea_color_near: Color = Color.WHITE
## Cloud-sea colour under the horizon, far edge.
@export var proc_sea_color_far: Color = Color.WHITE
## Environment fog density.
@export_range(0.0, 1.0, 0.0005) var fog_density: float = 0.015
## Global volumetric fog density.
@export_range(0.0, 1.0, 0.0005) var volumetric_fog_density: float = 0.003
## Sun light energy before the contrast gain.
@export_range(0.0, 16.0, 0.01) var light_energy: float = 0.85
## Environment ambient light energy.
@export_range(0.0, 16.0, 0.01) var ambient_energy: float = 0.5
## Width of the horizon glow band.
@export_range(0.0, 2.0, 0.01) var proc_horizon_glow_width: float = 0.18
## Strength of the glow around the sun.
@export_range(0.0, 8.0, 0.05) var proc_sun_glow_strength: float = 1.0
## Sun disc core colour (sky shader).
@export var sun_core_color: Color = Color.WHITE
## Sun halo colour (sky shader).
@export var sun_halo_color: Color = Color.WHITE
## Sun ray colour (sky shader).
@export var sun_ray_color: Color = Color.WHITE
## Sky-shader cloud shadow tone.
@export var cloud_shadow_color: Color = Color.WHITE
## Sky-shader cloud mid tone.
@export var cloud_mid_color: Color = Color.WHITE
## Sky-shader cloud lit tone.
@export var cloud_lit_color: Color = Color.WHITE
## Sky-shader cloud rim tone.
@export var cloud_rim_color: Color = Color.WHITE
## Cloud puff cel shadow tone.
@export var puff_shadow_color: Color = Color.WHITE
## Cloud puff cel mid tone.
@export var puff_mid_color: Color = Color.WHITE
## Cloud puff cel lit tone.
@export var puff_lit_color: Color = Color.WHITE
## Cloud puff cel rim tone.
@export var puff_rim_color: Color = Color.WHITE
