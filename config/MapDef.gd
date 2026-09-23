class_name MapDef
extends Resource
## One map's size, shape and layout (spec 2.1, 2.2, 3.3). M1 only needed the
## round field and its radius; M2 adds the cell grid the holes are cut from,
## the territory texture resolution, and where the home and goal flags sit.
## Later map variants (oval, ring, twin, cross) reuse the same scale.

## Spec 2.8's "Map size S/M/L". The enum lives here rather than on
## MatchConfig so that MapDef never has to reference MatchConfig, which would
## make the two classes cyclic (MatchConfig already reaches the other way to
## resolve its map).
enum MapSize { SMALL, MEDIUM, LARGE }

const RADIUS_SMALL: float = 30.0
const RADIUS_MEDIUM: float = 45.0
const RADIUS_LARGE: float = 60.0

## Spec 3.3: the territory texture is territory_res x territory_res, 256 for
## S, 384 for M, 512 for L.
const TERRITORY_RES_SMALL: int = 256
const TERRITORY_RES_MEDIUM: int = 384
const TERRITORY_RES_LARGE: int = 512

@export var id: StringName = &"round_medium"
@export var field_radius: float = RADIUS_MEDIUM

## Which placeholder six-face skybox set (config/SkyboxConfig.gd, game/Skybox.gd)
## this map loads at match start. A name with no matching
## assets/original/textures/<set> folder installed just falls back to the
## existing ProceduralSkyMaterial (see Skybox.load_set()), so this is safe to
## set even where the owner hasn't installed the original textures locally.
@export var skybox_set: String = "beach"

## Thickness of the disk. Field builds its collision and mesh from this.
##
## DECISION (config/MapDef.gd, Bontago-xtq.6, owner 2026-09-23: "the glass
## disk is quite thick... looks like the blocks are hovering"): lowered from
## 1.0 to 0.2 m -- a thin slab a 1 m block visibly rests ON rather than IN.
## Every reader of this field already scales with it (game/Field.gd's hole/
## rim wall depth and overlay y-offset, game/TerritoryOverlay.gd's CylinderMesh
## height), so nothing needed a second, decoupled tunable to keep the old
## depth: a shallower guide wall still pushes a block sliding into a hole off
## to the side before it clears the wall's bottom edge and free-falls, the
## same behaviour test_a_block_over_a_lone_hole_cell_falls_through
## (tests/unit/test_field_cells.gd) pins with its own fixture MapDef. Interim
## fix per the owner's note ("we'll work more on the design in m7"); not art
## direction.
@export var disk_height: float = 0.2

## Spec 3.3: the disk's collision is a square grid of BoxShape3Ds of this
## edge length, clipped to the disk. One cell is also one pixel of the
## authoritative territory raster (see docs/M2_PLAN.md, "Raster resolution").
@export var cell_size: float = 1.0

## Spec 3.3: the size of the ImageTexture handed to territory.gdshader. The
## cell-resolution raster is upscaled to this before upload, so the shader's
## bilinear sampling and smoothstep have something smooth to work with.
@export var territory_res: int = TERRITORY_RES_MEDIUM

## Spec 2.2: home flags sit at 0.85 * field_radius, spaced evenly around the
## edge; extra goal flags are placed symmetrically at 0.4 * field_radius.
@export var home_flag_radius_fraction: float = 0.85
@export var goal_flag_radius_fraction: float = 0.4

## Spec 3.3: "Wake up any sleeping blocks above cells that change state."
## How far above the disk surface Field's wake query reaches, in meters —
## tall enough to cover any tower this map can realistically carry. It is a
## physics-query extent rather than a rule number, so it lives with the map's
## other geometry instead of in TerritoryTuning.
@export var cell_wake_height: float = 60.0
## Upper bound on bodies one cell's wake query reports. A cell is 1 m square,
## so even a dense tower puts only a handful of blocks over it.
@export var cell_wake_max_bodies: int = 32

## HISTORICAL (Bontago-ruw, 2026-09-22): Field no longer reads this. The disk
## surface is now one ConcavePolygonShape3D trimesh (two triangles per solid
## cell, an exact opening per hole cell), so there are no per-cell boxes to
## grow and a lone hole is a full cell wide. The 0.2 m value used to be the
## load-bearing fix for a tower that leaned 0.78 m on per-cell boxes; the real
## cause of that lean was Jolt's body-pair contact cache reusing stale
## contacts inside a slowly creeping column (see the
## body_pair_contact_cache_distance_threshold DECISION in
## tools/bootstrap_project.gd and Beads Bontago-ddz), which made the result
## depend on body creation order. Kept only so saved .tres files still load.
@export var cell_overlap: float = 0.2


## The MapDef for a MatchConfig.MapSize value. Round maps only for M2; the
## other variants from spec 2.1 arrive in M6.
static func for_size(size: MapSize) -> MapDef:
	match size:
		MapSize.SMALL:
			return load("res://config/maps/round_small.tres") as MapDef
		MapSize.LARGE:
			return load("res://config/maps/round_large.tres") as MapDef
		_:
			return load("res://config/maps/round_medium.tres") as MapDef


## Number of cells along one edge of the square grid that covers the disk.
func cells_per_side() -> int:
	return int(ceil(2.0 * field_radius / maxf(cell_size, 0.001)))


## Spec 2.2: "Each player's home flag sits at 0.85 * field_radius, spaced
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
	return Vector2(cos(angle), sin(angle)) * field_radius * home_flag_radius_fraction


## Spec 2.2: "1 goal flag in the center by default. Setup allows 1-5. Extra
## flags are placed symmetrically at 0.4 * field_radius."
##
## DECISION (config/MapDef.gd): the spec does not say whether a multi-flag
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
		positions.append(Vector2(cos(angle), sin(angle)) * ring_radius)
	return positions
