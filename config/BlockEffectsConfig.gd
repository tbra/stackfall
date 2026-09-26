class_name BlockEffectsConfig
extends Resource
## Tunables for game/BlockEffectsManager.gd's one-shot particle effects
## (Bontago-xtq.29, M7 P4, spec 2.10 "effects + camera shake"). Two effect
## kinds share one spawn helper (BlockEffectsManager._spawn_burst()),
## parameterised entirely by the exported fields below, following the same
## "no magic numbers" pattern config/CameraShakeConfig.gd already uses for
## game/CameraRig.gd:
## - landing dust / impact burst: Events.block_impacted_at (this revision),
##   a softer grey-brown puff with a ground-plane spread.
## - kill-plane edge-fall burst: Events.block_removed with
##   Events.REASON_KILL_PLANE (unchanged from the original candidate), a
##   brighter, faster burst at the block's last position before it's freed.

# --- Landing dust / impact burst (Events.block_impacted_at) -----------------

## Minimum impact speed (the same deceleration magnitude
## Events.block_impacted/block_impacted_at carry) that spawns a landing-dust
## burst at all -- a soft landing/settle should not visibly puff dust.
@export var dust_impact_speed_threshold: float = 4.0

@export var dust_particle_amount: int = 16
@export var dust_lifetime_s: float = 0.5
@export var dust_initial_speed: float = 1.5
## Wide half-angle from the UP emission direction so most particles fan out
## close to the ground plane instead of shooting straight up, distinguishing
## this from the kill-plane burst's narrower, more vertical spread.
@export var dust_spread_deg: float = 70.0
@export var dust_gravity: Vector3 = Vector3(0.0, -4.0, 0.0)
@export var dust_scale: float = 0.06
@export var dust_color: Color = Color(0.55, 0.47, 0.37)

# --- Kill-plane edge-fall burst (Events.block_removed) -----------------------

@export var kill_particle_amount: int = 24
@export var kill_lifetime_s: float = 0.6
@export var kill_initial_speed: float = 3.5
@export var kill_spread_deg: float = 45.0
@export var kill_gravity: Vector3 = Vector3(0.0, -9.8, 0.0)
@export var kill_scale: float = 0.08
@export var kill_color: Color = Color(0.82, 0.78, 0.68)

# --- Cleanup -----------------------------------------------------------------

## GPUParticles3D.finished may not fire in a headless run (no renderer to
## drive the particle system's visual lifetime). Each spawned burst also
## schedules a get_tree().create_timer(own lifetime + this margin) fallback
## that frees it if it's somehow still alive, so active_effect_count() always
## returns to 0 well after a burst's own lifetime -- see
## BlockEffectsManager._schedule_cleanup_fallback().
@export var cleanup_margin_s: float = 0.2
