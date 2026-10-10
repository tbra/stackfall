class_name DiscSizeTuning
extends Resource
## The lobby's disc-size slider (Bontago-1pi.107, owner 2026-10-07): six steps,
## each a uniform scale of the default (round, medium) map. Step labels and
## factors live in config/disc_size_tuning.tres so no number is baked into code.
##
## DECISION (Bontago-1pi.107): a step scales MapDef's geometric lengths
## (field_radius, so the home/goal flags, spawn area, kill plane, camera framing
## and the influence cap, which are all fractions of it; the territory texture
## resolution; the Ring/Twin bridge widths) uniformly. It does NOT scale block
## sizes, flag/beacon models, physics tunables, cell_size (one cell stays one
## metre, one raster pixel) or the influence formula r = base + k * height: a
## block claims the same ground on every disc, so a larger disc simply asks more
## blocks to claim it, which is the point of the size option.

const RESOURCE_PATH: String = "res://config/disc_size_tuning.tres"

## One label per step ("Tiny" ... "Enormous"), index = step.
@export var step_labels: PackedStringArray = PackedStringArray()
## One scale factor per step (0.5 ... 1.75), index = step.
@export var step_factors: PackedFloat32Array = PackedFloat32Array()
## Format for the lobby's value text; %s = label, %d = percent.
@export var value_format: String = "%s - %d%%"

static var _shared: DiscSizeTuning = null


static func shared() -> DiscSizeTuning:
	if _shared == null:
		_shared = load(RESOURCE_PATH) as DiscSizeTuning
	return _shared


## Bontago-xtq.44: drops the shared instance on exit so its textures are freed with the tree.
static func release_shared() -> void:
	_shared = null


func step_count() -> int:
	return step_factors.size()


func clamp_step(step: int) -> int:
	return clampi(step, 0, maxi(step_count() - 1, 0))


## Scale factor of `step` (clamped); 1.0 when the table is empty.
func factor_for(step: int) -> float:
	if step_factors.is_empty():
		return 1.0
	return step_factors[clamp_step(step)]


func label_for(step: int) -> String:
	if step_labels.is_empty():
		return ""
	return step_labels[clampi(step, 0, step_labels.size() - 1)]


## "Medium - 100%" style text for the lobby.
func value_text(step: int) -> String:
	return value_format % [label_for(step), roundi(factor_for(step) * 100.0)]
