class_name TuningPanelHints
extends Resource
## Per-property slider/spinbox ranges for ui/TuningPanel.gd's reflection-built
## tabs (Bontago-mv0.18, owner request: "add a settings menu with sliders").
##
## Every numeric @export field TuningPanel finds gets a control regardless of
## whether it has an entry here: an unlisted field falls back to
## TuningPanel._fallback_range() (roughly "[0, 4x current value]", the shape
## the design brief specified), which is a fine slider range for most
## tunables but a poor one for anything whose sane default sits at or below
## zero (kill_plane_y, the negative camera pitch angles...) or whose useful
## range isn't proportional to its default at all (a friction/bounce
## coefficient conventionally reads 0..1-ish regardless of where it currently
## sits). This resource only needs entries for those -- the fields the owner
## is actually likely to reach for (camera feel, gravity/damping/bounce/
## friction) get a deliberately chosen range; everything else is left to the
## fallback rather than hand-tuning every field across every tuning resource.
##
## Loaded once as config/tuning_panel_hints.tres.

## "<script class name>.<property name>" -> Vector2(min, max). Keyed on the
## class name too (not just the bare property name) so two tuning resources
## that ever share a field name -- none do today -- can't collide.
@export var ranges: Dictionary = {}


## Vector2(NAN, NAN) (an invalid sentinel TuningPanel._range_for() checks for)
## when `class_name_ + "." + property_name` has no entry here.
func range_for(class_name_: String, property_name: String) -> Vector2:
	var key: String = "%s.%s" % [class_name_, property_name]
	if ranges.has(key):
		return ranges[key] as Vector2
	return Vector2(NAN, NAN)
