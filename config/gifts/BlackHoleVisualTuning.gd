class_name BlackHoleVisualTuning
extends Resource
## Presentation tunables for the black hole vortex (Bontago-8or.26). Presentation
## only; the pull radius and lifetime come from BlackHoleEffect.

## Seconds the vortex takes to grow from grow_start_fraction to full size after the
## special triggers (Bontago-1pi.85.56). The pull and capture radius follow the same
## curve (BlackHoleField), so what you see is what pulls.
@export var grow_in_s: float = 1.5

## Size fraction (0..1) the hole spawns at.
@export_range(0.0, 1.0) var grow_start_fraction: float = 0.1

## Ease-in exponent: size = start + (1 - start) * t^power. 1 is linear, above 1 starts
## slowly and accelerates.
@export var grow_ease_power: float = 2.0

## Seconds the vortex collapses out before its lifetime ends.
@export var collapse_out_s: float = 0.6

## Depth (m) below the surface the core starts at; it rises to the surface over
## grow_in_s so the hole "opens up underneath" the drop point (Bontago-1pi.85.45).
@export var core_emerge_depth_m: float = 0.7

## Height (m) of the vortex disc above the trigger point, to avoid z-fighting.
@export var disc_lift_m: float = 0.08

## Core radius as a fraction of the disc radius in the shader.
@export_range(0.0, 1.0) var core_fraction: float = 0.16

## Inner and outer edge of the accretion ring as fractions of the disc radius.
@export_range(0.0, 1.0) var ring_inner: float = 0.16
@export_range(0.0, 1.0) var ring_outer: float = 0.7

## Spiral arm count and twist (radians of curl from the ring's inner to outer edge).
@export var arm_count_high: float = 4.0
@export var arm_count_low: float = 2.0
@export var arm_twist: float = 5.0

## Spin speed of the arms (radians per second).
@export var spin_speed: float = 1.6

## Inward streaks outside the ring: count around the circle, radial density and speed.
@export var streak_count: float = 14.0
@export var streak_density: float = 7.0
@export var streak_speed: float = 0.8
@export var streak_width: float = 0.12
@export_range(0.0, 1.0) var streak_alpha: float = 0.5

## Dash threshold and fade start for streak appearance.
@export var dash_threshold: float = 0.35
@export var streak_fade_start: float = 0.8

## Number of flat cel steps the alpha is quantised to.
@export var cel_steps: float = 3.0

@export var core_color: Color = Color(0.02, 0.0, 0.05, 1.0)
@export var ring_color_a: Color = Color(0.62, 0.25, 0.95, 1.0)
@export var ring_color_b: Color = Color(0.95, 0.55, 0.25, 1.0)
@export var streak_color: Color = Color(0.75, 0.6, 1.0, 1.0)
