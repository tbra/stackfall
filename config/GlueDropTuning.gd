class_name GlueDropTuning
extends Resource
## Host physics settings for blocks placed while Glue charges are active.

@export_range(1, 64, 1) var max_contacts_reported: int = 16
## Bond formation soaks the impact: the glued block takes the partner's linear velocity and
## both bodies lose spin, so an off-edge landing does not topple the pair.
@export var absorb_impact: bool = true
## Safety cap on cubes in one fused body; 0 = unlimited.  (OQ5)
@export_range(0, 512, 1) var max_fused_cubes: int = 0
## After the first fuse the carrier keeps fusing what it touches for this long (s), so a block
## bridging two stacks sticks to both (joint-era parity); 0 = the first contact tick only.
@export_range(0.0, 2.0, 0.05) var fuse_window_s: float = 0.25
## A disc-anchored group reports "asleep" (no snapshot bandwidth) once the disc has not moved it
## for this many physics ticks; a disc tilt wakes it at once.
@export_range(1, 120, 1) var anchor_rest_ticks: int = 6
