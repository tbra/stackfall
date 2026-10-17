class_name PhysicsTuning
extends Resource
## Every tunable number the block physics needs (spec 1.4, 2.7). Loaded once as
## config/physics/physics_tuning.tres and shared by BlockFactory, Field, and the
## benchmark scenes.

## -- Block bodies (spec 1.4) ------------------------------------------------
## Cube edge length in meters.
@export var cube_size: float = 1.0
## Shrink each cube's collision box by this much so neighboring blocks don't
## jam against each other.
@export var cube_margin: float = 0.02
## Mass per cube; a shape's total mass is cube count * cube_mass.
@export var cube_mass: float = 2.0
## Block physics material.
@export var block_friction: float = 0.85
@export var block_bounce: float = 0.4
## DECISION: spec 1.4 doesn't specify body damping, so blocks use Godot's
## project-default 0.1 and nothing more. Damping is deliberately NOT used to hold
## towers up: linear damping of 4.0 caps a falling block at g/damp = 2.5 m/s and
## kills the "sense of weight" of spec 1.6, and it only slowed a topple (about 7x)
## rather than preventing it. The cause was Jolt's velocity solver running too few
## iterations (see velocity_steps in tools/bootstrap_project.gd) plus its body-pair
## contact cache distance threshold (same file); with those fixed a 40-cube tower
## is stable at zero damping, so 0.1 is insurance (terminal velocity 98 m/s).
## Jolt sleeps a whole connected island together, so one vibrating block near the
## top keeps every block below awake. These are not the sleep_linear/angular
## thresholds below, which describe spec 1.5's settled-block/influence rule.
## See tests/unit/match/test_tower_placement.gd and tests/bench/bench_tower.gd.
@export var block_linear_damp: float = 0.1
@export var block_angular_damp: float = 0.15

## -- Field (spec 1.7, 2.7) ---------------------------------------------------
@export var disk_friction: float = 0.9
## Any body below this world Y is freed (spec 1.7).
@export var kill_plane_y: float = -40.0

## -- Ghost preview (spec 1.4) ------------------------------------------------
@export var hover_height: float = 0.3

## -- Settled-block rule (spec 1.5: "A block counts as settled when its
## linear speed is below 0.15 m/s and its angular speed below 0.3 rad/s for
## 0.5 s"), used for territory influence. ---------
@export var sleep_linear_threshold: float = 0.15
@export var sleep_angular_threshold: float = 0.3
@export var sleep_settle_time: float = 0.5

## -- Gravity (spec 1.9 "Gravity 0.5x-2x") ------------------------------------
## Base gravity multiplier (1.25x the original 1.4).
@export var gravity_multiplier: float = 1.75
## The Heavy & Bouncy factor folded out of the lobby scale.
## start_match() sets gravity_multiplier = this * MatchConfig.gravity_multiplier.
@export var lobby_gravity_baseline: float = 1.75

## -- Rebound damping ("heavier and more bouncy, but a dropped block shouldn't just
## bounce straight up again") -----------------------------------------------
## DECISION: block_bounce (the PhysicsMaterial restitution above) is Jolt's only
## source of bounciness and applies along the whole contact-normal impulse, so a
## flat landing gets it straight back as vertical velocity while a corner/edge hit
## scatters some sideways. There is no Jolt knob for "restitution, but not
## vertical", so this field damps only the world-Y component of a block's own
## post-solve velocity, only on the physics step a bounce happens
## (game/Block._integrate_forces(), host-only since a client's synced blocks are
## frozen). Horizontal and angular velocity are untouched, so block_bounce still
## gives lateral/tumbling liveliness. 1.0 is a pass-through. See
## config/physics/presets/*.tres and game/Block._damp_rebound(). The script
## defaults equal the shipped Heavy & Bouncy tuning so F4 "modified" markers and
## Reset agree with config/physics/physics_tuning.tres.
@export var rebound_damping: float = 0.3

## Experimental Original feel preset: deterministic release tilt, not a
## reconstruction of the original solver. Applied once only above the gap.
@export var release_tilt_degrees: float = 0.0
@export var release_tilt_min_gap_cubes: float = 1.0

## -- Stable-block freeze (spec 2.7 "Stable-block optimization") ---------------
## DECISION: spec 2.7 gives the number directly ("asleep for more than 20 s"). 20.0
## also matches the Freeze special's duration (spec 1.8: "static for 20 s"), so
## "how long is a block frozen" stays one number. A block resets this timer (and
## un-freezes if frozen) the instant it wakes, per spec 2.7's "goes back to normal
## the moment any impulse, tilt, or change in the cells under it happens".
@export var stable_freeze_delay_s: float = 20.0
## DECISION: spec 2.7 names no scan interval, but the no-magic-numbers rule keeps it
## a field rather than a constant in game/blocks/StableBlockManager.gd. 0.5 s is
## cheap at a few hundred live blocks (it only reads Block.sleeping and, rarely,
## flips freeze_mode) and fine enough for the 20 s freeze delay.
@export var stable_freeze_scan_interval_s: float = 0.5
## A sleeping block's freeze timer survives a wake (Jolt
## wakes whole contact islands on any landing) as long as the block stays
## within this distance (m; also applied to each unit basis axis) of the pose
## it fell asleep in; moving further restarts the timer. See
## game/blocks/StableBlockManager.gd's own DECISION.
@export var stable_freeze_rest_epsilon_m: float = 0.005

## -- Settle freeze (spec 2.7) ------------
## Jolt keeps a micro-jittering pile awake forever, so the sleep-based freeze above
## never reaches it. With this on, a block that is AWAKE but has stayed within
## settle_freeze_move_epsilon_m / settle_freeze_rotation_epsilon of the pose its
## still window started in for settle_freeze_window_s, with no fast-moving block
## within settle_freeze_neighbour_radius_m, is frozen through the same path as an
## asleep block (game/blocks/StableBlockManager.gd), so every existing release rule applies.
@export var settle_freeze_enabled: bool = true
## Continuous still time (s) before an awake block is frozen.
@export var settle_freeze_window_s: float = 5.0
## Max drift (m) from the window's start pose that still counts as still (5 mm).
@export var settle_freeze_move_epsilon_m: float = 0.005
## Max change of any unit basis axis (about radians) that still counts as still.
@export var settle_freeze_rotation_epsilon: float = 0.005
## A block faster than this (m/s) is a "fast neighbour" that blocks freezing near it.
@export var settle_freeze_fast_speed_mps: float = 0.5
## Distance (m, centre to centre) within which a fast block holds a neighbour back;
## about one cube diagonal plus slack, so it only stops blocks it could be touching.
@export var settle_freeze_neighbour_radius_m: float = 1.8

## -- Physics catch-up cap -------------------------
## When a frame runs long, the engine runs extra physics steps to catch up, which
## makes the next frame longer still (a spiral). Capping them trades a brief
## slow-motion for a stable frame time. The project setting
## physics/common/max_physics_steps_per_frame is set from catchup_steps_capped by
## tools/bootstrap_project.gd; the F4 toggle switches Engine's live value between the
## two numbers (game/blocks/StableBlockManager.gd applies it).
@export var catchup_cap_enabled: bool = true
@export var catchup_steps_capped: int = 2
@export var catchup_steps_default: int = 8
