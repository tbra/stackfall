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
## Bontago-1pi.11.6: icosphere subdivisions of each cloud puff hull (1 = 80 tris, 2 = 320).
## The shader carves the silhouette per pixel, so 1 looks the same at a quarter of the
## ~1.2M-primitive cloud-sea cost.
@export_range(1, 2) var cloud_puff_subdivisions: int = 2
## Bontago-adt.1: distant animated bird flocks (vfx/DistantBirds.gd); off on Low.
@export var birds_enabled: bool = true
## Bontago-adt.3: cosmetic ambient life (perching birds, fireflies); off on Low.
@export var ambient_life_enabled: bool = true
## Bontago-1pi.11.2: sun DirectionalLight3D cascade count (DirectionalLight3D.ShadowMode;
## 2 = 4 splits, 1 = 2 splits, 0 = one orthogonal split). Shadow pass cost grows with
## block count, and the mirror camera pays it a second time.
@export_enum("Orthogonal:0", "PSSM 2 Splits:1", "PSSM 4 Splits:2") var sun_shadow_mode: int = 2
## Bontago-1pi.11.2: sun shadow max distance in metres (engine default 100).
@export var sun_shadow_max_distance: float = 100.0
## Bontago-1pi.11.2: multiplies TerritoryVisuals.mirror_resolution_scale for the disc
## mirror SubViewport (1.0 = unchanged; lower renders the second scene pass smaller).
@export_range(0.1, 1.0) var mirror_resolution_factor: float = 1.0

## Bontago-1pi.11.42: the swirl animation (noise, per-pixel) of the hole void
## on the disc. Off on Low: the void is then a flat deep colour with its rim.
@export var hole_void_animated: bool = true
## Bontago-1pi.11.42: the noise dissolve + rim glow on a block eaten by a hole
## (game/BlockDissolveFx.gd). Off on Low: the block simply vanishes on time.
@export var block_dissolve_effect_enabled: bool = true
## Bontago-mp0.23: the persistent per-crate OmniLight3D on a landed gift
## (game/GiftCrate.gd). Off on Low: only the brief spawn flash remains.
@export var gift_idle_glow_enabled: bool = true

## Bontago-1pi.11.37: the fields below are all-default on every shipped preset; only
## the adaptive quality governor (core/QualityGovernor.gd) lowers them, on a duplicate
## handed out by Settings.current_graphics_preset(). The stored .tres never changes.
## Multiplies the block-effect burst caps and particle amounts (1 = unchanged).
@export_range(0.0, 1.0) var particle_budget_scale: float = 1.0
## Multiplies the rain / snow / storm-mote density (1 = unchanged).
@export_range(0.0, 1.0) var weather_density_scale: float = 1.0
## False stops the disc mirror's second scene render (visuals.mirror_enabled still applies).
@export var mirror_enabled: bool = true
## Viewport.scaling_3d_scale (1 = native resolution).
@export_range(0.25, 1.0) var render_scale_3d: float = 1.0
