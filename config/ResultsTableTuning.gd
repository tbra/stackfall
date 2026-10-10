class_name ResultsTableTuning
extends Resource
## Stackfall Arcade results table / scoreboard overlay / loading card numbers (docs/UI_RESKIN_PLAN.md
## P5, Bontago-hfa.7). Colours and radii come from ArcadeVisualTuning; this holds only the sizes and
## mixes specific to ui/ScoreTable.gd, ui/ResultsScreen.gd and ui/ScoreboardOverlay.gd
## (the loading card's own sizes live in config/LoadingScreenTuning.gd).

## How far a winner row's disc-700 face is mixed toward rim gold.
@export_range(0.0, 1.0, 0.01) var winner_tint_mix: float = 0.2
## Width of the rim edge on the left of a winner row (the lip-sm token's 4 px).
@export var winner_edge_px: int = 4
## Vertical padding inside a table row.
@export var row_pad_y_px: int = 6
## Horizontal padding inside a table row.
@export var row_pad_x_px: int = 12
## Gap between table rows.
@export var row_gap_px: int = 4
## Gap between the diamond marker and the player name.
@export var marker_gap_px: int = 8
## Edge length of the diamond marker in a table row.
@export var marker_size_px: float = 20.0
## Font size of the results banner (Bungee).
@export var banner_font_size_px: int = 48
## Font size of the mode kicker above the banner.
@export var kicker_font_size_px: int = 16
## Letter spacing of the kicker in px.
@export var kicker_spacing_px: int = 2
## Font size of the mode score line under the banner.
@export var outcome_font_size_px: int = 16
## Font size of Bungee numbers inside table rows.
@export var number_font_size_px: int = 15
## Opacity of the scrim behind the held scoreboard overlay (the results screen uses scrim_alpha).
@export_range(0.0, 1.0, 0.01) var overlay_scrim_alpha: float = 0.6
## Vertical gap between the card's blocks.
@export var card_gap_px: int = 14
