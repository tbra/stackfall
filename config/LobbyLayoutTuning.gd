class_name LobbyLayoutTuning
extends Resource
## Layout tunables for the lobby rework (Bontago-1pi.53, docs/LOBBY_REWORK_PLAN.md,
## D9): sizes and spacings that are new to the rework live here, so
## config/menu_visual_tuning.tres (colours, pill shapes) is never touched. Read by
## ui/Lobby.gd and ui/lobby/LobbyPlayersPanel.gd.
##
## Not one of the F4 tuning panel's six resource classes (CameraTuning,
## GhostTuning, PhysicsTuning, TerritoryTuning, TerritoryVisuals,
## BlockFeedConfig -- same note as config/LoadingScreenTuning.gd), so these
## exports do not need a config/tuning_panel_hints.tres entry.
##
## E1 (the lobby extraction) keeps today's look: every default below equals the
## literal it replaced, so moving the roster rows into LobbyPlayersPanel changes
## no pixel. The section/advanced fields are consumed by the S1 packages.

## Vertical gap between two LobbySection blocks in the settings column (S1a).
@export var section_spacing_px: int = 10

## Left indent of an Advanced block under its section header (S1b).
@export var advanced_indent_px: int = 12

## Width of the label column every settings row shares (Bontago-1pi.61), in px.
@export var label_column_width_px: int = 150

## Width of the value column (slider readout chip / value label) every row shares.
@export var value_column_width_px: int = 64

## Horizontal gap between the cells of one settings row.
@export var row_separation_px: int = 12

## Vertical gap between settings rows (and between checklist rows).
@export var row_spacing_px: int = 8

## Edge of a seat row's colour box, in px (width, height). Replaces the 24 x 24
## clay-cube icon the roster rows drew before the rework.
@export var color_box_size_px: Vector2 = Vector2(24.0, 24.0)

## Corner radius of the colour box.
@export var color_box_corner_radius_px: int = 6

## Smallest height of a seat row, in px. 0 = natural content height (today's
## look); the seat-row package raises it once rows carry buttons.
@export var seat_row_min_height_px: int = 0

## Gap between the controls of one seat row (colour box, name column, badge).
@export var seat_row_separation_px: int = 10

## Gap between a seat's name and its subtitle line.
@export var seat_text_separation_px: int = 0

## Font size of a seat's name.
@export var seat_name_font_size: int = 16

## Seat-row controls (PL1a, ui/lobby/LobbySeatRow.gd). Smallest size of the team
## number button (visible with teams on): width, height in px.
@export var seat_team_button_min_size_px: Vector2 = Vector2(36.0, 28.0)

## Smallest width of a bot's difficulty dropdown, in px.
@export var seat_difficulty_min_width_px: int = 96

## Smallest size of a bot row's remove ("x") button: width, height in px.
@export var seat_remove_button_min_size_px: Vector2 = Vector2(28.0, 28.0)

## Width of the focus ring drawn round the colour box while it holds gamepad/keyboard
## focus, in px (the box is a flat colour, so the shared theme's ring would vanish
## into it).
@export var seat_color_focus_border_px: int = 3
