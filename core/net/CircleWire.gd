class_name CircleWire
extends RefCounted
## Wire packing for the territory circle list (Bontago-cmc.5, owner
## requirement: "should look smooth... some kind of metaballs system").
##
## game/TerritoryOverlay.gd's shader now draws territory as the analytic
## union of the *home-anchored* circles TerritorySolver/TerritoryGroups kept,
## rather than smoothstepping a bilinearly-upscaled 1 m cell grid (see that
## class's doc comment for why the grid route cannot recover a curved
## border). Clients need the same circle list a client's raster mirror does
## not otherwise carry, so net/MatchNet.gd's replicate_territory()/
## net_territory() ship it alongside the existing raster diff, on the same
## NetConfig.raster_diff_hz cadence. Pure functions over PackedByteArray, no
## nodes, no signals, no engine state beyond a Vector2 (CLAUDE.md: core/
## holds pure logic with no scene-tree dependence) — mirrors
## core/net/Quantize.gd's style, and reuses its axis quantizer rather than
## duplicating it.
##
## **Layout**, little-endian throughout:
##
## | offset | size | field |
## |---|---|---|
## | 0 | 1 | version (VERSION) |
## | 1 | 2 | circle_count, u16 |
## | 3 | 1 | goal_count, u8 |
## | 4 | 1 | argmax_mode, u8 (0 or 1; MatchConfig.HoleMode.OFF) |
## | 5 | circle_count * 7 | circle records |
## | 5 + circle_count*7 | goal_count * 6 | goal records |
##
## **One circle record** (CIRCLE_RECORD_BYTES = 7): x:u16, z:u16 (disk-local,
## quantized over [-xz_bound, xz_bound], the same symmetric-range convention
## Quantize.quantize_axis/dequantize_axis already implement), radius:u16
## (quantized over [0, radius_max]), team:u8. At TerritoryTuning.max_circles
## = 400 that is 2800 bytes.
##
## **One goal record** (GOAL_RECORD_BYTES = 6): x:u16, z:u16, radius:u16 —
## no team, a goal's no-build zone belongs to nobody. Spec 2.2 allows 1-5
## goal flags; GOAL_COUNT_MAX below is a wire safety cap, not a rule.
##
## DECISION (core/net/CircleWire.gd): unlike net/MatchNet.gd's raster payload
## (_finish_raster_payload(), optionally zstd-compressed), this payload is
## never compressed. At the graded size it is already under the 4 KB budget
## uncompressed (see the class doc's arithmetic below), and quantized,
## already-dense u16 fields compress poorly compared to the raster's mostly-
## repeated bytes — not worth a second codec path for a packet this small.
##
## At the graded size (400 circles, 5 goals) the whole payload is
## HEADER_BYTES + 400*7 + 5*6 = 5 + 2800 + 30 = 2835 bytes, under the
## ticket's 4 KB budget (tests/unit/test_circle_wire.gd asserts this).

## Bumped whenever the layout changes, exactly like Quantize's body record
## and MatchNet.RASTER_VERSION — architecture, not a tunable (CLAUDE.md's "no
## magic numbers" targets tunables, not wire-format constants).
const VERSION: int = 1

const HEADER_BYTES: int = 5
const CIRCLE_RECORD_BYTES: int = 7
const GOAL_RECORD_BYTES: int = 6

## u16 circle_count and u8 goal_count field limits. A caller hands in more
## than TerritoryTuning.max_circles kept anyway only if it forgot to apply
## the cap; clamping here (rather than erroring) keeps a stale/hostile
## payload merely truncated, never mis-parsed.
const CIRCLE_COUNT_MAX: int = 0xFFFF
const GOAL_COUNT_MAX: int = 0xFF


## Packs the home-anchored circle list plus the goal no-build discs into one
## payload. `xs`/`zs`/`radii`/`teams` must be the same length (extra entries
## in a longer array are ignored, matching PackedByteArray.resize()'s usual
## silent-truncate style elsewhere in this codebase); ditto `goal_positions`/
## `goal_radii`. `xz_bound` is the disk-local half-extent circle centers are
## quantized over (the caller's NetConfig.position_bounds() half-width, the
## same bound the snapshot's own positions use); `radius_max` is the largest
## radius a circle or goal zone can have (TerritoryTuning.influence_max_
## fraction * field_radius comfortably covers both — a goal zone's radius is
## much smaller).
static func encode(
	xs: PackedFloat32Array,
	zs: PackedFloat32Array,
	radii: PackedFloat32Array,
	teams: PackedInt32Array,
	goal_positions: PackedVector2Array,
	goal_radii: PackedFloat32Array,
	argmax_mode: bool,
	xz_bound: float,
	radius_max: float
) -> PackedByteArray:
	var circle_count: int = mini(
		mini(xs.size(), zs.size()), mini(radii.size(), teams.size())
	)
	circle_count = clampi(circle_count, 0, CIRCLE_COUNT_MAX)
	var goal_count: int = mini(goal_positions.size(), goal_radii.size())
	goal_count = clampi(goal_count, 0, GOAL_COUNT_MAX)

	var out: PackedByteArray = PackedByteArray()
	out.resize(HEADER_BYTES + circle_count * CIRCLE_RECORD_BYTES + goal_count * GOAL_RECORD_BYTES)
	out.encode_u8(0, VERSION)
	out.encode_u16(1, circle_count)
	out.encode_u8(3, goal_count)
	out.encode_u8(4, 1 if argmax_mode else 0)

	var offset: int = HEADER_BYTES
	for i: int in range(circle_count):
		out.encode_u16(offset, Quantize.quantize_axis(xs[i], -xz_bound, xz_bound))
		out.encode_u16(offset + 2, Quantize.quantize_axis(zs[i], -xz_bound, xz_bound))
		out.encode_u16(offset + 4, Quantize.quantize_axis(radii[i], 0.0, radius_max))
		out.encode_u8(offset + 6, clampi(teams[i], 0, 255))
		offset += CIRCLE_RECORD_BYTES

	for i: int in range(goal_count):
		var position: Vector2 = goal_positions[i]
		out.encode_u16(offset, Quantize.quantize_axis(position.x, -xz_bound, xz_bound))
		out.encode_u16(offset + 2, Quantize.quantize_axis(position.y, -xz_bound, xz_bound))
		out.encode_u16(offset + 4, Quantize.quantize_axis(goal_radii[i], 0.0, radius_max))
		offset += GOAL_RECORD_BYTES

	return out


## Inverse of encode(). Returns {"xs", "zs", "radii", "teams": PackedInt32Array,
## "goal_positions": PackedVector2Array, "goal_radii": PackedFloat32Array,
## "argmax_mode": bool} or an empty Dictionary for a truncated, foreign or
## wrong-version payload — the same "ignore rather than half-apply" contract
## MatchNet.decode_raster_payload() uses, so a corrupt packet leaves the
## client's last-known circle list alone instead of drawing garbage.
static func decode(packet: PackedByteArray, xz_bound: float, radius_max: float) -> Dictionary:
	if packet.size() < HEADER_BYTES:
		return {}
	if packet.decode_u8(0) != VERSION:
		return {}
	var circle_count: int = packet.decode_u16(1)
	var goal_count: int = packet.decode_u8(3)
	var argmax_mode: bool = packet.decode_u8(4) != 0

	var expected: int = HEADER_BYTES + circle_count * CIRCLE_RECORD_BYTES + goal_count * GOAL_RECORD_BYTES
	if packet.size() != expected:
		return {}

	var xs: PackedFloat32Array = PackedFloat32Array()
	var zs: PackedFloat32Array = PackedFloat32Array()
	var radii: PackedFloat32Array = PackedFloat32Array()
	var teams: PackedInt32Array = PackedInt32Array()
	xs.resize(circle_count)
	zs.resize(circle_count)
	radii.resize(circle_count)
	teams.resize(circle_count)

	var offset: int = HEADER_BYTES
	for i: int in range(circle_count):
		xs[i] = Quantize.dequantize_axis(packet.decode_u16(offset), -xz_bound, xz_bound)
		zs[i] = Quantize.dequantize_axis(packet.decode_u16(offset + 2), -xz_bound, xz_bound)
		radii[i] = Quantize.dequantize_axis(packet.decode_u16(offset + 4), 0.0, radius_max)
		teams[i] = packet.decode_u8(offset + 6)
		offset += CIRCLE_RECORD_BYTES

	var goal_positions: PackedVector2Array = PackedVector2Array()
	var goal_radii: PackedFloat32Array = PackedFloat32Array()
	goal_positions.resize(goal_count)
	goal_radii.resize(goal_count)
	for i: int in range(goal_count):
		var x: float = Quantize.dequantize_axis(packet.decode_u16(offset), -xz_bound, xz_bound)
		var z: float = Quantize.dequantize_axis(packet.decode_u16(offset + 2), -xz_bound, xz_bound)
		goal_positions[i] = Vector2(x, z)
		goal_radii[i] = Quantize.dequantize_axis(packet.decode_u16(offset + 4), 0.0, radius_max)
		offset += GOAL_RECORD_BYTES

	return {
		"xs": xs,
		"zs": zs,
		"radii": radii,
		"teams": teams,
		"goal_positions": goal_positions,
		"goal_radii": goal_radii,
		"argmax_mode": argmax_mode,
	}
