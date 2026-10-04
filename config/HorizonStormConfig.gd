class_name HorizonStormConfig
extends Resource
## Bontago-mp0.126: tunables for the distant storm cells on the horizon during
## storm weather (vfx/weather/HorizonStormCells.gd). Presentation only.
## config/horizon_storm.tres is the shipped instance.

@export_group("Layout")
## Fewest cells a storm shows on the horizon.
@export var cell_count_min: int = 1
## Most cells a storm shows on the horizon (each uses a different silhouette).
@export var cell_count_max: int = 2
## Distance (m) from the arena centre to a cell; far beyond the 45-90 m play field.
@export var distance_m: float = 900.0
## A cell's distance varies by up to this much either way (m).
@export var distance_jitter_m: float = 120.0
## Uniform scale of the 56 m wide authored cell; with the distance this sets how small it looks.
@export var cell_scale: float = 3.2
## Height (m) of the cell origin (cloud mid line) relative to the arena top plane; it sits on the horizon band behind the near cloud puffs.
@export var elevation_m: float = 10.0
## Two cells are at least this many degrees apart around the horizon.
@export var min_bearing_separation_deg: float = 70.0
## Mixed into the match seed so the horizon layout differs from other seeded visuals.
@export var seed_salt: int = 52126

@export_group("Fade")
## Storm intensity below which the cells are fully hidden.
@export_range(0.0, 1.0, 0.01) var min_intensity: float = 0.05
## Opacity change per second while following the weather intensity (smooth fade).
@export var fade_rate_per_s: float = 0.6

@export_group("Lightning")
## Shortest wait (s) before a cell's first flash after it appears.
@export var first_flash_min_s: float = 0.5
## Longest wait (s) before a cell's first flash.
@export var first_flash_max_s: float = 5.0
## Shortest gap (s) between flashes of one cell.
@export var flash_interval_min_s: float = 3.0
## Longest gap (s) between flashes of one cell.
@export var flash_interval_max_s: float = 9.0
