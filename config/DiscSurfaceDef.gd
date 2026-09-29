class_name DiscSurfaceDef
extends Resource
## One swappable texture set for the disc top (Bontago-adt.2). Referenced from
## TerritoryVisuals.disc_surface (config/territory_visuals.tres); switch sets by
## pointing that field at another config/disc_surfaces/*.tres in the editor.
## TerritoryVisuals.disc_surface = null keeps the flat/procedural look.
##
## Maps are ambientCG CC0 PBR sets under assets/disc/<id>/ (see LICENSE.md
## there). Color is sampled as sRGB; NormalGL, Roughness and Metalness are
## linear data (no source_color hint in shaders/territory.gdshader).
## UVs are world-space planar on the disc top, so the pattern never depends on
## the mesh's own UVs.

@export var albedo_texture: Texture2D
@export var normal_texture: Texture2D
@export var roughness_texture: Texture2D
@export var metalness_texture: Texture2D

## Edge length in meters of one texture tile on the disc top.
@export var tile_size_m: float = 6.0
## Rotation of the texture on the disc, in degrees.
@export var rotation_deg: float = 0.0
## How much of the albedo map's detail modulates the disc base colour (0 = flat
## base colour, 1 = full map).
@export var albedo_strength: float = 0.5
## Brightness multiplier on the albedo map before it modulates the base colour.
@export var albedo_gain: float = 1.0
## Exponent applied to the albedo map before use; above 1 deepens dark detail
## (scratches, rivets, seams) so it reads at a glance.
@export var albedo_contrast: float = 1.0
## Strength of the normal map's bump; shows mainly in sun/sky reflections.
@export var normal_strength: float = 1.0
## The roughness map (0..1) is remapped into this range.
@export var roughness_min: float = 0.2
@export var roughness_max: float = 0.5
## Blend between the scalar disk_metallic (0) and the metalness map (1).
@export var metalness_map_mix: float = 0.0
## Multiplier on the metalness map when it is used.
@export var metalness_scale: float = 1.0
## On-screen tile size in pixels below which normal/roughness detail fades to
## its average, so distant views never show moire.
@export var detail_fade_px: float = 96.0
