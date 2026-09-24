class_name GhostPreview
extends Node3D
## The non-physics held block (spec 2.5): floats at a height PlayerController
## reports (the disk surface plus hover_height plus the wheel's manual
## offset, Bontago-mv0.17 item 5 — never whatever is directly underneath the
## cursor), with a projected footprint (one convex polygon for the *whole*
## rotated held shape's silhouette, item 6, Bontago-xtq.7) showing exactly
## what it would land on.
##
## Bontago-mv0.25 (docs/rotation-issue.png, owner test 2026-09-22): the old
## drop-shadow quad under the ghost is gone -- the footprint is now the only
## ground marker (see config/GhostTuning.gd's DECISION). The footprint quad
## used to always be an axis-aligned unit square whose *position* tracked the
## rotated shape but whose *shape* never did; it is now a real convex polygon
## built from the rotated shape's own corners projected to the XZ plane
## (Geometry2D.convex_hull), rebuilt every frame alongside its position.
##
## Bontago-xtq.7 (docs/solid-blocks2-issue.png, owner test 2026-09-23, "the
## ghost blocks are still clearly made up of smaller blocks ... I can see the
## internal dividers inside the ghost blocks and the preview is also clearly
## the smaller blocks footprints ... in the original the ghost block projects
## its whole shape downwards to the disc"): two independent fixes.
## (1) The "dividers" were never geometry -- BlockMeshBuilder already emits
## one seamless shell per shape with interior faces removed (game/
## BlockFactory.gd, Bontago-xtq.3/xtq.5) -- they were this material's own
## CULL_DISABLED: with alpha blending (no depth write) and both faces drawn,
## every triangle on the *far* side of the shape bled through the near side
## in emission order (not camera depth order), so the far shell's own face
## seams (a bar's side is several coplanar-but-separate quads, one per cell --
## BlockMeshBuilder never merges them) painted visible lines across the near
## face. _material is now CULL_BACK (front faces only): a translucent solid
## has nothing to bleed through, and no other project code ever relied on
## seeing the ghost's inside (the winding-order bug CULL_DISABLED used to
## paper over, BlockMeshBuilder's own header, was fixed independently at
## Bontago-xtq.5).
## (2) The footprint was one polygon *per bottom cell*, so a shape whose cells
## span different heights underneath it (e.g. a tilted bar with its middle
## cell over a placed tower and its ends over the bare disc) showed a broken-
## up set of footprints at different heights instead of one whole-shape
## marker -- and had no vertical "this is the volume in between" cue at all,
## unlike the original's own translucent silhouette prism reaching from the
## held shape straight down to the disc. _update_footprint() now computes one
## convex hull of *every* rotated cell's corners (not per cell), shows it
## flat on the disc surface exactly as before (landing_y from a disk-only
## raycast that skips placed blocks, matching PlayerController's own surface
## probe -- never a tower's top), and adds a second, separate mesh
## (_projection_mesh): the same hull extruded as vertical walls from the
## ghost's own current lowest point down to that same disc height, so the
## whole rotated silhouette reads as one solid prism the way the original
## does, regardless of what is directly underneath any one part of it.
##
## Bontago-xtq.9 (owner test 2026-09-23, "the ghost block should be a bit more
## opaque. the preview starts from the bottom of the ghost block which looks
## a bit weird when it's angled."): two independent fixes on top of xtq.7's.
## (1) Every valid/state tint's own alpha (tint_color, invalid_tint_color,
## hole_tint_color, locked_tint_color) raised from ~0.55-0.65 to 0.75 --
## config/GhostTuning.gd's own DECISIONs, not this file.
## (2) The projection prism's top cap used to sit at the rotated shape's own
## *lowest* point (_rotated_bottom_offset(), matching where the shape's
## underside rests on the cursor height) -- correct for an unrotated shape
## (whose lowest point already reads as "the bottom"), but for a pitched or
## yawed shape that point is no longer anywhere near the shape's own top, so
## the prism visibly cut through the middle of an angled ghost instead of
## surrounding it. _update_projection_mesh() now caps the prism at the
## rotated shape's own *highest* point instead (_rotated_top_offset(), a new
## sibling of _rotated_bottom_offset() below), so the column always reaches
## from the disc up past the whole ghost, at any rotation -- the ghost sits
## fully inside the column exactly like the original's own silhouette
## (docs/original_single-block.png, docs/original_stacked-tower.png), not
## just its lower half.
## DECISION (game/GhostPreview.gd, Bontago-xtq.9): _rotated_top_offset() uses
## the *visual* mesh's own full cube_size (matching BlockMeshBuilder.
## build_mesh()'s own `half: float = cube_size * 0.5`, core/blocks/
## BlockMeshBuilder.gd), not _rotated_bottom_offset()'s cube_margin-shrunk
## collision half_size -- the prism's job is to visually contain the
## *rendered* shape, so it should match the rendered shape's own true extent
## exactly rather than the (deliberately smaller, so blocks don't jam)
## physics box _rotated_bottom_offset() measures for placement.
##
## Bontago-xtq.10 (owner test 2026-09-23, "the projection colour is right but
## any surface that falls within the projection should be a lot brighter
## (maybe emissive?), and the footprint on the disc should be almost white."):
## two more independent fixes, both purely visual.
## (1) The flat footprint decal (_footprint_color_for_state()) is now
## ghost_tuning.footprint_base_color (near-white) with only a faint amount of
## the current validity state's own hue blended in
## (ghost_tuning.footprint_hue_strength), at a higher footprint_alpha (0.55 ->
## 0.85) -- previously it was the *same* full state colour the held shape's
## own body shows, just more transparent, so it never read as the original's
## own bright ground marker.
## (2) The projection prism's own material (_projection_material) now blends
## additively (BaseMaterial3D.BLEND_MODE_ADD, _ready()) and emits its own
## light (emission_enabled, driven every refresh by
## ghost_tuning.projection_emission_energy in _apply_projection_material())
## instead of the usual alpha-over translucency -- a surface seen through the
## column now brightens instead of just being tinted over, matching the
## brief's own "a lot brighter (maybe emissive?)" wording. DECISION
## (game/GhostPreview.gd, Bontago-xtq.10): a per-block emission hook on
## BlockFactory/Block.gd (outside this package's default ownership) was
## considered and rejected in favour of this material-only change -- it
## reaches the same brightening effect with no gameplay-code touch at all,
## confined entirely to this file/config/GhostTuning.gd.
##
## Bontago-xtq.16 (owner playtest 2026-09-23, "the projection column [is]
## visible above the actual cells (S-piece)"): xtq.9's single whole-hull prism
## (capped at the whole shape's own *highest* point, walled by the whole
## shape's own *convex* hull) reads wrong for any non-convex shape -- config/
## blocks/S4.tres has a cell at (0, 1, 0) with nothing at (0, 0, 0) beneath it,
## so the old convex-hull column drew a lit shaft over that empty notch too,
## reaching all the way up to the *other* column's own top -- exactly "a
## projected piece above the actual block". Correct model (docs/original_
## hover-preview.png, original_stacked-tower.png): the shaft is per silhouette
## column, reaching only from the disc up to the *underside of the lowest
## solid cell sitting over that column* -- nothing is ever drawn beside or
## above a solid cell, and a column with no cell in it draws nothing at all.
## _update_projection_mesh() now groups `_shape.cells` by their own rotated XZ
## footprint centre (_group_cells_by_footprint(), merging cells that land on
## the same column -- an unrotated or yaw-only stack -- so the column caps at
## the *lowest* member's own underside, never a higher member's) and builds
## one prism wall per surviving column (_append_prism_walls(), appended into
## one shared mesh/surface since they all share _projection_material already).
## DECISION (game/GhostPreview.gd, Bontago-xtq.16): a pitched/rolled shape's
## cells generically rotate to distinct XZ centres (no merging occurs), so the
## same grouping code doubles as "one column per cell" for that case with no
## extra branch -- exactly the brief's own "for axis-aligned yaw this is per
## cell column; for pitched/rolled ghosts use the rotated cell AABBs" split,
## reached by one algorithm rather than two. Overlapping columns (a cell whose
## own prism wall happens to pass behind/through another cell's solid body,
## e.g. every member of a merged stack below the top one) are accepted rather
## than trimmed -- _projection_material already blends additively/translucent,
## so an overlap reads as "a bit brighter there", never as a visible seam.
## projection_span_y() itself is untouched (still the *whole* shape's own
## highest point down to the disc) -- game/PlayerController.gd's own
## _pending_spawn_top_y (outside this package's ownership) reads exactly that
## contract for spawn clearance, unrelated to how the prism's own walls are
## now built.
##
## Bontago-xtq.13 (owner playtest 2026-09-23, "ghost block should still be
## less transparent -> add a slider for it in the F4 menu"): every state
## tint's own RGB is unchanged, but _apply_validity_material() now applies
## ghost_tuning.ghost_opacity as the material's alpha in every branch instead
## of each colour's own baked-in alpha channel, so one F4 slider (config/
## GhostTuning.gd) controls every state's opacity together.
##
## Bontago-xtq.15 (owner playtest 2026-09-23, "the same white projection that
## shows up on the disk should show up on the blocks as well, just a bit
## fainter"): a Decal (_block_projection_decal), sized/positioned over the
## footprint hull's own world-space bounding box every frame
## (_update_block_projection_decal()), projects ghost_tuning.
## block_projection_color/_alpha straight down from the ghost's own current
## underside to the disc -- a real placed block sitting in that gap now reads
## pale/whitish (docs/original_hover-preview.png), not just the disc's own
## footprint quad. See _update_block_projection_decal()'s own DECISION for why
## cull_mask is left at its default rather than restricted to placed blocks.
##
## Bontago-xtq.18 attempt 3 (feel8a, feedback/owner-noise-footprint.png, owner
## "none of the feel issues were fixed" on c50510c): the black/white speckle
## under the ghost was never the footprint quad, the hatch texture or the
## prism -- it was _block_projection_decal painting the *disc*.
## tools/screenshot_feel8a_footprint.gd evidence: the speckle survives hiding
## the footprint quad, the prism, the planar mirror, SSR, the sun's shadows and
## the ReflectionProbe one at a time (feel8a-before_bisect-*.png), and vanishes
## (241 -> 0 near-black pixels) the moment the decal stops reaching the disc
## (cull_mask 0, or cull_mask without DiscMirror.DISC_LAYER_BIT). The decal's
## box bottom sits exactly on the disc surface (landing_y) and both fades were
## 0.0: Godot's decal fade is pow(1 - |uv.y|, fade), and at the box's own
## bottom plane that is pow(0, 0) -- NaN on the GPU (exp2(0 * log2(0))) for
## every disc pixel whose interpolated height lands exactly on the plane,
## i.e. a per-pixel speckle, and a NaN stays black through the translucent
## footprint quad blended over it. Two fixes, _ready()/_update_block_
## projection_decal(): the decal's cull_mask drops DiscMirror.DISC_LAYER_BIT
## (the disc already has its own footprint quad; the decal is for placed
## blocks, xtq.15's own brief), and both fades are clamped above zero
## (ghost_tuning.block_projection_edge_fade) so no surface lying exactly on
## either box plane (a block face at the ghost's underside, the ghost's own
## lowest edge) can ever hit pow(0, 0) again.
##
## Bontago-xtq.19 attempt 2 (owner test 2026-09-24, screenshot_20260924_204137/
## 204154.png: "the segmented preview is not fixed" -- a pitched 4-long bar and
## a T-piece both still show internal vertical seams inside the prism).
## Attempt 1 (xtq.18) fixed the *S4* case (two adjacent columns' hulls sharing
## an edge in reverse) but never fixed the general case: _rotated_cell_
## footprint() computed each cell's own footprint as the convex hull of its
## *own* 8 rotated corners (top face *and* bottom face) projected to XZ. For a
## pure yaw (or identity) that hull always reduces to a simple rectangle
## exactly matching the cell's own side faces, so two grid-adjacent cells'
## hulls share an exact edge in reverse and xtq.18's float-epsilon match
## (_shared_edge_exists()) finds it. For *any* combined yaw+pitch (or roll),
## the projected shadow of a rotated cube is a hexagon, not a rectangle, whose
## edges generally do **not** correspond to the cube's own side faces at all
## (verified numerically: two grid-adjacent cells pitched 20 degrees and yawed
## 30 degrees produce two hexagons with no edge pair matching within any
## epsilon) -- both cells' full hexagonal shadows get walled independently,
## and their overlapping/crossing edges are exactly the "dark seams" the owner
## keeps seeing (this material blends additively, so a doubled wall reads
## *brighter*; a lone unmatched internal wall by contrast reads relatively
## *darker* against its doubled neighbours -- matching the screenshots).
## _group_cells_by_footprint()/_rotated_cell_footprint()/_shared_edge_exists()/
## _append_prism_walls() are removed outright rather than patched again: no
## amount of post-hoc float matching on independently-rotated per-cell hulls
## can be made robust, because the hulls themselves are the wrong shape once a
## cell is tilted.
## New model: build the footprint's outline in the shape's own *local*, pre-
## rotation frame, where adjacency between cells is an exact integer-grid
## question with no floating point in it at all (_local_footprint_columns()
## keys cells by their local (x, z) grid coordinate, ignoring y -- the same
## "column" concept xtq.16 already used, just computed before rotation instead
## of after it). An edge of one column's unit square is only ever emitted
## (_outline_edges_for_column()) when the neighbouring grid cell in that
## direction is *not* part of the shape -- a shared boundary between two
## occupied columns is structurally never emitted by either side, so there is
## nothing left to "match and skip": the internal walls this bug is about
## simply never exist in the first place, at any rotation. Each surviving
## outline edge's two local endpoints (at that column's own ceiling height --
## the underside of its lowest occupied cell, xtq.16's own cap) are then
## rotated by the ghost's *current* basis individually (_append_outline_wall())
## rather than the old code's single shared `top_y` scalar per column -- under
## a pitch/roll a locally-flat ceiling is a genuinely tilted plane in world
## space, so the wall's own top edge is allowed to slope between its two
## corners exactly the way the real rotated shape's surface does, instead of
## forcing a flat cap that no longer matches the tilted body above it.
## DECISION (game/GhostPreview.gd, Bontago-xtq.19): outline edges are emitted
## one grid-unit at a time (never merged into longer runs along a straight
## side -- a 1x4 bar's long side is 4 separate unit-length quads, not one), per
## the brief's own acceptance count (10 edges for bar4's 4 cells, not 16) --
## merging collinear runs would cut the triangle count further but buys
## nothing visually (abutting same-material quads with no gap or overlap
## already read as one seamless wall) and would add real complexity for no
## reported problem.
##
## Rotation is stored as an integer index over the 24 axis-aligned cube
## orientations (core/blocks/BlockOrientations.gd) plus a separate free-
## rotation quaternion layered on top. Resetting clears the quaternion and
## sets the index back to 0, so — unlike the original — rotation can never
## drift (spec 1.7, 2.5).
##
## M2 (spec 2.2, 2.5, docs/M2_PLAN.md P4) adds the placement-validity tint:
## player-colour when Match.preview_placement says VALID, red when it says
## OUTSIDE_TERRITORY/CONTESTED/OFF_DISK/EMPTY, and a hatched pattern over a
## HOLE. It also owns the visual side of a rejected placement (spec 2.2's
## "thrown off the map with a visible reject animation") and the auto-drop
## flash — both purely cosmetic; PlayerController decides *when* to play them.
##
## Territory v2 (docs/TERRITORY_V2_PLAN.md package C): a goal flag's no-build
## zone (Result.GOAL_ZONE) reads the same as HOLE — hatched, hole_tint_color —
## reusing the existing "can't build here" visual language rather than adding
## a fourth tint state or a new GhostTuning field.
##
## DECISION (game/GhostPreview.gd, Bontago-mv0.17 item 3 -- owner feel report
## "the ghost/body pivot is the block's middle"): this node's own origin
## (0, 0, 0) is BlockShape.bottom_center() of the *unrotated* shape (matching
## game/BlockFactory.gd's cell offsets), but rotation still happens about
## that same fixed local origin — after a 90-degree pitch/roll, that point is
## no longer the rotated shape's lowest point. update_placement() corrects
## for this every frame (_rotated_bottom_offset()) so the shape actually
## resting on the cursor's reported height is always the *rotated* one's
## lowest point, per the spec audit's "simplest correct behaviour" note,
## never the original's own "keep the block where it is and let it fall".
##
## Bontago-mv0.28 (owner test 2026-09-22, "when rotating the block the camera
## adjusts; lock the camera to the center of the box without messing up the
## bottom center"): rotation still swings this node's own fixed local origin
## around, which used to be what game/CameraRig.gd followed -- so a pitch/
## roll visibly dragged the camera's framing sideways even though the block
## itself should just spin in place. update_placement() now also re-centres
## this node's XZ so the *rotated* shape's own geometric centre (not the
## fixed origin) sits over the cursor (rotated_center_offset()), and
## game/PlayerController.gd's camera follow now tracks
## rotated_center_world() instead of this node's own global_position. The Y
## fix above is untouched: bottom_offset still measures from the same fixed
## origin, so the shape's rotated lowest point still lands exactly at the
## reported hover height.

const STATE_VALID: StringName = &"valid"
const STATE_INVALID: StringName = &"invalid"
const STATE_HOLE: StringName = &"hole"
const STATE_LOCKED: StringName = &"locked"
## M4 P2e (docs/M4_P2_PACKAGES.md P2e): shown while game/PlayerController.gd
## reports is_aiming_throw() true (show_throw_hint()) -- a distinct state
## from the placement-validity ones above since it says nothing about where
## the block would land, only that the current gesture is a throw in
## progress.
const STATE_THROW: StringName = &"throw"

const HATCH_TEXTURE_SIZE: int = 32

## Bontago-xtq.18 attempt 3 (this file's own header): the smallest decal fade
## exponent _update_block_projection_decal() ever applies. Not a look tunable
## (ghost_tuning.block_projection_edge_fade is): a structural floor, because a
## fade of exactly 0.0 makes Godot's pow(1 - |uv.y|, fade) evaluate pow(0, 0)
## (NaN, drawn black) on any surface lying exactly on the decal box's top or
## bottom plane.
const _MIN_DECAL_FADE: float = 0.0001

## Bontago-xtq.19: the 4 grid directions _outline_edges_for_column() checks
## for an occupied neighbour -- local (x, z) grid space, exact integers, so
## (unlike xtq.18's removed _EDGE_MATCH_EPSILON float comparison) there is no
## tolerance to tune here at all: two adjacent cells either share a face or
## they don't.
const _COLUMN_NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]

## Bontago-mv0.35: the group game/PlayerController.gd puts its own (local,
## player-driven) ghost in, so ui/HUD.gd can show that block's height
## (height_above_surface()) without a node path. Remote peers' ghosts
## (game/RemoteCursors.gd) are never in it.
const LOCAL_HELD_GROUP: StringName = &"local_held_ghost"

## The 8 corner signs of a unit box centred on its own local position, used by
## _rotated_bottom_offset() to find a rotated shape's true lowest point.
const _CORNER_SIGNS: Array[Vector3] = [
	Vector3(-1.0, -1.0, -1.0), Vector3(1.0, -1.0, -1.0), Vector3(-1.0, 1.0, -1.0), Vector3(1.0, 1.0, -1.0),
	Vector3(-1.0, -1.0, 1.0), Vector3(1.0, -1.0, 1.0), Vector3(-1.0, 1.0, 1.0), Vector3(1.0, 1.0, 1.0),
]

@export var tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
@export var ghost_tuning: GhostTuning = preload("res://config/ghost_tuning.tres")

var orientation_index: int = 0
var free_quaternion: Quaternion = Quaternion.IDENTITY
## Extra manual raise/lower on top of tuning.hover_height (hover_raise/lower).
var manual_hover_offset: float = 0.0

var _shape: BlockShape = null
var _shape_visual: Node3D = null
## Bontago-xtq.7: at most one entry now (the whole rotated shape's own convex
## hull, not one per bottom cell -- see this file's own header). Kept as an
## Array (not a single nullable MeshInstance3D) so _set_footprint_quad_count()
## and the footprint_quad_count()/footprint_quad_position() test contracts
## below stay unchanged in shape, just always 0 or 1 long now.
var _footprint_quads: Array[MeshInstance3D] = []
## World-space XZ polygon currently shown by the footprint quad at the same
## index -- kept alongside _footprint_quads so tests can check the actual
## projected shape, not just where its center landed.
var _footprint_polygons: Array[PackedVector2Array] = []
## Shared by every footprint quad (like _material is shared by every mesh of
## the held shape's own visual) so updating validity/lock state once repaints
## all of them.
var _footprint_material: StandardMaterial3D
## Bontago-xtq.7: the vertical prism connecting the held shape's own lowest
## point down to the footprint on the disc (this file's own header, fix 2) --
## a single persistent node (unlike the footprint quads, its mesh is rebuilt
## in place every frame rather than pooled/recreated, since there is always
## at most one).
var _projection_mesh: MeshInstance3D
var _projection_material: StandardMaterial3D
## For tests: the world-space Y span _projection_mesh currently covers (top,
## bottom) -- Vector2.ZERO (and no visible mesh) when nothing is held or the
## prism collapsed (top <= bottom; see _update_footprint()'s own guard).
var _projection_span_y: Vector2 = Vector2.ZERO
## Bontago-xtq.16: one (top_y, bottom_y) entry per surviving footprint column
## the prism mesh currently draws (see _local_footprint_columns(), Bontago-
## xtq.19) -- unlike
## _projection_span_y above (kept at the *whole* shape's own bookkeeping for
## game/PlayerController.gd's spawn-clearance contract), every entry here is
## capped at its own column's lowest solid cell, for tests to check the S4
## bug's own literal repro directly.
var _projection_columns: Array[Vector2] = []
## Bontago-xtq.7: the last disk-surface point PlayerController's own
## placed-block-skipping probe reported (update_placement()'s own
## `surface_point` argument), kept so _update_footprint()'s disk-under-the-
## hull-centre raycast has a same-frame fallback height (the ghost's own
## already-known landing height) for a shape wide enough to overhang the
## disk's edge at its own rotated centre. sync_remote_position() never
## updates this -- a remote peer's ghost has no local surface_point to store,
## so its footprint prism fallback (also never exercised: a remote ghost
## always shows a footprint sized from a surface point the *sending* peer
## already resolved) simply keeps whatever this last held, same as it held no
## fallback data at all before this field existed.
var _last_surface_point: Vector3 = Vector3.ZERO

var _material: StandardMaterial3D
var _hatch_texture: ImageTexture
var _player_color: Color = Color.WHITE
var _last_result: PlacementRules.Result = PlacementRules.Result.VALID
## Bontago-mv0.10 (spec 2.4/2.5): whether this slot's held piece was released
## early this interval and is now only being aimed/prepared -- see
## Match.is_release_locked(). Overrides the validity tint below whenever true,
## since the lock is about *when* the piece may drop, not *where* the ghost
## sits.
var _locked: bool = false
## M4 P2e: set by show_throw_hint(); wins over the validity tint (below
## _locked in priority -- see _apply_validity_material()) exactly the way
## _locked already wins over it, since "aiming a throw" is about the current
## gesture, not the landing spot show_throw_hint()'s caller never queried.
var _throw_hint_active: bool = false

## Bontago-xtq.15 (owner playtest 2026-09-23, "the same white projection that
## shows up on the disk should show up on the blocks as well, just a bit
## fainter"): projects ghost_tuning.block_projection_color downward over the
## whole footprint hull, from the ghost's own current underside down to the
## disc, so a placed block sitting in that gap reads pale/whitish like the
## disc's own footprint marker (docs/original_hover-preview.png). top_level
## (like _footprint_quads/_projection_mesh) so it never tilts with the ghost's
## own rotation. Persistent (like _projection_mesh) -- _update_block_
## projection_decal() rebuilds its size/position every frame rather than
## pooling/recreating it, since there is always at most one.
var _block_projection_decal: Decal

var _flash_tween: Tween
var _reject_tween: Tween
## Bontago-mv0.25 (docs/rotation-issue.png): a world-space offset added on top
## of update_placement()/sync_remote_position()'s own computed position every
## frame, animated by play_reject_animation()'s kick tween. World-space (not
## a rotated local offset like the old _shape_visual.position kick) so the
## kick direction never depends on the held block's current rotation.
var _reject_offset: Vector3 = Vector3.ZERO


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# DECISION (game/GhostPreview.gd, Bontago-xtq.7): CULL_BACK, not the old
	# CULL_DISABLED -- see this file's own header, fix (1). Front faces only,
	# so translucency reads as a solid surface instead of bleeding through to
	# the far side's own face seams.
	_material.cull_mode = BaseMaterial3D.CULL_BACK
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_material.uv1_triplanar = true

	_footprint_material = StandardMaterial3D.new()
	_footprint_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_footprint_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_footprint_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Bontago-xtq.18 (feedback/owner-noise-footprint.png): the footprint quad
	# is a near-ground-parallel decal viewed at a shallow grazing angle from
	# the match camera -- on top of _build_hatch_texture()'s own mipmap fix,
	# anisotropic filtering keeps the HOLE/GOAL_ZONE hatch's diagonal stripes
	# from re-aliasing at that angle the way plain trilinear filtering still
	# can. Harmless for every other state, which never assigns albedo_texture
	# here at all (_apply_footprint_material()).
	_footprint_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

	# Bontago-xtq.7 (this file's own header, fix (2)): the flat footprint
	# above stays CULL_DISABLED (a flat quad has no "back" a camera can't
	# already see straight through from below the disk, and it's viewed from
	# above), but the vertical prism's own walls are a convex hull's outer
	# surface -- CULL_DISABLED here on purpose too, unlike the shape's own
	# body, because a *convex* hull has no internal face seams to bleed
	# through (no adjacent-but-separate coplanar quads at cell boundaries the
	# way BlockMeshBuilder's per-cell shell has); double-siding it just lets
	# the far wall read faintly through the near one, exactly like the
	# original's own translucent legs (docs/original_in-game.png).
	_projection_material = StandardMaterial3D.new()
	_projection_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_projection_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_projection_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Bontago-xtq.10 (owner test 2026-09-23, "any surface that falls within
	# the projection should be a lot brighter (maybe emissive?)"): additive
	# blending sums the prism's own colour onto whatever already rendered
	# behind it instead of the usual alpha-over mix, so a surface seen
	# through the column reads brighter, not just tinted -- combined with
	# emission_enabled below (_apply_projection_material() drives both the
	# emission colour and ghost_tuning.projection_emission_energy every
	# refresh), matching the brief's own "additive blend / emission" wording.
	_projection_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_projection_material.emission_enabled = true

	_projection_mesh = MeshInstance3D.new()
	_projection_mesh.material_override = _projection_material
	_projection_mesh.top_level = true
	_projection_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_projection_mesh)

	# Bontago-xtq.15: a plain, fully-opaque white texture -- Decal has no
	# "flat colour, no texture" mode, so this is the runtime-built equivalent
	# of _footprint_material's own flat StandardMaterial3D.albedo_color,
	# tinted/faded through `modulate` instead (see
	# _update_block_projection_decal()). A tiny 2x2 image is enough: the
	# decal only ever stretches it across size.x/size.z, it is never sampled
	# for detail.
	_block_projection_decal = Decal.new()
	_block_projection_decal.texture_albedo = _build_white_decal_texture()
	_block_projection_decal.upper_fade = _decal_fade()
	_block_projection_decal.lower_fade = _decal_fade()
	# Bontago-xtq.18 attempt 3 (this file's own header): never paint the disc.
	# DiscMirror moves the disc onto DISC_LAYER_BIT alone, so removing that
	# bit from Decal's own default (all 20 layers) leaves placed blocks
	# (layer 1) painted and the disc -- whose box-bottom contact produced the
	# speckle -- untouched; the disc keeps its own footprint quad.
	_block_projection_decal.cull_mask = _block_projection_decal.cull_mask & ~DiscMirror.DISC_LAYER_BIT
	_block_projection_decal.top_level = true
	_block_projection_decal.visible = false
	add_child(_block_projection_decal)

	_hatch_texture = _build_hatch_texture()
	_refresh_materials()


func set_shape(shape: BlockShape) -> void:
	_shape = shape
	if _shape_visual != null:
		_shape_visual.queue_free()
		_shape_visual = null
	if shape == null:
		return
	_shape_visual = BlockFactory.build_visual_only(shape, tuning)
	add_child(_shape_visual)
	_apply_material_to_visual()


func get_shape() -> BlockShape:
	return _shape


func set_orientation_index(index: int) -> void:
	orientation_index = ((index % BlockOrientations.ORIENTATION_COUNT) + BlockOrientations.ORIENTATION_COUNT) % BlockOrientations.ORIENTATION_COUNT
	_apply_rotation()


func reset_rotation() -> void:
	orientation_index = 0
	free_quaternion = Quaternion.IDENTITY
	_apply_rotation()


## Bontago-mv0.22 (spec 2.5 "Rotate block (hold + drag)" [ORIGINAL, owner test
## 2026-09-22]): PlayerController calls this while rotate_drag (MMB) is held,
## driving free_quaternion continuously -- already the exact field
## submit_cursor/submit_place send unmodified over the wire, so no new
## replication path was needed.
##
## Bontago-mv0.25 (docs/rotation-issue.png, owner test 2026-09-22, "like the
## RMB orbit but for the block"): full 3-DOF now, not yaw-only -- `yaw` spins
## about world up (matching CameraRig's own orbit yaw), `pitch` spins about
## `pitch_axis` (PlayerController passes the camera's current world-space
## right axis, so pitching the block always matches "push the mouse forward
## and it tips away from you" regardless of which way the camera currently
## faces). Each axis is composed onto free_quaternion independently
## (`Quaternion(axis, angle) * free_quaternion`, normalised) rather than
## pre-combined into one delta quaternion, so a frame with only one axis of
## motion (the common case) never even nudges the other.
func apply_free_rotation_delta(yaw: float, pitch: float, pitch_axis: Vector3 = Vector3.RIGHT) -> void:
	if yaw != 0.0:
		free_quaternion = (Quaternion(Vector3.UP, yaw) * free_quaternion).normalized()
	if pitch != 0.0:
		free_quaternion = (Quaternion(pitch_axis, pitch) * free_quaternion).normalized()
	_apply_rotation()


func _apply_rotation() -> void:
	var base_basis: Basis = BlockOrientations.get_basis(orientation_index)
	basis = Basis(free_quaternion) * base_basis


## Called every frame by PlayerController with the disk surface point/normal
## straight under the cursor (Bontago-mv0.17 item 5: a raycast that skips
## over any placed block, so this is always the bare disk, tilt-ready via
## `hit_normal` for M4). Positions the ghost so the *rotated* held shape's
## lowest point sits at hover height above that surface (item 3's
## rotated-bounds pivot, Y only -- unchanged by Bontago-mv0.28 below), and so
## the *rotated* shape's own geometric centre column sits over the cursor's
## XZ (Bontago-mv0.28, owner report "lock the camera to the center of the box
## without messing up the bottom center" -- see rotated_center_offset()'s own
## doc comment), then refreshes the footprint projection (item 6).
func update_placement(surface_point: Vector3, surface_normal: Vector3) -> void:
	var hover: float = tuning.hover_height + manual_hover_offset
	var anchor: Vector3 = surface_point + surface_normal * hover
	var bottom_offset: float = _rotated_bottom_offset()
	var center_offset: Vector3 = rotated_center_offset()
	global_position = Vector3(
		anchor.x - center_offset.x, anchor.y - bottom_offset, anchor.z - center_offset.z
	) + _reject_offset
	_last_surface_point = surface_point
	_update_footprint()


## Bontago-mv0.35: how high the held shape's own lowest point hovers above
## the disk surface under it (the point update_placement() last received),
## in meters -- what the player is actually adjusting with the wheel. The
## HUD shows this next to the tower height, which alone never moved while
## the block was raised (the follow camera keeps the ghost centred on screen
## too), so a raise read as "stuck".
func height_above_surface() -> float:
	return global_position.y - _reject_offset.y + _rotated_bottom_offset() - _last_surface_point.y


## Positions this ghost at an already-fully-resolved world point, with no
## further hover/rotation-pivot math applied on top -- used by
## game/RemoteCursors.gd for a synced remote peer's ghost, whose `origin` is
## that peer's own already-adjusted GhostPreview.global_position (spec 3.4's
## update_cursor carries a resolved pose, not a surface to re-derive one
## from). Re-running it through update_placement()'s hover/rotated-bottom
## math a second time would double-apply the correction for any slot whose
## held shape isn't null (Bontago-mv0.17 items 3/5); this is the one-line fix
## that keeps game/RemoteCursors.gd correct against the changed
## update_placement() contract above.
func sync_remote_position(origin: Vector3) -> void:
	global_position = origin + _reject_offset
	_update_footprint()


# --- Rotated-bottom pivot correction (spec 2.5, Bontago-mv0.17 item 3) ------

## How far below this node's own local origin (BlockShape.bottom_center() of
## the *unrotated* shape) the current, rotated shape's lowest point sits.
## Zero for an unrotated shape (the origin already is its lowest point); a
## 90-degree pitch/roll can put the true lowest point below (or, for a
## symmetric shape, level with) the origin, never above it, since the origin
## itself is always a point on the shape's own surface. Always <= 0.
func _rotated_bottom_offset() -> float:
	if _shape == null or _shape.cells.is_empty():
		return 0.0
	var half_size: float = (tuning.cube_size - tuning.cube_margin) * 0.5
	var pivot: Vector3 = _shape.bottom_center()
	var min_y: float = INF
	for cell: Vector3i in _shape.cells:
		var local: Vector3 = (Vector3(cell) - pivot) * tuning.cube_size
		for corner_sign: Vector3 in _CORNER_SIGNS:
			var corner: Vector3 = local + corner_sign * half_size
			var rotated_y: float = (basis * corner).y
			min_y = minf(min_y, rotated_y)
	return 0.0 if min_y == INF else min_y


## Bontago-xtq.9 (this file's own header, fix (2)): the mirror image of
## _rotated_bottom_offset() above -- how far *above* this node's own local
## origin the current, rotated shape's *highest* point sits, so
## _update_projection_mesh() can cap the projection prism there instead of at
## the shape's lowest point (correct for an unrotated shape, wrong for a
## pitched/yawed one -- this file's own header). Always >= 0 for the same
## reason _rotated_bottom_offset() is always <= 0: the origin itself is
## always a point on the shape's own surface.
## DECISION (game/GhostPreview.gd, Bontago-xtq.9): uses the *visual* mesh's
## own full cube_size (`half_size = tuning.cube_size * 0.5`, matching
## core/blocks/BlockMeshBuilder.gd's build_mesh()), not
## _rotated_bottom_offset()'s cube_margin-shrunk collision half_size -- the
## prism's job is to contain the *rendered* shape the player actually sees,
## so its top should match that shape's true rendered extent, not the
## slightly smaller physics box.
func _rotated_top_offset() -> float:
	if _shape == null or _shape.cells.is_empty():
		return 0.0
	var half_size: float = tuning.cube_size * 0.5
	var pivot: Vector3 = _shape.bottom_center()
	var max_y: float = -INF
	for cell: Vector3i in _shape.cells:
		var local: Vector3 = (Vector3(cell) - pivot) * tuning.cube_size
		for corner_sign: Vector3 in _CORNER_SIGNS:
			var corner: Vector3 = local + corner_sign * half_size
			var rotated_y: float = (basis * corner).y
			max_y = maxf(max_y, rotated_y)
	return 0.0 if max_y == -INF else max_y


## Bontago-mv0.28 (owner report 2026-09-22, "when rotating the block the
## camera adjusts; lock the camera to the center of the box without messing
## up the bottom center"): how far this node's own local origin (still
## BlockShape.bottom_center() of the *unrotated* shape) sits from the
## *rotated* held shape's own geometric centre, in world space. The
## unrotated centre-to-origin vector is always purely vertical -- the AABB
## centre of `cells` shares bottom_center()'s own X/Z (both are the same cell
## bounds' midpoint by construction, whatever shape the cells happen to
## trace), so only Y ever differs before rotation -- so a yaw-only rotation
## (about world/local up) never moves this in XZ, while a pitch/roll tips
## that vertical offset sideways exactly as update_placement() needs to keep
## the *rotated* shape's centre, not this fixed local origin, under the
## cursor. Zero for a shape with no cells and when nothing is held (global_
## position itself is then already the only sensible "centre").
func rotated_center_offset() -> Vector3:
	if _shape == null or _shape.cells.is_empty():
		return Vector3.ZERO
	var pivot: Vector3 = _shape.bottom_center()
	var min_local: Vector3 = Vector3(INF, INF, INF)
	var max_local: Vector3 = Vector3(-INF, -INF, -INF)
	for cell: Vector3i in _shape.cells:
		var local: Vector3 = (Vector3(cell) - pivot) * tuning.cube_size
		min_local.x = minf(min_local.x, local.x)
		min_local.y = minf(min_local.y, local.y)
		min_local.z = minf(min_local.z, local.z)
		max_local.x = maxf(max_local.x, local.x)
		max_local.y = maxf(max_local.y, local.y)
		max_local.z = maxf(max_local.z, local.z)
	var center_local: Vector3 = (min_local + max_local) * 0.5
	return basis * center_local


## The rotated held shape's own geometric centre, in world space -- what
## game/CameraRig.gd's follow target should track instead of this node's own
## origin (see rotated_center_offset()'s doc comment) so orbiting/pitching the
## block spins it in place instead of visibly swinging the camera's framing.
## Falls back to global_position itself (rotated_center_offset() is then
## Vector3.ZERO) when nothing is held, so callers never need a null check.
func rotated_center_world() -> Vector3:
	return global_position + rotated_center_offset()


# --- Footprint projection (spec 2.5, Bontago-mv0.17 item 6, Bontago-xtq.7) --

## The *whole* rotated held shape's own convex hull, projected onto the XZ
## plane, ghost-local (not yet world-translated): every cell's own 8 corners
## (BlockFactory's own cube_size/cube_margin box, same pivot) go through the
## full rotation basis, get projected to (x, z), and the convex hull of *all*
## of them together becomes the one footprint/projection polygon -- not one
## hull per cell (Bontago-xtq.7, docs/solid-blocks2-issue.png, this file's own
## header fix (2)): a shape's silhouette from directly above is one shape,
## however many cells or landing heights are underneath different parts of
## it.
func _rotated_shape_hull() -> PackedVector2Array:
	if _shape == null or _shape.cells.is_empty():
		return PackedVector2Array()
	var half_size: float = (tuning.cube_size - tuning.cube_margin) * 0.5
	var pivot: Vector3 = _shape.bottom_center()
	var points: PackedVector2Array = PackedVector2Array()
	for cell: Vector3i in _shape.cells:
		var local_center: Vector3 = (Vector3(cell) - pivot) * tuning.cube_size
		for corner_sign: Vector3 in _CORNER_SIGNS:
			var rotated_corner: Vector3 = basis * (local_center + corner_sign * half_size)
			points.append(Vector2(rotated_corner.x, rotated_corner.z))
	return Geometry2D.convex_hull(points)


## Rebuilds the footprint quad (0 or 1 -- see _rotated_shape_hull()'s own
## comment) and the vertical projection prism to match the current shape/
## rotation. Bontago-xtq.7: the footprint's own landing height now comes from
## a disk-only raycast (_raycast_disk_surface(), skipping any placed
## RigidBody3D -- the same technique game/PlayerController.gd's own surface
## probe uses to keep the ghost's *own* height off of towers, Bontago-mv0.17
## item 5) straight down from the hull's own centroid, so the marker always
## lands on the bare disc even when part of the held shape hovers over a
## placed block -- never that block's own top face, which the old per-cell
## raycast (against the unfiltered world) happily landed on. If nothing is
## under the hull's centroid (a wide shape overhanging the disk's edge), this
## falls back to the ghost's own already-known landing height (this file's
## `_last_surface_point`, set by update_placement() every frame) rather than
## leaving the marker with no floor at all.
func _update_footprint() -> void:
	var hull: PackedVector2Array = _rotated_shape_hull()
	if hull.size() < 3:
		_set_footprint_quad_count(0)
		_footprint_polygons.clear()
		_clear_projection_mesh()
		_hide_block_projection_decal()
		return

	_set_footprint_quad_count(1)
	_footprint_polygons.resize(1)

	var centroid: Vector2 = _polygon_centroid(hull)
	var world_x: float = global_position.x + centroid.x
	var world_z: float = global_position.z + centroid.y
	var probe_origin: Vector3 = Vector3(world_x, ghost_tuning.cursor_ray_height, world_z)
	var hit: Dictionary = _raycast_disk_surface(probe_origin)
	var landing_y: float
	var landing_normal: Vector3
	if hit.is_empty():
		landing_y = _last_surface_point.y
		landing_normal = Vector3.UP
	else:
		landing_y = (hit["position"] as Vector3).y
		landing_normal = hit["normal"] as Vector3

	_footprint_quads[0].global_position = Vector3(world_x, landing_y, world_z) + landing_normal * ghost_tuning.footprint_offset
	_footprint_quads[0].mesh = _build_polygon_mesh(hull, centroid)
	var world_hull: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in hull:
		world_hull.append(Vector2(global_position.x + point.x, global_position.z + point.y))
	_footprint_polygons[0] = world_hull

	_update_projection_mesh(landing_y)
	_update_block_projection_decal(world_hull, landing_y)


## Bontago-xtq.16 (this file's own header): `_projection_span_y` stays the
## *whole* shape's own bookkeeping (top = _rotated_top_offset(), untouched --
## game/PlayerController.gd's own spawn-clearance reads this contract), but
## the prism's actual mesh is now one wall per surviving footprint column
## (_local_footprint_columns()), each capped at that column's own lowest solid
## cell's underside instead of the whole shape's own highest point -- the fix
## for the S4 bug this package exists for (see this file's own header). A
## column collapses (drawn nothing) the same way the old single hull did: its
## own top within ghost_tuning.footprint_offset of the disc, or below it.
## Bontago-xtq.19 (this file's own header): columns and their outline edges
## are now built entirely in the shape's own *local*, pre-rotation grid
## (_local_footprint_columns()/_outline_edges_for_column()) -- no float
## comparison between independently-rotated per-cell hulls remains anywhere in
## this function, so there is nothing left for a combined yaw+pitch to break.
func _update_projection_mesh(landing_y: float) -> void:
	if _shape == null or _shape.cells.is_empty():
		_clear_projection_mesh()
		return

	var whole_top_y: float = global_position.y + _rotated_top_offset()
	if whole_top_y - landing_y <= ghost_tuning.footprint_offset:
		# The whole shape's own top is at or below the ground -- every column
		# below it would collapse too (a column's own cap is always <= the
		# whole shape's own top), so skip straight to the same "nothing to
		# show" state _clear_projection_mesh() already gives the no-shape-held
		# case, preserving projection_span_y()'s existing "Vector2.ZERO when
		# collapsed" contract (test_projection_prism_collapses_when_even_the_
		# shapes_own_top_is_at_the_ground).
		_clear_projection_mesh()
		return

	_projection_span_y = Vector2(whole_top_y, landing_y)
	_projection_columns.clear()
	_projection_mesh.global_position = Vector3(global_position.x, 0.0, global_position.z)

	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()

	# Bontago-xtq.18 (feedback/owner-noise-footprint.png): every wall bottoms
	# out at ghost_tuning.footprint_offset above `landing_y`, the same Y the
	# disc's own collision mesh sits at right there -- CULL_DISABLED (this
	# file's own _ready(), needed so the far wall of a column's own box reads
	# through the near one) has no way to prefer one coincident surface over
	# another, so sitting exactly on the disc Z-fights into visible noise.
	var wall_bottom_y: float = landing_y + ghost_tuning.footprint_offset
	var columns: Dictionary = _local_footprint_columns()
	for key: Vector2i in columns.keys():
		var min_cell_y: int = columns[key]
		var bounds: Dictionary = _column_local_bounds(key, min_cell_y)
		var top_y: float = _column_top_world_y(bounds)
		if top_y - landing_y <= ghost_tuning.footprint_offset:
			continue
		_projection_columns.append(Vector2(top_y, landing_y))
		for edge: Dictionary in _outline_edges_for_column(key, bounds, columns):
			_append_outline_wall(edge["a"], edge["b"], wall_bottom_y, verts, normals, uvs, indices)

	if verts.is_empty():
		_projection_mesh.mesh = null
		return

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var built: ArrayMesh = ArrayMesh.new()
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_projection_mesh.mesh = built


## Hides the projection prism (nothing held, or every column collapsed -- see
## _update_projection_mesh()'s own guard) without freeing the persistent node.
func _clear_projection_mesh() -> void:
	_projection_span_y = Vector2.ZERO
	_projection_columns.clear()
	if _projection_mesh != null:
		_projection_mesh.mesh = null


# --- Block projection decal (spec 2.5, Bontago-xtq.15) ----------------------

## Bontago-xtq.15 (owner playtest 2026-09-23, docs/original_hover-preview.png:
## a placed block inside the light shaft reads pale/whitish): sizes and
## positions `_block_projection_decal` over `world_hull`'s own bounding box
## (world-space X/Z, same hull _update_footprint() already built the flat
## footprint quad from), projecting straight down from the ghost's own
## current underside (_rotated_bottom_offset() -- deliberately *not* any
## higher, so the decal's own projection volume never overlaps the held
## ghost's own rendered body) down to `landing_y` (the footprint's own disc
## height). Bontago-xtq.18 attempt 3 supersedes xtq.15's original "painting
## the disc too is harmless" DECISION: it was not harmless (this file's own
## header) -- the disc lives on DiscMirror.DISC_LAYER_BIT since xtq.12, and
## _ready() now strips that bit from this decal's cull_mask.
func _update_block_projection_decal(world_hull: PackedVector2Array, landing_y: float) -> void:
	if _block_projection_decal == null:
		return
	var top_y: float = global_position.y + _rotated_bottom_offset()
	if top_y - landing_y <= 0.001:
		_hide_block_projection_decal()
		return

	var min_point: Vector2 = world_hull[0]
	var max_point: Vector2 = world_hull[0]
	for point: Vector2 in world_hull:
		min_point = Vector2(minf(min_point.x, point.x), minf(min_point.y, point.y))
		max_point = Vector2(maxf(max_point.x, point.x), maxf(max_point.y, point.y))
	var size_x: float = maxf(max_point.x - min_point.x, 0.01)
	var size_z: float = maxf(max_point.y - min_point.y, 0.01)
	var center_x: float = (min_point.x + max_point.x) * 0.5
	var center_z: float = (min_point.y + max_point.y) * 0.5

	_block_projection_decal.visible = true
	_block_projection_decal.upper_fade = _decal_fade()
	_block_projection_decal.lower_fade = _decal_fade()
	_block_projection_decal.size = Vector3(size_x, top_y - landing_y, size_z)
	_block_projection_decal.global_position = Vector3(center_x, (top_y + landing_y) * 0.5, center_z)
	_block_projection_decal.modulate = Color(
		ghost_tuning.block_projection_color.r, ghost_tuning.block_projection_color.g,
		ghost_tuning.block_projection_color.b, ghost_tuning.block_projection_alpha
	)


## Bontago-xtq.18 attempt 3: ghost_tuning.block_projection_edge_fade, never
## below _MIN_DECAL_FADE (see that constant for why zero is unsafe).
func _decal_fade() -> float:
	return maxf(ghost_tuning.block_projection_edge_fade, _MIN_DECAL_FADE)


## For tests: the decal's own cull mask and (upper, lower) fade exponents
## (Bontago-xtq.18 attempt 3 -- the disc layer must be excluded and both
## fades must stay above zero).
func block_projection_decal_cull_mask() -> int:
	return _block_projection_decal.cull_mask if _block_projection_decal != null else 0


func block_projection_decal_fades() -> Vector2:
	if _block_projection_decal == null:
		return Vector2.ZERO
	return Vector2(_block_projection_decal.upper_fade, _block_projection_decal.lower_fade)


## Hides the block-projection decal (nothing held, or the gap collapsed --
## see _update_block_projection_decal()'s own guard) without freeing the
## persistent node -- same idea as _clear_projection_mesh() just above.
func _hide_block_projection_decal() -> void:
	if _block_projection_decal != null:
		_block_projection_decal.visible = false


## For tests: whether the block-projection decal is currently shown.
func block_projection_decal_visible() -> bool:
	return _block_projection_decal != null and _block_projection_decal.visible


## For tests: the block-projection decal's own current world-space size
## (width, height, depth -- Decal.size's own axis order) and position.
func block_projection_decal_size() -> Vector3:
	return _block_projection_decal.size if _block_projection_decal != null else Vector3.ZERO


func block_projection_decal_position() -> Vector3:
	return _block_projection_decal.global_position if _block_projection_decal != null else Vector3.ZERO


## For tests: the block-projection decal's own current modulate colour (RGB
## from ghost_tuning.block_projection_color, alpha from
## ghost_tuning.block_projection_alpha -- see _update_block_projection_decal()).
func block_projection_decal_color() -> Color:
	return _block_projection_decal.modulate if _block_projection_decal != null else Color.WHITE


## A plain, fully-opaque white 2x2 texture -- Decal.texture_albedo needs a
## real Texture2D, and this project has no flat-colour art asset to spend on
## something `modulate` (see _update_block_projection_decal()) already tints
## and fades on its own; same runtime-built-texture idea as _build_hatch_
## texture() below.
func _build_white_decal_texture() -> ImageTexture:
	var image: Image = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 1.0))
	return ImageTexture.create_from_image(image)


## Bontago-xtq.19 (replaces the old rotated-hull _rotated_cell_footprint()):
## buckets `_shape.cells` by their own *local*, pre-rotation (x, z) grid
## coordinate (ignoring y) -- a "column" in the sense xtq.16 already used
## (several cells stacked at the same XZ merge into one), just computed
## before any rotation is applied instead of after it, so it needs no
## floating-point tolerance at all: two cells share a column iff their local
## x and z indices are literally equal. Value is the lowest cell.y among that
## column's members (the underside the column's own cap sits at, xtq.16's own
## "never above the lowest solid cell" rule).
func _local_footprint_columns() -> Dictionary:
	var columns: Dictionary = {}
	for cell: Vector3i in _shape.cells:
		var key: Vector2i = Vector2i(cell.x, cell.z)
		if columns.has(key):
			columns[key] = mini(columns[key], cell.y)
		else:
			columns[key] = cell.y
	return columns


## One column's own local (pre-rotation) unit-square bounds and ceiling
## height, in the same local space _rotated_bottom_offset()/_rotated_top_
## offset() already build corners in (ghost-local, not yet rotated). `ceiling_
## y` is the underside of the column's lowest cell (`min_cell_y`) -- the same
## visual half_size _rotated_top_offset() uses (this prism contains the
## *rendered* shape, not the shrunk collision box), matching xtq.9's own
## DECISION.
func _column_local_bounds(key: Vector2i, min_cell_y: int) -> Dictionary:
	var half_size: float = tuning.cube_size * 0.5
	var pivot: Vector3 = _shape.bottom_center()
	var local_center: Vector3 = (Vector3(key.x, min_cell_y, key.y) - pivot) * tuning.cube_size
	return {
		"x0": local_center.x - half_size, "x1": local_center.x + half_size,
		"z0": local_center.z - half_size, "z1": local_center.z + half_size,
		"ceiling_y": local_center.y - half_size,
	}


## Bontago-xtq.19: the column's own cap, in world space -- the minimum, over
## its own 4 local ceiling corners individually rotated by the ghost's current
## `basis`, of `global_position.y + rotated.y`. Deliberately per-corner (not a
## single rotated centre point): a locally-flat ceiling is a genuinely tilted
## plane once pitched/rolled, and taking the min of its 4 true corners is what
## keeps this "must never sit above the shape's own solid cell" (the S4/xtq.16
## contract every prior test already checks) exactly regardless of rotation --
## a single centre-point cap could sit *above* one of the tilted corners.
func _column_top_world_y(bounds: Dictionary) -> float:
	var ceiling_y: float = bounds["ceiling_y"]
	var corners: Array[Vector2] = [
		Vector2(bounds["x0"], bounds["z0"]), Vector2(bounds["x1"], bounds["z0"]),
		Vector2(bounds["x1"], bounds["z1"]), Vector2(bounds["x0"], bounds["z1"]),
	]
	var min_world_y: float = INF
	for corner: Vector2 in corners:
		var rotated: Vector3 = basis * Vector3(corner.x, ceiling_y, corner.y)
		min_world_y = minf(min_world_y, global_position.y + rotated.y)
	return min_world_y


## Bontago-xtq.19 (this file's own header -- replaces xtq.16/xtq.18's rotated-
## hull grouping and its own float-epsilon _shared_edge_exists()): the 4 local
## unit-square sides of `key`'s own column, one entry per side whose grid
## neighbour (`columns` -- the same dictionary _local_footprint_columns()
## returns) is *not* part of the shape. A side whose neighbour *is* present is
## a shared boundary between two occupied columns and is never emitted at
## all -- there is no post-hoc matching step left to get wrong, at any
## rotation. Each edge's two endpoints are local (ghost-local, pre-rotation)
## 3D points at the column's own ceiling height, ready for
## _append_outline_wall() to rotate individually.
func _outline_edges_for_column(key: Vector2i, bounds: Dictionary, columns: Dictionary) -> Array[Dictionary]:
	var edges: Array[Dictionary] = []
	var y: float = bounds["ceiling_y"]
	var x0: float = bounds["x0"]
	var x1: float = bounds["x1"]
	var z0: float = bounds["z0"]
	var z1: float = bounds["z1"]
	if not columns.has(Vector2i(key.x + 1, key.y)):
		edges.append({"a": Vector3(x1, y, z0), "b": Vector3(x1, y, z1)})
	if not columns.has(Vector2i(key.x - 1, key.y)):
		edges.append({"a": Vector3(x0, y, z1), "b": Vector3(x0, y, z0)})
	if not columns.has(Vector2i(key.x, key.y + 1)):
		edges.append({"a": Vector3(x1, y, z1), "b": Vector3(x0, y, z1)})
	if not columns.has(Vector2i(key.x, key.y - 1)):
		edges.append({"a": Vector3(x0, y, z0), "b": Vector3(x1, y, z0)})
	return edges


## Appends one outline edge's own prism wall into the caller's shared mesh
## arrays: a vertical(-ish) quad (2 triangles) from `a_local`/`b_local` --
## ghost-local, pre-rotation 3D points at the edge's own column's ceiling
## height (_outline_edges_for_column()) -- down to `bottom_y` (world Y).
## Bontago-xtq.19 (this file's own header): `a_local`/`b_local` are rotated by
## the ghost's current `basis` individually, right here, rather than the old
## per-column _append_prism_walls()'s single shared `top_y` scalar -- under a
## pitch/roll the two ends of one flat local edge land at different world Y
## (a tilted plane's own true silhouette edge), which is what keeps this
## wall's own geometry matching the real rotated shape above it exactly,
## instead of forcing a flat cap that no longer lines up with a tilted
## neighbour's own true (also tilted) edge -- the geometric root cause of the
## visible seams this fix exists for (this file's own header).
func _append_outline_wall(
	a_local: Vector3, b_local: Vector3, bottom_y: float,
	verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array
) -> void:
	var edge_length: float = a_local.distance_to(b_local)
	if edge_length <= 0.0:
		return
	var a_rot: Vector3 = basis * a_local
	var b_rot: Vector3 = basis * b_local
	var a_top_y: float = global_position.y + a_rot.y
	var b_top_y: float = global_position.y + b_rot.y
	if maxf(a_top_y, b_top_y) - bottom_y <= 0.0:
		return
	# Bontago-xtq.19: clamp each corner independently rather than skipping the
	# whole edge -- an extreme rotation could in principle tip one corner of
	# an otherwise-valid edge below the ground while its neighbour stays well
	# above it; clamping keeps the wall a valid (if locally flattened) quad
	# instead of an inverted one. No shipped rotation range reaches this in
	# practice (this file's own _column_top_world_y() already guarantees the
	# column's own worst corner clears the ground before this is ever called).
	var a_top: float = maxf(a_top_y, bottom_y)
	var b_top: float = maxf(b_top_y, bottom_y)

	var projected_dir: Vector2 = Vector2(b_rot.x - a_rot.x, b_rot.z - a_rot.z)
	var projected_length: float = projected_dir.length()
	# Outward-ish normal for this edge (SHADING_MODE_UNSHADED means it has no
	# visible effect today, but a correct value costs nothing and keeps the
	# mesh sane if the material ever changes). Falls back to a fixed axis for
	# the degenerate near-vertical-in-XZ case (a wall edge whose two ends
	# project to (almost) the same XZ point) rather than dividing by zero.
	var normal: Vector3 = Vector3.UP
	if projected_length > 0.0001:
		var edge_dir: Vector2 = projected_dir / projected_length
		normal = Vector3(edge_dir.y, 0.0, -edge_dir.x)

	var base_index: int = verts.size()
	verts.append(Vector3(a_rot.x, a_top, a_rot.z))
	verts.append(Vector3(b_rot.x, b_top, b_rot.z))
	verts.append(Vector3(b_rot.x, bottom_y, b_rot.z))
	verts.append(Vector3(a_rot.x, bottom_y, a_rot.z))
	for _k: int in range(4):
		normals.append(normal)
	var wall_height: float = maxf(a_top, b_top) - bottom_y
	uvs.append(Vector2(0.0, 0.0))
	uvs.append(Vector2(edge_length / tuning.cube_size, 0.0))
	uvs.append(Vector2(edge_length / tuning.cube_size, wall_height / tuning.cube_size))
	uvs.append(Vector2(0.0, wall_height / tuning.cube_size))
	indices.append(base_index)
	indices.append(base_index + 2)
	indices.append(base_index + 1)
	indices.append(base_index)
	indices.append(base_index + 3)
	indices.append(base_index + 2)


## Unweighted average of `hull`'s own vertices -- good enough as "roughly the
## middle of the shape" for the one straight-down probe _update_footprint()
## needs (a true polygon centroid would weight by edge geometry, which buys
## nothing here: the probe only has to land somewhere inside a convex shape
## the disc is expected to be under almost all of, with _last_surface_point
## as the fallback for the rare edge-of-disk overhang anyway).
func _polygon_centroid(hull: PackedVector2Array) -> Vector2:
	var sum: Vector2 = Vector2.ZERO
	for point: Vector2 in hull:
		sum += point
	return sum / float(hull.size())


## Builds a flat (Y = 0 in its own local space), upward-facing triangle-fan
## mesh from `hull` (a convex polygon, in ghost-local XZ) recentered on
## `center` -- the point the caller positions the MeshInstance3D itself at --
## so the mesh's own vertices are the polygon's true rotated shape, not a
## fixed unit square. UVs tile at roughly one cube_size per unit so the hole
## hatch texture (uv1_scale in ghost_tuning.hatch_scale) still reads sensibly.
func _build_polygon_mesh(hull: PackedVector2Array, center: Vector2) -> ArrayMesh:
	var vertex_count: int = hull.size()
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in hull:
		var local: Vector2 = point - center
		verts.append(Vector3(local.x, 0.0, local.y))
		normals.append(Vector3.UP)
		uvs.append(Vector2(local.x / tuning.cube_size + 0.5, local.y / tuning.cube_size + 0.5))
	var indices: PackedInt32Array = PackedInt32Array()
	for i: int in range(1, vertex_count - 1):
		indices.append(0)
		indices.append(i)
		indices.append(i + 1)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var built: ArrayMesh = ArrayMesh.new()
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return built


## Straight down from `origin`, skipping any RigidBody3D (a placed block) so
## the first hit reported is the disk's own collision -- never a tower
## underneath the hull's own centroid (Bontago-xtq.7, this file's own header
## fix (2)). Mirrors game/PlayerController.gd's own _raycast_disk_surface()
## (out of this package's ownership, so duplicated rather than reached into --
## same call this file already makes for collision_box_local_centers(), see
## its own DECISION) exactly, including its surface_probe_max_blocks bound
## against a very tall or adversarial stack.
func _raycast_disk_surface(origin: Vector3) -> Dictionary:
	if not is_inside_tree():
		return {}
	var world: World3D = get_world_3d()
	if world == null:
		return {}
	var space_state: PhysicsDirectSpaceState3D = world.direct_space_state
	if space_state == null:
		return {}
	var exclude: Array[RID] = []
	var attempts: int = 0
	while attempts <= ghost_tuning.surface_probe_max_blocks:
		var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			origin, origin + Vector3.DOWN * ghost_tuning.placement_ray_length
		)
		params.exclude = exclude
		var hit: Dictionary = space_state.intersect_ray(params)
		if hit.is_empty():
			return {}
		if hit["collider"] is RigidBody3D:
			exclude.append(hit["rid"] as RID)
			attempts += 1
			continue
		return hit
	return {}


func _set_footprint_quad_count(count: int) -> void:
	while _footprint_quads.size() < count:
		var quad: MeshInstance3D = _make_footprint_quad()
		add_child(quad)
		_footprint_quads.append(quad)
	while _footprint_quads.size() > count:
		var extra: MeshInstance3D = _footprint_quads.pop_back()
		extra.queue_free()


## For tests: how many footprint quads are currently shown -- 0 with nothing
## held, otherwise always 1 (Bontago-xtq.7: the whole rotated shape's own
## silhouette, not one per bottom cell -- see _rotated_shape_hull()'s own
## comment).
func footprint_quad_count() -> int:
	return _footprint_quads.size()


## For tests: where footprint quad `index` currently sits.
func footprint_quad_position(index: int) -> Vector3:
	return _footprint_quads[index].global_position


## For tests: the world-space (X, Z) convex polygon footprint quad `index` is
## currently showing -- the exact rotated silhouette of the whole held shape,
## not just its center point (see footprint_quad_position()).
func footprint_polygon_world(index: int) -> PackedVector2Array:
	return _footprint_polygons[index]


## For tests: the world-space Y span (top, bottom) of the held shape's own
## whole bookkeeping -- Vector2.ZERO when nothing is held or every prism
## column collapsed (see _update_projection_mesh()'s own guard). `top` is
## always the held shape's own current *highest* point (Bontago-xtq.9: matches
## _rotated_top_offset()'s own contract, not _rotated_bottom_offset()'s);
## `bottom` is the footprint's own landing height. Bontago-xtq.16: this no
## longer describes the prism *mesh*'s own AABB (a non-convex shape's columns
## can each cap lower than this) -- game/PlayerController.gd's own spawn-
## clearance still reads exactly this whole-shape contract, so it stays
## unchanged; see projection_column_span_y() for what an individual column's
## own wall actually spans.
func projection_span_y() -> Vector2:
	return _projection_span_y


## For tests (Bontago-xtq.16, S4 bug -- docs/original_hover-preview.png): how
## many separate light-shaft columns the projection prism currently draws --
## one per rotated XZ footprint patch with at least one solid cell over it
## (several cells merge into one column when they share a patch, e.g. a
## straight unrotated stack), not one flat hull for the whole shape's own
## convex silhouette any more (that used to draw a shaft over an empty notch
## of a non-convex shape like S4, reaching as high as a *different*, taller
## column).
func projection_column_count() -> int:
	return _projection_columns.size()


## For tests: the world-space (top, bottom) Y span projection column `index`
## currently covers. `top` is the lowest world-space Y among every cell
## sharing that column's own rotated XZ footprint patch -- never the whole
## shape's own highest point (see projection_span_y() for that, which
## PlayerController's spawn clearance still reads unchanged); `bottom` is
## always the footprint's own disc landing height, the same value
## projection_span_y().y already reports.
func projection_column_span_y(index: int) -> Vector2:
	return _projection_columns[index]


## For tests: every world-space vertex of the projection prism mesh currently
## built, flattened across every column's own walls -- lets a test check the
## S4 bug's own literal repro ("no prism vertex lies above the min Y of the
## cells over its XZ patch") directly against the real rendered geometry
## rather than trusting this file's own per-column bookkeeping above.
func projection_mesh_vertices_world() -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	if _projection_mesh == null or _projection_mesh.mesh == null:
		return result
	var mesh: ArrayMesh = _projection_mesh.mesh as ArrayMesh
	var offset: Vector3 = _projection_mesh.global_position
	for surface: int in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for v: Vector3 in verts:
			result.append(Vector3(v.x + offset.x, v.y, v.z + offset.z))
	return result


## For tests: whether the projection prism mesh is currently visible (has a
## non-null mesh assigned) -- distinct from footprint_quad_count() > 0, since
## a collapsed (top <= bottom) prism still has a footprint quad but no prism.
func has_projection_mesh() -> bool:
	return _projection_mesh != null and _projection_mesh.mesh != null


# --- Ghost-vs-placed-block collision (Bontago-mv0.23, spec 2.5) -------------

## Local (unrotated), cell-local centers of the held shape's own collision
## boxes -- matching game/BlockFactory.gd's build() exactly (same cube_size/
## cube_margin and BlockShape.bottom_center() pivot) so game/PlayerController.
## gd's swept collision test lines up with the box the real spawned Block
## would occupy there. DECISION (game/GhostPreview.gd): duplicated rather
## than calling into BlockFactory's own private, static
## _make_collision_shape() -- BlockFactory is outside this package's file
## ownership, and this is the same few lines _rotated_bottom_offset()/
## _rotated_footprint_columns() above already compute for the same shape.
## Empty (not null) when nothing is held.
func collision_box_local_centers() -> Array[Vector3]:
	var centers: Array[Vector3] = []
	if _shape == null:
		return centers
	var pivot: Vector3 = _shape.bottom_center()
	for cell: Vector3i in _shape.cells:
		centers.append((Vector3(cell) - pivot) * tuning.cube_size)
	return centers


## Half-extent of one collision box, matching game/BlockFactory.gd's own
## `half_size` (see collision_box_local_centers()'s DECISION above). A sloped
## cell (ConvexPolygonShape3D in BlockFactory) is approximated as a full box
## here -- no shipped shape sets sloped_cells today (Bontago-mv0.17 removed
## the only one, config/blocks/wedge.tres), so this never runs against a
## shape it would misrepresent.
func collision_half_size() -> float:
	return (tuning.cube_size - tuning.cube_margin) * 0.5


# --- Placement validity tint (spec 2.2, 2.5) --------------------------------

## The active slot's colour, used for the VALID tint. Setting it re-applies
## the material immediately if the ghost is currently showing VALID, so a
## hot-seat turn change re-colours the ghost without waiting for the next
## preview_placement() poll.
func set_player_color(color: Color) -> void:
	_player_color = color
	if _last_result == PlacementRules.Result.VALID:
		_refresh_materials()


## Maps Match.preview_placement()'s advisory result onto the three tint
## states spec 2.5 calls for. Safe to call every frame.
func apply_validity(result: PlacementRules.Result) -> void:
	_last_result = result
	_refresh_materials()


## Bontago-mv0.10 (spec 2.4/2.5's "distinct timer-locked state"): whether this
## slot's held piece may be released right now. Called every frame alongside
## apply_validity() by game/PlayerController.gd; the locked tint wins over
## whatever validity state was just applied.
func set_locked(locked: bool) -> void:
	_locked = locked
	_refresh_materials()


## M4 P2e (docs/M4_P2_PACKAGES.md P2e): called every frame by game/
## PlayerController.gd's _drive_throw_visuals() with is_aiming_throw(), so the
## tint appears/disappears the same frame the drag starts/ends. Reuses
## _refresh_materials()'s existing dispatch (only _apply_validity_material()
## reads _throw_hint_active -- see that function's own priority comment).
func show_throw_hint(active: bool) -> void:
	_throw_hint_active = active
	_refresh_materials()


func _refresh_materials() -> void:
	_apply_validity_material()
	_apply_footprint_material()
	_apply_projection_material()


## For tests: which tint state the ghost is currently showing.
func current_state() -> StringName:
	if _locked:
		return STATE_LOCKED
	if _throw_hint_active:
		return STATE_THROW
	match _last_result:
		PlacementRules.Result.VALID:
			return STATE_VALID
		PlacementRules.Result.HOLE, PlacementRules.Result.GOAL_ZONE:
			return STATE_HOLE
		_:
			return STATE_INVALID


## For tests: the material colour currently applied to the held shape.
func current_tint_color() -> Color:
	return _material.albedo_color if _material != null else Color.WHITE


## Bontago-xtq.13 (owner playtest 2026-09-23, "ghost block should still be
## less transparent"): every branch below now applies ghost_tuning.
## ghost_opacity as the material's own alpha instead of whatever alpha the
## picked colour happens to carry (_with_alpha() below) -- one F4 slider then
## controls every state's own opacity together, rather than five separate
## colour-picker alpha channels that would otherwise all need editing to stay
## in sync.
func _apply_validity_material() -> void:
	if _material == null:
		return
	if _locked:
		_material.albedo_texture = null
		_material.albedo_color = _with_alpha(ghost_tuning.locked_tint_color, ghost_tuning.ghost_opacity)
		return
	# M4 P2e: throw-aim wins over plain validity (same precedence _locked
	# already has above) but loses to _locked -- an interval-locked piece
	# cannot be released as a throw either, so that cue must still win.
	if _throw_hint_active:
		_material.albedo_texture = null
		_material.albedo_color = _with_alpha(ghost_tuning.throw_aim_tint_color, ghost_tuning.ghost_opacity)
		return
	match _last_result:
		PlacementRules.Result.VALID:
			_material.albedo_texture = null
			_material.albedo_color = _with_alpha(_player_color, ghost_tuning.ghost_opacity)
		PlacementRules.Result.HOLE, PlacementRules.Result.GOAL_ZONE:
			_material.albedo_texture = _hatch_texture
			_material.uv1_scale = Vector3(ghost_tuning.hatch_scale, ghost_tuning.hatch_scale, 1.0)
			_material.albedo_color = _with_alpha(ghost_tuning.hole_tint_color, ghost_tuning.ghost_opacity)
		_:
			_material.albedo_texture = null
			_material.albedo_color = _with_alpha(ghost_tuning.invalid_tint_color, ghost_tuning.ghost_opacity)


## Bontago-mv0.17 item 6: the footprint quads get a validity/lock cue tied to
## the held shape's own body state (_apply_validity_material() above), at
## ghost_tuning.footprint_alpha -- every footprint quad shares this one
## material. Bontago-xtq.10 (owner test 2026-09-23, "the footprint on the
## disc should be almost white"): that cue is now only a faint hue blended
## into a near-white base (_footprint_color_for_state()'s own doc), not the
## full state colour the held shape's own body still shows -- see this same
## file's _state_hue_color() for the one shared lookup both now use.
func _apply_footprint_material() -> void:
	if _footprint_material == null:
		return
	_footprint_material.albedo_color = _footprint_color_for_state()
	var hatched: bool = not _locked and (
		_last_result == PlacementRules.Result.HOLE or _last_result == PlacementRules.Result.GOAL_ZONE
	)
	if hatched:
		_footprint_material.albedo_texture = _hatch_texture
		_footprint_material.uv1_scale = Vector3(ghost_tuning.hatch_scale, ghost_tuning.hatch_scale, 1.0)
	else:
		_footprint_material.albedo_texture = null


## For tests: the footprint's own current tint colour (see current_tint_color()
## for the held shape's own body colour).
func current_footprint_tint_color() -> Color:
	return _footprint_material.albedo_color if _footprint_material != null else Color.WHITE


## Bontago-xtq.10 (owner test 2026-09-23, "the projection colour is right"):
## the raw, un-alpha'd, un-blended state colour -- valid/invalid/hole/locked,
## exactly what _apply_validity_material() picks for the held shape's own
## body -- factored out of the old _footprint_color_for_state() so both the
## footprint (now blended toward near-white below) and the projection prism
## (still the plain state colour, just fainter and additive) can share one
## lookup instead of drifting apart.
func _state_hue_color() -> Color:
	if _locked:
		return ghost_tuning.locked_tint_color
	match _last_result:
		PlacementRules.Result.VALID:
			return _player_color
		PlacementRules.Result.HOLE, PlacementRules.Result.GOAL_ZONE:
			return ghost_tuning.hole_tint_color
		_:
			return ghost_tuning.invalid_tint_color


## Bontago-xtq.10 (owner test 2026-09-23, "the footprint on the disc should
## be almost white"): the footprint decal is now ghost_tuning.
## footprint_base_color (near-white) with only a faint amount of the current
## state's own hue blended in (footprint_hue_strength), rather than the full
## state colour this used to return directly -- validity is still readable
## (a hint of red/grey/gold tints the near-white disc), just far more subtle
## than the held shape's own body or the projection prism now are.
func _footprint_color_for_state() -> Color:
	var blended: Color = ghost_tuning.footprint_base_color.lerp(_state_hue_color(), ghost_tuning.footprint_hue_strength)
	return _with_alpha(blended, ghost_tuning.footprint_alpha)


## Bontago-xtq.7 (this file's own header, fix (2)): the projection prism's own
## walls, at ghost_tuning.projection_alpha instead of footprint_alpha -- the
## brief calls for a noticeably fainter volume marker than the flat footprint
## decal it stands on. DECISION (game/GhostPreview.gd): reuses
## _state_hue_color()'s own plain state colour when
## ghost_tuning.projection_uses_state_tint is true (the default -- the owner
## report's own reference screenshot, docs/original_in-game.png, tints its
## silhouette prism the same as everything else the ghost shows), just at the
## prism's own alpha; false is kept as a tuning-panel escape hatch to compare
## a state-neutral prism (always the base tint_color) without a second
## migration, the same reasoning already used for several other GhostTuning
## fields' own master-switch DECISIONs in this file/config/GhostTuning.gd.
## Bontago-xtq.10 (owner test 2026-09-23, "any surface that falls within the
## projection should be a lot brighter (maybe emissive?)"): the prism's own
## _projection_material now blends additively (BLEND_MODE_ADD, _ready())
## rather than the usual alpha-over compositing, and this also drives its
## emission colour at ghost_tuning.projection_emission_energy -- both make
## the column brighten whatever is behind/inside it instead of just tinting
## over it. DECISION (game/GhostPreview.gd, Bontago-xtq.10): a per-block
## emission hook on BlockFactory/Block.gd (outside this package's ownership)
## was considered and rejected -- the prism material approach here achieves
## the brief's own brightening effect with a purely visual, self-contained
## change to this package's own material, with no gameplay-code touch at all.
func _apply_projection_material() -> void:
	if _projection_material == null:
		return
	var state_color: Color = _state_hue_color() if ghost_tuning.projection_uses_state_tint else ghost_tuning.tint_color
	_projection_material.albedo_color = _with_alpha(state_color, ghost_tuning.projection_alpha)
	_projection_material.emission = Color(state_color.r, state_color.g, state_color.b)
	_projection_material.emission_energy_multiplier = ghost_tuning.projection_emission_energy


## For tests: the projection prism's own current tint colour (see
## current_footprint_tint_color() for the flat footprint decal's own colour).
func current_projection_tint_color() -> Color:
	return _projection_material.albedo_color if _projection_material != null else Color.WHITE


## For tests: the projection prism's own current emission colour
## (Bontago-xtq.10 -- see ghost_tuning.projection_emission_energy for its
## strength and projection_uses_additive_blend()/projection_emission_enabled()
## for the material settings that make it actually brighten what's behind it).
func current_projection_emission_color() -> Color:
	return _projection_material.emission if _projection_material != null else Color.BLACK


## For tests: whether the projection prism material blends additively
## (BaseMaterial3D.BLEND_MODE_ADD) instead of the usual alpha-over
## compositing (Bontago-xtq.10, owner test 2026-09-23: "any surface that
## falls within the projection should be a lot brighter").
func projection_uses_additive_blend() -> bool:
	return _projection_material != null and _projection_material.blend_mode == BaseMaterial3D.BLEND_MODE_ADD


## For tests: whether the projection prism material emits its own light
## (Bontago-xtq.10) on top of the additive blend above.
func projection_emission_enabled() -> bool:
	return _projection_material != null and _projection_material.emission_enabled


func _with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)


func _apply_material_to_visual() -> void:
	if _shape_visual == null:
		return
	for child: Node in _shape_visual.get_children():
		if child is MeshInstance3D:
			var mesh_instance: MeshInstance3D = child as MeshInstance3D
			mesh_instance.material_override = _material
			# DECISION (owner 2026-09-22, "the ghost has both the indicator and
			# a shadow"): the held block is a preview, so it casts no light
			# shadow; the projected footprint is its only ground marker.
			mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# --- Reject / auto-drop animation (spec 2.2, 2.5) ---------------------------

## Spec 2.2: "released [in a contested area] ... is thrown off the map with a
## visible reject animation" (docs/M2_PLAN.md owner decision 2: every invalid
## release burns the block, decided by Match.request_place — this is just the
## ghost-side cue: a bright flash plus a small arc kick on _reject_offset, a
## world-space position offset applied on top of update_placement()'s/
## sync_remote_position()'s own computed position every frame.
##
## Bontago-mv0.25 (docs/rotation-issue.png, owner test 2026-09-22): used to
## kick _shape_visual's own *local* position instead -- that offset rides
## along with the ghost's rotation basis (_shape_visual is a plain, non-
## top_level child), so a pitched or rolled held block's reject kick visibly
## went the wrong way (an "upward" kick could come out sideways or backwards
## depending on orientation). _reject_offset is a plain world-space vector
## added after rotation is applied, so the kick direction (world +X sideways,
## +Y up) never depends on the block's current rotation, while still
## surviving PlayerController re-homing the ghost's position every frame --
## the same reason the old local-offset trick existed in the first place.
func play_reject_animation() -> void:
	_flash_material(ghost_tuning.reject_flash_color, ghost_tuning.reject_flash_duration)
	if _reject_tween != null and _reject_tween.is_valid():
		_reject_tween.kill()
	_reject_offset = Vector3.ZERO
	var kick: Vector3 = Vector3(ghost_tuning.reject_arc_sideways, ghost_tuning.reject_arc_height, 0.0)
	var half_duration: float = ghost_tuning.reject_arc_duration * 0.5
	_reject_tween = create_tween()
	_reject_tween.tween_property(self, ^"_reject_offset", kick, half_duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_reject_tween.tween_property(self, ^"_reject_offset", Vector3.ZERO, half_duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## For tests: the reject arc's current world-space position offset (zero
## outside a reject animation).
func reject_offset() -> Vector3:
	return _reject_offset


## Spec 2.5: "When the timer runs out, the held block drops from its current
## ghost position." A quick neutral flash tells the player the drop was
## automatic, not a click.
func play_auto_drop_flash() -> void:
	_flash_material(ghost_tuning.auto_drop_flash_color, ghost_tuning.auto_drop_flash_duration)


func _flash_material(color: Color, duration: float) -> void:
	if _material == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	var restore_color: Color = _material.albedo_color
	_material.albedo_color = color
	_flash_tween = create_tween()
	_flash_tween.tween_property(_material, ^"albedo_color", restore_color, duration)


# --- Mesh / texture builders -------------------------------------------------

## Bontago-mv0.17 item 6: one flat polygon per bottom cell of the rotated
## held shape (replaces _make_guide_mesh()'s old vertical line), tinted by the
## shared _footprint_material so every quad repaints together when validity/
## lock state changes. Starts meshless -- _update_footprint() assigns each
## instance's real convex-hull mesh (_build_polygon_mesh()) every frame, since
## its shape depends on the held shape's current rotation.
func _make_footprint_quad() -> MeshInstance3D:
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.material_override = _footprint_material
	mesh_instance.top_level = true
	return mesh_instance


## A small diagonal-stripe pattern (spec 2.5: "hatched pattern when over a
## hole"), generated once instead of shipped as an art asset. Tiled across
## the held shape via ghost_tuning.hatch_scale (StandardMaterial3D.uv1_scale).
func _build_hatch_texture() -> ImageTexture:
	var image: Image = Image.create(HATCH_TEXTURE_SIZE, HATCH_TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	var period: float = float(HATCH_TEXTURE_SIZE) / 4.0
	for y: int in range(HATCH_TEXTURE_SIZE):
		for x: int in range(HATCH_TEXTURE_SIZE):
			var phase: float = fmod(float(x + y), period) / period
			var opaque: bool = phase < ghost_tuning.hatch_stripe_width
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, 1.0 if opaque else 0.0))
	# Bontago-xtq.18 (owner F12 2026-09-23, feedback/owner-noise-footprint.png:
	# the footprint under the ghost read as black/white speckled noise instead
	# of a flat pale quad/hatch pattern): the footprint quad's own diagonal
	# stripe pattern is a HOLE/GOAL_ZONE-only visual (_apply_footprint_
	# material()/_apply_validity_material() above) tiled several times across
	# a small quad via ghost_tuning.hatch_scale -- with no mip chain, the GPU
	# had only this one full-resolution level to minify from at any distance
	# or oblique ground-decal viewing angle, and linear-filtering a
	# diagonal high-frequency stripe pattern down that hard aliases into the
	# reported speckled noise (confirmed by reproducing the exact same
	# artefact via tools/screenshot_xtq15_block_projection.gd with the ghost
	# forced into PlacementRules.Result.HOLE, and by ruling out
	# _block_projection_decal -- its own texture is a single flat colour
	# with no frequency content to alias, and the artefact persisted with
	# ghost_tuning.block_projection_alpha forced to 0). generate_mipmaps()
	# gives the renderer the downsampled levels it needs to blend a proper
	# grey average instead of aliasing, fixing this at any distance/angle.
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
