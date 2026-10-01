class_name BlockEffectsConfig
extends Resource
## Tunables for game/BlockEffectsManager.gd's particle effects (Bontago-xtq.29,
## M7 P4, spec 2.10 "effects + camera shake"; extended Bontago-mp0.3.4, M7 art
## direction pass 2 -- docs/art_mockups/08-cel-shaded-home-beacons.png). Three
## effect kinds, following the same "no magic numbers" pattern
## config/CameraShakeConfig.gd already uses for game/CameraRig.gd:
## - landing dust / impact burst: Events.block_impacted_at, now TWO bursts
##   spawned together under one wrapper Node3D (so active_effect_count() still
##   counts it as a single "effect"): a small team-colored cubelet shower
##   (cubelet_*) plus the original softer grey-brown dust puff (dust_*), both
##   scaled by how hard the impact was (BlockEffectsManager._impact_intensity()).
## - falling-block trail: a continuous, team-tinted luminous streak
##   (trail_*) behind any block whose measured fall speed
##   (BlockEffectsManager._update_falling_trails()) crosses
##   trail_speed_threshold -- not an Events signal, since there is no
##   "still falling fast" signal to listen for; see that method's own doc.
## - kill-plane edge-fall burst: Events.block_removed with
##   Events.REASON_KILL_PLANE (unchanged from the original candidate), a
##   brighter, faster burst at the block's last position before it's freed.

# --- Landing dust / impact burst (Events.block_impacted_at) -----------------

## Minimum impact speed (the same deceleration magnitude
## Events.block_impacted/block_impacted_at carry) that spawns a landing-dust
## burst at all -- a soft landing/settle should not visibly puff dust.
@export var dust_impact_speed_threshold: float = 4.0

## Fix round (owner: dust rendered as "huge flat hard-edged blown-out yellow
## rectangles" -- billboarded unshaded BoxMesh cubes overlapping into one
## blob): dust is now a soft round billboarded quad (vfx/dust_puff.gdshader,
## a procedural radial alpha falloff, no texture asset needed) emitted on a
## ring around the impact point (dust_ring_*), capped well below
## Environment.glow_hdr_threshold so it never blooms.
@export var dust_particle_amount: int = 9
@export var dust_lifetime_s: float = 0.5
@export var dust_initial_speed: float = 0.5
## Half-angle from the UP emission direction -- kept mild since the ring
## emission shape (dust_ring_radius_m) already spreads puffs across the
## ground; this only adds a little outward/upward drift on top of that.
@export var dust_spread_deg: float = 40.0
@export var dust_gravity: Vector3 = Vector3(0.0, -2.0, 0.0)
## Base billboard quad size in meters (0.3-0.8 m range once
## dust_size_variance_min/max is applied) -- NOT a cube edge length anymore
## (see this section's own fix-round doc).
@export var dust_scale: float = 0.55
@export var dust_size_variance_min: float = 0.6
@export var dust_size_variance_max: float = 1.3
## Alpha is capped here, not just left to the shader's own falloff -- "a
## soft round puff", never a hard, fully-opaque shape.
@export var dust_alpha_max: float = 0.42
@export var dust_color: Color = Color(0.82, 0.78, 0.7)
## ParticleProcessMaterial.EMISSION_SHAPE_RING: puffs spawn spread around a
## ring at the impact point rather than all at one origin -- "a ring-shaped
## spread along the ground from the impact point".
@export var dust_ring_radius_m: float = 0.5
@export var dust_ring_inner_radius_m: float = 0.15

## Upper bound on how much a hard impact scales up cubelet/dust particle
## counts and cubelet speed (BlockEffectsManager._impact_intensity()) --
## impact speed / dust_impact_speed_threshold, clamped to this. Without a
## cap, an extreme impact (e.g. a special's throw) could spawn an
## unbounded-looking burst; this keeps a 300-block match's worst case bounded.
@export var impact_intensity_max: float = 3.0

# --- Landing cubelet shower (Events.block_impacted_at, team-colored) --------

## Base particle count before impact_intensity scaling; see
## cubelet_max_particle_amount for the scaled-up cap.
@export var cubelet_particle_amount: int = 10
@export var cubelet_max_particle_amount: int = 24
## Fix round (owner: "make them actual tiny 3D cubes... shrinking/fading out
## over ~0.8 s"): bumped from 0.45 s so the shrink+fade is actually visible,
## not gone before it registers.
@export var cubelet_lifetime_s: float = 0.8
@export var cubelet_initial_speed: float = 3.0
## Narrower than dust_spread_deg -- cubelets should read as a small shard
## burst near the impact point, not a wide ground-hugging puff.
@export var cubelet_spread_deg: float = 55.0
@export var cubelet_gravity: Vector3 = Vector3(0.0, -9.8, 0.0)
## Base BoxMesh edge length in meters (0.1-0.18 m range once
## cubelet_size_variance_min/max is applied) -- vfx/cubelet.gdshader gives
## each one a cheap 2-tone cel look from a fixed faux light direction, no
## real light/normal-map setup needed for a particle this small.
@export var cubelet_scale: float = 0.14
@export var cubelet_size_variance_min: float = 0.75
@export var cubelet_size_variance_max: float = 1.3
## Random per-particle spin (ParticleProcessMaterial.angular_velocity_min/
## max, degrees/second) -- "tumbling", not a static thrown cube.
@export var cubelet_angular_velocity_max_deg: float = 540.0
## How much darker vfx/cubelet.gdshader's faux-lit "shadow" faces are than
## its "lit" faces (0 = no shading at all, 1 = shadow faces fully black).
@export var cubelet_shade_mix: float = 0.35
## Used only when the impacting block's owner (resolved via a physics shape
## query at the impact position, BlockEffectsManager._find_block_at()) cannot
## be found -- e.g. an impacting body with no owner_slot set, or a test that
## emits Events.block_impacted_at directly with no real Block in the world.
@export var cubelet_fallback_color: Color = Color(0.85, 0.85, 0.9)

# --- Falling-block trail (continuous, not an Events burst) ------------------

## Fix round (owner: the previous particle-burst trail read as "dashed/
## dotted... not attached to the falling piece"): the trail is now a small
## fixed number of single, continuous stretched-quad meshes
## (vfx/trail_streak.gdshader) re-oriented and re-scaled every frame to run
## from the block's own top back along the direction opposite its fall --
## a mesh has no gaps by construction, and re-reading the block's live
## global_position every frame (not just every physics step) keeps it
## visually attached. See BlockEffectsManager._ensure_trail()'s own doc.

## Downward speed (m/s, measured from the block's own position delta each
## physics step -- see BlockEffectsManager._update_falling_trails()'s own
## doc for why not RigidBody3D.linear_velocity) above which a block gets a
## luminous trail.
@export var trail_speed_threshold: float = 8.0
## How many parallel streaks fan out across the block's width -- "2-3 thin
## parallel streaks offset across the block's width, like the mockup's
## falling blue piece".
@export var trail_streak_count: int = 3
@export var trail_streak_width_m: float = 0.07
@export var trail_lateral_offset_m: float = 0.16
## Streak length (meters) = fall speed (m/s) * this factor, clamped to
## [trail_min_length_m, trail_max_length_m] -- "length proportional to
## speed".
@export var trail_length_per_speed_s: float = 0.12
@export var trail_min_length_m: float = 0.4
@export var trail_max_length_m: float = 3.0
## Offset above the block's own global_position the streak's head (the
## bright end) starts from -- an approximation of "the block's top" without
## reading its actual mesh bounds (game/Block.gd is not an owned file).
@export var trail_top_offset_m: float = 0.3
@export var trail_alpha_max: float = 0.8
## Multiplies the resolved team/fallback color for vfx/trail_streak.gdshader's
## EMISSION -- "modest emission", well down from an earlier candidate's 2.2
## (which read as over-bright/blown-out) but still enough to pick up
## Main.tscn's shared HDR glow a little, matching a "luminous" streak.
@export var trail_emission_energy: float = 1.2
## How long a released trail (block no longer falling fast) takes to
## disappear -- BlockEffectsManager._release_trail()'s own fade-out delay,
## not a per-particle lifetime anymore (see this section's own fix-round
## doc: the trail is a persistent mesh, not particles).
@export var trail_release_fade_s: float = 0.15
## Hard cap on simultaneously active trails (one per fast-falling block) --
## bounds a multiplayer match where several players drop pieces at once to a
## fixed, cheap worst case rather than one continuous emitter per block.
@export var trail_max_concurrent: int = 6
## Used only when the trailing block's owner_slot cannot be resolved to a
## color (see cubelet_fallback_color's own doc for when that happens).
@export var trail_fallback_color: Color = Color(0.75, 0.85, 1.0)

# --- Kill-plane edge-fall burst (Events.block_removed) -----------------------

@export var kill_particle_amount: int = 24
@export var kill_lifetime_s: float = 0.6
@export var kill_initial_speed: float = 3.5
@export var kill_spread_deg: float = 45.0
@export var kill_gravity: Vector3 = Vector3(0.0, -9.8, 0.0)
@export var kill_scale: float = 0.08
@export var kill_color: Color = Color(0.82, 0.78, 0.68)

# --- Burst pool and budget (Bontago-1pi.11.31) -------------------------------

## Hard cap on simultaneously active one-shot bursts (landing + kill-plane
## together). This is also the pool size: nodes are created lazily up to this
## many and reused, never instantiated per impact.
@export var burst_max_active: int = 16
## Cap on NEW bursts started within one physics frame -- a collapse can land
## many blocks in the same step. Excess bursts are dropped.
@export var burst_max_new_per_frame: int = 4

# --- Cleanup -----------------------------------------------------------------

## GPUParticles3D.finished may not fire in a headless run (no renderer to
## drive the particle system's visual lifetime). Each spawned burst also
## schedules a get_tree().create_timer(own lifetime + this margin) fallback
## that frees it if it's somehow still alive, so active_effect_count() always
## returns to 0 well after a burst's own lifetime -- see
## BlockEffectsManager._schedule_cleanup_fallback().
@export var cleanup_margin_s: float = 0.2
