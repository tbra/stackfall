class_name GraphicsPreset
extends Resource
## One selectable graphics quality tier (spec 3.1). autoload/Settings.gd
## loads one of config/graphics_presets/{low,medium,high}.tres by id;
## Settings itself never applies these fields to a Viewport/Environment --
## that's C2/M7's job (Settings only persists the choice and emits
## graphics_preset_changed so a consumer can react).
##
## SSIL/volumetric-fog fields intentionally absent -- neither render feature
## exists yet (M7 presentation polish adds them); a preset that named them
## today would be a promise this milestone cannot keep. Revisit once M7
## lands those effects (docs/M6_PLAN.md, Known limitations).

@export var id: StringName
@export var ssr_enabled: bool = true
@export var msaa_3d: Viewport.MSAA = Viewport.MSAA_2X
@export var shadow_atlas_size: int = 4096
