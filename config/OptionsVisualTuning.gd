class_name OptionsVisualTuning
extends Resource
## Stackfall Arcade look of the Options, Pause and rebinding screens (docs/UI_RESKIN_PLAN.md P2,
## Bontago-hfa.4). Colours and radii come from ArcadeVisualTuning; this resource only owns the
## sizes and counts that are specific to these three screens. Read by ui/OptionsMenu.gd,
## ui/KeyRebindRow.gd, and ui/PauseMenu.gd. Not one of the F4 tuning panel's
## resource classes, so no config/tuning_panel_hints.tres entry is needed.

## Thickness of the rule under a group header.
@export var group_rule_px: int = 2
## Minimum height of a binding row.
@export var binding_row_min_height_px: int = 52
## Opacity of the lightly banded (alternate) binding rows.
@export var binding_band_alpha: float = 0.55
## Width of the pause dialog.
@export var dialog_width_px: int = 340
