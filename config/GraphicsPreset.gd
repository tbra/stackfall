class_name GraphicsPreset
extends Resource
## One selectable graphics quality tier (spec 3.1). autoload/Settings.gd
## loads one of config/graphics_presets/{low,medium,high}.tres by id;
## Settings itself never applies these fields to a Viewport/Environment --
## that's game/Main.gd's job (Bontago-xtq.26, M7 P1): Settings only persists
## the choice and emits graphics_preset_changed so a consumer can react.
##
## SSIL intentionally absent -- that render feature doesn't exist yet (a
## later M7 package adds it); a preset that named it today would be a promise
## this milestone cannot keep. volumetric_fog_enabled below is the owner's M7
## art-direction performance budget (docs/M7_ART_DIRECTION.md §3): Low drops the cloud-deck
## FogVolume P3 adds to the field; Medium/High keep it.

@export var id: StringName
@export var ssr_enabled: bool = true
@export var msaa_3d: Viewport.MSAA = Viewport.MSAA_2X
@export var shadow_atlas_size: int = 4096
@export var volumetric_fog_enabled: bool = true
## Bontago-adt.1: fraction (0..1) of the theme's 3D cloud-puff clumps
## (vfx/CloudSea.gd) to draw; 0 hides them and leaves only the sky panorama's
## far cloud sea. Low draws a sparse set.
@export var cloud_puff_density: float = 1.0
## Bontago-adt.1: distant animated bird flocks (vfx/DistantBirds.gd); off on Low.
@export var birds_enabled: bool = true
## Bontago-adt.3: cosmetic ambient life (perching birds, fireflies); off on Low.
@export var ambient_life_enabled: bool = true
