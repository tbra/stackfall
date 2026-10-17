class_name MapDef
extends Resource
## One map's size, shape and layout (spec 1.7, 1.5, 2.5): the round field and
## its radius, the cell grid the holes are cut from, the territory texture
## resolution, and where the home and goal flags sit.

const RADIUS_MEDIUM: float = 45.0
const RADIUS_LARGE: float = 60.0

## Spec 2.5: the territory texture is territory_res x territory_res (384 on the unscaled map).
const TERRITORY_RES_MEDIUM: int = 384

## The one round map; the lobby's disc-size step scales it (scaled()).
const BASE_PATH: String = "res://config/match/maps/round.tres"

@export var id: StringName = &"round_medium"
@export var field_radius: float = RADIUS_MEDIUM

## Thickness of the disk. Field builds its collision and mesh from this.
##
## DECISION: 0.2 m, a thin slab a 1 m block visibly rests ON rather than IN (a 1.0 m disk
## made blocks look like they hover). Every reader scales with this field (Field's hole/rim
## wall depth and overlay y-offset, TerritoryOverlay's CylinderMesh height); a shallower guide
## wall still pushes a block sliding into a hole off to the side before it clears the wall's
## bottom edge (pinned by test_a_block_over_a_lone_hole_cell_falls_through in
## tests/unit/field/test_field_cells.gd).
@export var disk_height: float = 0.2

## Spec 2.5: the disk's collision is a square grid of BoxShape3Ds of this
## edge length, clipped to the disk. One cell is also one pixel of the
## authoritative territory raster ("Raster resolution").
@export var cell_size: float = 1.0

## Spec 2.5: the size of the ImageTexture handed to territory.gdshader. The
## cell-resolution raster is upscaled to this before upload, so the shader's
## bilinear sampling and smoothstep have something smooth to work with.
@export var territory_res: int = TERRITORY_RES_MEDIUM

## Spec 1.5: home flags are spaced evenly around the edge; extra goal flags
## are placed symmetrically at 0.4 * field_radius.
##
## DECISION: a home flag sits at field_radius - home_flag_edge_inset, so the gap to the rim
## does not grow with the map. 6.0 m equals TerritoryTuning.home_radius, so a home circle
## just reaches the rim, and leaves the 1 m beacon socket and a held-block spawn well inside
## the safe margin. Sudden-death shrink never moves homes (it only removes outer cells), and
## the lobby's disc-size slider scales the radius only, so the inset stays fixed there too.
@export var home_flag_edge_inset: float = 6.0
@export var goal_flag_radius_fraction: float = 0.4

## Spec 2.5: "Wake up any sleeping blocks above cells that change state."
## How far above the disk surface Field's wake query reaches, in meters —
## tall enough to cover any tower this map can realistically carry. It is a
## physics-query extent rather than a rule number, so it lives with the map's
## other geometry instead of in TerritoryTuning.
@export var cell_wake_height: float = 60.0
## Upper bound on bodies one cell's wake query reports. A cell is 1 m square,
## so even a dense tower puts only a handful of blocks over it.
@export var cell_wake_max_bodies: int = 32


## The one shipped map, unscaled.
static func base() -> MapDef:
	return load(BASE_PATH) as MapDef


## True where `local` (disk-local (x, z), CellGrid's own convention) is solid
## ground: inside the field_radius circle. Kept as a method so callers need not
## know the disc is the only shape.
func shape_contains(local: Vector2) -> bool:
	return local.length_squared() <= field_radius * field_radius


## Callable form of shape_contains() for CellGrid's optional third argument.
## Always empty: CellGrid's plain circle test is the only membership check.
func shape_test() -> Callable:
	return Callable()


## A uniformly scaled copy of this map (the lobby's disc-size slider, see
## config/match/DiscSizeTuning.gd for the DECISION on what scales). The radius and the
## territory texture resolution scale; the goal flag ring follows the radius by itself, home
## flags keep their fixed edge inset, and cell_size / disk_height / wake query extents stay.
## A factor of 1.0 returns this very resource so the default map is untouched.
func scaled(factor: float) -> MapDef:
	if is_equal_approx(factor, 1.0) or factor <= 0.0:
		return self
	var copy: MapDef = duplicate(true) as MapDef
	copy.field_radius = field_radius * factor
	copy.territory_res = maxi(roundi(float(territory_res) * factor), 1)
	return copy


## Number of cells along one edge of the square grid that covers the disk.
func cells_per_side() -> int:
	return int(ceil(2.0 * field_radius / maxf(cell_size, 0.001)))


## Spec 1.5: "Each player's home flag sits near the edge, spaced
## evenly around the edge." Slot 0 sits at angle 0 (+x) and slots advance
## counter-clockwise, so a 2-player match puts the two players opposite each
## other and an 8-player match spaces them at pi/4.
##
## The geometry lives here, on the map that defines it, so that Field's flag
## placement and PlayerSlot.home_position_for cannot drift apart — both call
## this. Returns a disk-local (x, z) point; see CellGrid for the convention.
func home_flag_position(slot_id: int, slot_count: int) -> Vector2:
	var count: int = maxi(slot_count, 1)
	var index: int = posmod(slot_id, count)
	var angle: float = TAU * float(index) / float(count)
	var home_radius: float = home_flag_ring_radius()
	return Vector2(cos(angle) * home_radius, sin(angle) * home_radius)


## Distance of every home flag from the disc centre: the disc radius minus the
## fixed edge inset (never negative on a tiny disc).
func home_flag_ring_radius() -> float:
	return maxf(field_radius - home_flag_edge_inset, 0.0)


## Spec 1.5: "1 goal flag in the center by default. Setup allows 1-5. Extra
## flags are placed symmetrically at 0.4 * field_radius."
##
## DECISION (config/match/MapDef.gd): the spec does not say whether a multi-flag
## layout keeps a flag in the center as well. The simplest symmetric reading
## is taken: one flag is the center, and any count above one is that many
## flags evenly spaced on the 0.4 * field_radius ring (starting at +x), which
## keeps every layout rotationally symmetric and gives no player a shorter
## walk than another. No gameplay rule depends on which reading is used.
func goal_flag_positions(count: int) -> PackedVector2Array:
	var wanted: int = maxi(count, 1)
	var positions: PackedVector2Array = PackedVector2Array()
	if wanted == 1:
		positions.append(Vector2.ZERO)
		return positions
	var ring_radius: float = field_radius * goal_flag_radius_fraction
	for i: int in range(wanted):
		var angle: float = TAU * float(i) / float(wanted)
		positions.append(Vector2(cos(angle) * ring_radius, sin(angle) * ring_radius))
	return positions
