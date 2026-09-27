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
## separate, collision-free band + chamfer mesh that hangs below the
## overlay's own underside, so the two read as one continuous, much thicker
## edge without moving a single physics number.
##
## Loaded once as config/disc_body_visuals.tres.

## -- Metal side band ---------------------------------------------------------
## Height of the band, as a fraction of the disc's own diameter
## (2 * MapDef.field_radius). The top chamfer_height_fraction slice of this
## budget is carved into the sloped chamfer face (see below); the remainder
## stays a plain vertical wall.
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
## The band's own vertical wall (and the chamfer's own bottom/outer edge --
## see chamfer_height_fraction below) is scaled out from field_radius by this
## factor, so it never z-fights game/TerritoryOverlay.gd's own CylinderMesh
## side wall, which occupies the exact same radius over the same
## [-disk_height, 0] range.
##
## DECISION (config/DiscBodyVisuals.gd, Bontago-pt.12, owner: "the glowing
## strip currently sits slightly outside the disc as its own separate
## element; in the mockup the disc has a chamfered edge that makes up the
## glowing strip"): doubled from the old 1.003 hair's-width to 1.006 -- the
## chamfer face now bridges from the true edge (radius scale 1.0, flush with
## the overlay's own top-face boundary) down to THIS radius, so the value
## also sets how far the chamfer visibly slopes outward. 1.003 read as an
## almost-invisible sliver of bevel once the chamfer replaced the old
## separately-lifted rim; 1.006 (the old rim_radius_scale's own "hair's-width
## proud lip" value, coincidentally already tuned against this same mockup)
## reads as a genuine, visible chamfer without looking like a floating gap.
@export var band_radius_scale: float = 1.006
## Radial segments the band/chamfer outline is walked in (game/DiscBody.gd's
## own _outline_points()) -- independent of TerritoryVisuals.disk_mesh_segments
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

## -- Surface texture (Bontago-pt.12, owner: "the disc looks close to the
## mockup but it lacks the texture, it's especially visible in the mockup
## where it interacts with the sun") -- a subtle brushed-metal look on the
## band + chamfer material (the only disc surfaces this package owns; the
## flat mirrored top surface belongs to game/TerritoryOverlay.gd /
## config/TerritoryVisuals.gd, a different package's ownership). Both the
## band's own StandardMaterial3D and the chamfer's ShaderMaterial sample the
## same procedurally-generated (FastNoiseLite-backed NoiseTexture2D, no
## third-party asset) tangent-space normal map, using each mesh's own
## generated UV/tangent data (SurfaceTool.generate_tangents(), U running
## around the disc's circumference) so the "grain" runs circumferentially
## like a lathe-turned metal edge.
## -----------------------------------------------------------------------
## StandardMaterial3D.anisotropy / the chamfer shader's own ANISOTROPY output
## -- 0 disables the anisotropic brushed-metal specular streak entirely
## (a plain isotropic GGX highlight).
@export var surface_anisotropy: float = 0.0
## Strength (BaseMaterial3D.normal_scale / the chamfer shader's own
## NORMAL_MAP_DEPTH) of the generated fine-noise normal map -- how strongly
## it perturbs the surface normal, and so how visible the resulting specular
## sparkle is in the sun sheen. 0 disables the bump entirely (a perfectly
## smooth normal).
@export var surface_noise_strength: float = 0.0
## FastNoiseLite.frequency for the generated normal-map texture -- higher
## reads as a finer, tighter grain; lower as broad, soft undulations.
@export var surface_noise_frequency: float = 0.35

## -- Glowing chamfer (mockup: "the disc has a chamfered edge that makes up
## the glowing strip") -----------------------------------------------------
## Height of the emissive chamfer face, as a fraction of the band's own
## height (band_height_fraction * diameter) -- it sits at the very top of
## the band, sloping from the true playing-surface edge (flush with game/
## TerritoryOverlay.gd's own top-face boundary, no gap) down and out to the
## band's own outer radius (band_radius_scale above).
##
## DECISION (config/DiscBodyVisuals.gd, Bontago-pt.12, owner: "the glowing
## strip currently sits slightly outside the disc as its own separate
## element ... the disc has a chamfered edge that makes up the glowing
## strip"): replaces the old separate, radius- and Y-offset "rim" mesh
## (Bontago-mp0.3.2/mp0.3.8) with a single sloped face that shares its top
## ring with the true disc edge and its bottom ring with the band's own top
## ring -- watertight, no floating gap, no second offset element. Kept at the
## same 0.08 magnitude the old rim_height_fraction (a thin lip, not a thick
## neon band) was already tuned to across two owner review passes.
@export var chamfer_height_fraction: float = 0.08
@export var chamfer_glow_color: Color = Color(1.0, 0.78, 0.35)
## Main.tscn's HDR glow threshold is 1.1 (Bontago-mp0.3); comfortably above
## that so the chamfer actually blooms, matching the mockup's soft glow.
@export var chamfer_glow_energy: float = 2.6
## shaders/disc_rim.gdshader's own min_screen_width_factor uniform -- world
## meters the chamfer's bottom edge (where it meets the band, never the true
## top edge shared with the overlay) is pushed down per world meter of camera
## distance, so a thin chamfer's rasterized screen coverage never drops below
## roughly a pixel no matter how far the camera is, on any map radius. 0
## disables it (the mesh renders exactly as authored).
@export var chamfer_screen_min_width_factor: float = 0.004
