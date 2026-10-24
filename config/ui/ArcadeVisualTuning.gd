class_name ArcadeVisualTuning
extends Resource
## Stackfall Arcade design tokens, plus the few derived recipe numbers (top/lip mix, well
## shadow...) that ui/theme/BlockStyleBox.gd and ui/theme/MenuStyleFactory.gd need. Loaded from
## config/ui/arcade_visual_tuning.tres; no UI script should carry a literal colour or size of its own.

## -- Colours --
## Deepest disc black: the solid ledge under every raised block and the countdown/pause scrims.
@export var disc_950_color: Color = Color("#0e0b12")
## Menu ground and HUD plate colour; also the ink colour for text on bright faces.
@export var disc_900_color: Color = Color("#16121c")
## Panel face: menu card, lobby columns, options, pause, results.
@export var disc_800_color: Color = Color("#1f1a26")
## Raised face inside a panel: rows, fields, dropdowns, HUD cards.
@export var disc_700_color: Color = Color("#2a2433")
## Secondary block face (Join, Options, Back) and hovered rows.
@export var disc_600_color: Color = Color("#383040")
## Secondary face on hover, empty bar tracks, locked timer ring.
@export var disc_500_color: Color = Color("#4a4154")
## Visible control edges: field, dropdown and checkbox outlines, dividers.
@export var disc_400_color: Color = Color("#6e6478")
## Primary text and numbers on any disc surface; the focus outline colour.
@export var cream_color: Color = Color("#fff6ea")
## Secondary text: setting values, descriptions, table cells.
@export var sand_color: Color = Color("#d9cbbd")
## Tertiary text: field labels, table headers, captions (13 px and up).
@export var dust_color: Color = Color("#a89aa8")
## Text and icons on a bright face (flare, rim, mint, player colours).
@export var ink_color: Color = Color("#16121c")
## The single primary action colour per screen.
@export var flare_color: Color = Color("#ff5a3d")
## Lit top edge of a flare block.
@export var flare_top_color: Color = Color("#ff9a85")
## Dark lower lip of a flare block; also its pressed face.
@export var flare_lip_color: Color = Color("#c23a22")
## The disc's gold rim accent: active tab notch, timer hurry, winner row, GO.
@export var rim_color: Color = Color("#ffc65a")
## Lower lip of a rim-gold block.
@export var rim_lip_color: Color = Color("#c9921a")
## Positive state: ready, enabled chips, connected, captured.
@export var mint_color: Color = Color("#59cc66")
## Lower lip of a mint block.
@export var mint_lip_color: Color = Color("#3c9a49")
## Negative feedback colour (rejected placement, kick, eliminated).
@export var alert_color: Color = Color("#ff5a3d")
## Timer ring and next card while the release lock holds.
@export var locked_color: Color = Color("#4a4154")
## Slot 2 player colour, equal to MatchConfig.player_colors[1].
@export var player_2_color: Color = Color("#408cf2")

## -- Spacing --
## Gap between voxel cells, share segments and chips.
@export var space_1_px: int = 4
## Icon-to-label gap; padding inside chips and keycaps.
@export var space_2_px: int = 8
## Gap between stacked block buttons (plus the drop); HUD card padding.
@export var space_3_px: int = 12
## Button horizontal padding; gap between peer controls.
@export var space_4_px: int = 16
## Panel padding; HUD inset from the screen edge at 1080p.
@export var space_5_px: int = 24
## Menu column inset from the screen edge.
@export var space_7_px: int = 48
## Gap between settings categories (UiSection stacks, e.g. the lobby's GAME / ROUND / GIFTS /
## EXPERIMENTS); the design's "gap between panel groups" (space-6).
@export var section_gap_px: int = 32
## Thickness of the hairline rule under a UiSection header (disc-700).
@export var section_rule_px: int = 2

## -- Radii --
## Voxel cell corner radius.
@export var radius_cell_px: int = 3
## Chips, keycaps, badges and toggle knob radius.
@export var radius_chip_px: int = 5
## Block buttons, fields, HUD cards and list rows radius.
@export var radius_block_px: int = 8
## Panel and dialog radius (the largest; nothing is a pill).
@export var radius_panel_px: int = 12

## -- Depth --
## Dark inner bottom edge height of a block button.
@export var lip_px: int = 6
## Lip height on compact buttons, chips, keycaps and HUD cards.
@export var lip_sm_px: int = 4
## Lit inner top edge height of a block.
@export var top_px: int = 3
## Solid ledge under a block button; the face moves down this far when pressed.
@export var drop_px: int = 6
## Ledge under compact blocks and HUD cards.
@export var drop_sm_px: int = 4
## Focus outline width.
@export var focus_px: int = 3
## How far the face colour is mixed toward white for the lit top edge.
@export var block_top_light_mix: float = 0.38
## How far the face colour is mixed toward black for the dark lower lip.
@export var block_lip_dark_mix: float = 0.3
## How far a hovered block face is mixed toward white.
@export var block_hover_light_mix: float = 0.15
## Shallow lip height of a pressed block.
@export var pressed_lip_px: int = 2
## How far the pressed block's top edge is mixed toward black.
@export var pressed_top_dark_mix: float = 0.15
## Height of the shadow along the top edge of a sunken well.
@export var well_shadow_px: int = 3
## How far a well's top shadow is mixed toward black.
@export var well_shadow_mix: float = 0.35
## Border width of fields, dropdowns and lists.
@export var well_border_px: int = 2
## Solid ledge under a floating panel.
@export var panel_drop_px: int = 8
## Opacity of the soft shadow under a floating panel.
@export var panel_shadow_alpha: float = 0.35
## Maximum icon width inside a Button.
@export var icon_max_width_px: int = 26
## Vertical padding of a block button above and below its label.
@export var button_pad_y_px: int = 8
## Vertical padding of a compact block button above and below its label.
@export var button_sm_pad_y_px: int = 5

## -- Opacity --
## Opacity of the disc-900 scrim behind menus and dialogs.
@export var scrim_alpha: float = 0.88
## Opacity of a disabled block (the ledge is removed).
@export var disabled_alpha: float = 0.45

## Font size of the score text style.
@export var font_size_score_px: int = 40
## Font size of the timer text style.
@export var font_size_timer_px: int = 34
## Font size of the heading text style.
@export var font_size_heading_px: int = 24
## Font size of the button text style.
@export var font_size_button_px: int = 20
## Font size of the button-sm text style.
@export var font_size_button_sm_px: int = 15
## Font size of the body text style.
@export var font_size_body_px: int = 16
## Font size of the label text style.
@export var font_size_label_px: int = 13
## Font size of the caption text style.
@export var font_size_caption_px: int = 13
## Disc drop under the countdown numerals.
@export var countdown_drop_px: int = 8
