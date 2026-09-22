class_name TinyMapMatchConfig
extends MatchConfig
## Test-only seam (Bontago-mv0.3): overrides map_def() so a duplicated
## MatchConfig can be pointed at an arbitrarily small MapDef instead of one
## of MatchConfig's three real SMALL/MEDIUM/LARGE presets (MapDef.for_size()
## always resolves to a real, shared-cache .tres -- there is no config-level
## seam for a custom size). Tests build one MapDef, hand it to both this and
## the Field under test (see tests/unit/test_match_flow.gd's before_each), so
## Match's home-flag/kill-plane/cell-grid geometry and Field's physical
## collision always agree, without paying the real round_medium.tres map's
## ~6300-cell collision build (see Bontago-mv0.3) in every test.
##
## Built via `existing_config.duplicate(true)` then `set_script()` to this
## script -- in that order, and *before* any other field is set on the
## result: Object.set_script() resets script-level state to the new script's
## declared defaults, so a field set beforehand (player_count, hot_seat, ...)
## would otherwise be silently discarded. Every call site below does the
## swap first, then sets its own fields on the now-TinyMapMatchConfig result.
##
## `tiny_map` must be `@export`: Match.start_match() takes its own
## `match_config.duplicate(true)` (autoload/Match.gd, so a match never writes
## back into a caller's config); Resource.duplicate() only carries over
## exported/storage properties, so a plain, non-exported var here would
## silently come back null on the copy Match actually runs on.
@export var tiny_map: MapDef


func set_tiny_map(map: MapDef) -> void:
	tiny_map = map


func map_def() -> MapDef:
	return tiny_map
