class_name GiftBlinkTuning
extends Resource
## Presentation tunables for GiftBlink's warning flash (Bomb). Loaded from
## config/specials/fx/gift_blink_tuning.tres. Visual-only: not part of the F4 tuning
## panel (ui/TuningPanel.gd lists its resources explicitly), so no
## config/tuning_panel_hints.tres entries are needed, same as HoleVisualTuning.
## The blink timing itself (period and duration) lives on the gift's own effect.

## Overlay colour of the flash on the gift model.
@export var flash_color: Color = Color(1.0, 0.25, 0.1)

## Overlay opacity at the brightest point of a flash (0 invisible, 1 solid).
@export_range(0.0, 1.0, 0.01) var flash_max_alpha: float = 0.55

## Final blink period as a share of the starting period: the blink accelerates from
## period_s to period_s * this ratio over the blink duration (plan: 0.25 s to 0.1 s).
@export_range(0.05, 1.0, 0.01) var end_period_ratio: float = 0.4
