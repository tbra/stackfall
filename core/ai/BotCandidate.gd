class_name BotCandidate
extends RefCounted
## One sampled placement spot (spec 2.9): a disk-local origin, an
## orientation, and what BotController's own raycasts found there. Pure data
## -- no scene-tree reference, so core/ai/ scorers can be unit-tested without
## a running Field.
##
## docs/M5_PLAN.md P1 (Bontago-d5c): this is the interface-stub package's own
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
var on_top_of_own_stack: bool = false
