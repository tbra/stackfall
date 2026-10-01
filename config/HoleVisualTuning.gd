class_name HoleVisualTuning
extends Resource
## Bontago-1pi.11.42 (owner decision Bontago-gdb, option A): holes are a shader
## effect on a solid disc. Hole cells read as an animated "void" in
## shaders/territory.gdshader (game/TerritoryOverlay.gd uploads these) and a
## block touching one dissolves with a rim glow toward the void colour
## (shaders/block_cell_grid.gdshader, game/BlockDissolveFx.gd). Presentation
## only; not part of the F4 tuning panel, so no config/tuning_panel_hints.tres
## entries are needed.

@export_group("Void (hole cells)")
## Deepest colour of the void.
@export var void_deep_color: Color = Color(0.01, 0.005, 0.03)
## Colour the swirl bands lift toward.
@export var void_mid_color: Color = Color(0.24, 0.08, 0.55)
## Lit rim along every hole-cell edge that borders solid floor; also the
## dissolve rim glow on blocks.
@export var void_rim_color: Color = Color(0.65, 0.35, 1.0)
## Rim width, in fractions of one grid cell.
@export_range(0.01, 0.5, 0.01) var void_rim_width_cells: float = 0.18
@export_range(0.0, 8.0, 0.1) var void_rim_glow: float = 1.8
## Swirl pattern frequency (per metre), speed (rad-ish per second) and twist.
@export_range(0.05, 4.0, 0.05) var void_swirl_scale: float = 0.8
@export_range(0.0, 3.0, 0.05) var void_swirl_speed: float = 0.35
@export_range(0.0, 6.0, 0.05) var void_swirl_twist: float = 1.4
## Cel bands in the swirl, and how soft their steps are.
@export_range(1, 6, 1) var void_band_count: int = 3
@export_range(0.0, 0.5, 0.01) var void_band_softness: float = 0.08
## How far the brightest band lifts from deep toward mid colour.
@export_range(0.0, 1.0, 0.01) var void_mid_amount: float = 1.0

@export_group("Block dissolve")
## Noise frequency in block-local metres (higher = finer crumbs).
@export_range(0.5, 30.0, 0.5) var dissolve_noise_scale: float = 5.0
## Width of the glowing edge of the eaten-away region (0..1 of the noise range).
@export_range(0.01, 0.6, 0.01) var dissolve_edge_width: float = 0.14
@export_range(0.0, 8.0, 0.1) var dissolve_rim_glow: float = 3.0
## Fade curve: progress is raised to this power (>1 starts slow, ends fast).
@export_range(0.25, 4.0, 0.05) var dissolve_progress_power: float = 1.0
