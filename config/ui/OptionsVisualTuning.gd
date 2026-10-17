class_name OptionsVisualTuning
extends Resource
## Stackfall Arcade look of the Options, Pause and rebinding screens,
## ). Colours and radii come from ArcadeVisualTuning; this resource only owns the
## sizes and counts that are specific to these three screens. Read by ui/menus/OptionsMenu.gd,
## ui/menus/KeyRebindRow.gd, and ui/menus/PauseMenu.gd. Not one of the F4 tuning panel's
## resource classes, so no config/ui/tuning_panel_hints.tres entry is needed.

## Thickness of the rule under a group header.
@export var group_rule_px: int = 2
## Minimum height of a binding row.
@export var binding_row_min_height_px: int = 52
## Opacity of the lightly banded (alternate) binding rows.
@export var binding_band_alpha: float = 0.55
## Width of the pause dialog.
@export var dialog_width_px: int = 340
## how far a trigger or stick must travel (0..1) before a listening
## gamepad rebind row binds it. Higher than detection noise, below a full push.
@export var rebind_axis_threshold: float = 0.6
## seconds a listening rebind row waits with no input before it cancels
## itself (B is bindable, so a pad player has no cancel button).
@export var rebind_idle_timeout_s: float = 6.0
