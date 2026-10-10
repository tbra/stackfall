class_name LoadingScreenTuning
extends Resource
## Tunables for ui/LoadingScreen.gd (Bontago-1pi.8, owner playtest 2026-09-27:
## "add a proper loading screen instead" of the idle centre-beacon camera
## shot between Start Match and the countdown).
##
## Not one of the F4 tuning panel's six resource classes (CameraTuning,
## GhostTuning, PhysicsTuning, TerritoryTuning, TerritoryVisuals,
## BlockFeedConfig -- docs/AGENT_WORKFLOW.md's "New tunables" note), so these
## exports do not need a config/tuning_panel_hints.tres entry.

## Opaque overlay color while loading -- must fully hide the 3D disk/camera
## behind it (CLAUDE.md "no magic numbers": every tunable lives in a
## Resource).
@export var background_color: Color = Color("#0e0b12")

## How long ui/LoadingScreen.gd's fade-to-transparent tween runs once it
## starts (see LoadingScreen.fade_out()'s own doc for why that start is
## itself delayed by warmup_frames below).
@export var fade_out_duration_s: float = 0.35

## Rendered frames LoadingScreen.fade_out() holds the overlay up once called,
## before starting the actual fade -- see that function's own DECISION doc.
@export var warmup_frames: int = 3

## Bontago-t8x.4: rendered frames the host holds the overlay up after Start is
## pressed, before Match.start_match() runs its synchronous world build, so the
## overlay is actually presented first.
@export var pre_start_frames: int = 2

## Bontago-t8x.4: a "pending" overlay (shown ahead of the match start) that no
## start ever follows (host left, start refused) hides itself after this long.
@export var pending_timeout_s: float = 10.0

## Maximum time to wait for the first applied territory result after world build.
@export var ready_timeout_s: float = 20.0

## Presented frames after the first result, while the new world renders covered.
@export var stable_frames: int = 4

## Bontago-1pi.125: the ready-wait auto-start cap (ready_wait_max_s) was removed; the match starts
## only when every required player is ready.

## --- Bontago-1pi.32 L2: the ready prompt and player ready list (presentation) ---
## Colours come from config/arcade_visual_tuning.tres; only sizes and wording live here.

## Bontago-1pi.63: the line above the device glyph ("Ready?" + [Enter] / [A]); the
## glyph is the bound ui_accept key/button of the player's active device
## (ui/InputGlyph.gd).
@export var ready_prompt_text: String = "Ready?"

## Appended to a bot's name in the player list (a bot is always ready).
@export var bot_suffix: String = " (bot)"

## How many bindings of the active device the prompt shows ("Press [Enter]").
@export var ready_prompt_glyph_count: int = 1

@export var ready_prompt_font_size: int = 20
@export var ready_row_font_size: int = 18

## Opacity of the prompt once the local player has pressed it (it stays visible but
## disabled while the others catch up).
@export var ready_prompt_disabled_alpha: float = 0.55

## Vertical gap inside the ready box, and between the prompt text and its glyph.
@export var ready_box_separation_px: int = 8
@export var ready_prompt_separation_px: int = 10

## Player ready list: gap between rows, between a row's cells, the colour swatch
## and the tick/ring mark (diameters), plus the tick's stroke width.
@export var ready_list_separation_px: int = 6
@export var ready_row_separation_px: int = 10

## Stackfall Arcade LoadingCard (Bontago-hfa.7): the searching-cells size and gap (ui/SearchingCells.gd), the, the mode-name size (Bungee), the name size, the card width and the
## diamond marker edge.
@export var loading_cell_width_px: int = 18
@export var loading_cell_height_px: int = 12
@export var loading_cell_gap_px: int = 4
## Bontago-1pi.158: the Ready / Not ready pill on each player row (smaller than the lobby seat's badge so
## eight rows still fit the card at 1280x720).
@export var loading_pill_width_px: int = 32
@export var loading_pill_height_px: int = 24
@export var loading_pill_margin_y_px: int = 0
@export var loading_title_font_size_px: int = 36
@export var loading_name_font_size_px: int = 18
@export var loading_card_min_width_px: int = 420
@export var loading_marker_size_px: float = 22.0

## Draw order of the overlay; above the lobby/menu controls that are still
## children of Main until the match world clears them.
@export var overlay_z_index: int = 100

## Bontago-1pi.32 L3: the overlay lives on its own CanvasLayer so it covers the HUD
## (CanvasLayer 1: player bars, held/next, minimap, timer ring, the big countdown
## digit), which a Control z_index can never beat. Above the HUD and the sandbox
## and tuning panels (1-11), below the pause menu and perf overlay (100).
@export var overlay_canvas_layer: int = 50

## Progress milestones, expressed as fractions of the complete load.
@export var preparing_progress: float = 0.02
@export var world_progress: float = 0.15
@export var flags_progress: float = 0.35
@export var territory_progress: float = 0.48
@export var players_progress: float = 0.60
@export var solve_progress: float = 0.70
@export var materials_progress: float = 0.85
@export var stabilize_start_progress: float = 0.86
@export var stabilize_end_progress: float = 0.99
@export var complete_progress: float = 1.0
@export var warm_viewport_size: Vector2i = Vector2i(128, 128)
@export var warm_camera_distance: float = 8.0
@export var warm_mesh_offset: float = 1.5

## --- Bontago-mp0.96 / 1pi.157: the loading backdrop. The image is one of the main menu's
## (MainMenuTuning.backdrop_paths, the single list), picked at random per loading screen and
## drawn cover-cropped behind the loading card.

## Seconds the plate takes to fade in when it was not already cached (it is
## loaded on a worker thread so showing the overlay never stalls). 0 = no fade.
@export var backdrop_fade_in_s: float = 0.45

## Flat darkening laid over the plate so the cream card keeps the focus. The
## alpha is the amount of dimming (0 = the plate untouched).
@export var backdrop_dim_color: Color = Color("#0e0b12", 0.32)

## Radial vignette over the plate: clear until backdrop_vignette_start (0 = the
## screen centre, 1 = the middle of each edge), then easing to this colour at
## the edges. Drawn from a small generated gradient, so it costs no shader.
@export var backdrop_vignette_color: Color = Color("#0e0b12", 0.45)
@export_range(0.0, 0.99, 0.01) var backdrop_vignette_start: float = 0.55
@export var backdrop_vignette_size_px: int = 128

