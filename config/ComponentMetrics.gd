class_name ComponentMetrics
extends Resource
## Sizes shared by every ui/components/ component (Bontago-1pi.159.4, docs/UI_COMPONENTS_PLAN.md
## section 3.1). Colours, radii, lips and the spacing scale (space-1..7) stay in
## config/arcade_visual_tuning.tres (the design tokens); this resource only holds the sizes that
## the tokens do not name. Not an F4 tuning-panel class (no tuning_panel_hints entry needed).

## The one height of every row item (button, icon button, toggle, stepper, dropdown, badge,
## meter). Replaces LobbyLayoutTuning.row_control_height_px (36) and seat_control_height_px (32).
@export var row_height_px: int = 36
## Width of the label column of a UiRow.
@export var row_label_width_px: int = 180
## Minimum width of a UiRow's optional value cell (the readout right of the control).
@export var row_value_cell_width_px: int = 72

## Minimum width of a text status badge.
@export var badge_min_width_px: int = 56
## Minimum width of an icon-only status badge (the ready tile).
@export var badge_icon_only_min_width_px: int = 36
## Diameter of the live dot in a status badge.
@export var badge_dot_px: int = 8

## Widths per kind; a stepper is `stepper_width_units` row heights wide.
@export var stepper_width_units: int = 4
@export var toggle_min_width_px: int = 96
@export var dropdown_min_width_px: int = 160
@export var meter_min_width_px: int = 200
## Minimum width of a small block button (a label always grows it further).
@export var button_sm_min_width_px: int = 64

## Font size of the glyph (the default X) inside an icon button; the block's top, lip and ledge
## plus this line must still fit row_height_px.
@export var icon_glyph_font_px: int = 16

## Toggle (Bontago-1pi.159.5): the sunken well the knob slides in (width x height), the gap
## between well edge and knob.
@export var toggle_well_width_px: int = 52
@export var toggle_well_height_px: int = 26
@export var toggle_knob_inset_px: int = 3

## ChipToggle: edge of the check box drawn left of the label and the stroke of its tick.
@export var chip_box_px: int = 18
@export var chip_check_stroke_px: int = 3

## Stepper: font size of the Bungee value between the - and + blocks.
@export var stepper_value_font_px: int = 16

## Tabs: height of one tab (the active tab's rim notch sits inside it) and the notch thickness.
@export var tab_height_px: int = 40
@export var tab_notch_px: int = 4
