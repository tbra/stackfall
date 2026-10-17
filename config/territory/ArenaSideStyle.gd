class_name ArenaSideStyle
extends Resource
## Look of the arena's side and underside. One enum picks between the shipped look
## (CURRENT: DiscBodyVisuals' metal band + glowing chamfer + flat bottom) and
## the alternative generated looks. Every option is
## cheap static geometry built once per map by game/field/ArenaSideBuilder.gd: flat
## shaded, vertex-coloured, opaque, at most two materials (body + glow), no
## per-frame work. Loaded once as config/territory/arena_side_style.tres.

## MACHINED_STYLISED (bold cel bands), MACHINED_DETAILED (rivets, light strip,
## vents, thrusters) and MACHINED_HEAVY (bevelled rim, terraces) refine MACHINED_DISC.
## MONOLITH, TAPERED_STRATA and PLATED_DOME continue the top instead of decorating
## a separate object: the dark plated playing surface (plates
## ~5 m, hairline seams, small rivets) wraps over the edge under a gold lip and
## carries on down the side and underneath. MONOLITH is one plated slab with a flat
## plated underside, TAPERED_STRATA a plated wall then an inverted frustum in
## three strata of the top's own browns, PLATED_DOME two plate courses and a
## shallow dome of plate rings.
## SHADER_DOME is PLATED_DOME's silhouette with no modelled detail, shaded by
## the top's own plating shader
## (shaders/territory/arena_side_shell.gdshader, sharing shaders/include/disc_plating.gdshaderinc).
enum Style {
	CURRENT,
	LAYERED_PLATES,
	ROCKY_ISLAND,
	MACHINED_DISC,
	MACHINED_STYLISED,
	MACHINED_DETAILED,
	MACHINED_HEAVY,
	MONOLITH,
	TAPERED_STRATA,
	PLATED_DOME,
	SHADER_DOME,
}

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

## -- MACHINED_STYLISED: bold cel bands, few big panels, crisp seams -----
## Total side depth as a fraction of the disc diameter.
@export var stylised_depth_fraction: float = 0.075
## Number of big panels around the disc.
@export var stylised_panel_count: int = 12
## Outline segments per panel; the last one is the recessed seam.
@export var stylised_panel_segments: int = 6
## Seam recess as a fraction of the disc radius.
@export var stylised_seam_depth_fraction: float = 0.007
## Shares of the side depth, top down: gold trim, upper panels, colour stripe,
## then the lower panels take what is left before the closing gold trim.
@export var stylised_trim_share: float = 0.07
@export var stylised_upper_share: float = 0.34
@export var stylised_stripe_share: float = 0.14
@export var stylised_lower_trim_share: float = 0.05
## Underside depth as a multiple of the side depth.
@export var stylised_underside_ratio: float = 0.8
## Where the underside narrows to (fraction of the radius) and how far the
## glowing core hangs (fraction of the underside depth).
@export var stylised_keel_scale: float = 0.25
@export var stylised_core_height_fraction: float = 0.3
## Brightness of the gold trim and core (HDR glow surface).
@export var stylised_glow_energy: float = 0.8
@export var stylised_gold_color: Color = Color(1.0, 0.72, 0.2)
@export var stylised_upper_color: Color = Color(0.96, 0.9, 0.78)
@export var stylised_stripe_color: Color = Color(0.95, 0.32, 0.22)
@export var stylised_lower_color: Color = Color(0.12, 0.16, 0.32)
@export var stylised_seam_color: Color = Color(0.04, 0.03, 0.07)
@export var stylised_underside_color: Color = Color(0.14, 0.18, 0.34)
@export var stylised_underside_alt_color: Color = Color(0.9, 0.4, 0.3)
@export var stylised_core_color: Color = Color(1.0, 0.78, 0.4)

## -- MACHINED_DETAILED: panel lines, rivets, light strip, vents, thrusters
@export var detailed_depth_fraction: float = 0.07
@export var detailed_panel_count: int = 24
@export var detailed_panel_segments: int = 4
@export var detailed_seam_depth_fraction: float = 0.004
## Shares of the side depth: gold hairline, upper panels, light strip, closing
## lip (the lower panels take the rest).
@export var detailed_trim_share: float = 0.04
@export var detailed_upper_share: float = 0.3
@export var detailed_strip_share: float = 0.12
@export var detailed_lip_share: float = 0.05
## How far the light strip sits behind the panels, as a fraction of the radius.
@export var detailed_strip_recess_fraction: float = 0.006
## Rivet half-width and height as fractions of the radius; two rows of two per panel.
@export var detailed_rivet_size_fraction: float = 0.006
@export var detailed_rivet_height_fraction: float = 0.006
## Concentric underside terraces and the groove drop of each (share of the underside depth).
@export var detailed_ring_count: int = 4
@export var detailed_groove_share: float = 0.08
@export var detailed_underside_ratio: float = 1.0
@export var detailed_keel_scale: float = 0.22
## Dark vent slots on one terrace and glowing thruster cones on another (1-based terrace).
@export var detailed_vent_count: int = 16
@export var detailed_vent_ring: int = 1
@export var detailed_thruster_count: int = 6
@export var detailed_thruster_ring: int = 3
@export var detailed_thruster_size_fraction: float = 0.035
@export var detailed_thruster_length_share: float = 0.22
## Brightness of every glowing part (HDR glow surface).
@export var detailed_glow_energy: float = 0.85
@export var detailed_gold_color: Color = Color(1.0, 0.72, 0.2)
@export var detailed_panel_color: Color = Color(0.34, 0.4, 0.54)
@export var detailed_lower_color: Color = Color(0.24, 0.3, 0.44)
@export var detailed_seam_color: Color = Color(0.04, 0.04, 0.08)
@export var detailed_rivet_color: Color = Color(0.9, 0.85, 0.7)
@export var detailed_lip_color: Color = Color(0.12, 0.14, 0.24)
@export var detailed_strip_color: Color = Color(1.0, 0.45, 0.1)
@export var detailed_underside_color: Color = Color(0.22, 0.27, 0.4)
@export var detailed_underside_alt_color: Color = Color(0.3, 0.35, 0.5)
@export var detailed_groove_color: Color = Color(0.06, 0.07, 0.12)
@export var detailed_vent_color: Color = Color(0.06, 0.06, 0.1)
@export var detailed_thruster_color: Color = Color(1.0, 0.5, 0.15)
@export var detailed_core_color: Color = Color(1.0, 0.6, 0.25)

## -- MACHINED_HEAVY: thick bevelled rim band, terraces to a keel --------
@export var heavy_depth_fraction: float = 0.11
@export var heavy_panel_count: int = 20
@export var heavy_panel_segments: int = 4
@export var heavy_seam_depth_fraction: float = 0.005
## Shares of the side depth: gold trim, thick rim band, bevel; terraces take the rest.
@export var heavy_trim_share: float = 0.04
@export var heavy_rim_share: float = 0.22
@export var heavy_bevel_share: float = 0.1
## How far the bevel and each terrace step in, as fractions of the radius.
@export var heavy_bevel_inset_fraction: float = 0.04
@export var heavy_step_inset_fraction: float = 0.09
@export var heavy_step_count: int = 3
## Gold trim on each terrace edge, as a share of the side depth.
@export var heavy_step_trim_share: float = 0.025
## Keel taper depth as a multiple of the side depth, where it narrows to, and
## the radius of the glowing core on its flat cap (fractions of the radius).
@export var heavy_keel_ratio: float = 0.7
@export var heavy_keel_scale: float = 0.2
@export var heavy_core_scale: float = 0.1
@export var heavy_glow_energy: float = 0.85
@export var heavy_gold_color: Color = Color(1.0, 0.72, 0.2)
@export var heavy_rim_color: Color = Color(0.95, 0.88, 0.74)
@export var heavy_bevel_color: Color = Color(0.95, 0.38, 0.25)
@export var heavy_wall_color: Color = Color(0.18, 0.23, 0.4)
@export var heavy_wall_alt_color: Color = Color(0.12, 0.16, 0.3)
@export var heavy_ledge_color: Color = Color(0.06, 0.05, 0.1)
@export var heavy_seam_color: Color = Color(0.04, 0.03, 0.07)
@export var heavy_keel_color: Color = Color(0.12, 0.15, 0.26)
@export var heavy_core_color: Color = Color(1.0, 0.65, 0.25)

## -- Shared by the plated options: the top's own plating carried onto the side ------------
## Plate length along the rim (m); matches DiscSurfaceDef.proc_plate_length_m, so
## the side has as many plates as the top has around its edge.
@export var top_plate_length_m: float = 5.0
## Width of the hairline seams between plates and plate courses (m).
@export var top_seam_width_m: float = 0.12
## Recess of the vertical seams, as a fraction of the disc radius.
@export var top_seam_depth_fraction: float = 0.0015
## Random per-plate brightness variation (the top's proc_tone_variation).
@export var top_tone_variation: float = 0.12
## Seed of the per-plate brightness.
@export var top_seed: int = 5
## Rivet half-width and height as fractions of the radius (two per plate corner row).
@export var top_rivet_size_fraction: float = 0.0025
@export var top_rivet_height_fraction: float = 0.0015
## Inset of the rivet rows from the plate edges, as a share of the course height.
@export var top_rivet_row_inset: float = 0.18
## Inset of a plate's rivets from its ends, as a share of the plate width.
@export var top_rivet_end_inset: float = 0.12
## Underside plate ring width and central hub radius (m), as on the top.
@export var top_ring_width_m: float = 4.5
@export var top_hub_radius_m: float = 3.5
## The gold lip wraps over the playing surface's edge. How far it hangs below the
## slab's bottom edge (fraction of the disc diameter), how far it stands proud of
## the wall (fraction of the radius) and the share of its height that is the
## upper bevel.
@export var top_lip_below_fraction: float = 0.002
@export var top_lip_out_fraction: float = 0.004
@export var top_lip_bevel_share: float = 0.45
## Brightness of the gold lip (HDR glow surface).
@export var top_lip_energy: float = 1.3
@export var top_lip_color: Color = Color(1.0, 0.72, 0.2)
@export var top_lip_shade_color: Color = Color(0.85, 0.42, 0.1)
## Dark ledge under the lip.
@export var top_ledge_color: Color = Color(0.01, 0.01, 0.02)
## Plate, seam, rivet and darker underside colours (the top's navy plating).
@export var top_plate_color: Color = Color(0.04, 0.045, 0.085)
@export var top_under_color: Color = Color(0.03, 0.034, 0.065)
@export var top_hub_color: Color = Color(0.02, 0.022, 0.045)
@export var top_seam_color: Color = Color(0.006, 0.006, 0.014)
@export var top_rivet_color: Color = Color(0.2, 0.18, 0.17)

## -- MONOLITH: one plated slab, flat plated underside ------------------------
## Wall height below the lip, as a fraction of the disc diameter.
@export var monolith_depth_fraction: float = 0.05
## Bottom-edge bevel: share of the wall height and inset (fraction of the radius).
@export var monolith_bevel_share: float = 0.15
@export var monolith_bevel_inset_fraction: float = 0.012

## -- TAPERED_STRATA: plated wall, then an inverted frustum in strata ---------
## Vertical wall height and the frustum depth, as fractions of the disc diameter.
@export var tapered_wall_fraction: float = 0.03
@export var tapered_bowl_fraction: float = 0.06
## Radius of the frustum's flat bottom as a fraction of the disc radius.
@export var tapered_bowl_scale: float = 0.5
## Number of strata bands on the frustum and the inward step between them
## (fraction of the radius).
@export var tapered_strata_count: int = 3
@export var tapered_step_inset_fraction: float = 0.01
## Strata colours from the top band down (cycled), drawn from the top's browns.
@export var tapered_strata_colors: PackedColorArray = PackedColorArray([
	Color(0.075, 0.05, 0.05), Color(0.055, 0.038, 0.042), Color(0.04, 0.03, 0.036)
])

## -- PLATED_DOME: plate courses on the wall, a shallow dome of plate rings ---
## Number and height of the plate courses (fraction of the disc diameter each).
@export var dome_course_count: int = 2
@export var dome_course_fraction: float = 0.025
## How far the dome sags at its centre (fraction of the disc diameter).
@export var dome_depth_fraction: float = 0.06

## -- SHADER_DOME: PLATED_DOME's silhouette, shaded by the top's own shader ---
## (Geometry uses dome_* above; the lip uses top_lip_*.) Outline segments of the
## smooth wall and dome; the plates are drawn by the shader, not by geometry.
@export var shell_segments: int = 128
