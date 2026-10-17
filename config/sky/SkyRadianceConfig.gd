class_name SkyRadianceConfig
extends Resource
## Cadence of the sky's radiance (ambient + reflection) refresh.
## game/sky/Skybox.gd drives the shaders' global `sky_time` every frame (smooth visible
## sky) but only dirties the material, and so the radiance octmap, this often.

## How many times per second the sky radiance and the day/night cycle's material
## writes refresh. The visible background does not step at this rate except the cycle's
## sun/palette (0.12 degrees per step at 10 Hz on the default 300 s cycle).
@export var radiance_hz: float = 10.0

## `sky_time` wraps at this many seconds.
@export var time_wrap_seconds: float = 3600.0
