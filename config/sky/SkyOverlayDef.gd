class_name SkyOverlayDef
extends Resource
## A weather look (the storm today) as target values, blended over the cycle by an amount 0..1
## (SkyEvaluator.apply_storm). Plain data; the light direction is never part of an overlay
## because the cycle owns the sun path.

## Environment fog colour at full overlay.
@export var fog_color: Color = Color.WHITE
## Environment fog density at full overlay.
@export_range(0.0, 1.0, 0.0005) var fog_density: float = 0.015
## How much the depth fog tints the sky at full overlay.
@export_range(0.0, 1.0, 0.01) var fog_sky_affect: float = 0.0
## Global volumetric fog density at full overlay.
@export_range(0.0, 1.0, 0.0005) var volumetric_fog_density: float = 0.003
## Global volumetric fog tint at full overlay.
@export var volumetric_fog_albedo: Color = Color.WHITE
## Sun light colour at full overlay.
@export var light_color: Color = Color.WHITE
## Sun light energy at full overlay.
@export_range(0.0, 16.0, 0.01) var light_energy: float = 0.85
## Environment ambient light energy at full overlay.
@export_range(0.0, 16.0, 0.01) var ambient_energy: float = 0.5
## Environment glow intensity at full overlay.
@export_range(0.0, 8.0, 0.01) var glow_intensity: float = 0.5
## Sky gradient zenith colour at full overlay.
@export var proc_zenith_color: Color = Color.WHITE
## Sky gradient mid colour at full overlay.
@export var proc_mid_color: Color = Color.WHITE
## Sky gradient horizon colour at full overlay.
@export var proc_horizon_color: Color = Color.WHITE
## Horizon glow colour at full overlay.
@export var proc_horizon_glow_color: Color = Color.WHITE
## Height of the gradient mid stop at full overlay.
@export_range(0.0, 1.0, 0.01) var proc_gradient_mid_height: float = 0.35
## Gradient curve exponent at full overlay.
@export_range(0.1, 8.0, 0.05) var proc_gradient_power: float = 1.5
## Horizon glow width at full overlay.
@export_range(0.0, 2.0, 0.01) var proc_horizon_glow_width: float = 0.18
## Glow around the sun at full overlay.
@export_range(0.0, 8.0, 0.05) var proc_sun_glow_strength: float = 1.0
## Cloud-sea near colour at full overlay.
@export var proc_sea_color_near: Color = Color.WHITE
## Cloud-sea far colour at full overlay.
@export var proc_sea_color_far: Color = Color.WHITE
## Cloud puff cel shadow tone at full overlay.
@export var puff_shadow_color: Color = Color.WHITE
## Cloud puff cel mid tone at full overlay.
@export var puff_mid_color: Color = Color.WHITE
## Cloud puff cel lit tone at full overlay.
@export var puff_lit_color: Color = Color.WHITE
## Cloud puff cel rim tone at full overlay.
@export var puff_rim_color: Color = Color.WHITE
## Sky-shader cloud shadow tone at full overlay.
@export var cloud_shadow_color: Color = Color.WHITE
## Sky-shader cloud mid tone at full overlay.
@export var cloud_mid_color: Color = Color.WHITE
## Sky-shader cloud lit tone at full overlay.
@export var cloud_lit_color: Color = Color.WHITE
## Sky-shader cloud rim tone at full overlay.
@export var cloud_rim_color: Color = Color.WHITE
