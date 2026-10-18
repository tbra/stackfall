class_name BalloonFxTuning
extends Resource
## Presentation tunables for the Propeller gift's party balloon (game/gifts/specials/fx/
## BalloonRig.gd, driven by PropellerStand on every peer). Loaded through
## PropellerEffect.fx (config/gifts/specials/propeller.tres). Visual-only: not in the
## F4 tuning panel. Timings that belong to the gift itself (inflate, rise, string
## length) live on PropellerEffect.

## Balloon body: radius (m) and height / width ratio (a latex balloon is a little tall).
@export var balloon_radius_m: float = 0.95
@export var balloon_height_ratio: float = 1.18

## Knot at the balloon's mouth: radius (m).
@export var knot_radius_m: float = 0.13

## String thickness (m) and the clip ring at the drop point: radius and thickness (m).
@export var string_width_m: float = 0.035
@export var clip_radius_m: float = 0.16
@export var clip_thickness_m: float = 0.05

## Scale overshoot while inflating (0.2 = peaks at 1.2x before settling to 1x).
@export_range(0.0, 1.0, 0.01) var inflate_overshoot: float = 0.2

## Sway of the risen balloon on its string: peak angle (degrees) and cycles per second.
@export var sway_deg: float = 7.0
@export var sway_hz: float = 0.6

## Specular highlight blob: offset (fraction of the radius) and size (fraction).
@export var highlight_offset: Vector3 = Vector3(-0.38, 0.42, 0.62)
@export_range(0.0, 1.0, 0.01) var highlight_size: float = 0.17

## Colours: team colour used when the owner slot is unknown, the string, the clip and the
## highlight.
@export var fallback_color: Color = Color(0.92, 0.36, 0.33, 1.0)
@export var string_color: Color = Color(0.96, 0.92, 0.84, 1.0)
@export var clip_color: Color = Color(0.20, 0.22, 0.26, 1.0)
@export var highlight_color: Color = Color(1.0, 1.0, 1.0, 1.0)

## POP: confetti shard count, edge (m), launch speed (m/s), gravity (m/s^2) and life (s).
@export var confetti_count: int = 30
@export var confetti_size_m: float = 0.22
@export var confetti_speed_mps: float = 5.0
@export var confetti_gravity_mps2: float = 7.0
@export var confetti_life_s: float = 1.2
## Fraction of the shards in the team colour; the rest alternate white / yellow.
@export_range(0.0, 1.0, 0.01) var confetti_team_share: float = 0.5
@export var confetti_white: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var confetti_yellow: Color = Color(1.0, 0.85, 0.25, 1.0)

## The limp rag after the pop: size (fraction of the balloon radius) and seconds it takes
## to fall down its string to the clip.
@export_range(0.05, 1.0, 0.01) var rag_size: float = 0.4
@export var rag_fall_s: float = 0.9
