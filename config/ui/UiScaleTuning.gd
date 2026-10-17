class_name UiScaleTuning
extends Resource
## the player-facing UI scale (Options > Settings > Display). The stored setting is
## RELATIVE: 1.0 (100%) is base_scale times the project stretch (1280x720 base). Applied by autoload/Settings.gd as
## Window.content_scale_factor on the root window; the pure rules (sanitize, effective factor)
## are statics here so Settings (autoload) and ui/theme/UiScale.gd share them without a ui/ dependency.
## Not one of the F4 tuning panel's resource classes, so no config/ui/tuning_panel_hints.tres entry.

## content_scale_factor at 100% (half of 1280 / 960).
@export var base_scale: float = 0.6666667
## The stored value a fresh install gets: 100%.
@export var default_scale: float = 1.0
## Smallest stored value: 0.75 x base = 0.5 effective factor.
@export var min_scale: float = 0.75
## Largest stored value. DECISION: 200% (2.0 x base = ~1.333 effective, logical canvas 960x540 at 1280x720). Saved values above it clamp via sanitize().
@export var max_scale: float = 2.0
## Slider step; stored values are snapped to it on set and load.
@export var step: float = 0.05

## Gap kept between the HUD's top-left scoreboard and the centred round timer ring when a narrow
## (UI-scaled) canvas would make them touch.
@export var hud_timer_clearance_px: int = 12

## the in-match HUD scale shares the UI scale's range and step (min_scale..max_scale,
## step); its default is default_scale (100%).
## DECISION: minimap size is three presets (small / medium / large) in square HUD pixels; medium is the
## original 168 px. Index 1 is the default.
@export var minimap_size_presets_px: PackedInt32Array = PackedInt32Array([128, 168, 224])
## Option-list label for each preset, same order and length as minimap_size_presets_px.
@export var minimap_size_labels: PackedStringArray = PackedStringArray(["Small", "Medium", "Large"])
@export var minimap_default_preset: int = 1

const RESOURCE_PATH: String = "res://config/ui/ui_scale_tuning.tres"
static var _shared: UiScaleTuning = null
## Runtime mirror of Settings' value (set by Settings on load/change) so ui/theme/UiScale.gd, the
## AgentProbe viewport emulation and layout tests use the same factor as the real window.
static var current_scale: float = -1.0
## Same, for the HUD scale; -1 until Settings publishes it.
static var current_hud_scale: float = -1.0
## Same, for the minimap preset index; -1 until Settings publishes it.
static var current_minimap_preset: int = -1


static func shared() -> UiScaleTuning:
	if _shared == null:
		_shared = load(RESOURCE_PATH) as UiScaleTuning
	return _shared


## drops the shared instance on exit so its textures are freed with the tree.
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


## Runtime HUD scale (stored, relative); the default until Settings publishes one.
static func runtime_hud_scale() -> float:
	if current_hud_scale < 0.0:
		return shared().default_scale
	return current_hud_scale


## Clamps a minimap preset index into the presets array.
func sanitize_minimap_preset(index: int) -> int:
	return clampi(index, 0, maxi(minimap_size_presets_px.size() - 1, 0))


## Square pixel size of a minimap preset (index is sanitized).
func minimap_size_px_for(index: int) -> int:
	return minimap_size_presets_px[sanitize_minimap_preset(index)]


## Runtime minimap preset index.
static func runtime_minimap_preset() -> int:
	if current_minimap_preset < 0:
		return shared().minimap_default_preset
	return current_minimap_preset


## Factor the HUD's root is scaled by so the HUD's total size follows the HUD scale alone instead of the
## UI scale: HUD scale / UI scale (both stored, relative values).
static func hud_relative_factor() -> float:
	var ui: float = maxf(runtime_scale(), 0.01)
	return runtime_hud_scale() / ui
