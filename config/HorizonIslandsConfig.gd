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
@export var radius_min_m: float = 650.0
@export var radius_max_m: float = 1050.0
## Height band (m, world Y) of each island's cap-surface center. The rock body
## hangs below, so the lower part is buried in the cloud layer.
@export var height_min_m: float = 14.0
@export var height_max_m: float = 46.0
## Uniform scale range (distant islands must read at 600m+).
@export var scale_min: float = 1.6
@export var scale_max: float = 2.8
## Random angular jitter inside each ring slot (0 = evenly spaced, 1 = whole
## slot), so the ring is irregular with clear sky gaps.
@export var angle_jitter: float = 0.7
## Seed mixed with the map id so every map gets its own stable arrangement.
@export var seed: int = 1207
## Distance (m) at which LOD0 hands over to LOD1.
@export var lod1_begin_m: float = 800.0
## Distance (m) at which LOD1 hands over to LOD2.
@export var lod2_begin_m: float = 950.0
## Distance (m) beyond which the island is culled (0 = never).
@export var visibility_end_m: float = 0.0
