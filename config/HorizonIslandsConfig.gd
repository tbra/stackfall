class_name HorizonIslandsConfig
extends Resource
## Tunables for game/HorizonIslands.gd: the cosmetic ring of low-poly floating
## islands on the horizon (assets/models/horizon_islands_v1). Visual only: no
## collision, no shadows, never networked. Placement is a pure function of
## (seed, map id, these values), so host and clients agree.

## Master switch.
@export var enabled: bool = true
## Number of islands in the ring (0 hides them).
@export var count: int = 7
## Ring distance from the arena center (m), inner and outer bound.
@export var radius_min_m: float = 900.0
@export var radius_max_m: float = 1300.0
## Height band (m, world Y) of each island's cap-surface center. The rock body
## hangs below, so the lower part is buried in the cloud layer.
@export var height_min_m: float = -4.0
@export var height_max_m: float = 8.0
## Uniform scale range (distant islands must read at 600m+).
@export var scale_min: float = 1.8
@export var scale_max: float = 3.0
## Random angular jitter inside each ring slot (0 = evenly spaced, 1 = whole
## slot), so the ring is irregular with clear sky gaps.
@export var angle_jitter: float = 0.7
## Seed mixed with the map id so every map gets its own stable arrangement.
@export var seed: int = 1207
## Distance (m) at which LOD0 hands over to LOD1.
@export var lod1_begin_m: float = 1050.0
## Distance (m) at which LOD1 hands over to LOD2.
@export var lod2_begin_m: float = 1250.0
## Distance (m) beyond which the island is culled (0 = never).
@export var visibility_end_m: float = 0.0
## Extra width/depth stretch: each island's x and z are scaled independently by
## 1 +/- this fraction, so repeats of one variant stop reading as the same cone.
@export var stretch_fraction: float = 0.25
## Maximum random tilt (degrees) around x and z, so no island sits dead level.
@export var tilt_max_deg: float = 7.0
## How far the island colours are mixed toward the live sky fog/horizon colour
## (0 = raw asset facets, 1 = flat haze). Replaces the scene depth fog.
@export var haze_amount: float = 0.28
## Brightness multiplier on the asset's own facet colours before haze and light.
@export var color_gain: float = 1.0
