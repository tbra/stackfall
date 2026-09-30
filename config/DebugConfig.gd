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
@export var overlay_background: Color = Color(0.03, 0.04, 0.06, 0.72)
@export var overlay_text_color: Color = Color(0.86, 0.95, 0.88, 1.0)
@export var overlay_warn_color: Color = Color(1.0, 0.72, 0.28, 1.0)
@export var graph_frame_color: Color = Color(0.45, 0.9, 0.55, 1.0)
@export var graph_physics_color: Color = Color(0.95, 0.65, 0.3, 1.0)
@export var graph_blocks_color: Color = Color(0.5, 0.7, 1.0, 0.9)
@export var graph_budget_color: Color = Color(1.0, 1.0, 1.0, 0.25)

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
