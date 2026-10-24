class_name BotCandidate
extends RefCounted
## One sampled placement spot (spec 1.8): a disk-local origin, an
## orientation, and what BotController's own raycasts found there. Pure data
## -- no scene-tree reference, so core/ai/ code can be unit-tested without
## a running Field.
##
## This is the shared data shape of a bot candidate. Fields may be appended when a
## genuinely new fact is needed (note the reason in the change), but must not remove or retype any of the
## five below.

## Disk-local (x, z), BlockShape.bottom_center() pivot.
var origin: Vector2 = Vector2.ZERO
## BlockOrientations index.
var orientation_index: int = 0
## Disk-local (Field-local) Y of whatever is directly below the candidate's
## origin -- the support raycast's hit height, or a safe disk-surface
## fallback (0.0) when nothing was hit (see BotController._raycast_support_
## height()'s own doc).
var support_height: float = 0.0
var footprint_cells: PackedInt32Array = PackedInt32Array()

## Append-only: the oriented shape's own height, in cube units, above its own pivot
## (a pillar lying flat is 1, standing on end is 3); 0.0 until the producer fills it.
## BotEvaluator adds this to `support_height` (top_height) since a block's influence radius
## is driven by its own highest point above the disk, not merely where its pivot rests.
var shape_height: float = 0.0

## Bot V2 (append-only): which generator produced the site
## (BotThink.SITE_NONE = 0 until BotCandidateGen sets a targeted kind).
var site_kind: int = 0
## Height above the disk of the highest point of the placed piece
## (support_height + shape_height); the influence-circle radius is driven by it.
var top_height: float = 0.0
## Support height under each probed footprint cell (-1 = hole or no hit), in
## footprint order; empty until the footprint was probed.
var cell_support: PackedFloat32Array = PackedFloat32Array()

## append-only: disk-local XZ of each probed bottom cube
## (BotStatics.contact_probe_points); `cell_support` is parallel to it once probed. Empty = the
## grid-cell probing of older candidates.
var probe_points: PackedVector2Array = PackedVector2Array()
## Parallel to `probe_points`: instance id of the block collider the ray hit, -1 = disc / miss.
var support_bodies: PackedInt64Array = PackedInt64Array()
## append-only: cubes in the placed piece's top layer (BotStatics.OrientationInfo.top_area),
## the landing area the next piece gets; 0 = unknown (older candidates).
var top_area: float = 0.0

## append-only: BotStability.evaluate's slack (min margin - required over the piece cut and
## every lower cut; stable iff > 0). INF = not evaluated.
var stability_slack: float = INF
