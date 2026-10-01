class_name HoleDissolveTuning
extends Resource
## Bontago-1pi.11.41 (owner decision Bontago-gdb, option A): the disc stays
## solid under holes; a block whose footprint rests or lands on an applied
## hole cell dissolves on the host and is removed like an edge fall.
## game/HoleDissolver.gd reads every number here.

## Seconds between a block touching a hole and its removal. The A2 visual fade
## (Events.block_dissolve_started) plays over this span on host and clients.
@export_range(0.0, 5.0, 0.01) var dissolve_delay_s: float = 0.35

## Footprint sample points within this height (metres, along the disc normal)
## of the disc surface count as touching it. A block resting on another block
## sits a whole cube above the disc, far beyond this.
@export_range(0.01, 1.0, 0.01) var contact_height_m: float = 0.15

## Each collision corner is pulled this far (metres) toward its shape's centre
## before it is mapped to a cell, so a cube whose edge only grazes the line
## between a solid cell and a hole does not count as touching the hole.
@export_range(0.0, 0.45, 0.01) var contact_inset_m: float = 0.08

## A block moving away from the disc faster than this (m/s along the disc
## normal) is leaving it, not resting or landing on it: a Jumping Bean kicked
## out of the hole it just punched, or a block an explosion launched.
@export_range(0.0, 20.0, 0.1) var contact_leave_speed: float = 1.0

## Upper bound on bodies one hole-open contact query returns per opened cell.
@export_range(1, 256, 1) var open_query_max_bodies: int = 32
