class_name LobbyLayoutTuning
extends Resource
## Layout tunables for the lobby: sizes and spacings live here, so
## config/ui/menu_visual_tuning.tres (colours, pill shapes) is never touched. Read by
## ui/lobby/Lobby.gd and ui/lobby/LobbyPlayersPanel.gd.
##
## Not one of the F4 tuning panel's six resource classes (CameraTuning,
## GhostTuning, PhysicsTuning, TerritoryTuning, TerritoryVisuals,
## BlockFeedConfig -- same note as config/ui/LoadingScreenTuning.gd), so these
## exports do not need a config/ui/tuning_panel_hints.tres entry.
##
## E1 (the lobby extraction) keeps today's look: every default below equals the
## literal it replaced, so moving the roster rows into LobbyPlayersPanel changes
## no pixel. The section/advanced fields are consumed by the S1 packages.


## Left indent of an Advanced block under its section header (S1b).
@export var advanced_indent_px: int = 12






## smallest width of the Players card, so a full seat row (colour box, name,
## difficulty, remove, badge) never clips on the 960x540 mockup-scale canvas; the settings column
## takes what is left.
@export var players_card_min_width_px: int = 384

## Edge of a seat row's colour box, in px (width, height). Replaces the 24 x 24
## clay-cube icon the roster rows drew before the rework.
@export var color_box_size_px: Vector2 = Vector2(24.0, 24.0)

## Corner radius of the colour box.
@export var color_box_corner_radius_px: int = 6

## Smallest height of a seat row, in px. 0 = natural content height (today's
## look); the seat-row package raises it once rows carry buttons.
@export var seat_row_min_height_px: int = 0

## Gap between a seat's name and its subtitle line.
@export var seat_text_separation_px: int = 0

## Font size of a seat's name.
@export var seat_name_font_size: int = 16

## Widest a seat name may force its row to be (logical px, scaled by the one UI scale
## rule): a short name is never clipped, a longer one ends in an ellipsis.
@export var seat_name_max_width_px: int = 180

## Seat-row controls (PL1a, ui/lobby/LobbySeatRow.gd). Smallest size of the team
## number button (visible with teams on): width, height in px.
@export var seat_team_button_min_size_px: Vector2 = Vector2(40.0, 32.0)

## Smallest width of a bot's difficulty dropdown, in px.
@export var seat_difficulty_min_width_px: int = 108

## Width of the focus ring drawn round the colour box while it holds gamepad/keyboard
## focus, in px (the box is a flat colour, so the shared theme's ring would vanish
## into it).
@export var seat_color_focus_border_px: int = 3

## Open-seat row (ui/lobby/LobbyOpenSeatRow.gd): dash length, gap and line width of its
## dashed outline, and how far the next-free-colour diamond is dimmed (alpha).
@export var open_seat_dash_px: int = 8
@export var open_seat_gap_px: int = 6
@export var open_seat_border_px: int = 2
@export_range(0.0, 1.0, 0.05) var open_seat_diamond_alpha: float = 0.45

## Players-row looks (ui/lobby/LobbySeatRow.gd). Colour of team 1..4 on the team blocks, the board's lane caps and
## fields (the pick wraps past the end); Random keeps the neutral block.
@export var seat_team_colors: PackedColorArray = PackedColorArray([
	Color("#ff7a59"), Color("#4aa8ff"), Color("#5fd38a"), Color("#c08cff"),
])
## Roster tiles: grid columns, the hero marker's edge in px and how much of the player's colour washes the tile.
@export var seat_tile_columns: int = 4
@export var seat_tile_marker_px: int = 48
@export_range(0.0, 1.0, 0.01) var seat_tile_tint_mix: float = 0.22
## Versus board: lanes side by side, and how much of the team colour tints a lane's field.
@export var seat_board_columns: int = 2
@export_range(0.0, 1.0, 0.01) var seat_board_lane_tint_mix: float = 0.14
