class_name HoneyCoatTuning
extends Resource
## Look of the glue glaze: an inflated translucent jelly shell (jelly-only per slot
## ) on placed glued blocks, the held ghost (scaled by ghost_alpha so
## its validity colour shows through) and, as an amber tint, the HUD held/next preview.

## Honey yellow of the jelly.
@export var color: Color = Color(1.0, 0.7, 0.04, 1.0)
## Deep amber the glaze darkens toward at grazing angles.
@export var deep_amber: Color = Color(0.85, 0.42, 0.0)
## Ghost preview: opacity factor on the jelly. Below 1 so the green/red validity tint shows through.
@export_range(0.0, 1.0, 0.01) var ghost_alpha: float = 0.6
## Fresnel exponent of the grazing rim.
@export_range(0.5, 8.0, 0.1) var rim_power: float = 3.5
## Colour of the hard specular highlight.
@export var shine_color: Color = Color(1.0, 0.96, 0.75)
## HUD held/next preview of a glued block: amber tint laid over the silhouette.
@export var hud_jelly_tint: Color = Color(1.0, 0.7, 0.04, 0.55)
## Draw order among transparent surfaces; above the ghost's own material so the glaze is not painted over.
@export_range(0, 127, 1) var render_priority: int = 10

## Cel diffuse bands and the hard specular highlight cut (n.h threshold) and strength, shared by the jelly.
@export_range(1, 6, 1) var blob_band_count: int = 3
@export_range(0.8, 0.999, 0.001) var blob_gloss_threshold: float = 0.985
@export_range(0.0, 4.0, 0.05) var blob_gloss_strength: float = 1.0
## Glow floor (so honey never goes black at night) and extra glow toward the rim ("light through the blob").
@export_range(0.0, 1.0, 0.01) var blob_glow_floor: float = 0.12
@export_range(0.0, 2.0, 0.05) var blob_glow_rim: float = 0.5
## JELLY: grid lines per cell face, opacity, how far the cube is pushed toward a ball (0..1) and the ball radius (m),
## inflate (m, keeps the shell outside the block), noise bulge height (m), noise frequency and wobble speed, and how far the lower rim sags into drip lobes (m).
@export_range(2, 16, 1) var jelly_subdivisions: int = 8
@export_range(0.1, 1.0, 0.01) var jelly_alpha: float = 0.6
@export_range(0.0, 1.0, 0.01) var jelly_roundness: float = 0.5
@export_range(0.4, 0.9, 0.01) var jelly_radius_m: float = 0.7
@export_range(0.0, 0.1, 0.005) var jelly_inflate_m: float = 0.04
@export_range(0.0, 0.2, 0.005) var jelly_bulge_m: float = 0.05
@export_range(0.5, 12.0, 0.1) var jelly_bulge_freq: float = 4.0
@export_range(0.0, 4.0, 0.05) var jelly_wobble_speed: float = 1.2
@export_range(0.0, 0.5, 0.01) var jelly_sag_m: float = 0.18

const JELLY_SHADER_PATH: String = "res://shaders/gifts/honey_jelly.gdshader"


## `ghost` = the held preview: same shell, opacity scaled by ghost_alpha so the validity tint shows through.
func build_jelly_material(ghost: bool = false) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load(JELLY_SHADER_PATH) as Shader
	material.render_priority = render_priority
	material.set_shader_parameter(&"honey_color", color)
	material.set_shader_parameter(&"deep_amber", deep_amber)
	material.set_shader_parameter(&"rim_power", rim_power)
	material.set_shader_parameter(&"rim_strength", blob_glow_rim)
	material.set_shader_parameter(&"glow_floor", blob_glow_floor)
	material.set_shader_parameter(&"band_count", blob_band_count)
	material.set_shader_parameter(&"gloss_threshold", blob_gloss_threshold)
	material.set_shader_parameter(&"gloss_strength", blob_gloss_strength)
	material.set_shader_parameter(&"gloss_color", shine_color)
	material.set_shader_parameter(&"alpha", jelly_alpha * (ghost_alpha if ghost else 1.0))
	material.set_shader_parameter(&"roundness", jelly_roundness)
	material.set_shader_parameter(&"ball_radius", jelly_radius_m)
	material.set_shader_parameter(&"inflate", jelly_inflate_m)
	material.set_shader_parameter(&"bulge", jelly_bulge_m)
	material.set_shader_parameter(&"bulge_freq", jelly_bulge_freq)
	material.set_shader_parameter(&"wobble_speed", jelly_wobble_speed)
	material.set_shader_parameter(&"sag", jelly_sag_m)
	return material
