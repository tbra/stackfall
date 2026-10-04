class_name BlockEffectsManager
extends Node3D
## Bontago-xtq.29 (M7 P4, spec 2.10 "effects + camera shake"): visual effects
## for block events. Purely additive/cosmetic -- never touches
## territory/physics/win-check state (core/ stays untouched), so it is safe to
## add as a child of game/Field.tscn without affecting any existing gameplay
## test (tests/unit/test_field.gd builds Field.new() directly and never loads
## the .tscn, so this node never even exists in that suite).
##
## Three effect kinds (config/BlockEffectsConfig.gd has every tunable):
## - landing burst: Events.block_impacted_at, whenever a block's own detected
##   impact speed reaches config.dust_impact_speed_threshold. Spawns a small
##   team-colored cubelet shower (_find_block_at() resolves the owner by a
##   physics point query at the impact position -- Events.block_impacted_at
##   only carries speed/position, not the block itself) plus the original
##   softer dust puff, both under one wrapper Node3D so active_effect_count()
##   still reads it as a single effect. Events.block_impacted_at is additive
##   alongside the pre-existing Events.block_impacted (autoload/Sfx.gd's own
##   listener, untouched).
## - falling-block trail: a continuous, team-tinted luminous streak behind any
##   block whose measured fall speed crosses config.trail_speed_threshold --
##   see _update_falling_trails()'s own doc for why this is driven from
##   Block.TUNING_GROUP every physics step rather than an Events signal.
## - kill-plane edge-fall burst: Events.block_removed(block,
##   REASON_KILL_PLANE), fired at the block's last position immediately
##   before game/Field.gd's queue_free() call.
## # DECISION: the kill-plane burst is a one-shot particle burst fired at
## removal time, not a continuous falling trail, since the block node is
## about to be freed -- matches spec intent without new mid-flight tracking.

@export var config: BlockEffectsConfig = preload("res://config/block_effects.tres")

## Radius (meters) of the sphere shape query _find_block_at() uses to
## resolve the impacting block's owner -- see that method's own DECISION for
## why a sphere, not a point. A query-robustness implementation detail, not
## a gameplay tunable (config/BlockShape.gd's own single-cube edge length is
## the real reference scale this only has to comfortably beat).
const FIND_BLOCK_QUERY_RADIUS_M: float = 0.35

const DUST_SHADER: Shader = preload("res://vfx/dust_puff.gdshader")
const CUBELET_SHADER: Shader = preload("res://vfx/cubelet.gdshader")
const TRAIL_SHADER: Shader = preload("res://vfx/trail_streak.gdshader")

## A single Gradient-driven fade (alpha 1 -> 0 over a particle's own
## lifetime), shared by every dust/cubelet burst's ParticleProcessMaterial.
## color_ramp -- both vfx/dust_puff.gdshader and vfx/cubelet.gdshader read
## this back as COLOR.a. Built once (GradientTexture1D.update() has real
## cost) and cached, not rebuilt per burst.
# DECISION: instance (not static) caches -- static Resource vars kept the
# whole Block/Field script graph alive at editor exit ("resources still in
# use" leak on the open-project check). One manager per match, so cost is equal.
var _fade_ramp: GradientTexture1D = null

## Bontago-mp0.3.4: per-block previous global_position, keyed by
## Object.get_instance_id() -- the same idiom
## _schedule_cleanup_fallback()'s own DECISION already uses for a
## freed-object-safe key. Used only to measure each block's own fall speed
## every physics step (_update_falling_trails()); pruned in the same pass for
## any id no longer seen in Block.TUNING_GROUP.
var _prev_positions: Dictionary = {}

## instance id (int) -> the wrapper Node3D (holding config.trail_streak_count
## MeshInstance3D streaks) currently following that block. Absence means "no
## active trail for this block" -- either it never crossed
## trail_speed_threshold, or _release_trail() already started freeing it.
var _trails: Dictionary = {}

## Settings.graphics_preset_changed-driven (see _on_graphics_preset_changed()):
## gates only the falling trail, the one continuous per-frame effect this
## package adds -- matches game/Skybox.gd's own volumetric_fog_enabled gate
## for its FogVolume cloud deck (docs/M7_ART_DIRECTION.md's Low-preset
## performance budget), reusing that same flag as "heavy atmospheric/ambient
## effects" rather than inventing a second graphics-preset field. The
## one-shot landing/kill bursts stay on every preset -- they already existed
## before this package and are bounded, one-shot costs, not a new continuous
## per-frame one.
var _trail_effects_enabled: bool = true
## Bontago-1pi.11.37: GraphicsPreset.particle_budget_scale (adaptive quality governor).
var _particle_budget_scale: float = 1.0


func _ready() -> void:
	Events.block_removed.connect(_on_block_removed)
	Events.block_impacted_at.connect(_on_block_impacted_at)
	var preset: GraphicsPreset = Settings.current_graphics_preset()
	_trail_effects_enabled = preset == null or preset.volumetric_fog_enabled
	_particle_budget_scale = preset.particle_budget_scale if preset != null else 1.0
	Settings.graphics_preset_changed.connect(_on_graphics_preset_changed)


func _exit_tree() -> void:
	release_pool()
	if Settings.graphics_preset_changed.is_connected(_on_graphics_preset_changed):
		Settings.graphics_preset_changed.disconnect(_on_graphics_preset_changed)


func _on_graphics_preset_changed(preset: GraphicsPreset) -> void:
	_trail_effects_enabled = preset == null or preset.volumetric_fog_enabled
	_particle_budget_scale = preset.particle_budget_scale if preset != null else 1.0


func _physics_process(delta: float) -> void:
	if delta <= 0.0:
		return
	var probe_effects: int = PerfProbe.start()
	_release_expired_bursts()
	_update_falling_trails(delta)
	PerfProbe.stop(&"block_effects", probe_effects)


func _on_block_removed(block: RigidBody3D, reason: String) -> void:
	if reason != String(Events.REASON_KILL_PLANE):
		return
	if block == null:
		return
	var burst: PooledBurst = _acquire_burst(_kill_pool, 1, true)
	if burst == null:
		return
	burst.wrapper.global_position = block.global_position
	burst.wrapper.reset_physics_interpolation()
	var particles: GPUParticles3D = burst.particles[0]
	particles.lifetime = config.kill_lifetime_s
	particles.draw_pass_1 = _kill_mesh_for(config.kill_color)
	_restart_particles(particles, config.kill_particle_amount)
	_start_burst(burst, config.kill_lifetime_s)


## Landing burst (Bontago-mp0.3.4): a team-colored cubelet shower plus the
## original grey-brown dust puff, both scaled by _impact_intensity() and
## held by one pooled wrapper Node3D so active_effect_count() still reports
## one effect per impact. Bontago-1pi.11.31: wrappers/particle systems come
## from a reuse pool and are restarted, meshes/materials are shared per
## colour/kind, and new bursts are budgeted (see _acquire_burst()).
func _on_block_impacted_at(speed: float, position: Vector3) -> void:
	if speed < config.dust_impact_speed_threshold:
		return
	# Budget check first: the owner physics query below is not free either.
	_spawn_impact_puff(speed, position)
	var burst: PooledBurst = _acquire_burst(_landing_pool, 2, false)
	if burst == null:
		return
	var intensity: float = _impact_intensity(speed)
	var owner_block: Block = _find_block_at(position)
	var owner_slot: int = owner_block.owner_slot if owner_block != null else -1
	var cubelet_color: Color = _color_for_owner_slot(owner_slot, config.cubelet_fallback_color)
	burst.wrapper.global_position = position
	burst.wrapper.reset_physics_interpolation()

	var cubelet_amount: int = int(round(min(
		float(config.cubelet_max_particle_amount),
		float(config.cubelet_particle_amount) * intensity,
	)))
	var cubelets: GPUParticles3D = burst.particles[0]
	cubelets.lifetime = config.cubelet_lifetime_s
	cubelets.draw_pass_1 = _cubelet_mesh_for(cubelet_color)
	var cubelet_material: ParticleProcessMaterial = cubelets.process_material as ParticleProcessMaterial
	cubelet_material.initial_velocity_min = config.cubelet_initial_speed * 0.5 * intensity
	cubelet_material.initial_velocity_max = config.cubelet_initial_speed * intensity
	_restart_particles(cubelets, cubelet_amount)

	var dust: GPUParticles3D = burst.particles[1]
	dust.lifetime = config.dust_lifetime_s
	_restart_particles(dust, int(round(float(config.dust_particle_amount) * intensity)))
	_start_burst(burst, maxf(config.cubelet_lifetime_s, config.dust_lifetime_s))


## Bontago-mp0.120: pooled flipbook puff (game/ImpactPuff.gd) at the contact
## point. Cosmetic only, driven by the same replicated impact event on host and
## clients. Over-cap puffs are dropped (like bursts); the cap shrinks with the
## graphics preset's particle_budget_scale, so a Low preset thins/disables them.
# DECISION: spawned before the burst budget check so a dropped burst still
# leaves a puff; puffs have their own cap (config.puff_max_active) and live in
# an INTERNAL-mode container so the manager's public child indices are unchanged.
func _spawn_impact_puff(speed: float, position: Vector3) -> void:
	if not config.puff_enabled:
		return
	var cap: int = int(floorf(float(config.puff_max_active) * _particle_budget_scale))
	if cap <= 0:
		return
	var intensity: float = _impact_intensity(speed)
	var puff: ImpactPuff = null
	var active_count: int = 0
	for candidate: ImpactPuff in _puffs:
		if candidate.active:
			active_count += 1
		elif puff == null:
			puff = candidate
	if active_count >= cap:
		return
	if puff == null:
		puff = ImpactPuff.new()
		if _puff_root == null:
			_puff_root = Node3D.new()
			add_child(_puff_root, false, Node.INTERNAL_MODE_BACK)
		_puff_root.add_child(puff)
		_puffs.append(puff)
	var span: float = maxf(config.impact_intensity_max - 1.0, 0.001)
	var t: float = clampf((intensity - 1.0) / span, 0.0, 1.0)
	puff.play(
		position,
		intensity >= config.puff_hard_intensity,
		lerpf(config.puff_size_min_m, config.puff_size_max_m, t),
		config.puff_tint,
		lerpf(config.puff_alpha_min, config.puff_alpha_max, t),
		config.puff_fps,
		config.puff_frame_count,
	)


## Test seam: puffs currently playing.
func active_puff_count() -> int:
	var count: int = 0
	for puff: ImpactPuff in _puffs:
		if puff.active:
			count += 1
	return count


## Test seam: the pooled puffs.
func puffs() -> Array[ImpactPuff]:
	return _puffs


## impact speed / dust_impact_speed_threshold, clamped to [1, impact_intensity_
## max] -- 1.0 at exactly the threshold (no scale-up for a barely-qualifying
## impact), growing for a harder one. Shared by both the cubelet and dust
## bursts above so a single hard impact scales both together.
func _impact_intensity(speed: float) -> float:
	if config.dust_impact_speed_threshold <= 0.0:
		return 1.0
	return clampf(speed / config.dust_impact_speed_threshold, 1.0, config.impact_intensity_max)


## Events.block_impacted_at carries only (speed, position) -- Block.gd is not
## an owned file for this package, so this resolves the impacting block's
## owner_slot from the outside instead: a small-sphere physics shape query
## centered at the impact position (the block's own global_position at emit
## time, game/Block.gd). Returns null (the cubelet burst falls back to
## config.cubelet_fallback_color) when nothing resolves -- e.g. a test that
## emits the signal directly with no real Block in the world
## (tests/unit/test_block_effects.gd).
##
## DECISION (game/BlockEffectsManager.gd, fix round): a sphere query, not a
## zero-radius point query (the original candidate) -- game/BlockFactory.gd
## builds a multi-cube block as a COMPOUND of one CollisionShape3D per cube,
## each offset from the RigidBody3D's own origin (BlockFactory.build(), "one
## CollisionShape3D per cell"). For any shape wider than a single cube, that
## origin can sit exactly on a shared edge/corner between cubes -- outside
## every individual cube's own box shape -- so a zero-radius point query
## there can miss the block entirely. Reproduced while capturing this
## package's own vfx/capture_vfx_evidence_probe.gd evidence: a landing
## square4 (2x2) block's cubelet burst rendered in
## cubelet_fallback_color instead of its own team color. A small sphere
## (FIND_BLOCK_QUERY_RADIUS_M) reliably overlaps at least one of the
## impacting block's own cube shapes regardless of where its origin sits.
func _find_block_at(position: Vector3) -> Block:
	var world: World3D = get_world_3d()
	if world == null:
		return null
	var space_state: PhysicsDirectSpaceState3D = world.direct_space_state
	if space_state == null:
		return null
	var query_shape: SphereShape3D = SphereShape3D.new()
	query_shape.radius = FIND_BLOCK_QUERY_RADIUS_M
	var params: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	params.shape = query_shape
	params.transform = Transform3D(Basis(), position)
	params.collide_with_bodies = true
	params.collide_with_areas = false
	var results: Array[Dictionary] = space_state.intersect_shape(params, 8)
	for result: Dictionary in results:
		var collider: Object = result.get("collider")
		if collider is Block:
			return collider as Block
	return null


## GiftCrate._claim_color()'s own fallback shape (that file's own doc explains
## why it is not shared as a common helper): a real PlayerSlot's own colour
## when Match can name one for `slot_id`, otherwise the live match's
## MatchConfig.player_colors[slot_id], and `fallback` if neither resolves
## (slot_id < 0, no match running -- both true in
## tests/unit/test_block_effects.gd, which emits these signals with no Match
## configured).
func _color_for_owner_slot(slot_id: int, fallback: Color) -> Color:
	if slot_id < 0:
		return fallback
	var slot: PlayerSlot = Match.slot(slot_id)
	if slot != null:
		return slot.color
	var palette: MatchConfig = Match.config
	if palette != null and slot_id < palette.player_colors.size():
		return palette.player_colors[slot_id]
	return fallback


## Bontago-1pi.11.31 burst pool. One PooledBurst = one wrapper Node3D plus its
## particle systems, created lazily (up to config.burst_max_active active at a
## time), kept in the tree and restarted on reuse instead of re-instantiated.
## Each pooled particle system owns its ParticleProcessMaterial (built once,
## only the impact-scaled velocity is rewritten per reuse); the colour-bearing
## draw-pass meshes (and their ShaderMaterial/StandardMaterial3D) are shared
## per colour/kind below, so no material is allocated per impact.
class PooledBurst:
	extends RefCounted
	var wrapper: Node3D = null
	var particles: Array[GPUParticles3D] = []
	var active: bool = false
	var expire_msec: int = 0


var _landing_pool: Array[PooledBurst] = []
var _kill_pool: Array[PooledBurst] = []
var _active_bursts: int = 0
var _budget_frame: int = -1
var _new_bursts_this_frame: int = 0
## Color -> shared draw-pass mesh (carrying the shared material), per kind.
var _cubelet_meshes: Dictionary = {}
var _kill_meshes: Dictionary = {}
var _dust_mesh: Mesh = null
## Bontago-mp0.120 flipbook puff pool (see _spawn_impact_puff()).
var _puffs: Array[ImpactPuff] = []
var _puff_root: Node3D = null


## Returns an idle pooled burst of `particle_count` systems, or null when the
## burst must be skipped.
# DECISION: over-budget bursts are DROPPED, not merged or queued -- they are
# purely cosmetic, a collapse already shows many nearby bursts, and dropping
# keeps the cost strictly bounded with no deferred work.
func _acquire_burst(pool: Array[PooledBurst], particle_count: int, is_kill: bool) -> PooledBurst:
	var frame: int = Engine.get_physics_frames()
	if frame != _budget_frame:
		_budget_frame = frame
		_new_bursts_this_frame = 0
	if _new_bursts_this_frame >= int(ceilf(float(config.burst_max_new_per_frame) * _particle_budget_scale)):
		return null
	if _active_bursts >= int(ceilf(float(config.burst_max_active) * _particle_budget_scale)):
		return null
	var burst: PooledBurst = null
	for candidate: PooledBurst in pool:
		if not candidate.active:
			burst = candidate
			break
	if burst == null:
		burst = _build_burst(particle_count, is_kill)
		pool.append(burst)
	_new_bursts_this_frame += 1
	return burst


func _build_burst(particle_count: int, is_kill: bool) -> PooledBurst:
	var burst: PooledBurst = PooledBurst.new()
	burst.wrapper = Node3D.new()
	burst.wrapper.visible = false
	add_child(burst.wrapper)
	for i: int in range(particle_count):
		var particles: GPUParticles3D = GPUParticles3D.new()
		particles.emitting = false
		particles.one_shot = true
		particles.explosiveness = 1.0
		# Built once at its maximum count: changing `amount` reallocates the
		# particle buffers, so reuse only scales amount_ratio.
		particles.amount = _max_amount_for(i, is_kill)
		if is_kill:
			particles.process_material = _build_process_material(
				config.kill_spread_deg, config.kill_initial_speed, config.kill_gravity
			)
		elif i == 0:
			particles.process_material = _build_cubelet_process_material(1.0)
		else:
			particles.draw_pass_1 = _get_dust_mesh()
			particles.process_material = _build_dust_process_material()
		burst.wrapper.add_child(particles)
		burst.particles.append(particles)
	return burst


func _max_amount_for(index: int, is_kill: bool) -> int:
	if is_kill:
		return maxi(config.kill_particle_amount, 1)
	if index == 0:
		return maxi(config.cubelet_max_particle_amount, 1)
	return maxi(int(ceil(float(config.dust_particle_amount) * config.impact_intensity_max)), 1)


## Never writes `amount` (buffer reallocation); scales amount_ratio instead.
func _restart_particles(particles: GPUParticles3D, amount: int) -> void:
	particles.emitting = false
	amount = int(roundf(float(amount) * _particle_budget_scale))
	if amount <= 0:
		return
	particles.amount_ratio = clampf(float(amount) / float(maxi(particles.amount, 1)), 0.0, 1.0)
	particles.restart()
	particles.emitting = true


func _start_burst(burst: PooledBurst, lifetime_s: float) -> void:
	burst.active = true
	burst.wrapper.visible = true
	burst.expire_msec = Time.get_ticks_msec() + int((lifetime_s + config.cleanup_margin_s) * 1000.0)
	_active_bursts += 1


## Returns finished bursts to the pool (GPUParticles3D.finished may never fire
## headless, so expiry is time-based, like the old cleanup-fallback timer).
func _release_expired_bursts() -> void:
	if _active_bursts <= 0:
		return
	var now: int = Time.get_ticks_msec()
	_release_expired_in(_landing_pool, now)
	_release_expired_in(_kill_pool, now)


func _release_expired_in(pool: Array[PooledBurst], now: int) -> void:
	for burst: PooledBurst in pool:
		if burst.active and now >= burst.expire_msec:
			burst.active = false
			burst.wrapper.visible = false
			for particles: GPUParticles3D in burst.particles:
				particles.emitting = false
			_active_bursts -= 1


## Frees the pooled nodes and shared caches (match teardown / manager exit).
func release_pool() -> void:
	_free_pool(_landing_pool)
	_free_pool(_kill_pool)
	_active_bursts = 0
	if is_instance_valid(_puff_root):
		_puff_root.queue_free()
	_puff_root = null
	_puffs.clear()
	_cubelet_meshes.clear()
	_kill_meshes.clear()
	_dust_mesh = null


func _free_pool(pool: Array[PooledBurst]) -> void:
	for burst: PooledBurst in pool:
		if is_instance_valid(burst.wrapper):
			burst.wrapper.queue_free()
	pool.clear()


func _cubelet_mesh_for(color: Color) -> Mesh:
	var mesh: Mesh = _cubelet_meshes.get(color) as Mesh
	if mesh == null:
		mesh = _build_cubelet_mesh(color)
		_cubelet_meshes[color] = mesh
	return mesh


func _kill_mesh_for(color: Color) -> Mesh:
	var mesh: Mesh = _kill_meshes.get(color) as Mesh
	if mesh == null:
		mesh = _build_mesh(config.kill_scale, color)
		_kill_meshes[color] = mesh
	return mesh


func _get_dust_mesh() -> Mesh:
	if _dust_mesh == null:
		_dust_mesh = _build_dust_mesh()
	return _dust_mesh


## Fix round (owner: "make them actual tiny 3D cubes... tumbling... a small
## bounce or just fall, shrinking/fading out"): a GPUParticles3D whose
## draw_pass_1 mesh/material give each cube vfx/cubelet.gdshader's cheap
## 2-tone cel look, random per-particle size (scale_min/max), tumbling
## (angular_velocity_min/max), real gravity (cubelet_gravity), and a shared
## fade+shrink profile (color_ramp/scale_curve, both built once by
## _get_fade_ramp()/_get_shrink_curve() below) rather than any bounce
## simulation of its own -- "a small bounce or just fall" -- falling alone
## already reads fine for a particle this short-lived and this is the
## cheaper of the two options.
func _build_cubelet_mesh(color: Color) -> Mesh:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3.ONE * config.cubelet_scale
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = CUBELET_SHADER
	material.set_shader_parameter(&"base_color", color)
	material.set_shader_parameter(&"shade_mix", config.cubelet_shade_mix)
	mesh.material = material
	return mesh


func _build_cubelet_process_material(intensity: float) -> ParticleProcessMaterial:
	var material: ParticleProcessMaterial = ParticleProcessMaterial.new()
	material.direction = Vector3.UP
	material.spread = config.cubelet_spread_deg
	material.initial_velocity_min = config.cubelet_initial_speed * 0.5 * intensity
	material.initial_velocity_max = config.cubelet_initial_speed * intensity
	material.gravity = config.cubelet_gravity
	material.scale_min = config.cubelet_size_variance_min
	material.scale_max = config.cubelet_size_variance_max
	material.angular_velocity_min = -config.cubelet_angular_velocity_max_deg
	material.angular_velocity_max = config.cubelet_angular_velocity_max_deg
	material.color_ramp = _get_fade_ramp()
	material.scale_curve = _get_shrink_curve()
	return material


func _build_dust_mesh() -> Mesh:
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = Vector2(config.dust_scale, config.dust_scale)
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = DUST_SHADER
	material.set_shader_parameter(&"dust_color", config.dust_color)
	material.set_shader_parameter(&"max_alpha", config.dust_alpha_max)
	mesh.material = material
	return mesh


func _build_dust_process_material() -> ParticleProcessMaterial:
	var material: ParticleProcessMaterial = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	material.emission_ring_axis = Vector3.UP
	material.emission_ring_height = 0.05
	material.emission_ring_radius = config.dust_ring_radius_m
	material.emission_ring_inner_radius = config.dust_ring_inner_radius_m
	material.direction = Vector3.UP
	material.spread = config.dust_spread_deg
	material.initial_velocity_min = config.dust_initial_speed * 0.5
	material.initial_velocity_max = config.dust_initial_speed
	material.gravity = config.dust_gravity
	material.scale_min = config.dust_size_variance_min
	material.scale_max = config.dust_size_variance_max
	material.color_ramp = _get_fade_ramp()
	return material


## Shared alpha-fade profile (1 -> 0 over a particle's own lifetime) for
## every dust/cubelet burst's ParticleProcessMaterial.color_ramp -- both
## vfx/dust_puff.gdshader and vfx/cubelet.gdshader read this back as
## COLOR.a. Built once and cached (GradientTexture1D.update() has real
## cost), not rebuilt per burst.
func _get_fade_ramp() -> GradientTexture1D:
	if _fade_ramp == null:
		var gradient: Gradient = Gradient.new()
		gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
		gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
		var texture: GradientTexture1D = GradientTexture1D.new()
		texture.gradient = gradient
		_fade_ramp = texture
	return _fade_ramp


## Shared shrink-to-nothing profile (scale x1 -> x0 over a particle's own
## lifetime) for cubelet_burst's ParticleProcessMaterial.scale_curve --
## "shrinking... over ~0.8 s". Not used by the dust burst (the brief asks for
## a "quick expand", not a shrink, for dust puffs).
var _shrink_curve: CurveTexture = null
func _get_shrink_curve() -> CurveTexture:
	if _shrink_curve == null:
		var curve: Curve = Curve.new()
		curve.add_point(Vector2(0.0, 1.0))
		curve.add_point(Vector2(1.0, 0.0))
		var texture: CurveTexture = CurveTexture.new()
		texture.curve = curve
		_shrink_curve = texture
	return _shrink_curve


## Bontago-mp0.3.4 (falling-block trail): every live Block adds itself to
## Block.TUNING_GROUP in _ready() (that constant's own doc -- built for
## exactly this "reach every live block without a new coupling" case, already
## used by ui/TuningPanel.gd's live-apply path). Measures each block's own
## fall velocity from its position delta this physics step, not
## RigidBody3D.linear_velocity: a client's synced blocks are frozen kinematic
## (net/SnapshotSync.gd's freeze_body(), spec 3.4) and driven purely by
## net/Interpolator.gd writing global_position directly, never by real
## physics integration, so linear_velocity would read as a false zero for
## every client-visible falling block. A position-delta measurement reads
## correctly on both the host (real physics) and a client (interpolated
## position) with no freeze-state branch needed here at all -- exactly the
## "host/client both" visual-only contract this package's brief asks for.
func _update_falling_trails(delta: float) -> void:
	# Bontago-1pi.11.32: only awake blocks (Block.awake_blocks(), which also
	# reports a block for a couple of frames after it sleeps) plus ids still
	# holding a previous position, i.e. recently moving ones. A sleeping block
	# has zero fall speed, so skipping it changes nothing; once a block is
	# dormant and unmoved its _prev_positions entry is dropped, so the map only
	# holds awake/recent blocks.
	var inv_delta: float = 1.0 / delta
	var threshold: float = config.trail_speed_threshold
	var trails_on: bool = _trail_effects_enabled
	var visited: Dictionary = {}
	for block: Block in Block.awake_blocks():
		if not is_instance_valid(block):
			continue
		var id: int = block.get_instance_id()
		visited[id] = true
		_update_block_trail(id, block, inv_delta, threshold, trails_on)
	for id: int in _prev_positions.keys():
		if visited.has(id):
			continue
		var block: Block = instance_from_id(id) as Block
		if block == null or not is_instance_valid(block):
			_prev_positions.erase(id)
			_release_trail(id)
			continue
		_update_block_trail(id, block, inv_delta, threshold, trails_on)


func _update_block_trail(id: int, block: Block, inv_delta: float, threshold: float, trails_on: bool) -> void:
	var position: Vector3 = block.global_position
	var prev_position: Vector3 = _prev_positions.get(id, position)
	var delta_vec: Vector3 = position - prev_position
	var fall_speed: float = -delta_vec.y * inv_delta
	if trails_on and fall_speed >= threshold:
		_prev_positions[id] = position
		_ensure_trail(id, block, fall_speed, delta_vec * inv_delta)
		return
	if _trails.has(id):
		_release_trail(id)
	if delta_vec == Vector3.ZERO and not Block.is_awake_registered(block):
		_prev_positions.erase(id)
	else:
		_prev_positions[id] = position


## Fix round (owner: the previous particle-burst trail read as "dashed/
## dotted... not attached to the falling piece" -- GPUParticles3D defaults
## to world-space simulation, so each already-emitted particle stayed fixed
## in place as the emitter/block kept falling past it, leaving a trail of
## disconnected blobs drifting behind). Now a single persistent wrapper
## Node3D per fast-falling block (built once by _build_trail_wrapper() and
## kept in `_trails`), re-positioned/re-oriented/re-scaled every physics
## step: `wrapper.global_position` is always exactly the block's own current
## position (plus trail_top_offset_m), so it can never lag or detach the way
## a world-space particle could. `wrapper`'s basis is re-derived every call
## from `velocity` so the streak always points opposite the block's current
## travel direction, and each streak's own length is re-derived from
## `fall_speed` (trail_length_per_speed_s, clamped to [trail_min_length_m,
## trail_max_length_m]) -- "length proportional to speed".
func _ensure_trail(id: int, block: Block, fall_speed: float, velocity: Vector3) -> void:
	var wrapper: Node3D = _trails.get(id) as Node3D
	if wrapper != null and not is_instance_valid(wrapper):
		wrapper = null
		_trails.erase(id)
	if wrapper == null:
		if _trails.size() >= config.trail_max_concurrent:
			return
		wrapper = _build_trail_wrapper(_color_for_owner_slot(block.owner_slot, config.trail_fallback_color))
		add_child(wrapper)
		_trails[id] = wrapper

	var tail_direction: Vector3 = -velocity.normalized() if velocity.length() > 0.001 else Vector3.UP
	var up_hint: Vector3 = Vector3.UP if absf(tail_direction.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	wrapper.global_position = block.global_position + Vector3.UP * config.trail_top_offset_m
	wrapper.global_transform.basis = Basis.looking_at(tail_direction, up_hint)

	var length: float = clampf(
		fall_speed * config.trail_length_per_speed_s, config.trail_min_length_m, config.trail_max_length_m
	)
	for child: Node in wrapper.get_children():
		var streak: MeshInstance3D = child as MeshInstance3D
		if streak != null:
			streak.scale = Vector3(config.trail_streak_width_m, 1.0, length)


## config.trail_streak_count parallel MeshInstance3D children, each sharing
## one unit-length/unit-width quad mesh (_get_trail_unit_mesh(), scaled per
## frame by _ensure_trail() instead of rebuilt) and one ShaderMaterial
## instance tinted to `color` -- "2-3 thin parallel streaks offset across
## the block's width".
func _build_trail_wrapper(color: Color) -> Node3D:
	var wrapper: Node3D = Node3D.new()
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = TRAIL_SHADER
	material.set_shader_parameter(&"trail_color", color)
	material.set_shader_parameter(&"emission_energy", config.trail_emission_energy)
	material.set_shader_parameter(&"max_alpha", config.trail_alpha_max)
	var mesh: ArrayMesh = _get_trail_unit_mesh()
	var count: int = maxi(config.trail_streak_count, 1)
	for i: int in range(count):
		var streak: MeshInstance3D = MeshInstance3D.new()
		streak.mesh = mesh
		streak.material_override = material
		var offset: float = (float(i) - float(count - 1) * 0.5) * config.trail_lateral_offset_m
		streak.position = Vector3(offset, 0.0, 0.0)
		wrapper.add_child(streak)
	return wrapper


## A flat quad from local (X, 0, 0) [head, UV.y=0] to (X, 0, -1) [tail,
## UV.y=1], X spanning -0.5..0.5 -- _ensure_trail() applies the actual
## width/length every frame via non-uniform scale (scale.x = width,
## scale.z = length) rather than rebuilding this mesh, so every trail
## streak in the game shares this exact same ArrayMesh resource. Built once
## and cached, matching _get_fade_ramp()/_get_shrink_curve()'s own pattern.
var _trail_unit_mesh: ArrayMesh = null
func _get_trail_unit_mesh() -> ArrayMesh:
	if _trail_unit_mesh == null:
		var positions: PackedVector3Array = PackedVector3Array([
			Vector3(-0.5, 0.0, 0.0), Vector3(0.5, 0.0, 0.0),
			Vector3(-0.5, 0.0, -1.0), Vector3(0.5, 0.0, -1.0),
		])
		var uvs: PackedVector2Array = PackedVector2Array([
			Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.0, 1.0), Vector2(1.0, 1.0),
		])
		var indices: PackedInt32Array = PackedInt32Array([0, 2, 1, 1, 2, 3])
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = positions
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh: ArrayMesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_trail_unit_mesh = mesh
	return _trail_unit_mesh


## The trail is a persistent mesh now, not particles, so there is nothing to
## stop emitting -- just free it after a short fade delay
## (trail_release_fade_s) once the block is no longer falling fast, the same
## create_timer(...) fallback pattern _schedule_cleanup_fallback() already
## uses elsewhere in this file.
func _release_trail(id: int) -> void:
	if not _trails.has(id):
		return
	var wrapper: Node3D = _trails[id]
	_trails.erase(id)
	if not is_instance_valid(wrapper):
		return
	_schedule_cleanup_fallback(wrapper, config.trail_release_fade_s)


## GPUParticles3D.finished is driven by the visual particle system and may
## never fire in a headless run (no renderer advancing it) -- confirmed by
## this package's own test_block_effects.gd cleanup case, which awaits this
## timer rather than the finished signal. This fallback frees the node
## `lifetime + config.cleanup_margin_s` after spawn if it's somehow still
## alive, guarded against a double free (finished already freed it first).
##
## DECISION: binds the particle node's own instance id (an int), not the node
## itself -- a lambda/Callable.bind() that captures a live Object reference
## and later fires after that same object has already been freed (e.g. by
## `finished` above, or by a GutTest tearing down a still-pending timer from a
## previous test) makes the engine print "Lambda capture ... was freed" as an
## unexpected error, even though the capture is otherwise harmless. Binding a
## plain int and resolving it back through instance_from_id() at call time
## avoids that engine-level check entirely.
##
## Bontago-mp0.3.4: `node` is now any Node (a bare GPUParticles3D for the
## kill-plane path's own original shape and every falling trail, or a wrapper
## Node3D holding two GPUParticles3D children for a landing burst) -- freeing
## a wrapper frees its particle children too, so one fallback timer is enough
## per effect regardless of how many particle systems it holds.
func _schedule_cleanup_fallback(node: Node, lifetime: float) -> void:
	var timer: SceneTreeTimer = get_tree().create_timer(lifetime + config.cleanup_margin_s)
	timer.timeout.connect(_on_cleanup_fallback_timeout.bind(node.get_instance_id()))


func _on_cleanup_fallback_timeout(node_id: int) -> void:
	var node: Object = instance_from_id(node_id)
	if node == null or not is_instance_valid(node):
		return
	var live_node: Node = node as Node
	if live_node == null or live_node.is_queued_for_deletion():
		return
	live_node.queue_free()


func _build_mesh(mesh_scale: float, color: Color) -> Mesh:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3.ONE * mesh_scale
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	return mesh


func _build_process_material(spread_deg: float, initial_speed: float, gravity: Vector3) -> ParticleProcessMaterial:
	var material: ParticleProcessMaterial = ParticleProcessMaterial.new()
	material.direction = Vector3.UP
	material.spread = spread_deg
	material.initial_velocity_min = initial_speed * 0.5
	material.initial_velocity_max = initial_speed
	material.gravity = gravity
	material.scale_min = 1.0
	material.scale_max = 1.0
	return material


## Test/inspection seam: how many pooled burst effects are currently active
## (still inside their lifetime).
func active_effect_count() -> int:
	return _active_bursts


## Test seam: total pooled burst wrappers ever created (pool reuse check).
func pooled_burst_count() -> int:
	return _landing_pool.size() + _kill_pool.size()
