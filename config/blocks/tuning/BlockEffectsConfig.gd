class_name BlockEffectsConfig
extends Resource
## Tunables for game/blocks/BlockEffectsManager.gd's particle effects (spec 1.10
## "effects + camera shake"). Three effect kinds:
## - landing dust / impact burst: Events.block_impacted_at spawns TWO bursts
##   together under one wrapper Node3D (so active_effect_count() counts it as a
##   single "effect"): a small team-colored cubelet shower (cubelet_*) plus a
##   softer grey-brown dust puff (dust_*), both scaled by how hard the impact was
##   (BlockEffectsManager._impact_intensity()).
## - falling-block trail: a continuous, team-tinted luminous streak (trail_*)
##   behind any block whose measured fall speed
##   (BlockEffectsManager._update_falling_trails()) crosses trail_speed_threshold.
##   Not an Events signal: there is no "still falling fast" signal to listen for.
## - kill-plane edge-fall burst: Events.block_removed with
##   Events.REASON_KILL_PLANE, a brighter, faster burst at the block's last
##   position before it's freed.

# --- Landing dust / impact burst (Events.block_impacted_at) -----------------

## Minimum impact speed (the same deceleration magnitude
## Events.block_impacted/block_impacted_at carry) that spawns a landing-dust
## burst at all -- a soft landing/settle should not visibly puff dust.
@export var dust_impact_speed_threshold: float = 4.0

## Dust is a soft round billboarded quad (shaders/gifts/dust_puff.gdshader, a
## procedural radial alpha falloff) emitted on a ring around the impact point
## (dust_ring_*), capped well below Environment.glow_hdr_threshold so it never
## blooms.
@export var dust_particle_amount: int = 9
@export var dust_lifetime_s: float = 0.5
@export var dust_initial_speed: float = 0.5
## Dust ring emitter thickness along its axis.
@export var dust_emission_ring_height_m: float = 0.05
## Lower bound of every burst's initial speed as a fraction of its maximum.
@export var velocity_min_ratio: float = 0.5
## Falling speed below which a trail points straight up instead of along the velocity.
@export var trail_min_speed: float = 0.001
## Half-angle from the UP emission direction; mild since the ring emission shape
## (dust_ring_radius_m) already spreads puffs across the ground.
@export var dust_spread_deg: float = 40.0
@export var dust_gravity: Vector3 = Vector3(0.0, -2.0, 0.0)
## Base billboard quad size in meters (0.3-0.8 m range once
## dust_size_variance_min/max is applied).
@export var dust_scale: float = 0.55
@export var dust_size_variance_min: float = 0.6
@export var dust_size_variance_max: float = 1.3
## Alpha is capped here, not just left to the shader's own falloff, so the puff
## is never a hard, fully-opaque shape.
@export var dust_alpha_max: float = 0.42
@export var dust_color: Color = Color(0.82, 0.78, 0.7)
## ParticleProcessMaterial.EMISSION_SHAPE_RING: puffs spawn spread around a
## ring at the impact point rather than all at one origin.
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
## Long enough that the shrink+fade is visible before the cubelet is gone.
@export var cubelet_lifetime_s: float = 0.8
@export var cubelet_initial_speed: float = 3.0
## Narrower than dust_spread_deg: cubelets read as a small shard burst near the
## impact point, not a wide ground-hugging puff.
@export var cubelet_spread_deg: float = 55.0
@export var cubelet_gravity: Vector3 = Vector3(0.0, -9.8, 0.0)
## Base BoxMesh edge length in meters (0.1-0.18 m range once
## cubelet_size_variance_min/max is applied) -- shaders/gifts/cubelet.gdshader gives
## each one a cheap 2-tone cel look from a fixed faux light direction, no
## real light/normal-map setup needed for a particle this small.
@export var cubelet_scale: float = 0.14
@export var cubelet_size_variance_min: float = 0.75
@export var cubelet_size_variance_max: float = 1.3
## Random per-particle spin (ParticleProcessMaterial.angular_velocity_min/
## max, degrees/second), so cubelets tumble rather than fly as static cubes.
@export var cubelet_angular_velocity_max_deg: float = 540.0
## How much darker shaders/gifts/cubelet.gdshader's faux-lit "shadow" faces are than
## its "lit" faces (0 = no shading at all, 1 = shadow faces fully black).
@export var cubelet_shade_mix: float = 0.35
## Used only when the impacting block's owning slot (resolved via a physics shape
## query at the impact position, BlockEffectsManager._find_block_at()) cannot
## be found -- e.g. an impacting body with no owner_slot set, or a test that
## emits Events.block_impacted_at directly with no real Block in the world.
@export var cubelet_fallback_color: Color = Color(0.85, 0.85, 0.9)

# --- Falling-block trail (continuous, not an Events burst) ------------------

## The trail is one continuous stretched quad (shaders/gifts/trail_streak.gdshader)
## re-oriented and re-scaled every physics step, so it has no gaps by construction
## and never detaches. It is one ribbon as wide as the block, anchored at the block
## mesh's own centre and turned about its travel axis to face the camera (a flat
## strip goes edge-on from many views). See BlockEffectsManager._ensure_trail().

## Downward speed (m/s, measured from the block's own position delta each
## physics step -- see BlockEffectsManager._update_falling_trails()'s own
## doc for why not RigidBody3D.linear_velocity) above which a block gets a
## luminous trail.
@export var trail_speed_threshold: float = 8.0
## Bright speed lines drawn inside the ribbon (the mockup's falling piece).
@export var trail_streak_count: int = 3
## Ribbon width = the block's mean horizontal mesh extent * this ratio,
## clamped to [trail_min_width_m, trail_max_width_m].
@export var trail_width_ratio: float = 1.0
@export var trail_min_width_m: float = 0.8
@export var trail_max_width_m: float = 2.4
## Ribbon length (meters) = fall speed (m/s) * this factor, clamped to
## [trail_min_length_m, trail_max_length_m] (length proportional to speed).
@export var trail_length_per_speed_s: float = 0.3
@export var trail_min_length_m: float = 1.0
@export var trail_max_length_m: float = 8.0
@export var trail_alpha_max: float = 0.9
## Multiplies the resolved team/fallback color for shaders/gifts/trail_streak.gdshader's
## EMISSION: modest, so it is not blown out but still picks up Main.tscn's shared
## HDR glow a little, matching a "luminous" streak.
@export var trail_emission_energy: float = 1.2
## How long a released trail (block no longer falling fast) takes to
## disappear -- BlockEffectsManager._release_trail()'s fade-out delay (the trail is
## a persistent mesh, not particles).
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

# --- Cel dust-puff flipbook (assets/textures/fx/impact_puff) -----

## Master switch for the flipbook puff at impact points.
@export var puff_enabled: bool = true
## Impact intensity (BlockEffectsManager._impact_intensity()) at or above which
## the "hard" atlas is used; below it the "soft" atlas plays.
@export var puff_hard_intensity: float = 1.6
## Quad edge (meters) at intensity 1 and at impact_intensity_max; the quad grows
## linearly between them (the soft atlas art is already smaller).
@export var puff_size_min_m: float = 1.0
@export var puff_size_max_m: float = 2.0
## Opacity at intensity 1 and at impact_intensity_max.
@export var puff_alpha_min: float = 0.6
@export var puff_alpha_max: float = 0.95
@export var puff_tint: Color = Color(1.0, 1.0, 1.0, 1.0)
## Flipbook rate and frame count (atlas manifest: 16 frames at 30 fps).
@export var puff_fps: float = 30.0
@export var puff_frame_count: int = 16
## Hard cap on simultaneously active puffs (scaled by the graphics preset's
## particle_budget_scale); extra puffs are dropped.
@export var puff_max_active: int = 12

# --- Burst pool and budget -------------------------------

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
