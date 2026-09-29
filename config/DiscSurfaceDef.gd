class_name DiscSurfaceDef
extends Resource
## One swappable surface for the disc top (Bontago-adt.2): an image texture set
## (mode TEXTURE) or the procedural cel plating (mode PROCEDURAL). Referenced from
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


## -- Bontago-adt.2: procedural cel-styled plating ---------------------------
## TEXTURE draws the image maps above; PROCEDURAL draws the analytic plating
## below in shaders/territory.gdshader (no textures, no tiling, so it never
## repeats, and every detail fades out with on-screen size).
enum Mode { TEXTURE, PROCEDURAL }

## Which disc-top look this set uses.
@export var mode: Mode = Mode.TEXTURE

@export_group("Procedural layout")
## Per-channel multiplier of the plating on the disc's base colour and fill:
## the gunmetal level and hue (the texture sets reach theirs through the albedo
## map's gain/contrast).
@export var proc_base_tint: Color = Color(0.14, 0.155, 0.25)
## Radius in meters of the round centre plate.
@export var proc_hub_radius_m: float = 3.5
## Radial width in meters of each concentric ring of plates.
@export var proc_ring_width_m: float = 4.5
## Target arc length in meters of one plate; each ring's plate count grows with
## its circumference so plates stay roughly square at every radius.
@export var proc_plate_length_m: float = 5.0
## Random +/- fraction applied to each ring's plate count, so rings never
## line up into a regular spoke pattern.
@export var proc_plate_count_jitter: float = 0.3
## Fraction of plates split lengthwise into two narrower plates along their
## ring, breaking up the ring structure.
@export var proc_split_chance: float = 0.3
## Per-plate brightness variation of the plate tone (fraction of the base).
@export var proc_tone_variation: float = 0.12
## Fraction of plates drawn as an inset access hatch (inner groove + tone shift).
@export var proc_hatch_chance: float = 0.06
## Distance in meters from the plate edge to the hatch groove.
@export var proc_hatch_inset_m: float = 0.7
## Brightness multiplier of the hatch cover relative to its plate.
@export var proc_hatch_tone: float = 0.88

@export_group("Procedural seams")
## Screen width in pixels of the dark seam line between plates.
@export var proc_seam_width_px: float = 1.3
## How dark the seam line gets (0 = invisible, 1 = black).
@export var proc_seam_darkness: float = 0.85
## Screen width in pixels of the lit lip beside each seam (the plate edge
## facing the sun catches a thin highlight, like the block bevels).
@export var proc_lip_width_px: float = 1.2
## Darkening of the lip on the shaded side of each seam.
@export var proc_lip_strength: float = 0.35
## Additive brightness of the sun-facing lip highlight.
@export var proc_lip_highlight: float = 0.07
## How much a seam also darkens the mirror reflection over it (0 = seams vanish
## under a strong reflection, 1 = seams cut through it).
@export var proc_seam_reflection_occlusion: float = 0.6

@export_group("Procedural rivets")
## Rivet head radius in meters.
@export var proc_rivet_radius_m: float = 0.085
## Centre-to-centre spacing in meters of rivets within a cluster or row.
@export var proc_rivet_spacing_m: float = 0.32
## Distance in meters from the plate edges to the first rivet centre.
@export var proc_rivet_inset_m: float = 0.3
## Spacing in meters of rivets along the edge-row pattern.
@export var proc_rivet_row_spacing_m: float = 0.75
## Relative weights of each per-plate rivet pattern (none, corner pairs, 2x2
## corner clusters, edge rows); normalised in the shader.
@export var proc_rivet_weight_none: float = 0.1
@export var proc_rivet_weight_pairs: float = 0.35
@export var proc_rivet_weight_clusters: float = 0.35
@export var proc_rivet_weight_rows: float = 0.2
## Brightness multiplier of a rivet head relative to its plate.
@export var proc_rivet_tone: float = 2.4
## Strength of the lit crescent on the sun side of each rivet.
@export var proc_rivet_highlight: float = 0.14
## Darkness of the rivet outline and the small cast shadow opposite the sun.
@export var proc_rivet_shadow: float = 0.75
## Darkness of the shaded crescent on the head, away from the sun.
@export var proc_rivet_shade: float = 0.35
## Offset of the cast shadow, as a fraction of the rivet radius.
@export var proc_rivet_shadow_offset: float = 0.6

@export_group("Procedural shading")
## Colour of the plate sheen bands, seam lips and rivet highlights.
@export var proc_highlight_color: Color = Color(1.0, 0.84, 0.62)
## Per-plate random tilt of the sheen normal, so neighbouring plates catch the
## sun in different bands (faceted, stylised metal).
@export var proc_plate_tilt: float = 0.08
## Peak strength of the banded per-plate sheen (sun lobe plus sky fresnel).
@export var proc_sheen_strength: float = 0.08
## Fresnel exponent of the sky part of the banded sheen (higher keeps it to
## grazing angles, i.e. the far side of the disc).
@export var proc_sky_sheen_power: float = 4.0
## Weight of the sky part against the sun lobe (0 = sun lobe only).
@export var proc_sky_sheen_weight: float = 0.8
## Exponent of the per-plate sun sheen lobe (lower is broader).
@export var proc_sheen_exponent: float = 4.0
## Number of flat cel bands the sheen is quantised into.
@export var proc_sheen_bands: int = 3
## Softness of the band edges (fraction of one band).
@export var proc_sheen_band_softness: float = 0.15
## Strength of the brushed streaks (sheen and roughness only, never albedo).
@export var proc_brush_strength: float = 0.35
## Spacing in meters of the brushed streaks.
@export var proc_brush_scale_m: float = 0.05
## Base roughness of the plates, plus a per-plate random spread.
@export var proc_roughness: float = 0.22
@export var proc_roughness_variation: float = 0.08

@export_group("Procedural distance fade")
## Plate size in pixels at which seams, hatches, tone variation and sheen
## facets are fully gone (start) and fully drawn (end). Between, they fade
## smoothly, so far/overview views show a calm glossy disc.
@export var proc_seam_fade_start_px: float = 45.0
@export var proc_seam_fade_end_px: float = 110.0
## Rivet diameter in pixels at which rivets are fully gone (start) and fully
## drawn (end); rivets fade well before the seams.
@export var proc_rivet_fade_start_px: float = 3.0
@export var proc_rivet_fade_end_px: float = 7.0
## Streak spacing in pixels below which the brushed streaks fade out.
@export var proc_brush_fade_px: float = 3.0
