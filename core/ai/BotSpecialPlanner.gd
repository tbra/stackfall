class_name BotSpecialPlanner
extends RefCounted
## Pure (CLAUDE.md "core/ ... no dependence on the scene tree"). Decides what
## a bot does with a held special (spec 2.6, 2.9) -- place it, or throw it at
## a target.
##
## docs/M5_PLAN.md P1 (Bontago-d5c): this file's own default body --
## `plan()` always returns `should_throw = false, should_place_ordinarily =
## true` (spend the special like a normal block). P3 rewrites the body; this
## signature does not change (P1 is the interface-stub package every later
## M5 package builds on).

class BotSpecialAction:
	var should_throw: bool = false
	## Disk-local release point, inside own territory.
	var throw_origin: Vector2 = Vector2.ZERO
	## World-space; caller still clamps via request_throw().
	var throw_velocity: Vector3 = Vector3.ZERO
	## Fall back to an ordinary placement candidate.
	var should_place_ordinarily: bool = true


## P1's own default body: always returns should_throw=false,
## should_place_ordinarily=true (spend the special like a normal block). P3
## rewrites the body; this signature does not change.
static func plan(
	held_special_id: StringName,
	own_home_position: Vector2,
	own_territory_sample_points: PackedVector2Array,
	enemy_circle_centers: PackedVector2Array,
	active_special_positions: PackedVector2Array,
	difficulty: MatchConfig.AiDifficulty,
	tuning: BotTuning
) -> BotSpecialAction:
	return BotSpecialAction.new()
