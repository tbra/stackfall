class_name BlockVisualTuning
extends Resource
## Bontago-xtq.27 (M7 P2, docs/M7_ART_DIRECTION.md, owner decision 2026-09-26
## Bontago-5h7 Q1/Q2): tunables for the block toon material + inverted-hull
## outline + cell-grid influence glow. The mesh itself stays one merged solid
## shape per block (Bontago-xtq.3); everything here only changes how that one
## `ArrayMesh` is shaded and outlined, never its geometry/collision.

## Inverted-hull outline pass (shaders/block_outline.gdshader): how far the
## outline mesh's vertices are pushed out along their own normal, in meters.
@export var outline_width_m: float = 0.012

## Flat, unshaded color of the outline pass.
@export var outline_color: Color = Color(0.05, 0.04, 0.05)

## shaders/block_cell_grid.gdshader: how many discrete lit/shadow bands the
## toon diffuse ramp is quantized into (cel-shading "steps").
@export var toon_band_count: int = 3

## Screen-space width, in pixels, of the dark line drawn along each visible
## face's UV edge (BlockMeshBuilder's existing 0..1 per-cell UVs put one such
## edge at every cell boundary, spec 2.10 as amended).
@export var grid_line_width_px: float = 1.5

## Cell-grid line color for a block that is not currently read as
## contributing to territory influence (in flight / just landed).
@export var grid_line_color: Color = Color(0.12, 0.1, 0.1)

## Cell-grid line color for a block whose `contributing` per-instance shader
## parameter is true (settled/sleeping -- see BlockFactory.build()'s
## `sleeping_state_changed` wiring).
@export var grid_line_glow_color: Color = Color(1.0, 0.92, 0.55)

## Emission multiplier applied to grid_line_glow_color while `contributing`
## is true. 0 would make the glow invisible; this is not a magic 1.0 because
## the grid lines are thin and need a boosted emission to read from the
## typical match camera distance.
@export var grid_line_glow_strength: float = 2.2
