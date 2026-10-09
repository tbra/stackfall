class_name ArenaSideStyle
extends Resource
## Look of the arena's side and underside (Bontago-mp0.150.2, owner: "the side
## and bottom needs to be redone"). One enum picks between the shipped look
## (CURRENT: DiscBodyVisuals' metal band + glowing chamfer + flat bottom) and
## three alternative generated looks the owner can flip between. Every option is
## cheap static geometry built once per map by game/ArenaSideBuilder.gd: flat
## shaded, vertex-coloured, opaque, at most two materials (body + glow), no
## per-frame work. Loaded once as config/arena_side_style.tres.

enum Style { CURRENT, LAYERED_PLATES, ROCKY_ISLAND, MACHINED_DISC }

## Which look to draw. CURRENT keeps the DiscBodyVisuals band/chamfer unchanged.
@export var style: Style = Style.CURRENT

## -- Shared material look ----------------------------------------------------
## Roughness of the toon-shaded body material shared by every option.
@export var body_roughness: float = 0.9

## -- LAYERED_PLATES: stepped pastel plates over a tapered keel ---------------
## Total drop of the option below the slab, as a fraction of the disc diameter.
@export var layered_depth_fraction: float = 0.07
## Number of stacked plates.
@export var layered_plate_count: int = 3
## How far each lower plate is inset from the one above, as a fraction of the radius.
@export var layered_inset_fraction: float = 0.05
## Share of the total depth used by the plates; the rest is the tapered keel.
@export var layered_plate_share: float = 0.5
## Radius of the keel where the taper ends, as a fraction of the disc radius.
@export var layered_keel_radius_fraction: float = 0.16
## Height of the glowing core cone as a fraction of the keel depth.
@export var layered_core_height_fraction: float = 0.3
## Plate colours from the top plate down (cycled when there are more plates).
@export var layered_plate_colors: PackedColorArray = PackedColorArray([
	Color(0.93, 0.87, 0.76), Color(0.95, 0.68, 0.5), Color(0.34, 0.42, 0.5)
])
## Colour of the tapered keel below the plates.
@export var layered_underside_color: Color = Color(0.17, 0.2, 0.27)
## Colour and brightness of the glowing core at the tip of the keel.
@export var layered_core_color: Color = Color(1.0, 0.7, 0.35)
@export var layered_core_energy: float = 2.5

## -- ROCKY_ISLAND: faceted stone strata tapering to a cone, with crystals ----
## Total depth of the rock as a fraction of the disc diameter.
@export var rock_depth_fraction: float = 0.2
## Number of stone strata (each one a wall plus an inward ledge).
@export var rock_strata_count: int = 6
## Polygon facets around the rock; fewer reads as chunkier stone.
@export var rock_segments: int = 28
## Random in/out wobble of each stratum ring, as a fraction of the disc radius.
@export var rock_roughness_fraction: float = 0.06
## Taper curve: 1 = straight cone, above 1 keeps wide shoulders before narrowing.
@export var rock_taper_exponent: float = 1.6
## How much of each stratum's inward step happens along its wall (0 = flat ledge).
@export var rock_wall_slope: float = 0.35
## Seed of the deterministic wobble and crystal placement.
@export var rock_seed: int = 7
@export var rock_wall_color: Color = Color(0.78, 0.62, 0.46)
@export var rock_alt_color: Color = Color(0.55, 0.4, 0.34)
@export var rock_ledge_color: Color = Color(0.4, 0.3, 0.3)
## Hanging crystals under the rock.
@export var rock_crystal_count: int = 7
## Crystal base radius as a fraction of the disc radius.
@export var rock_crystal_size_fraction: float = 0.03
## Crystal length as a fraction of the rock depth.
@export var rock_crystal_length_fraction: float = 0.25
@export var rock_crystal_color: Color = Color(0.45, 0.95, 0.85)
@export var rock_crystal_energy: float = 2.0

## -- MACHINED_DISC: paneled metal side, light strip, ribbed underside --------
## Total depth as a fraction of the disc diameter.
@export var machined_depth_fraction: float = 0.05
## Number of side panels (each is three faces plus a recessed seam).
@export var machined_panel_count: int = 28
## Seam recess depth as a fraction of the disc radius.
@export var machined_seam_depth_fraction: float = 0.004
## Where the light strip starts, as a fraction of the depth from the slab.
@export var machined_strip_position: float = 0.4
## Light strip height as a fraction of the depth.
@export var machined_strip_height_fraction: float = 0.1
## How far the strip is recessed behind the panels, as a fraction of the radius.
@export var machined_strip_recess_fraction: float = 0.006
## Fraction of the depth where the vertical side ends and the ribbed underside begins.
@export var machined_side_share: float = 0.6
## How far the underside ribs hang below the valleys, as a fraction of the depth.
@export var machined_rib_height_fraction: float = 0.08
## Radius of the central emitter disc as a fraction of the disc radius.
@export var machined_emitter_radius_fraction: float = 0.1
@export var machined_panel_color: Color = Color(0.12, 0.13, 0.17)
@export var machined_seam_color: Color = Color(0.05, 0.05, 0.07)
@export var machined_underside_color: Color = Color(0.14, 0.15, 0.19)
@export var machined_light_color: Color = Color(0.45, 0.85, 1.0)
@export var machined_light_energy: float = 1.4
