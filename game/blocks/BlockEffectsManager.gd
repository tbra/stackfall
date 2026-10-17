class_name BlockEffectsManager
extends Node3D
## Spec 1.10 "effects + camera shake": visual effects for block events.
## Purely cosmetic -- never touches territory/physics/win-check state.
##
## Three effect kinds (config/blocks/tuning/BlockEffectsConfig.gd has every tunable):
## - landing burst: Events.block_impacted_at, whenever a block's own detected
##   impact speed reaches config.dust_impact_speed_threshold. Spawns a small
##   team-colored cubelet shower (_find_block_at() resolves the owning slot by a
##   physics point query at the impact position -- Events.block_impacted_at
##   only carries speed/position, not the block itself) plus a softer dust
##   puff, both under one wrapper Node3D so one impact is a single effect.
## - falling-block trail: a continuous, team-tinted luminous streak behind any
##   block whose measured fall speed crosses config.trail_speed_threshold --
##   see _update_falling_trails()'s own doc for why this is driven from
##   Block.TUNING_GROUP every physics step rather than an Events signal.
## - kill-plane edge-fall burst: Events.block_removed(block,
##   REASON_KILL_PLANE), fired at the block's last position immediately
##   before game/field/Field.gd's queue_free() call.
## # DECISION: the kill-plane burst is a one-shot particle burst fired at
## removal time, not a continuous falling trail, since the block node is
## about to be freed -- matches spec intent without new mid-flight tracking.

@export var config: BlockEffectsConfig = preload("res://config/blocks/tuning/block_effects.tres")

## Radius (meters) of the sphere shape query _find_block_at() uses to
## resolve the impacting block's owning slot -- see that method's own DECISION for
## why a sphere, not a point. A query-robustness detail, not a gameplay tunable
## (a BlockShape's single-cube edge length is the reference scale it only has to
## comfortably beat).
const FIND_BLOCK_QUERY_RADIUS_M: float = 0.35
## Reused by _find_block_at; built lazily.
var _find_params: PhysicsShapeQueryParameters3D = null

const DUST_SHADER: Shader = preload("res://shaders/gifts/dust_puff.gdshader")
const CUBELET_SHADER: Shader = preload("res://shaders/gifts/cubelet.gdshader")
const TRAIL_SHADER: Shader = preload("res://shaders/gifts/trail_streak.gdshader")

## A single Gradient-driven fade (alpha 1 -> 0 over a particle's own
## lifetime), shared by every dust/cubelet burst's ParticleProcessMaterial.
## color_ramp -- both shaders/gifts/dust_puff.gdshader and shaders/gifts/cubelet.gdshader read
## this back as COLOR.a. Built once (GradientTexture1D.update() has real
## cost) and cached, not rebuilt per burst.
# DECISION: instance (not static) caches -- static Resource vars kept the
# whole Block/Field script graph alive at editor exit ("resources still in
# use" leak on the open-project check). One manager per match, so cost is equal.
var _fade_ramp: GradientTexture1D = null

## Per-block previous global_position, keyed by Object.get_instance_id() (the
## freed-object-safe key idiom from _schedule_cleanup_fallback()'s DECISION).
## Used only to measure each block's own fall speed
## every physics step (_update_falling_trails()); pruned in the same pass for
## any id no longer seen in Block.TUNING_GROUP.
var _prev_positions: Dictionary = {}

## instance id (int) -> the wrapper Node3D (holding config.trail_streak_count
## MeshInstance3D streaks) currently following that block. Absence means "no
## active trail for this block" -- either it never crossed
## trail_speed_threshold, or _release_trail() already started freeing it.
var _trails: Dictionary = {}

## Settings.graphics_preset_changed-driven (see _on_graphics_preset_changed()):
## gates only the falling trail, the one continuous per-frame effect. It reuses
## game/sky/Skybox.gd's volumetric_fog_enabled flag as "heavy atmospheric/ambient
## effects" rather than adding a second graphics-preset field. The one-shot
## landing/kill bursts stay on every preset: they are bounded one-shot costs.
var _trail_effects_enabled: bool = true
## GraphicsPreset.particle_budget_scale (adaptive quality governor).
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


## Landing burst: a team-colored cubelet shower plus a grey-brown dust puff,
## both scaled by _impact_intensity() and held by one pooled wrapper Node3D, one
## effect per impact. Wrappers/particle systems come from a reuse pool and are restarted, meshes/materials are shared per
## colour/kind, and new bursts are budgeted (see _acquire_burst()).
func _on_block_impacted_at(speed: float, position: Vector3) -> void:
	if speed < config.dust_impact_speed_threshold:
		return
	# Budget check first: the slot physics query below is not free either.
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


## Pooled flipbook puff (game/blocks/ImpactPuff.gd) at the contact
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


## impact speed / dust_impact_speed_threshold, clamped to [1, impact_intensity_
## max] -- 1.0 at exactly the threshold (no scale-up for a barely-qualifying
## impact), growing for a harder one. Shared by both the cubelet and dust
## bursts above so a single hard impact scales both together.
func _impact_intensity(speed: float) -> float:
	if config.dust_impact_speed_threshold <= 0.0:
		return 1.0
	return clampf(speed / config.dust_impact_speed_threshold, 1.0, config.impact_intensity_max)


## Events.block_impacted_at carries only (speed, position), so this resolves the
## impacting block's owner_slot from the outside: a small-sphere physics shape
## query centered at the impact position (the block's own global_position at emit
## time, game/blocks/Block.gd). Returns null (the cubelet burst falls back to
## config.cubelet_fallback_color) when nothing resolves -- e.g. a test that
## emits the signal directly with no real Block in the world
## (tests/unit/blocks/test_block_effects.gd).
##
## DECISION (game/blocks/BlockEffectsManager.gd): a sphere query, not a
## zero-radius point query (the original candidate) -- game/blocks/BlockFactory.gd
## builds a multi-cube block as a COMPOUND of one CollisionShape3D per cube,
## each offset from the RigidBody3D's own origin (BlockFactory.build(), "one
## CollisionShape3D per cell"). For any shape wider than a single cube, that
## origin can sit exactly on a shared edge/corner between cubes -- outside
## every individual cube's own box shape -- so a zero-radius point query
## there can miss the block entirely (a landing square4 (2x2) block's cubelet
## burst rendered in cubelet_fallback_color instead of its team color). A small sphere
## (FIND_BLOCK_QUERY_RADIUS_M) reliably overlaps at least one of the
## impacting block's own cube shapes regardless of where its origin sits.
func _find_block_at(position: Vector3) -> Block:
	var world: World3D = get_world_3d()
	if world == null:
		return null
	var space_state: PhysicsDirectSpaceState3D = world.direct_space_state
	if space_state == null:
		return null
	# query objects reused across impacts (same shape/radius/flags).
	if _find_params == null:
		var query_shape: SphereShape3D = SphereShape3D.new()
		query_shape.radius = FIND_BLOCK_QUERY_RADIUS_M
		_find_params = PhysicsShapeQueryParameters3D.new()
		_find_params.shape = query_shape
		_find_params.collide_with_bodies = true
		_find_params.collide_with_areas = false
	_find_params.transform = Transform3D(Basis(), position)
	var results: Array[Dictionary] = space_state.intersect_shape(_find_params, 8)
	for result: Dictionary in results:
		var collider: Object = result.get("collider")
		if collider is Block:
			return collider as Block
	return null


## Follows GiftCrate._claim_color()'s fallback shape (that file's doc explains
## why it is not a shared helper): a real PlayerSlot's own colour
## when Match can name one for `slot_id`, otherwise the live match's
## MatchConfig.player_colors[slot_id], and `fallback` if neither resolves
## (slot_id < 0, no match running -- both true in
## tests/unit/blocks/test_block_effects.gd, which emits these signals with no Match
## configured).
func _color_for_owner_slot(slot_id: int, fallback: Color) -> Color:
	if slot_id < 0:
		return fallback
	var context: MatchContext = MatchContext.current()
	return context.slot_color(slot_id, fallback)


## Burst pool. One PooledBurst = one wrapper Node3D plus its
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
## Flipbook puff pool (see _spawn_impact_puff()).
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
## headless, so expiry is time-based).
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


## A GPUParticles3D whose draw_pass_1 mesh/material give each cube
## shaders/gifts/cubelet.gdshader's cheap 2-tone cel look, random per-particle
## size (scale_min/max), tumbling (angular_velocity_min/max), real gravity
## (cubelet_gravity), and a shared fade+shrink profile (color_ramp/scale_curve,
## built once by _get_fade_ramp()/_get_shrink_curve() below). No bounce
## simulation: falling alone reads fine for a particle this short-lived and is
## cheaper.
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
## shaders/gifts/dust_puff.gdshader and shaders/gifts/cubelet.gdshader read this back as
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
## lifetime) for cubelet_burst's ParticleProcessMaterial.scale_curve. Not used
## by the dust burst (dust puffs expand quickly rather than shrink).
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


## Falling-block trail: every live Block adds itself to Block.TUNING_GROUP in
## _ready(), which reaches every live block without a new coupling. Measures each block's own
## fall velocity from its position delta this physics step, not
## RigidBody3D.linear_velocity: a client's synced blocks are frozen kinematic
## (net/SnapshotSync.gd's freeze_body(), spec 2.6) and driven purely by
## net/Interpolator.gd writing global_position directly, never by real
## physics integration, so linear_velocity would read as a false zero for
## every client-visible falling block. A position-delta measurement reads
## correctly on both the host (real physics) and a client (interpolated
## position) with no freeze-state branch needed here at all.
func _update_falling_trails(delta: float) -> void:
	# Only awake blocks (Block.awake_blocks(), which also
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


## A single persistent wrapper Node3D per fast-falling block, not a particle
## trail (GPUParticles3D simulates in world space by default, so emitted
## particles would stay behind as disconnected blobs). Built once by
## _build_trail_wrapper() and kept in `_trails`, re-positioned/re-oriented/re-scaled every physics
## step: `wrapper.global_position` is always exactly the block's own current
## visual centre (_trail_anchor()), so it can never lag or detach the way a
## world-space particle could, and the block itself hides the ribbon's head.
## `wrapper`'s basis is re-derived every call: local -Z runs opposite the
## block's travel and local +Y (the quad's normal) turns about that axis
## toward the camera (a fixed flat strip went edge-on from many
## views). The ribbon's length follows `fall_speed` (trail_length_per_speed_s,
## clamped to [trail_min_length_m, trail_max_length_m]); its width is fixed per
## block at build time.
func _ensure_trail(id: int, block: Block, fall_speed: float, velocity: Vector3) -> void:
	var wrapper: Node3D = _trails.get(id) as Node3D
	if wrapper != null and not is_instance_valid(wrapper):
		wrapper = null
		_trails.erase(id)
	if wrapper == null:
		if _trails.size() >= config.trail_max_concurrent:
			return
		wrapper = _build_trail_wrapper(
			_color_for_owner_slot(block.owner_slot, config.trail_fallback_color), _trail_width_for(block)
		)
		add_child(wrapper)
		_trails[id] = wrapper

	var anchor: Vector3 = _trail_anchor(block)
	var tail: Vector3 = -velocity.normalized() if velocity.length() > 0.001 else Vector3.UP
	wrapper.global_transform = Transform3D(_trail_basis(tail, anchor), anchor)

	var length: float = clampf(
		fall_speed * config.trail_length_per_speed_s, config.trail_min_length_m, config.trail_max_length_m
	)
	var ribbon: MeshInstance3D = wrapper.get_child(0) as MeshInstance3D
	if ribbon != null:
		ribbon.scale = Vector3(float(wrapper.get_meta(TRAIL_WIDTH_META, config.trail_min_width_m)), 1.0, length)


const TRAIL_WIDTH_META: StringName = &"trail_width_m"
## Below this squared length the camera lies on the travel axis (no facing direction).
const TRAIL_ON_AXIS_SQ: float = 0.0001
## |dot| above which a fallback normal is too close to the travel axis to use.
const TRAIL_PARALLEL_DOT: float = 0.99


## The block's visual centre: a gift carrier's GiftVisual (its BlockMesh is
## hidden, BlockFactory.apply_gift_visual), else the BlockMesh bounds centre in
## world space (a piece's body origin sits on its pivot cell, not its middle),
## else the body position.
func _trail_anchor(block: Block) -> Vector3:
	var gift: Node3D = block.get_node_or_null(NodePath(String(BlockFactory.GIFT_VISUAL_NODE))) as Node3D
	if gift != null:
		return gift.global_position
	var mesh: MeshInstance3D = block.get_node_or_null(^"BlockMesh") as MeshInstance3D
	if mesh == null or mesh.mesh == null:
		return block.global_position
	return mesh.global_transform * mesh.get_aabb().get_center()


## Ribbon width from the block's mean horizontal extent (trail_width_ratio,
## clamped to [trail_min_width_m, trail_max_width_m]): the BlockMesh bounds, or
## for a gift carrier its single box collider.
func _trail_width_for(block: Block) -> float:
	var size: Vector3 = Vector3.ZERO
	if block.get_node_or_null(NodePath(String(BlockFactory.GIFT_VISUAL_NODE))) != null:
		for child: Node in block.get_children():
			var collider: CollisionShape3D = child as CollisionShape3D
			var box: BoxShape3D = collider.shape as BoxShape3D if collider != null else null
			if box != null:
				size = box.size
				break
	else:
		var mesh: MeshInstance3D = block.get_node_or_null(^"BlockMesh") as MeshInstance3D
		if mesh != null and mesh.mesh != null:
			size = mesh.get_aabb().size * mesh.global_transform.basis.get_scale()
	var extent: float = (size.x + size.z) * 0.5 * config.trail_width_ratio
	return clampf(extent, config.trail_min_width_m, config.trail_max_width_m)


## Local -Z along `tail`, local +Y (the quad normal) toward the active camera,
## rotated only about the tail axis. Without a camera (headless) or when looking
## straight down the axis, any normal perpendicular to `tail` is used.
func _trail_basis(tail: Vector3, anchor: Vector3) -> Basis:
	var to_camera: Vector3 = Vector3.ZERO
	var viewport: Viewport = get_viewport()
	var camera: Camera3D = viewport.get_camera_3d() if viewport != null else null
	if camera != null:
		to_camera = camera.global_position - anchor
	var normal: Vector3 = to_camera - tail * to_camera.dot(tail)
	if normal.length_squared() < TRAIL_ON_AXIS_SQ:
		normal = Vector3.FORWARD if absf(tail.dot(Vector3.FORWARD)) < TRAIL_PARALLEL_DOT else Vector3.RIGHT
		normal = normal - tail * normal.dot(tail)
	normal = normal.normalized()
	var z_axis: Vector3 = -tail
	return Basis(normal.cross(z_axis), normal, z_axis)


## One camera-facing ribbon on the shared unit quad
## (_get_trail_unit_mesh(), scaled per frame by _ensure_trail() instead of
## rebuilt), tinted to `color`; shaders/gifts/trail_streak.gdshader draws a soft glow
## with config.trail_streak_count bright speed lines inside it.
func _build_trail_wrapper(color: Color, width_m: float) -> Node3D:
	var wrapper: Node3D = Node3D.new()
	wrapper.set_meta(TRAIL_WIDTH_META, width_m)
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = TRAIL_SHADER
	material.set_shader_parameter(&"trail_color", color)
	material.set_shader_parameter(&"emission_energy", config.trail_emission_energy)
	material.set_shader_parameter(&"max_alpha", config.trail_alpha_max)
	material.set_shader_parameter(&"line_count", float(maxi(config.trail_streak_count, 0)))
	var ribbon: MeshInstance3D = MeshInstance3D.new()
	ribbon.mesh = _get_trail_unit_mesh()
	ribbon.material_override = material
	ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ribbon.extra_cull_margin = config.trail_max_length_m
	wrapper.add_child(ribbon)
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


## The trail is a persistent mesh, so there is nothing to stop emitting: free it
## after a short fade delay (trail_release_fade_s) once the block is no longer
## falling fast, via _schedule_cleanup_fallback().
func _release_trail(id: int) -> void:
	if not _trails.has(id):
		return
	var wrapper: Node3D = _trails[id]
	_trails.erase(id)
	if not is_instance_valid(wrapper):
		return
	_schedule_cleanup_fallback(wrapper, config.trail_release_fade_s)


## Frees the node `lifetime + config.cleanup_margin_s` from now if it is still
## alive, guarded against a double free. Timer-based because
## GPUParticles3D.finished may never fire in a headless run (no renderer
## advancing it).
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
## `node` is any Node; freeing a wrapper frees its children too, so one fallback
## timer is enough per effect.
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
