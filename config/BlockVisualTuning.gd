class_name BlockVisualTuning
extends Resource
## Bontago-xtq.27 (M7 P2, docs/M7_ART_DIRECTION.md, owner decision 2026-09-26
## Bontago-5h7 Q1/Q2): tunables for the block toon material + inverted-hull
## outline + cell-grid influence glow. The mesh itself stays one merged solid
## shape per block (Bontago-xtq.3); everything here only changes how that one
## `ArrayMesh` is shaded and outlined, never its geometry/collision.

## Inverted-hull outline pass (shaders/block_outline.gdshader): how far the
## outline mesh's vertices are pushed out along their own normal, in meters.
## Bontago-mp0.3.1 (owner feedback "restrained... thinner/softer than now"):
## thinned from 0.009.
@export var outline_width_m: float = 0.006

## Flat, unshaded color of the outline pass.
@export var outline_color: Color = Color(0.05, 0.04, 0.05)

## shaders/block_cell_grid.gdshader: how many discrete lit/shadow bands the
## toon diffuse ramp is quantized into (cel-shading "steps").
@export var toon_band_count: int = 3

## Screen-space width, in pixels, of the dark line drawn along each visible
## face's UV edge (BlockMeshBuilder's existing 0..1 per-cell UVs put one such
## edge at every cell boundary, spec 2.10 as amended).
@export var grid_line_width_px: float = 0.9

## Cell-grid line color for a block that is not currently read as
## contributing to territory influence (in flight / just landed).
@export var grid_line_color: Color = Color(0.12, 0.1, 0.1)

## Cell-grid line color for a block whose `contributing` per-instance shader
## parameter is true (settled/sleeping -- see BlockFactory.build()'s
## `sleeping_state_changed` wiring). Owner playtest 2026-09-26 (Bontago-xtq.39):
## the owner-colour glow on landed blocks "looks bad, they should always stay
## black", so the shipped default now equals grid_line_color; the uniform and
## F4 slider stay so the glow can be re-enabled per session.
@export var grid_line_glow_color: Color = Color(0.12, 0.1, 0.1)

## Emission multiplier applied to grid_line_glow_color while `contributing`
## is true. 0 disables the glow entirely (owner decision above); raise it on
## the F4 "Blocks FX" tab to preview the old lit-lines look.
@export var grid_line_glow_strength: float = 0.0

## Bontago-mp0.3.1 (owner feedback: "the mockup shows much more detailed
## cel-shading with highlights and shadows... not heavy black lines"): how
## much of grid_line_color/grid_line_glow_color to mix into the seam versus
## the block's own albedo_color (0 = seam invisible, 1 = the old flat-replace
## look). A darker *shade of the block's own colour* reads as a seam instead
## of a heavy ink line.
@export var grid_line_seam_mix: float = 0.4

## -- Toon banding: three explicit, distinctly-coloured bands ----------------
## Fix round (owner review of blocks-r1: "Right now all red faces are nearly
## the same red... make the bands produce ~3 distinct values per colour").
## shaders/block_cell_grid.gdshader's light() builds shadow/lit/highlight
## "keyframe" colours from a block's own albedo_color using the tint/mix/
## brightness trio below, then interpolates between them by the toon-banded
## N.L, instead of the old single shadow_floor/highlight_boost scalar (which
## multiplied the *same* hue up/down and read as barely-different shades of
## one red). Defaults tuned to land close to the owner's own worked example
## (base red 0.9,0.25,0.25 -> top ~#F2705E, lit ~#DE3F30, shadow ~#9E2A2E).

## Warm near-white blended into the brightest (top, sun-facing) band.
@export var highlight_tint: Color = Color(1.0, 0.85, 0.65)
@export var highlight_tint_mix: float = 0.35
## Extra brightness multiplier on top of the tint mix; kept near 1.0 so the
## top band alone never pushes a pixel toward the HDR glow threshold.
@export var highlight_brightness: float = 1.0

## Warm, saturated tint blended lightly into the mid ("lit side") band, so it
## reads as the block's own strongest, most saturated colour.
@export var lit_tint: Color = Color(1.0, 0.15, 0.0)
@export var lit_tint_mix: float = 0.15

## Cool tint blended into the darkest (shadow) band before it is dimmed by
## shadow_brightness -- together they read as "darker but slightly cool/
## desaturated, never near-black" rather than a flat multiply-by-black.
@export var shadow_tint: Color = Color(0.85, 0.85, 0.95)
@export var shadow_tint_mix: float = 0.6
@export var shadow_brightness: float = 0.72

## -- Hard-edged specular highlight (a small "plastic" light-catcher) ---------
## Fix round (owner review: "blue blocks show large pure-white patches...
## clamp the specular so it stays a small, hard, slightly tinted highlight
## below the glow threshold [1.1] and never whites out a whole face"):
## specular_strength/sharpness/softness retuned so the lit dot is small and
## dim, and specular_albedo_tint blends the block's own colour into the
## highlight instead of a flat pure-white patch.
@export var specular_color: Color = Color(1.0, 1.0, 1.0)
## Blinn-Phong exponent before toon-quantizing; higher is a smaller, sharper dot.
@export var specular_sharpness: float = 96.0
## Width of the smoothstep used to turn the specular falloff into a hard edge.
@export var specular_softness: float = 0.03
@export var specular_strength: float = 0.16
## How much of the block's own lit albedo to blend into specular_color, so the
## highlight reads as a light-catch on the block's own surface, not a plain
## white sticker.
@export var specular_albedo_tint: float = 0.4

## -- Bevelled cell-edge highlight (hugs the true cell edge, fades inward) ----
## Fix round (owner review: "every cell face shows a second square drawn well
## inside the edge... remove it. The bevel highlight must hug the actual cell
## edge (outermost ~1-1.5 px, fading inward)"): the previous version offset
## the bright band past the seam width, drawing a visible inset "picture
## frame" square. Now both the seam (fragment(), always on) and the bevel
## (light(), lit-facing only) measure distance from the *same* true UV edge
## (dist_to_edge = 0), so the bright band starts exactly at the edge and
## fades over bevel_highlight_width_px, with no gap or offset ring.
## Screen-space width, in pixels, the bright edge band fades over.
@export var bevel_highlight_width_px: float = 1.4
@export var bevel_highlight_color: Color = Color(1.0, 0.92, 0.8)
## Only applied where a face's own N.L is bright enough to be "toward the
## light" -- see shaders/block_cell_grid.gdshader light()'s own bevel_mask.
@export var bevel_highlight_strength: float = 0.22

## -- Subtle warm rim light on silhouette/cell edges facing the sun -----------
## Fix round (owner review: "plus a subtle warm rim light on silhouette edges
## facing the sun"). A cheap Fresnel term (1 - N.V), masked to the lit side,
## kept low-strength so it reads as a soft edge glow rather than a second
## specular pass.
@export var rim_color: Color = Color(1.0, 0.75, 0.5)
@export var rim_power: float = 2.5
@export var rim_strength: float = 0.15

## -- Outline tint (owner feedback: "restrained... a dark tinted version of
## the block color rather than pure black") -----------------------------------
## How much of a block's own colour (darkened by outline_tint_darken) to mix
## into the outline pass versus the flat outline_color above. The outline
## ShaderMaterial stays one shared instance across every owner colour
## (game/BlockFactory.gd's own DECISION); the tint itself reaches it through a
## per-instance shader parameter, not a second cached material.
@export var outline_tint_amount: float = 0.65
## How much a block's own colour is darkened before it is mixed into the
## outline, so the tint still reads as a silhouette, not a lit surface.
@export var outline_tint_darken: float = 0.35
