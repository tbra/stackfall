class_name SkyNightKeyframe
extends Resource
## The night layer of the sky cycle (plain data), mixed over the day palette by the sun's
## elevation (SkyCycleDef.cycle_twilight_width). Evaluated by core/sky/SkyEvaluator.gd.

## Night sky colour at the zenith (cycle_night_zenith).
@export var zenith_color: Color = Color.WHITE
## Night sky colour at the horizon (cycle_night_horizon).
@export var horizon_color: Color = Color.WHITE
## Night sky colour below the horizon (cycle_night_below).
@export var below_color: Color = Color.WHITE
## Environment fog colour at full night.
@export var fog_color: Color = Color.WHITE
## Environment fog density at full night.
@export_range(0.0, 1.0, 0.0005) var fog_density: float = 0.015
## Global volumetric fog density at full night.
@export_range(0.0, 1.0, 0.0005) var volumetric_fog_density: float = 0.003
## Global volumetric fog tint at full night.
@export var volumetric_fog_albedo: Color = Color.WHITE
## Environment ambient light energy at full night.
@export_range(0.0, 16.0, 0.01) var ambient_energy: float = 0.5
## Moon key light energy (scaled by moon_light_ratio).
@export_range(0.0, 16.0, 0.01) var light_energy: float = 0.85
## Key light colour once the sun is below the horizon.
@export var light_color: Color = Color.WHITE
## Key light rotation (degrees) once the sun is below the horizon.
@export var light_rotation_deg: Vector3 = Vector3(-45.0, -30.0, 0.0)
## Fraction of light_energy the moon key light contributes.
@export_range(0.0, 1.0, 0.01) var moon_light_ratio: float = 0.2
## Cloud puff cel shadow tone at full night.
@export var puff_shadow_color: Color = Color.WHITE
## Cloud puff cel mid tone at full night.
@export var puff_mid_color: Color = Color.WHITE
## Cloud puff cel lit tone at full night.
@export var puff_lit_color: Color = Color.WHITE
## Cloud puff cel rim tone at full night.
@export var puff_rim_color: Color = Color.WHITE
## Sky-shader cloud shadow tone at full night.
@export var cloud_shadow_color: Color = Color.WHITE
## Sky-shader cloud mid tone at full night.
@export var cloud_mid_color: Color = Color.WHITE
## Sky-shader cloud lit tone at full night.
@export var cloud_lit_color: Color = Color.WHITE
## Sky-shader cloud rim tone at full night.
@export var cloud_rim_color: Color = Color.WHITE
## Moonlit grade, darkest stop, applied to the cloud puffs.
@export var grade_dark: Color = Color(0.02, 0.03, 0.08)
## Moonlit grade, middle stop.
@export var grade_mid: Color = Color(0.12, 0.17, 0.33)
## Moonlit grade, lightest stop.
@export var grade_light: Color = Color(0.55, 0.64, 0.82)
## Cloud-sea colour near the horizon at full night.
@export var proc_sea_color_near: Color = Color.WHITE
## Cloud-sea colour far from the horizon at full night.
@export var proc_sea_color_far: Color = Color.WHITE
## Night ambient life (fireflies); null for none.
@export var ambient_life: AmbientLifeConfig = null
