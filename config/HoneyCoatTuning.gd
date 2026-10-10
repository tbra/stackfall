class_name HoneyCoatTuning
extends Resource
## Look of the honey glaze (Bontago-1pi.128, owner mockup): placed glued blocks wear a
## glossy yellow pool on each top face with rounded drip tongues down the sides; the
## held ghost wears the same honey at ghost_alpha so its validity colour shows through.
## Fed to shaders/honey_coat.gdshader by build_material() / build_ghost_material().

## Honey yellow; alpha is the opacity of the honey patches on placed blocks (owner mockup: opaque blobs).
@export var color: Color = Color(1.0, 0.7, 0.04, 1.0)
## Deep amber the glaze darkens toward at grazing angles.
@export var deep_amber: Color = Color(0.85, 0.42, 0.0)
## How far (m) the glaze swells off the block surface (avoids z-fighting).
@export_range(0.0, 0.1, 0.002) var thickness_m: float = 0.02
## Ghost preview: honey patch opacity. Below 1 so the green/red validity tint shows through.
@export_range(0.0, 1.0, 0.01) var ghost_alpha: float = 0.6
@export_range(0.0, 1.0, 0.01) var roughness: float = 0.05
## Fresnel exponent and glow of the grazing rim.
@export_range(0.5, 8.0, 0.1) var rim_power: float = 3.5
@export_range(0.0, 4.0, 0.05) var rim_strength: float = 0.6
## Gloss: clearcoat amount and roughness, wet highlight power and strength, colour.
@export_range(0.0, 1.0, 0.01) var clearcoat_amount: float = 1.0
@export_range(0.0, 1.0, 0.01) var clearcoat_roughness: float = 0.03
@export_range(1.0, 128.0, 1.0) var shine_power: float = 12.0
@export_range(0.0, 4.0, 0.05) var shine_strength: float = 0.3
@export var shine_color: Color = Color(1.0, 0.96, 0.75)
## Honey pool on top faces (shader noise): wobble scale (1/m), covered fraction of
## each top, and edge softness; then side tongues (owner mockup): chance per slot
## (3 per side), length range as a fraction of the block height, width, and the
## thin lip of honey along the top edge.
@export_range(0.5, 8.0, 0.1) var patch_scale: float = 2.5
@export_range(0.0, 1.0, 0.01) var patch_coverage: float = 0.85
@export_range(0.005, 0.3, 0.005) var patch_edge: float = 0.06
@export_range(0.0, 1.0, 0.01) var tongue_chance: float = 0.65
@export_range(0.05, 1.0, 0.01) var tongue_min_len: float = 0.3
@export_range(0.05, 1.0, 0.01) var tongue_max_len: float = 0.75
@export_range(0.05, 0.5, 0.01) var tongue_width: float = 0.24
@export_range(0.0, 0.3, 0.005) var lip_depth: float = 0.07
@export_range(0.0, 0.1, 0.002) var top_swell: float = 0.035
## HUD held/next preview honey blobs: base colour, darker edge colour, highlight.
@export var hud_blob_color: Color = Color(1.0, 0.7, 0.04, 1.0)
@export var hud_blob_edge_color: Color = Color(0.85, 0.42, 0.0, 1.0)
@export var hud_blob_highlight: Color = Color(1.0, 0.96, 0.7, 0.8)
## HUD held/next preview of a glued block: amber tint laid over the silhouette (jelly) in addition to the bead colours above.
@export var hud_jelly_tint: Color = Color(1.0, 0.7, 0.04, 0.55)
## HUD preview beads: [x, y, radius] of each bead as fractions of the silhouette box (kept toward the edges, like beads squeezed out of a seam).
@export var hud_beads: PackedVector3Array = PackedVector3Array([
	Vector3(0.1, 0.15, 0.07), Vector3(0.92, 0.3, 0.08), Vector3(0.2, 0.9, 0.08),
	Vector3(0.78, 0.94, 0.06), Vector3(0.5, 0.06, 0.06), Vector3(0.95, 0.78, 0.07),
])
## Draw order among transparent surfaces; above the ghost's own material so the glaze is not painted over.
@export_range(0, 127, 1) var render_priority: int = 10

## Bontago-lv2 (owner decision lv2.1 = d): which glaze a coated block wears. PUDDLE is the old top
## puddle + side tongues (honey_coat.gdshader). JELLY is an inflated translucent shell, BEADS glossy
## glue beads on the cell edges, JELLY_BEADS both (shipped default).
# DECISION: one enum with the combined value instead of two bools, so "puddle" stays mutually exclusive.
enum Look { PUDDLE, JELLY, BEADS, JELLY_BEADS }
@export var look: Look = Look.JELLY_BEADS
## Cel diffuse bands and the hard specular highlight cut (n.h threshold) and strength, shared by the blob looks.
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
## BEADS: beads per cell, radius range (m) and how flat they sit (1 = round ball).
@export_range(0, 12, 1) var bead_count_per_cell: int = 8
@export_range(0.02, 0.2, 0.005) var bead_min_radius_m: float = 0.07
@export_range(0.02, 0.3, 0.005) var bead_max_radius_m: float = 0.17
@export_range(0.3, 1.0, 0.05) var bead_flatten: float = 0.75

const SHADER_PATH: String = "res://shaders/honey_coat.gdshader"


## One ShaderMaterial for the glaze on every placed mesh.
func build_material() -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load(SHADER_PATH) as Shader
	material.render_priority = render_priority
	material.set_shader_parameter(&"honey_color", color)
	material.set_shader_parameter(&"deep_amber", deep_amber)
	material.set_shader_parameter(&"thickness", thickness_m)
	material.set_shader_parameter(&"roughness_value", roughness)
	material.set_shader_parameter(&"rim_power", rim_power)
	material.set_shader_parameter(&"rim_strength", rim_strength)
	material.set_shader_parameter(&"clearcoat_amount", clearcoat_amount)
	material.set_shader_parameter(&"clearcoat_roughness", clearcoat_roughness)
	material.set_shader_parameter(&"shine_power", shine_power)
	material.set_shader_parameter(&"shine_strength", shine_strength)
	material.set_shader_parameter(&"shine_color", shine_color)
	material.set_shader_parameter(&"ghost_alpha", ghost_alpha)
	material.set_shader_parameter(&"patch_scale", patch_scale)
	material.set_shader_parameter(&"patch_coverage", patch_coverage)
	material.set_shader_parameter(&"tongue_chance", tongue_chance)
	material.set_shader_parameter(&"tongue_min_len", tongue_min_len)
	material.set_shader_parameter(&"tongue_max_len", tongue_max_len)
	material.set_shader_parameter(&"tongue_width", tongue_width)
	material.set_shader_parameter(&"lip_depth", lip_depth)
	material.set_shader_parameter(&"top_swell", top_swell)
	material.set_shader_parameter(&"patch_edge", patch_edge)
	material.set_shader_parameter(&"ghost_mode", false)
	return material


## The held ghost's preview glaze: same shader, translucent (ghost_alpha).
func build_ghost_material() -> ShaderMaterial:
	var material: ShaderMaterial = build_material()
	material.set_shader_parameter(&"ghost_mode", true)
	return material


const JELLY_SHADER_PATH: String = "res://shaders/honey_jelly.gdshader"
const BEADS_SHADER_PATH: String = "res://shaders/honey_beads.gdshader"


## Shared shading uniforms (honey_shading.gdshaderinc) for the blob looks.
func _blob_material(shader_path: String) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load(shader_path) as Shader
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
	return material


## `ghost` = the held preview: same shell, opacity scaled by ghost_alpha so the validity tint shows through.
func build_jelly_material(ghost: bool = false) -> ShaderMaterial:
	var material: ShaderMaterial = _blob_material(JELLY_SHADER_PATH)
	material.set_shader_parameter(&"alpha", jelly_alpha * (ghost_alpha if ghost else 1.0))
	material.set_shader_parameter(&"roundness", jelly_roundness)
	material.set_shader_parameter(&"ball_radius", jelly_radius_m)
	material.set_shader_parameter(&"inflate", jelly_inflate_m)
	material.set_shader_parameter(&"bulge", jelly_bulge_m)
	material.set_shader_parameter(&"bulge_freq", jelly_bulge_freq)
	material.set_shader_parameter(&"wobble_speed", jelly_wobble_speed)
	material.set_shader_parameter(&"sag", jelly_sag_m)
	return material


func build_beads_material(ghost: bool = false) -> ShaderMaterial:
	var material: ShaderMaterial = _blob_material(BEADS_SHADER_PATH)
	material.set_shader_parameter(&"alpha", ghost_alpha if ghost else 1.0)
	return material


func has_jelly() -> bool:
	return look == Look.JELLY or look == Look.JELLY_BEADS


func has_beads() -> bool:
	return look == Look.BEADS or look == Look.JELLY_BEADS
