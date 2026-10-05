class_name HorizonIslandsConfig
extends Resource
## Tunables for game/HorizonIslands.gd: the cosmetic ring of low-poly floating
## islands on the horizon (assets/models/horizon_islands_v1). Visual only: no
## collision, no shadows, never networked. Placement is a pure function of
## (seed, map id, these values), so host and clients agree.

## Master switch. Off by default (owner playtest 2026-10-05, Bontago-mp0.133: the
## islands looked bad); set true in config/horizon_islands.tres to restore them.
@export var enabled: bool = true
## Number of islands in the ring (0 hides them).
@export var count: int = 7
## Ring distance from the arena center (m), inner and outer bound.
@export var radius_min_m: float = 850.0
@export var radius_max_m: float = 1200.0
## Height band (m, world Y) of each island's cap-surface center. The rock body
## hangs below. Bontago-mp0.123 root cause: the sky's horizon cloud banks
## (ring 300-760 m, tops up to 60 m) stand between the camera and the ring, so
## a cap near eye height left only its edge above the banks (a thin wedge).
## Keep the hanging body above the bank tops so the whole rock mass shows.
@export var height_min_m: float = 210.0
@export var height_max_m: float = 270.0
## Uniform scale range (distant islands must read at 900m+).
@export var scale_min: float = 2.0
@export var scale_max: float = 2.8
## Random angular jitter inside each ring slot (0 = evenly spaced, 1 = whole
## slot), so the ring is irregular with clear sky gaps.
@export var angle_jitter: float = 0.7
## Seed mixed with the map id so every map gets its own stable arrangement.
@export var seed: int = 1207
## Distance (m) at which LOD0 hands over to LOD1.
@export var lod1_begin_m: float = 1050.0
## Distance (m) at which LOD1 hands over to LOD2.
@export var lod2_begin_m: float = 1300.0
## Distance (m) beyond which the island is culled (0 = never).
@export var visibility_end_m: float = 0.0
## Extra width/depth stretch: each island's x and z are scaled independently by
## 1 +/- this fraction, so repeats of one variant stop reading as the same cone.
@export var stretch_fraction: float = 0.25
## Maximum random tilt (degrees) around x and z, so no island sits dead level.
@export var tilt_max_deg: float = 4.0
## Tilt (degrees) of every island's cap toward the arena center. The islands
## float above eye height, so a level cap is seen from below; tipping it toward
## the camera by more than its elevation angle (~10-15 degrees) shows the top.
@export var toward_tilt_deg: float = 24.0
## How far the island colours are mixed toward the live sky fog/horizon colour
## (0 = raw asset facets, 1 = flat haze). Replaces the scene depth fog.
@export var haze_amount: float = 0.28
## Brightness multiplier on the asset's own facet colours before haze and light.
@export var color_gain: float = 1.0
## The island shader is self-lit (scene sky ambient flattened every facet to one
## tone): facets whose world normal y is at least cap_normal_min_y are the cap
## and get cap_tint, the rest are rock body with rock_tint (multiplied with the
## asset's vertex colours and the live sun colour).
@export var cap_normal_min_y: float = 0.55
@export var cap_tint: Color = Color(1.25, 1.45, 1.15)
@export var rock_tint: Color = Color(1.0, 0.92, 0.85)
## Brightness of facets turned away from the sun, and of half-lit facets
## (fully sun-facing facets are 1.0). The gap is the facet contrast.
@export var shadow_level: float = 0.35
@export var mid_level: float = 0.7
