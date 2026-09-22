class_name GiftSpawner
extends RefCounted
## Pure gift-crate spawning logic (spec 2.6): whether a crate should spawn
## this placement window, and where. No scene tree, no autoloads (CLAUDE.md).
##
## SPEC.md 2.6 "Gift spawning [ORIGINAL target]": probability per placement
## turn/window, not the earlier reconstructed seconds-based interval with
## jitter -- docs/M4_PLAN.md's own header amendment retires that mapping
## explicitly. This file implements only the probability form.

## Sentinel returned by pick_spawn_point() when every attempt failed, mirroring
## PlacementRules.NO_ORIGIN's convention (an unmistakable, non-finite point
## rather than a magic in-range coordinate).
const NO_SPAWN_POINT: Vector2 = Vector2(INF, INF)


static func is_no_spawn_point(point: Vector2) -> bool:
	return is_inf(point.x) or is_inf(point.y)


## Linearly maps MatchConfig.special_frequency (0..100) to a spawn chance of
## 0..config.frequency_to_chance_max: 0 at frequency 0, frequency_to_chance_max
## at frequency 100, monotonic in between. Clamped at both ends so an
## out-of-range frequency never produces a chance outside [0, frequency_to_chance_max].
static func chance_for_frequency(config: GiftConfig, special_frequency: float) -> float:
	var freq: float = clampf(special_frequency, 0.0, 100.0)
	var max_chance: float = maxf(config.frequency_to_chance_max, 0.0)
	return clampf((freq / 100.0) * max_chance, 0.0, max_chance)


## One Bernoulli roll. Pure logic: it has no idea how many players there are
## or how often it gets called, so the "for the whole match (not per player)"
## contract is the *caller's* job -- autoload/match/MatchGifts.gd (M4 P1b
## review fix, Bontago-4fa) calls this exactly once per placement window by
## rolling only when the issuing slot is the lowest-indexed one still alive,
## not once per slot's own feed event. Always false once max_live_crates are
## already live, regardless of chance, so a caller never has to check
## live_crates itself.
static func should_spawn(
	config: GiftConfig,
	special_frequency: float,
	live_crates: int,
	rng: RandomNumberGenerator
) -> bool:
	if live_crates >= config.max_live_crates:
		return false
	var chance: float = chance_for_frequency(config, special_frequency)
	return rng.randf() < chance


## Samples up to config.spawn_max_attempts random in-disk points (disk-local
## XZ, uniform over the disk's area), accepting the first whose cell is
## neither contested nor a hole and that stays spawn_edge_margin_m clear of
## the rim (spec 2.6: "at a random uncontested point"). Returns
## NO_SPAWN_POINT when every attempt failed; the caller just waits for the
## next window rather than treating that as an error (mirrors
## PlacementRules.closest_valid_origin()'s NO_ORIGIN contract).
##
## Deterministic given rng's seed: every random draw comes from the passed-in
## generator and nothing else, so replaying the same seed replays the same
## point.
static func pick_spawn_point(
	raster: TerritoryRaster, grid: CellGrid, rng: RandomNumberGenerator, config: GiftConfig
) -> Vector2:
	var effective_radius: float = maxf(grid.field_radius - config.spawn_edge_margin_m, 0.0)

	for attempt: int in range(config.spawn_max_attempts):
		var candidate: Vector2 = _random_point_in_disk(rng, effective_radius)
		var cell: Vector2i = grid.world_to_cell(candidate)
		if not grid.in_bounds(cell.x, cell.y) or not grid.is_in_disk(cell.x, cell.y):
			continue
		if raster.is_contested(cell.x, cell.y) or raster.is_hole(cell.x, cell.y):
			continue
		return candidate

	return NO_SPAWN_POINT


## Uniform-area sample of a disk of `radius` centered on the origin: the angle
## is uniform over [0, TAU) and the radius is scaled by sqrt() of a uniform
## draw, which is the standard correction so points don't bunch up near the
## centre (a plain linear radius scale would).
static func _random_point_in_disk(rng: RandomNumberGenerator, radius: float) -> Vector2:
	if radius <= 0.0:
		return Vector2.ZERO
	var angle: float = rng.randf() * TAU
	var r: float = radius * sqrt(rng.randf())
	return Vector2(cos(angle), sin(angle)) * r
