class_name SkyVariation
extends RefCounted
## Bontago-59o.18 (C1b variation, owner 2026-10-03: "lets add some variation and just
## set a range so it can vary"): the cycle sky's exposure and cloud coverage wander
## inside the SkyThemeDef.variation_* ranges. Pure rules, no scene tree, no RNG state
## and no clock: every value is a function of (match seed, cycle phase), so the host
## and every client compute the identical sky from the replicated match config and the
## shared cycle clock with no new wire field. game/Skybox.gd calls these in
## set_cycle_phase(), which a locked Sunset / Dawn / Night also goes through once (the
## locked phase is fixed, so the value is a stable seed-derived constant inside the
## range).
##
## The variation is value noise on the cycle's circle: `knots` seeded lattice values
## per full cycle, smoothstep-interpolated, wrapping from phase 1 back to 0 without a
## step. The lattice values are pushed toward the ends of 0..1 (a smoothstep of a
## uniform hash is end-heavy) so the sky uses most of its configured range rather than
## hugging the midpoint.

## Independent noise streams, so exposure and the two coverages do not move in lockstep.
const CHANNEL_EXPOSURE: int = 0
const CHANNEL_CLOUD_COVERAGE: int = 1
const CHANNEL_SEA_COVERAGE: int = 2
## A one-point lattice would be a constant; two is the least that can swing.
const MIN_KNOTS: int = 2
## The seed a match without a replicated one uses (MatchConfig.rng_seed < 0 means
## "randomise" and is not resolved for clients), and what a sky launched outside a
## match uses.
const DEFAULT_SEED: int = 0

# Integer hash (Chris Wellons' lowbias32 round) over 32 bits, kept under 2^62 per step
# so no intermediate overflows a 64-bit int on any platform.
const HASH_MASK: int = 0xFFFFFFFF
const HASH_SEED_MIX: int = 0x2545F491
const HASH_CHANNEL_MIX: int = 0x1B873593
const HASH_INDEX_MIX: int = 0x5BD1E995
const HASH_ROUND_A: int = 0x21F0AAAD
const HASH_ROUND_B: int = 0x735A2D97
const HASH_SHIFT_WIDE: int = 16
const HASH_SHIFT_NARROW: int = 15
## The low 24 bits become the 0..1 value (exactly representable in a float).
const HASH_VALUE_MASK: int = 0xFFFFFF
const HASH_RESOLUTION: float = 16777215.0


## The seed for a match: its rng_seed when it has one (>= 0), else DEFAULT_SEED.
static func seed_for(rng_seed: int) -> int:
	return rng_seed if rng_seed >= 0 else DEFAULT_SEED


## 0..1 variation of `channel` at cycle `phase` (0..1, wrapped) for `seed_value`, with
## `knots` lattice points per cycle. Continuous everywhere, including the 1 -> 0 wrap.
static func weight(phase: float, knots: int, seed_value: int, channel: int) -> float:
	var count: int = maxi(knots, MIN_KNOTS)
	var position: float = fposmod(phase, 1.0) * float(count)
	var index: int = int(floor(position))
	var blend: float = smoothstep(0.0, 1.0, position - float(index))
	var from_value: float = knot_value(seed_value, channel, index % count)
	var to_value: float = knot_value(seed_value, channel, (index + 1) % count)
	return lerpf(from_value, to_value, blend)


## The lattice value (0..1, end-heavy) of `channel` at lattice point `index`.
static func knot_value(seed_value: int, channel: int, index: int) -> float:
	var mixed: int = (seed_value * HASH_SEED_MIX + channel * HASH_CHANNEL_MIX + index * HASH_INDEX_MIX) & HASH_MASK
	mixed = (mixed ^ (mixed >> HASH_SHIFT_WIDE)) & HASH_MASK
	mixed = (mixed * HASH_ROUND_A) & HASH_MASK
	mixed = (mixed ^ (mixed >> HASH_SHIFT_NARROW)) & HASH_MASK
	mixed = (mixed * HASH_ROUND_B) & HASH_MASK
	mixed = (mixed ^ (mixed >> HASH_SHIFT_NARROW)) & HASH_MASK
	return smoothstep(0.0, 1.0, float(mixed & HASH_VALUE_MASK) / HASH_RESOLUTION)


## `weight` mapped into [low, high] (a swapped pair is read as min/max, so a
## mis-authored range stays a range).
static func in_range(low: float, high: float, weight_value: float) -> float:
	var lower: float = minf(low, high)
	var upper: float = maxf(low, high)
	# The clamp absorbs the last-bit rounding of a lerp at weight 1 (never above `upper`).
	return clampf(lerpf(lower, upper, clampf(weight_value, 0.0, 1.0)), lower, upper)


## The sky shader `exposure` baseline at `phase` (weather overcast scales it afterwards).
static func exposure_at(theme: SkyThemeDef, phase: float, seed_value: int) -> float:
	return in_range(theme.variation_exposure_min, theme.variation_exposure_max,
		weight(phase, theme.variation_knots_per_cycle, seed_value, CHANNEL_EXPOSURE))


## The sky shader `cloud_coverage` at `phase`.
static func cloud_coverage_at(theme: SkyThemeDef, phase: float, seed_value: int) -> float:
	return in_range(theme.variation_cloud_coverage_min, theme.variation_cloud_coverage_max,
		weight(phase, theme.variation_knots_per_cycle, seed_value, CHANNEL_CLOUD_COVERAGE))


## The sky and puff shaders' `proc_sea_coverage` at `phase`.
static func sea_coverage_at(theme: SkyThemeDef, phase: float, seed_value: int) -> float:
	return in_range(theme.variation_sea_coverage_min, theme.variation_sea_coverage_max,
		weight(phase, theme.variation_knots_per_cycle, seed_value, CHANNEL_SEA_COVERAGE))
