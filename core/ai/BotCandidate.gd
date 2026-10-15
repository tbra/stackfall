class_name BotCandidate
extends RefCounted
## One sampled placement spot (spec 2.9): a disk-local origin, an
## orientation, and what BotController's own raycasts found there. Pure data
## -- no scene-tree reference, so core/ai/ code can be unit-tested without
## a running Field.
##
## docs/archive/M5_PLAN.md P1 (Bontago-d5c): this is the interface-stub package's own
## data shape. P2 may append fields here if it needs a genuinely new fact
## (flagged in its own package doc), but must not remove or retype any of the
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

## How many of the footprint's BotThink cube probes landed at essentially the same height as
## `support_height` -- i.e. how much of `footprint_cells` is in flush contact, not hovering over a gap
## or a lower stack. -1 ("not measured") is the default; BotThink fills it from its cube probes.
var corner_support_hits: int = -1

## Bontago-d5c.9 (M5 P3b-i, append-only): the oriented shape's own height, in
## cube units, above its own pivot -- e.g. a pillar lying flat is 1, standing
## on end is 3. Producer is game/bots/BotController.gd (Bontago-d5c.8, a later
## package's own window); every candidate here defaults to 0.0 until that
## package wires it in. BotEvaluator adds this to `support_height`
## (top_height) since a block's influence radius is driven by its own highest point above the
## disk, not merely where its pivot rests.
var shape_height: float = 0.0

## Bot V2 (Bontago-1t5.19, append-only): which generator produced the site
## (BotThink.SITE_NONE = 0 until BotCandidateGen sets a targeted kind).
var site_kind: int = 0
## Height above the disk of the highest point of the placed piece
## (support_height + shape_height); the influence-circle radius is driven by it.
var top_height: float = 0.0
## Support height under each probed footprint cell (-1 = hole or no hit), in
## footprint order; empty until the footprint was probed.
var cell_support: PackedFloat32Array = PackedFloat32Array()

## Bontago-1t5.55.2 (append-only; stub for 1t5.53b): disk-local XZ of each probed bottom cube
## (BotStatics.contact_probe_points); `cell_support` is parallel to it once probed. Empty = the
## grid-cell probing of older candidates.
var probe_points: PackedVector2Array = PackedVector2Array()
## Parallel to `probe_points`: instance id of the block collider the ray hit, -1 = disc / miss.
var support_bodies: PackedInt64Array = PackedInt64Array()
## Bontago-1t5.69 (append-only): cubes in the placed piece's top layer (BotStatics.OrientationInfo.top_area),
## the landing area the next piece gets; 0 = unknown (older candidates).
var top_area: float = 0.0

## Bontago-1t5.72.4 (append-only): BotStability.evaluate's slack (min margin - required over the piece cut and
## every lower cut; stable iff > 0). INF = not evaluated.
var stability_slack: float = INF
## The cut that binds the slack (BotStability.BINDING_PIECE, a lower cut's body index, or BINDING_NONE = -2).
var stability_binding: int = BotStability.BINDING_NONE
## Where BotStability says the piece comes to rest (disc-local); read by nothing until the evaluator switches.
var stability_plane_y: float = 0.0
