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
@export var background_color: Color = Color(0.06, 0.07, 0.09, 1.0)

## How long ui/LoadingScreen.gd's fade-to-transparent tween runs once it
## starts (see LoadingScreen.fade_out()'s own doc for why that start is
## itself delayed by warmup_frames below).
@export var fade_out_duration_s: float = 0.35

## Seconds between one "Loading." / "Loading.." / "Loading..." frame and the
## next.
@export var spinner_interval_s: float = 0.35

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

## Bontago-1pi.32 (owner playtest 2026-10-03): the loading screen is shown for at
## least this long, even when the world is built sooner. Enforced by the host's
## ready gate (core/LoadingReadyGate.gd), measured from LOADING, and locally by
## ui/LoadingScreen.gd's fade-out so every instance displays it that long.
@export var min_display_s: float = 5.0

## Bontago-1pi.32 safety cap on the wait for every human player to press ready.
## Measured from LOADING (asset loading still has its own ready_timeout_s above);
## once it passes the host starts the countdown anyway. # DECISION: an AFK or
## frozen player must not block everyone forever.
@export var ready_wait_max_s: float = 60.0

## --- Bontago-1pi.32 L2: the ready prompt and player ready list (presentation) ---
## Colours reuse config/menu_visual_tuning.tres (ink, muted, mint) so the overlay
## stays on the menu palette; only sizes and wording live here.

## Subtle line shown while the minimum display time remains (or this instance is
## still loading).
@export var get_ready_text: String = "Get ready..."

## "<prefix> [glyph] <suffix>" -- the glyph is the bound ui_accept key/button of
## the player's active device (ui/InputGlyph.gd).
@export var ready_prompt_prefix: String = "Press"
@export var ready_prompt_suffix: String = "to ready"

## After the local press: how many required players have not pressed yet. %d is
## that count; one text per grammatical number.
@export var waiting_one_text: String = "Waiting for %d player..."
@export var waiting_many_text: String = "Waiting for %d players..."

## Safety-cap countdown while the host would start without a laggard; %d is whole
## seconds left (rounded up).
@export var cap_countdown_format: String = "Starting in %ds"

## Appended to a bot's name in the player list (a bot is always ready).
@export var bot_suffix: String = " (bot)"

## How many bindings of the active device the prompt shows ("Press [Enter]").
@export var ready_prompt_glyph_count: int = 1

@export var ready_prompt_font_size: int = 20
@export var ready_status_font_size: int = 16
@export var ready_cap_font_size: int = 14
@export var ready_row_font_size: int = 18

## Opacity of the prompt once the local player has pressed it (it stays visible but
## disabled while the others catch up).
@export var ready_prompt_disabled_alpha: float = 0.55

## Vertical gap between the ready box's status line, prompt and cap countdown, and
## the horizontal gap inside the prompt (prefix, glyph, suffix).
@export var ready_box_separation_px: int = 8
@export var ready_prompt_separation_px: int = 10

## Space reserved for the ready box (status + prompt + cap line) once the gate is
## armed, so the card does not jump when the prompt appears.
@export var ready_box_min_height_px: float = 128.0

## Player ready list: gap between rows, between a row's cells, the colour swatch
## and the tick/ring mark (diameters), plus the tick's stroke width.
@export var ready_list_separation_px: int = 6
@export var ready_row_separation_px: int = 10
@export var ready_swatch_size_px: float = 16.0
@export var ready_mark_size_px: float = 22.0
@export var ready_mark_stroke_px: float = 2.5
@export var ready_mark_arc_points: int = 24

## Draw order of the overlay; above the lobby/menu controls that are still
## children of Main until the match world clears them.
@export var overlay_z_index: int = 100

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
