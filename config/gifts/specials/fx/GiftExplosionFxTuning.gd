class_name GiftExplosionFxTuning
extends Resource
## Presentation tunables for the Bomb/Rocket blast drawn by GiftFxPresenter on
## every peer. Loaded from config/gifts/specials/fx/gift_explosion_fx_tuning.tres. Visual-only:
## not in the F4 tuning panel, so no tuning_panel_hints entries (same as GiftBlinkTuning).
##
## The blast is a CartoonBlast: a star flash,
## a cluster of cel-shaded, outlined fireball puffs that pop in with overshoot and cool
## from yellow through orange to smoke, a ground shock ring and a few flung debris
## chunks -- over a dust flipbook that stays as a ground layer.
## Sizes marked "per blast radius" scale with the special's ExplosionTuning.radius_m.

# --- Dust flipbook layer ---------------------------------

## Puff quad size as a multiple of the blast radius (the quad spans this many radii).
@export var size_per_blast_radius: float = 0.7

## Puff opacity scale (0 invisible, 1 solid).
@export_range(0.0, 1.0, 0.01) var alpha: float = 0.8

## Puff tint multiplied into the flipbook.
@export var tint: Color = Color(0.85, 0.75, 0.62, 1.0)

## Flipbook playback speed (frames per second) and frame count of the impact atlas.
@export var fps: float = 30.0
@export var frame_count: int = 16

## Whether to use the hard (sharp) atlas rather than the soft one.
@export var hard: bool = true

# --- Cartoon blast -------------------------------------------------------------

## Seconds from detonation until the whole cartoon blast is gone.
@export var duration_s: float = 1.1

## Fireball puffs in the cluster, and each puff's radius per blast radius (+/- jitter fraction).
@export var puff_count: int = 14
@export var puff_radius_per_blast_radius: float = 0.19
@export_range(0.0, 1.0, 0.01) var puff_radius_jitter: float = 0.4
## How far (per blast radius) the puffs travel out from the centre while they pop.
@export var puff_spread_per_blast_radius: float = 0.48
## Lifts the cluster by this many puff radii so it sits on the blast point instead of in it.
@export var puff_lift_radii: float = 0.8
## Upward share of each puff's outward direction (0 flat, 1 mostly up).
@export_range(0.0, 1.0, 0.01) var puff_upward_bias: float = 0.55
## Seconds for a puff to pop to full size, and the peak scale of its overshoot.
@export var puff_pop_s: float = 0.16
@export var puff_overshoot: float = 1.3
## Extra random delay (seconds) before each puff pops, so the cluster blooms.
@export var puff_stagger_s: float = 0.07
## Rise speed (m/s) of the cooling puffs.
@export var puff_rise_mps: float = 1.6
## Fraction of duration_s at which puffs start shrinking away.
@export_range(0.0, 1.0, 0.01) var puff_shrink_start: float = 0.5
## Seconds for a puff to cool from hot to smoke.
@export var puff_cool_s: float = 0.55
## Outermost puffs start cooling this much earlier than the core, so the cluster
## reads hot in the middle and orange/smoky at its edge.
@export var puff_outer_cool_lead_s: float = 0.2

## Fireball colours: white-hot core, flame, and the smoke it cools to; the dark outline.
@export var hot_color: Color = Color(1.0, 0.93, 0.4, 1.0)
@export var fire_color: Color = Color(1.0, 0.42, 0.04, 1.0)
@export var smoke_color: Color = Color(0.32, 0.29, 0.33, 1.0)
@export var outline_color: Color = Color(0.16, 0.08, 0.05, 1.0)
## Rim outline thickness (0..1 of the silhouette fresnel).
@export_range(0.0, 1.0, 0.01) var outline_width: float = 0.3
## Extra brightness on hot puffs (pushes them into the glow).
@export var hot_glow: float = 1.1

## Star flash: size per blast radius, lifetime, spikes and colour.
@export var flash_size_per_blast_radius: float = 1.5
@export var flash_s: float = 0.16
@export var flash_points: int = 8
@export var flash_color: Color = Color(1.0, 1.0, 0.82, 1.0)

## Ground shock ring: final radius per blast radius, lifetime, band width (m) and colour.
@export var ring_radius_per_blast_radius: float = 1.2
@export var ring_s: float = 0.4
@export var ring_width_m: float = 0.6
@export var ring_color: Color = Color(1.0, 0.92, 0.65, 1.0)
## Height of the ring above the blast point, so it never z-fights the disc.
@export var ring_lift_m: float = 0.08

## Debris chunks flung out: count, size (m), launch speed (m/s) and gravity (m/s^2).
@export var debris_count: int = 8
@export var debris_size_m: float = 0.5
## Debris colour on the puff shader's heat scale (0 smoke .. 0.5 flame).
@export_range(0.0, 1.0, 0.01) var debris_tone: float = 0.3
@export var debris_speed_mps: float = 11.0
@export var debris_gravity_mps2: float = 22.0
## Debris tumble rate (radians per second).
@export var debris_spin_rps: float = 9.0
