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


func _ready() -> void:
	Events.block_removed.connect(_on_block_removed)
	Events.block_impacted_at.connect(_on_block_impacted_at)
	var preset: GraphicsPreset = Settings.current_graphics_preset()
	_trail_effects_enabled = preset == null or preset.volumetric_fog_enabled
	Settings.graphics_preset_changed.connect(_on_graphics_preset_changed)


func _exit_tree() -> void:
	if Settings.graphics_preset_changed.is_connected(_on_graphics_preset_changed):
		Settings.graphics_preset_changed.disconnect(_on_graphics_preset_changed)


func _on_graphics_preset_changed(preset: GraphicsPreset) -> void:
	_trail_effects_enabled = preset == null or preset.volumetric_fog_enabled


func _physics_process(delta: float) -> void:
	if delta <= 0.0:
		return
	var probe_effects: int = PerfProbe.start()
	_update_falling_trails(delta)
	PerfProbe.stop(&"block_effects", probe_effects)


func _on_block_removed(block: RigidBody3D, reason: String) -> void:
	if reason != String(Events.REASON_KILL_PLANE):
		return
	if block == null:
		return
	var wrapper: Node3D = Node3D.new()
	add_child(wrapper)
	wrapper.global_position = block.global_position
	_attach_burst(
		wrapper,
		config.kill_particle_amount,
		config.kill_lifetime_s,
		config.kill_initial_speed,
		config.kill_spread_deg,
		config.kill_gravity,
		config.kill_scale,
		config.kill_color,
	)
	_schedule_cleanup_fallback(wrapper, config.kill_lifetime_s)


## Landing burst (Bontago-mp0.3.4): a team-colored cubelet shower plus the
## original grey-brown dust puff, both scaled by _impact_intensity() and
## spawned under one wrapper Node3D so active_effect_count() (counting the
## manager's own children) still reports one effect per impact, matching this
## file's pre-existing tests/unit/test_block_effects.gd contract.
func _on_block_impacted_at(speed: float, position: Vector3) -> void:
	if speed < config.dust_impact_speed_threshold:
		return
	var intensity: float = _impact_intensity(speed)
	var owner_block: Block = _find_block_at(position)
	var owner_slot: int = owner_block.owner_slot if owner_block != null else -1
	var cubelet_color: Color = _color_for_owner_slot(owner_slot, config.cubelet_fallback_color)

	var wrapper: Node3D = Node3D.new()
	add_child(wrapper)
	wrapper.global_position = position

	var cubelet_amount: int = int(round(min(
		float(config.cubelet_max_particle_amount),
		float(config.cubelet_particle_amount) * intensity,
	)))
	_attach_cubelet_burst(wrapper, cubelet_amount, cubelet_color, intensity)
	_attach_dust_burst(wrapper, int(round(float(config.dust_particle_amount) * intensity)))
	_schedule_cleanup_fallback(wrapper, max(config.cubelet_lifetime_s, config.dust_lifetime_s))


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
func _attach_cubelet_burst(parent: Node3D, amount: int, color: Color, intensity: float) -> void:
	if amount <= 0:
		return
	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.amount = amount
	particles.lifetime = config.cubelet_lifetime_s
	particles.explosiveness = 1.0
	particles.draw_pass_1 = _build_cubelet_mesh(color)
	particles.process_material = _build_cubelet_process_material(intensity)
	parent.add_child(particles)
	particles.finished.connect(particles.queue_free)
	particles.emitting = true


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


## Fix round (owner: dust rendered as "huge flat hard-edged blown-out yellow
## rectangles"): a GPUParticles3D whose draw_pass_1 mesh/material give each
## puff vfx/dust_puff.gdshader's soft round billboarded look, emitted on a
## ring around the impact point (dust_ring_*) so the spread reads as "along
## the ground from the impact point" rather than one dense clump.
func _attach_dust_burst(parent: Node3D, amount: int) -> void:
	if amount <= 0:
		return
	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.amount = amount
	particles.lifetime = config.dust_lifetime_s
	particles.explosiveness = 1.0
	particles.draw_pass_1 = _build_dust_mesh()
	particles.process_material = _build_dust_process_material()
	parent.add_child(particles)
	particles.finished.connect(particles.queue_free)
	particles.emitting = true


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
	var blocks: Array[Node] = get_tree().get_nodes_in_group(Block.TUNING_GROUP)
	var inv_delta: float = 1.0 / delta
	var threshold: float = config.trail_speed_threshold
	var trails_on: bool = _trail_effects_enabled
	var seen_count: int = 0
	for node: Node in blocks:
		var block: Block = node as Block
		if block == null or not is_instance_valid(block):
			continue
		seen_count += 1
		var id: int = block.get_instance_id()
		var position: Vector3 = block.global_position
		var prev_position: Vector3 = _prev_positions.get(id, position)
		var delta_vec: Vector3 = position - prev_position
		var fall_speed: float = -delta_vec.y * inv_delta
		_prev_positions[id] = position
		if trails_on and fall_speed >= threshold:
			_ensure_trail(id, block, fall_speed, delta_vec * inv_delta)
		elif _trails.has(id):
			_release_trail(id)

	# Every seen id is in _prev_positions by now, so a size mismatch is the
	# only case where a stale (removed block) entry exists: prune then.
	if _prev_positions.size() == seen_count:
		return
	var seen_ids: Dictionary = {}
	for node: Node in blocks:
		if node is Block and is_instance_valid(node):
			seen_ids[node.get_instance_id()] = true
	for id: int in _prev_positions.keys():
		if not seen_ids.has(id):
			_prev_positions.erase(id)
			_release_trail(id)


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


## Shared by every burst kind above: builds one continuous GPUParticles3D as
## a child of `parent` (a wrapper Node3D already positioned at the effect's
## world location, or -- for the trail's own separate pool -- `self`
## directly). Callers are responsible for parent's own cleanup; this only
## wires the particle node itself, matching its own pre-existing (pre-
## Bontago-mp0.3.4) one-shot-burst behavior exactly.
func _attach_burst(
	parent: Node3D,
	amount: int,
	lifetime: float,
	initial_speed: float,
	spread_deg: float,
	gravity: Vector3,
	mesh_scale: float,
	color: Color,
) -> void:
	if amount <= 0:
		return
	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.amount = amount
	particles.lifetime = lifetime
	particles.explosiveness = 1.0
	particles.draw_pass_1 = _build_mesh(mesh_scale, color)
	particles.process_material = _build_process_material(spread_deg, initial_speed, gravity)
	parent.add_child(particles)
	particles.finished.connect(particles.queue_free)
	particles.emitting = true


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


## Test/inspection seam: how many burst effects are currently alive (children
## still finishing their one-shot emission, or awaiting their cleanup
## fallback timer).
func active_effect_count() -> int:
	return get_child_count()
