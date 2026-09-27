class_name DiscBodyVisuals
extends Resource
## Purely-visual thickness for the play disc (Bontago-mp0.3.2, owner
## feedback: "The disc is just a thin mirror currently, the mockup has a
## much thicker metallic disc with a soft glowing border going round the
## rim."). game/TerritoryOverlay.gd's own CylinderMesh stays exactly
## MapDef.disk_height thick -- that number is load-bearing for physics
## (game/Field.gd's own collision walls are disk_height deep, so a block
## cannot tunnel into a hole) and this package's brief keeps that gameplay
## semantic untouched. Every field below only shapes game/DiscBody.gd's
## separate, collision-free band + rim mesh that hangs below the overlay's
## own underside, so the two read as one continuous, much thicker edge
## without moving a single physics number.
##
## Loaded once as config/disc_body_visuals.tres.

## -- Metal side band ---------------------------------------------------------
## Height of the band, as a fraction of the disc's own diameter
## (2 * MapDef.field_radius).
##
## DECISION (config/DiscBodyVisuals.gd, Bontago-mp0.3.2 review pass 2, owner:
## "make the visible band roughly 3-4% of the disc diameter tall"): the
## original 4-5% read against docs/art_mockups/08-cel-shaded-home-
## beacons.png's own side wall; narrowed into the reviewer's tighter 3-4%
## reading of the same image.
@export var band_height_fraction: float = 0.035
## Dark polished metal, matching the mockup's black-lacquer/graphite band.
@export var band_color: Color = Color(0.035, 0.035, 0.04)
@export var band_metallic: float = 0.85
@export var band_roughness: float = 0.32
## Closes the band's underside with a flat cap so the disc never reads as a
## hollow shell from a low or distant camera angle.
@export var bottom_cap_enabled: bool = true
## The band's own outline is scaled out from field_radius by this factor (a
## hair's-width proud lip, same idea as rim_radius_scale below) so its top
## edge (now y = 0, flush with the true playing surface -- see game/
## DiscBody.gd's own DECISION) never z-fights game/TerritoryOverlay.gd's own
## CylinderMesh side wall, which occupies the exact same radius over the
## same [-disk_height, 0] range.
@export var band_radius_scale: float = 1.003
## Radial segments the band/rim outline is walked in (game/DiscBody.gd's own
## _outline_points()) -- independent of TerritoryVisuals.disk_mesh_segments
## (the top surface's own CylinderMesh) so this mesh's circular silhouette
## can be tuned without paying for a denser top-surface mesh too.
##
## DECISION (config/DiscBodyVisuals.gd, Bontago-mp0.3.2 review pass 2, owner:
## "the bottom edge of the band is stair-stepped/jagged ... must be a smooth
## circle"): raised well past the 96 the top surface uses -- a life-sized
## (tens of meters) disc silhouette seen close up at a grazing angle shows
## polygon facets at 96 that a flat top-down view hides; this mesh is small
## enough that a much higher segment count costs nothing measurable.
@export var segments: int = 192

## -- Glowing rim line (mockup: "a soft glowing border going round the rim") -
## Height of the emissive rim strip, as a fraction of the band's own height
## (band_height_fraction * diameter) -- it sits at the very top of the band,
## flush against the overlay's own underside.
##
## DECISION (config/DiscBodyVisuals.gd, Bontago-mp0.3.2 review pass 2, owner:
## "the glow is a very thick neon-yellow band covering the whole side ...
## only a THIN warm-gold/amber lip line along the top edge glows"): cut to a
## genuinely thin lip -- 0.22 of the (now shorter) band was still a
## noticeable fraction of the visible edge, not a line.
##
## DECISION (config/DiscBodyVisuals.gd, Bontago-mp0.3.8): nudged 0.05 -> 0.08
## alongside rim_screen_min_width_factor below -- a small additional safety
## margin now that rim_radius_scale (below) turned out to be the actual fix
## for the "breaks into dashes at distance" report; still a thin lip up
## close (docs/art_mockups/08-cel-shaded-home-beacons.png).
@export var rim_height_fraction: float = 0.08
## The rim's own outline is scaled out from the band's by this factor (a
## hair's-width proud lip) so it never z-fights the band's top edge.
##
## DECISION (config/DiscBodyVisuals.gd, Bontago-mp0.3.8, owner: "the thin
## glowing gold lip breaks into dashes at distance"): diagnostic captures
## (feedback/overhaul/disc2-diag1..5) proved the far/away side of the ring
## stayed dashed even at 6x the rim's normal height and an extreme distance-
## based widening factor (rim_screen_min_width_factor below) -- the actual
## cause was the rim's TOP edge (radius = field_radius * this factor, y = 0)
## sitting almost exactly at the same radius AND the same y as game/
## TerritoryOverlay.gd's own CylinderMesh top-face edge, z-fighting at long
## camera distances. First fix attempt raised this to 1.02 to separate them
## radially, which did stop the dashing (disc2-diag5) but (owner review pass,
## reading disc2-r3-overview.png's own left disc edge) left a visibly
## floating gap ring between the disc's true edge and the lip -- 1.02 is
## ~2% of field_radius, which reads as "proud" rather than "flush" once
## actually looked for. Reverted to the original 1.006 (a genuine hair's-
## width); the z-fight is instead resolved by rim_lift below, which
## separates the two edges VERTICALLY (where nothing else needs to line up
## with the rim) instead of radially (where the top surface's own true edge
## does).
@export var rim_radius_scale: float = 1.006
## Bontago-mp0.3.8 (owner: fix the rim/overlay z-fight "another way ... lift
## the lip slightly above the top surface"). World meters the rim mesh's own
## top_y is raised above the true playing surface (0.0) -- separates it from
## game/TerritoryOverlay.gd's own CylinderMesh top-face edge on the Y axis
## instead of radially (rim_radius_scale above), so the lip can stay at
## rim_radius_scale's own hair's-width radius (no visible floating gap) while
## still resolving the depth-buffer precision fight at distance. Small enough
## on any map size (a few centimeters) to read as sitting exactly on the
## edge, not floating above it.
@export var rim_lift: float = 0.03
@export var rim_color: Color = Color(1.0, 0.78, 0.35)
## Main.tscn's HDR glow threshold is 1.1 (Bontago-mp0.3); comfortably above
## that so the rim actually blooms, matching the mockup's soft glow. Left
## unchanged from pass 1 -- pass 2's "neon" complaint was the glowing AREA
## (rim_height_fraction above), not this strip's own brightness.
@export var rim_emission_energy: float = 2.6
## shaders/disc_rim.gdshader's own min_screen_width_factor uniform -- world
## meters the rim's bottom edge is pushed down per world meter of camera
## distance, so a thin rim's rasterized screen coverage never drops below
## roughly a pixel no matter how far the camera is, on any map radius. Not
## the fix for the specific "dashes at distance" report (see
## rim_radius_scale's own DECISION above for the actual cause) -- kept as a
## genuine secondary safety net: it measurably thickened/solidified the
## rim's near-camera portion in every diagnostic capture. 0 disables it
## (the mesh renders exactly as authored).
@export var rim_screen_min_width_factor: float = 0.004
