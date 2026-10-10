class_name UiScaleTuning
extends Resource
## Bontago-1pi.150: the player-facing UI scale (Options > Settings > Display). The stored setting is
## RELATIVE: 1.0 (100%) is base_scale times the project stretch (1280x720 base). Applied by autoload/Settings.gd as
## Window.content_scale_factor on the root window; the pure rules (sanitize, effective factor)
## are statics here so Settings (autoload) and ui/UiScale.gd share them without a ui/ dependency.
## Not one of the F4 tuning panel's resource classes, so no config/tuning_panel_hints.tres entry.

## content_scale_factor at 100%. 2026-10-10 owner (Bontago-1pi.151): half the old mockup scale
## (1280 / 960 = 1.3333), i.e. 0.6666667.
@export var base_scale: float = 0.6666667
## The stored value a fresh install gets: 100%.
@export var default_scale: float = 1.0
## Smallest stored value: 0.75 x base = 0.5 effective factor.
@export var min_scale: float = 0.75
## Largest stored value. DECISION: 2.2 x base = ~1.467 effective, the old 110% maximum (logical canvas ~873x491 at 1280x720), so every previously reachable size stays reachable.
@export var max_scale: float = 2.2
## Slider step; stored values are snapped to it on set and load.
@export var step: float = 0.05

## Gap kept between the HUD's top-left scoreboard and the centred round timer ring when a narrow
## (UI-scaled) canvas would make them touch.
@export var hud_timer_clearance_px: int = 12

const RESOURCE_PATH: String = "res://config/ui_scale_tuning.tres"
static var _shared: UiScaleTuning = null
## Runtime mirror of Settings' value (set by Settings on load/change) so ui/UiScale.gd, the
## AgentProbe viewport emulation and layout tests use the same factor as the real window.
static var current_scale: float = -1.0


static func shared() -> UiScaleTuning:
	if _shared == null:
		_shared = load(RESOURCE_PATH) as UiScaleTuning
	return _shared


## Bontago-xtq.44: drops the shared instance on exit so its textures are freed with the tree.
static func release_shared() -> void:
	_shared = null


## Clamps to [min_scale, max_scale] and snaps to step (non-finite falls back to the default).
func sanitize(value: float) -> float:
	if is_nan(value) or is_inf(value):
		return default_scale
	var clamped: float = clampf(value, min_scale, max_scale)
	var snapped_value: float = min_scale + roundf((clamped - min_scale) / step) * step
	return clampf(snapped_value, min_scale, max_scale)


## The stored (relative) value the runtime currently uses.
static func runtime_scale() -> float:
	var tuning: UiScaleTuning = shared()
	if current_scale < 0.0:
		return tuning.default_scale
	return current_scale


## Multiplier on top of the project stretch for a stored value.
func effective_factor(stored: float) -> float:
	return base_scale * sanitize(stored)
