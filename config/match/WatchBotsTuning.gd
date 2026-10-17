class_name WatchBotsTuning
extends Resource
## Tunables of the debug "Watch bots" match (game/player/SpectatorController.gd,
## game/main/WatchBotsOptions.gd, ui/menus/WatchBotsDialog.gd). Debug-only, not shown
## in the F4 tuning panel, so no config/ui/tuning_panel_hints.tres entries are needed.

## Bot count limits of the picker and of `--watch-bots=<n>`.
@export var min_bots: int = 2
@export var max_bots: int = 8
## Bots when nothing was saved yet.
@export var default_bots: int = 4
## Engine.time_scale steps the speed key cycles through (first = normal speed).
@export var speeds: PackedFloat32Array = PackedFloat32Array([1.0, 2.0, 4.0])
## Where the overview camera sits: this many field radii out, at this pitch.
@export var overview_distance_factor: float = 1.6
@export var overview_pitch_deg: float = -50.0
## Follow camera: distance, pitch and how fast it eases onto the followed bot's piece (1/s).
@export var follow_distance_m: float = 14.0
@export var follow_pitch_deg: float = -35.0
@export var follow_ease_per_s: float = 6.0
## Free camera pan speed, as metres per second per metre of camera distance.
@export var pan_speed_per_distance: float = 1.2
## Zoom: metres per wheel notch, metres per second at full LT + stick.
@export var wheel_zoom_step_m: float = 2.0
@export var pad_zoom_speed_mps: float = 24.0
## Stick dead-zone for the spectator pan / zoom (axis strength).
@export var stick_deadzone: float = 0.15
## Corner labels (speed, followed bot).
@export var label_font_size: int = 22
@export var hint_font_size: int = 16
@export var label_outline_px: int = 5
## Opacity of the controls hint row, and the CanvasLayer the labels sit on.
@export_range(0.0, 1.0, 0.05) var hint_alpha: float = 0.75
@export var canvas_layer: int = 20
@export var label_margin_px: int = 16
## Extra top margin of the speed label (it sits under the round timer, top right).
@export var speed_label_top_px: int = 80
## Where the followed bot's tower sits relative to its tallest height (0 = base, 1 = top).
@export var tower_focus_fraction: float = 0.5
## How much the followed bot's colour is lightened for the name label (readable over its own territory).
@export_range(0.0, 1.0, 0.05) var follow_label_lighten: float = 0.55
