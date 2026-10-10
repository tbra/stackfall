class_name OptionsVisualTuning
extends Resource
## Stackfall Arcade look of the Options, Pause and rebinding screens (docs/UI_RESKIN_PLAN.md P2,
## Bontago-hfa.4). Colours and radii come from ArcadeVisualTuning; this resource only owns the
## sizes and counts that are specific to these three screens. Read by ui/OptionsMenu.gd,
## ui/KeyRebindRow.gd, ui/PauseMenu.gd and ui/SegmentMeter.gd. Not one of the F4 tuning panel's
## resource classes, so no config/tuning_panel_hints.tres entry is needed.

## Cells in a SegmentMeter (never fewer than 5, design system default 10).
@export var segment_count: int = 10
## Height of a SegmentMeter well in px.
@export var meter_height_px: int = 28
## Width reserved for the Bungee value to the right of a meter or toggle.
@export var value_min_width_px: int = 84
## Font size of a Bungee value (percentages, ON/OFF).
@export var value_font_size_px: int = 20
## Width of the side tab column.
@export var tab_column_width_px: int = 200
## Minimum height of a side tab.
@export var tab_min_height_px: int = 48
## Width of the rim notch on the active side tab.
@export var tab_notch_px: int = 4
## Thickness of the rule under a group header.
@export var group_rule_px: int = 2
## Edge length of the flare voxel bullet before a panel heading.
@export var heading_bullet_px: int = 14
## Minimum height of a binding row.
@export var binding_row_min_height_px: int = 52
## Opacity of the lightly banded (alternate) binding rows.
@export var binding_band_alpha: float = 0.55
## Width of the pause dialog.
@export var dialog_width_px: int = 340
## Width of the toggle ON/OFF word.
@export var state_word_min_width_px: int = 40
