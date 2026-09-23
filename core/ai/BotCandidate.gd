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

## Bontago-d5c.3 (M5 P2, append-only): how many of game/BotController.gd's own
## footprint-corner raycasts (_fire_stability_raycasts(), spec 2.9's stability
## factor) landed at essentially the same height as `support_height` -- i.e.
## how much of `footprint_cells` is actually in flush contact, not hovering
## over a gap or a lower stack. -1 ("not measured") is the default and is what
## every real candidate reports today: BotController._fire_stability_raycasts()
## still discards each raycast's own result (its own class doc: "P2 is the
## package that stores and scores what each one finds"), and this package's
## own brief was "Must NOT touch game/BotController.gd" (owned by another
## package's window at the time P2 landed). core/ai/BotPlacementScorer.gd
## falls back to treating the whole footprint as in contact when this is -1;
## wiring _fire_stability_raycasts() to set it for real is a follow-up for
## whichever package next owns game/BotController.gd.
var corner_support_hits: int = -1
