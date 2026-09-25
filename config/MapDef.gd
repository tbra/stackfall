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

## Spec 2.1's five map shapes. Ordinals match MatchConfig.MapVariant's own
## ROUND/OVAL/RING/TWIN/CROSS exactly (config/MatchConfig.gd:11) so
## for_variant_and_size() below can take that enum's raw int value without
## importing MatchConfig itself (see this file's own cycle note above
## for_size()).
enum MapShape { ROUND, OVAL, RING, TWIN, CROSS }

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

## Spec 2.1: "Round (default), Oval, Ring ..., Twin ..., and Cross." ROUND
## keeps shape_test() (below) empty so CellGrid's plain circle test is the
## only membership check every existing map already relies on; the other
## four are the map-shape mechanism this package adds, with no rule reading
## a shape by name -- only shape_contains()/shape_test() below and the
## flag-position overrides on this file know map_shape exists at all.
@export var map_shape: MapShape = MapShape.ROUND
## Oval: ellipse aspect ratio (x-radius = field_radius, z-radius = field_radius * oval_aspect).
@export var oval_aspect: float = 0.65
## Ring: no-disk hole in the middle, and the single goal flag sits on a bridge (spec 2.1).
@export var ring_hole_radius_fraction: float = 0.35
@export var ring_bridge_half_width: float = 3.0
## Twin: two same-size disks centered on +/-x, joined by a bridge.
## DECISION (config/MapDef.gd, orchestrator 2026-09-25, review fix for
## Bontago-keo.2): field_radius is the universal outer bound for every shape
## -- the cell grid, kill plane, overlay and shape_contains()'s own top guard
## all size from it and stay unchanged; each variant's geometry lives inside
## that circle. TWIN's two sub-disks can therefore not each be a full
## field_radius disk (a home flag at 1.65 * field_radius would sit outside
## the bounding circle) -- they are smaller disks inside it instead, each
## twin_disk_radius_fraction * field_radius, centered at
## +/-twin_center_offset_fraction * field_radius on x. Invariant this package
## keeps: twin_center_offset_fraction + twin_disk_radius_fraction <= 1.0, so
## neither sub-disk's own far edge crosses the outer bounding circle.
@export var twin_disk_radius_fraction: float = 0.55
@export var twin_center_offset_fraction: float = 0.45
@export var twin_bridge_half_width: float = 3.0
## Cross: four arms this wide (fraction of field_radius) cut from a square bound.
@export var cross_arm_half_width_fraction: float = 0.4

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


## The map-shape mechanism (spec 2.1, interface stub for A2a/A2b's data
## packages): true where `local` (disk-local (x, z), CellGrid's own
## convention) is solid ground for this map's `map_shape`. Every shape first
## rejects anything outside the field_radius bounding circle -- CellGrid's
## own is_in_disk() already gates on that circle before ever consulting
## shape_test() below, so this repeats it rather than relying on the caller,
## which keeps shape_contains() itself a complete, self-contained predicate a
## test (or a future renderer) can call directly with no CellGrid in hand.
func shape_contains(local: Vector2) -> bool:
	if local.length_squared() > field_radius * field_radius:
		return false
	match map_shape:
		MapShape.OVAL:
			var z_radius: float = field_radius * oval_aspect
			return (
				(local.x * local.x) / (field_radius * field_radius)
				+ (local.y * local.y) / (z_radius * z_radius)
			) <= 1.0
		MapShape.RING:
			# DECISION (config/MapDef.gd): the hole itself is a plain
			# annulus -- ring_bridge_half_width only shapes the goal flag's
			# override position below (goal_flag_positions()), not a break
			# cut through the hole here. A literal bridge deck crossing the
			# void is a rendering/geometry detail spec 2.1 does not specify
			# further ("[NEW], based on the planned 2.0 feature"); the
			# simplest reading that still keeps the hole a real hole (no
			# rule concern: nothing but the single center goal needed to
			# move off it) is this annulus, with the flag itself relocated
			# onto solid ground just past the hole's edge.
			var hole_radius: float = field_radius * ring_hole_radius_fraction
			return local.length_squared() > hole_radius * hole_radius
		MapShape.TWIN:
			var offset: float = twin_center_offset_fraction * field_radius
			var disk_radius: float = twin_disk_radius_fraction * field_radius
			if local.distance_squared_to(Vector2(-offset, 0.0)) <= disk_radius * disk_radius:
				return true
			if local.distance_squared_to(Vector2(offset, 0.0)) <= disk_radius * disk_radius:
				return true
			return absf(local.y) <= twin_bridge_half_width
		MapShape.CROSS:
			var half_width: float = field_radius * cross_arm_half_width_fraction
			return absf(local.y) <= half_width or absf(local.x) <= half_width
		_:
			return true


## Callable form of shape_contains(), consulted by CellGrid.is_in_disk()
## (core/territory/CellGrid.gd) only when non-empty. ROUND returns an empty
## Callable so every existing map keeps CellGrid's plain circle test as its
## only membership check, byte-identical to before this package.
func shape_test() -> Callable:
	if map_shape == MapShape.ROUND:
		return Callable()
	return Callable(self, "shape_contains")


## The MapDef for a MatchConfig.MapVariant + MapSize pair. `variant` is that
## raw int/enum-compatible value (MapDef cannot import MatchConfig -- see the
## note above MapSize) rather than MapShape itself, but the two enums'
## ordinals match exactly (this file's own MapShape doc comment), so `variant
## as MapShape` below is always a valid member. ROUND returns for_size(size)
## unchanged -- byte-identical to every caller that only ever passed a size
## before this package existed.
static func for_variant_and_size(variant: int, size: MapSize) -> MapDef:
	if variant == MapShape.ROUND:
		return for_size(size)
	var result: MapDef = for_size(size).duplicate(true) as MapDef
	result.map_shape = variant as MapShape
	return result


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
	# DECISION (config/MapDef.gd): TWIN and CROSS override the shared
	# circular-fraction formula below -- the one every other variant
	# (ROUND/OVAL/RING) still reuses unchanged -- because a single circle at
	# home_flag_radius_fraction * field_radius can land in TWIN's own gap
	# between its two sub-disks (each smaller than field_radius -- see the
	# twin_disk_radius_fraction/twin_center_offset_fraction DECISION above)
	# or straddle CROSS's own arms rather than sit on solid ground. Spec 2.1
	# names the five shapes but gives no interior layout for any of them
	# ("[NEW], based on the planned 2.0 feature"), so this is the simplest
	# symmetric reading for each, not a rule concern.
	if map_shape == MapShape.TWIN:
		var offset: float = twin_center_offset_fraction * field_radius
		var disk_radius: float = twin_disk_radius_fraction * field_radius
		var side: float = -1.0 if index % 2 == 0 else 1.0
		var side_index: int = index / 2
		var side_count: int = maxi((count + 1) / 2 if side < 0.0 else count / 2, 1)
		var side_angle: float = TAU * float(side_index) / float(side_count)
		var center: Vector2 = Vector2(side * offset, 0.0)
		# home_flag_radius_fraction < 1.0 keeps this inside its own sub-disk
		# (radius disk_radius), which shape_contains()'s TWIN branch tests.
		return center + Vector2(cos(side_angle), sin(side_angle)) * disk_radius * home_flag_radius_fraction
	if map_shape == MapShape.CROSS:
		var arm: int = index % 4
		var lap: int = index / 4
		var lap_radius: float = field_radius * home_flag_radius_fraction * (1.0 - 0.15 * float(lap))
		var arm_angle: float = TAU * float(arm) / 4.0
		return Vector2(cos(arm_angle), sin(arm_angle)) * lap_radius
	# DECISION (config/MapDef.gd, review fix for Bontago-keo.2): OVAL scales
	# the shared circular-fraction formula's z component (Vector2.y here) by
	# oval_aspect so a slot near the z-axis (e.g. (0, 0.85 * field_radius))
	# still lands inside the ellipse instead of past its shorter axis --
	# same pattern as the TWIN/CROSS overrides above, kept as a fall-through
	# on the identical angle math rather than a separate branch.
	var angle: float = TAU * float(index) / float(count)
	var z_scale: float = oval_aspect if map_shape == MapShape.OVAL else 1.0
	return Vector2(
		cos(angle) * field_radius * home_flag_radius_fraction,
		sin(angle) * field_radius * home_flag_radius_fraction * z_scale
	)


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
	# DECISION (config/MapDef.gd): Ring's own MapShape.RING branch overrides
	# only the single-goal case -- the plain center flag (below) would sit
	# inside Ring's own hole (shape_contains() rejects it) -- putting the
	# sole goal on the bridge instead: just past the hole's edge, on solid
	# ground, at ring_hole_radius_fraction * field_radius plus the bridge's
	# own half-width. A count above one falls through to the shared ring
	# formula unchanged: goal_flag_radius_fraction (0.4 by default) already
	# keeps every extra goal outside ring_hole_radius_fraction's smaller
	# hole for every real map size this package ships, so those flags never
	# need their own override. Cross reuses this same shared formula for
	# every goal count, including one (an extra goal ring still makes sense
	# inscribed in the cross); only its home flags move to the arm tips
	# (home_flag_position() above).
	if map_shape == MapShape.RING and wanted == 1:
		var bridge_radius: float = field_radius * ring_hole_radius_fraction + ring_bridge_half_width
		positions.append(Vector2(bridge_radius, 0.0))
		return positions
	if wanted == 1:
		positions.append(Vector2.ZERO)
		return positions
	# DECISION (config/MapDef.gd, review fix for Bontago-keo.2): TWIN's own
	# ring at goal_flag_radius_fraction can fall in the bridge gap between
	# its two sub-disks (e.g. straight up the z-axis), same failure as the
	# home flags before the fix above -- so a wanted-above-one TWIN layout
	# distributes goals across both sub-disks with the same side-splitting
	# math home_flag_position() uses, at goal_flag_radius_fraction of the
	# sub-disk's own radius from its centre. wanted == 1 (handled above)
	# stays the plain center flag: the origin sits inside both sub-disks
	# whenever twin_center_offset_fraction <= twin_disk_radius_fraction.
	if map_shape == MapShape.TWIN:
		var offset: float = twin_center_offset_fraction * field_radius
		var disk_radius: float = twin_disk_radius_fraction * field_radius
		for i: int in range(wanted):
			var side: float = -1.0 if i % 2 == 0 else 1.0
			var side_index: int = i / 2
			var side_count: int = maxi((wanted + 1) / 2 if side < 0.0 else wanted / 2, 1)
			var side_angle: float = TAU * float(side_index) / float(side_count)
			var center: Vector2 = Vector2(side * offset, 0.0)
			positions.append(
				center + Vector2(cos(side_angle), sin(side_angle)) * disk_radius * goal_flag_radius_fraction
			)
		return positions
	var ring_radius: float = field_radius * goal_flag_radius_fraction
	# OVAL scales the shared ring's z component (Vector2.y here) by
	# oval_aspect for the same reason home_flag_position() does above --
	# see that DECISION note.
	var z_scale: float = oval_aspect if map_shape == MapShape.OVAL else 1.0
	for i: int in range(wanted):
		var angle: float = TAU * float(i) / float(wanted)
		positions.append(Vector2(cos(angle) * ring_radius, sin(angle) * ring_radius * z_scale))
	return positions
