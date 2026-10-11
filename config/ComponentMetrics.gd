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
## Dropdown: no minimum width (it hugs its widest item); edge of the per-item icon in the block.
@export var dropdown_icon_px: int = 20
@export var meter_min_width_px: int = 200
## SegmentMeter: width of one cell. The meter's width follows the cell count (never the layout).
@export var meter_cell_width_px: int = 16
## Minimum width of a small block button (a label always grows it further).
@export var button_sm_min_width_px: int = 64

## Font size of the glyph (the default X) inside an icon button; the block's top, lip and ledge
## plus this line must still fit row_height_px.
@export var icon_glyph_font_px: int = 16

## Toggle (Bontago-1pi.159.5): the sunken well's height and the gap between well edge and knob. The
## knob is a square block, so the well's width follows (2 knobs and 3 gaps; owner 2026-10-11).
@export var toggle_well_height_px: int = 26
@export var toggle_knob_inset_px: int = 3

## ChipToggle: edge of the check box drawn left of the label and the stroke of its tick.
@export var chip_box_px: int = 18
@export var chip_check_stroke_px: int = 3

## Stepper: font size of the Bungee value between the - and + blocks.
@export var stepper_value_font_px: int = 16

## Cycler: clear space between the value area and each arrow block (both sides of the widest item),
## and the edge of the optional per-item icon drawn left of the text.
@export var cycler_value_padding_px: int = 10
@export var cycler_icon_px: int = 20

## Tabs: height of one tab (the active tab's rim notch sits inside it) and the notch thickness.
@export var tab_height_px: int = 40
@export var tab_notch_px: int = 4

## Disclosure arrow of UiSection's Advanced bar: edge of its (square) box.
@export var disclosure_arrow_px: int = 10

## Icon-only status badge marks (tick / hourglass): the same square box and stroke for both.
@export var status_icon_px: int = 14
@export var status_icon_stroke_px: int = 3

## UiText (Bontago-1pi.159.11 C4a): size of the VALUE role (a Bungee readout in a row or a card;
## the other roles take their sizes from the ArcadeVisualTuning type styles) and the outline every
## role draws (0: the design's text has no outline; this also cancels a theme outline).
@export var text_value_font_px: int = 16
@export var text_outline_px: int = 0
