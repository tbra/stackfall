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
## Colours reuse config/menu_visual_tuning.tres (ink, muted, mint) so the overlay
## stays on the menu palette; only sizes and wording live here.

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
@export var ready_swatch_size_px: float = 16.0
@export var ready_mark_size_px: float = 22.0
@export var ready_mark_stroke_px: float = 2.5
@export var ready_mark_arc_points: int = 24

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

## --- Bontago-mp0.96: prerendered arena backdrop (owner playtest 2026-10-03:
## "the next step would be to have a prerendered background of the arena") ---
## One plate per arena shape and sky theme: assets/ui/loading_arena_v2/
## <shape>_<theme>.png, 1920x1080, drawn cover-cropped behind the loading card.
## Map sizes share a plate (the art illustrates the shape, not the size).

## Folder holding the plates (Bontago-mp0.99, the round shape x sunset/night/dawn).
@export var backdrop_dir: String = "res://assets/ui/loading_arena_v2"

## Plate file name: %s are the shape id and the sky theme id, in that order.
@export var backdrop_file_format: String = "%s_%s.png"

## Optional shape id override per MatchConfig.MapVariant (index = enum value).
## Empty (default) derives the ids from MapDef.shape_id(); with an override, a
## variant outside the list uses backdrop_fallback_shape.
@export var backdrop_shape_ids: PackedStringArray = []

## Used when the match's variant or sky theme has no plate (unknown id, or the
## file is missing). A missing fallback plate too leaves the plain background.
@export var backdrop_fallback_shape: String = "round"
@export var backdrop_fallback_theme: String = "sunset"

## A running day/night cycle has no theme id of its own: the plate nearest (on
## the cycle ring) to this theme's cycle_start_phase is shown. The theme is
## where SkyThemeDef.cycle_start_phase / locked_phase_for() live (Skybox's
## DEFAULT_THEME_ID).
@export var backdrop_cycle_theme_path: String = "res://config/sky_themes/sunset.tres"

## Seconds the plate takes to fade in when it was not already cached (it is
## loaded on a worker thread so showing the overlay never stalls). 0 = no fade.
@export var backdrop_fade_in_s: float = 0.45

## Flat darkening laid over the plate so the cream card keeps the focus. The
## alpha is the amount of dimming (0 = the plate untouched).
@export var backdrop_dim_color: Color = Color(0.06, 0.07, 0.09, 0.32)

## Radial vignette over the plate: clear until backdrop_vignette_start (0 = the
## screen centre, 1 = the middle of each edge), then easing to this colour at
## the edges. Drawn from a small generated gradient, so it costs no shader.
@export var backdrop_vignette_color: Color = Color(0.02, 0.03, 0.05, 0.45)
@export_range(0.0, 0.99, 0.01) var backdrop_vignette_start: float = 0.55
@export var backdrop_vignette_size_px: int = 128


## The plate path for a map variant and sky theme id, with no filesystem check
## (the screen verifies it exists). An unknown variant or theme maps to the
## fallback shape / theme.
func backdrop_path(variant: int, theme_id: String) -> String:
	var shape_id: String = backdrop_fallback_shape
	if backdrop_shape_ids.is_empty():
		if not MapDef.shape_id(variant).is_empty():
			shape_id = MapDef.shape_id(variant)
	elif variant >= 0 and variant < backdrop_shape_ids.size():
		shape_id = backdrop_shape_ids[variant]
	var theme: String = theme_id if MatchConfig.SKY_THEME_IDS.has(theme_id) else backdrop_fallback_theme
	return "%s/%s" % [backdrop_dir, backdrop_file_format % [shape_id, theme]]


## The default plate (fallback shape, fallback theme).
func backdrop_fallback_path() -> String:
	return "%s/%s" % [backdrop_dir, backdrop_file_format % [backdrop_fallback_shape, backdrop_fallback_theme]]


## The concrete sky theme id whose locked phase is closest, around the cycle
## ring, to `phase` (a running cycle's opening phase). "" if the theme is null.
func backdrop_theme_for_phase(phase: float, sky_theme: SkyThemeDef) -> String:
	if sky_theme == null:
		return ""
	var best_id: String = ""
	var best_distance: float = INF
	for theme_id: String in MatchConfig.SKY_THEME_IDS:
		var locked: float = sky_theme.locked_phase_for(theme_id)
		if locked < 0.0:
			continue
		var gap: float = absf(fposmod(phase - locked, 1.0))
		var distance: float = minf(gap, 1.0 - gap)
		if distance < best_distance:
			best_distance = distance
			best_id = theme_id
	return best_id
