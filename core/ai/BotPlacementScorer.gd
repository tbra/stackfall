class_name BotPlacementScorer
extends RefCounted
## Pure (CLAUDE.md "core/ ... no dependence on the scene tree"): every
## argument is a value type or an already-built core/ object.
##
## docs/M5_PLAN.md P1 (Bontago-d5c): this file's own default body --
## `pick_best()` returns `candidates[0]` unscored, `score()` returns 0.0,
## `flattest_orientations()` returns `[0]`. P2 rewrites every body below; the
## *signatures* do not change (P1 is the interface-stub package every later
## M5 package builds on).

static func score(
	candidate: BotCandidate,
	raster: TerritoryRaster,
	grid: CellGrid,
	team_id: int,
	goal_positions: PackedVector2Array,
	enemy_circle_centers: PackedVector2Array,
	active_special_positions: PackedVector2Array,
	tuning: BotTuning,
	field_radius: float
) -> float:
	return 0.0


## Spec 2.9 "the orientation (out of the 24) that gives the flattest base" --
## purely from `shape.cells` geometry, independent of terrain. Returns a
## short ranked list, not all 24; the caller still scores each returned index
## against the real site.
##
## P1's own default: the identity orientation alone. P2 ranks every face of
## `shape.cells`' bounding box by flat-footprint coverage and returns up to
## `max_count` distinct indices.
static func flattest_orientations(shape: BlockShape, max_count: int) -> Array[int]:
	var result: Array[int] = [0]
	return result


## The one entry point BotController calls once a think-tick's candidate list
## is complete. Null only when `candidates` is empty.
static func pick_best(
	candidates: Array[BotCandidate],
	raster: TerritoryRaster,
	grid: CellGrid,
	team_id: int,
	goal_positions: PackedVector2Array,
	enemy_circle_centers: PackedVector2Array,
	active_special_positions: PackedVector2Array,
	tuning: BotTuning,
	field_radius: float
) -> BotCandidate:
	if candidates.is_empty():
		return null
	return candidates[0]
