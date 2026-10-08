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
## Draw order among transparent surfaces; above the ghost's own material so the glaze is not painted over.
@export_range(0, 127, 1) var render_priority: int = 10

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
