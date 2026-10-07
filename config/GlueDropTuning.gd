class_name GlueDropTuning
extends Resource
## Host physics settings for blocks placed while Glue charges are active.

## Direct stress threshold for GlueJoint.apply_stress_sample() (test/debug seam).
@export_range(1.0, 10000.0, 1.0) var break_force: float = 2000.0
## A bond breaks when the glued bodies drift this far (m) from their bind-time relative pose.
@export_range(0.01, 5.0, 0.01) var break_separation_m: float = 0.4
## A bond breaks when the glued bodies' relative linear speed exceeds this (m/s), e.g. a blast.
@export_range(0.5, 50.0, 0.1) var break_speed_mps: float = 12.0
## A bond breaks when either glued body's velocity changes by more than this (m/s) in one
## physics tick: the signature of a blast, which the joint solver otherwise absorbs.
@export_range(0.5, 20.0, 0.1) var break_shock_mps: float = 4.0
@export_range(1, 64, 1) var max_contacts_reported: int = 16
