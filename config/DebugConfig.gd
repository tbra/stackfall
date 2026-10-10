class_name DebugConfig
extends Resource
## Tunables for debug mode (Bontago-470.8): the debug-mode gate itself
## (game/DebugMode.gd), the F1 performance overlay (ui/PerfOverlay.gd), its
## sampler (game/PerfSampler.gd) and the per-session CSV logger
## (game/PerfLogger.gd). Nothing here touches match rules.
##
## Not shown in the F4 tuning panel (debug-only, not a gameplay tunable), so no
## config/tuning_panel_hints.tres entries are needed.

## When true, debug mode is on whenever OS.has_feature("editor") is true. That
## is every run of a standard (non-export) Godot binary: F5 from the editor and
## `godot --path .` alike. Set false to test the player-facing build locally
## (or pass `-- --no-debug`).
@export var auto_enable_in_editor: bool = true

## Window (seconds) each PerfSampler snapshot averages over. The overlay text,
## the CSV rows and every mean/worst figure cover this same window, so fps,
## frame ms and physics ms are mutually consistent. (Godot's own FPS monitor is
## a separate 1 s average and is not used.)
@export_range(0.1, 10.0, 0.1) var stats_window_s: float = 1.0

## Seconds per graph point (worst frame / worst physics tick in the bucket).
@export_range(0.02, 1.0, 0.01) var graph_interval_s: float = 0.1

## Seconds of history the overlay graphs show.
@export_range(2.0, 60.0, 1.0) var graph_window_s: float = 10.0

## Graph ceilings (ms / blocks). Values above are clamped to the top edge.
@export var graph_frame_ms_max: float = 33.4
@export var graph_physics_ms_max: float = 16.7
@export var graph_blocks_max: float = 400.0

## Frame time (ms) that draws the graph's reference line (60 fps budget).
@export var graph_budget_ms: float = 16.7

@export var graph_size: Vector2 = Vector2(260.0, 48.0)

## Overlay layout.
@export var overlay_margin: Vector2 = Vector2(12.0, 12.0)
@export var overlay_font_size: int = 13
## Overlay colours (Bontago-hfa.10): by default sourced from the ArcadeVisualTuning tokens so the
## dev overlay follows the Stackfall Arcade palette. Each *_override colour with alpha > 0 replaces
## its token (owner-tunable); leave it fully transparent to follow the token. Read them through the
## *_color() getters below, never the raw overrides.
@export var overlay_background_override: Color = Color(0.0, 0.0, 0.0, 0.0)
@export var overlay_text_override: Color = Color(0.0, 0.0, 0.0, 0.0)
@export var overlay_warn_override: Color = Color(0.0, 0.0, 0.0, 0.0)
@export var graph_frame_override: Color = Color(0.0, 0.0, 0.0, 0.0)
@export var graph_physics_override: Color = Color(0.0, 0.0, 0.0, 0.0)
@export var graph_blocks_override: Color = Color(0.0, 0.0, 0.0, 0.0)
@export var graph_budget_override: Color = Color(0.0, 0.0, 0.0, 0.0)

## Alpha applied to the token colours that sit over the scene or under the graph lines.
@export_range(0.0, 1.0, 0.01) var overlay_background_alpha: float = 0.72
@export_range(0.0, 1.0, 0.01) var graph_blocks_alpha: float = 0.9
@export_range(0.0, 1.0, 0.01) var graph_budget_alpha: float = 0.25


func overlay_background_color() -> Color:
	return _resolve(overlay_background_override, _arcade().disc_950_color, overlay_background_alpha)


func overlay_text_color() -> Color:
	return _resolve(overlay_text_override, _arcade().cream_color, 1.0)


func overlay_warn_color() -> Color:
	return _resolve(overlay_warn_override, _arcade().rim_color, 1.0)


func graph_frame_color() -> Color:
	return _resolve(graph_frame_override, _arcade().mint_color, 1.0)


func graph_physics_color() -> Color:
	return _resolve(graph_physics_override, _arcade().flare_top_color, 1.0)


func graph_blocks_color() -> Color:
	return _resolve(graph_blocks_override, _arcade().player_2_color, graph_blocks_alpha)


func graph_budget_color() -> Color:
	return _resolve(graph_budget_override, _arcade().cream_color, graph_budget_alpha)


## DECISION (Bontago-hfa.10): config/ must not depend on ui/, so this loads the same
## config/arcade_visual_tuning.tres MenuStyleFactory.arcade_tuning() loads, directly.
const ARCADE_TUNING_PATH: String = "res://config/arcade_visual_tuning.tres"
static var _arcade_cache: ArcadeVisualTuning = null


static func _arcade() -> ArcadeVisualTuning:
	if _arcade_cache == null:
		_arcade_cache = load(ARCADE_TUNING_PATH) as ArcadeVisualTuning
	return _arcade_cache


static func _resolve(override: Color, token: Color, token_alpha: float) -> Color:
	if override.a > 0.0:
		return override
	return Color(token.r, token.g, token.b, token_alpha)

## Frame ms at or above which the overlay tints the frame line as a warning.
@export var warn_frame_ms: float = 20.0

## PerfLogger: one row every `log_interval_s`, flushed every
## `log_flush_every_rows` rows, keeping the newest `log_keep_files` files in
## `log_dir`.
@export var log_enabled: bool = true
@export_range(0.1, 60.0, 0.1) var log_interval_s: float = 1.0
@export_range(1, 600, 1) var log_flush_every_rows: int = 5
@export_range(1, 200, 1) var log_keep_files: int = 20
@export var log_dir: String = "user://perf_logs"
