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

## Thickness of the disk. Field builds its collision and mesh from this.
@export var disk_height: float = 1.0

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
