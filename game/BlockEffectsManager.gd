class_name BlockEffectsManager
extends Node3D
## Bontago-xtq.29 (M7 P4, spec 2.10 "effects + camera shake"): one-shot visual
## effects for block events. Purely additive/cosmetic -- never touches
## territory/physics/win-check state (core/ stays untouched), so it is safe to
## add as a child of game/Field.tscn without affecting any existing gameplay
## test (tests/unit/test_field.gd builds Field.new() directly and never loads
## the .tscn, so this node never even exists in that suite).
##
## Two effect kinds, one shared spawn helper (_spawn_burst(), parameterised
## entirely by config's exported fields -- see config/BlockEffectsConfig.gd):
## - landing dust / impact burst: Events.block_impacted_at, whenever a block's
##   own detected impact speed reaches config.dust_impact_speed_threshold.
##   Events.block_impacted_at is additive alongside the pre-existing
##   Events.block_impacted (autoload/Sfx.gd's own listener, untouched) and
##   also carries the block's global_position at emit time (game/Block.gd).
## - kill-plane edge-fall burst: Events.block_removed(block,
##   REASON_KILL_PLANE), fired at the block's last position immediately
##   before game/Field.gd's queue_free() call.
## # DECISION: the kill-plane burst is a one-shot particle burst fired at
## removal time, not a continuous falling trail, since the block node is
## about to be freed -- matches spec intent without new mid-flight tracking.

@export var config: BlockEffectsConfig = preload("res://config/block_effects.tres")


func _ready() -> void:
	Events.block_removed.connect(_on_block_removed)
	Events.block_impacted_at.connect(_on_block_impacted_at)


func _on_block_removed(block: RigidBody3D, reason: String) -> void:
	if reason != String(Events.REASON_KILL_PLANE):
		return
	if block == null:
		return
	_spawn_burst(
		block.global_position,
		config.kill_particle_amount,
		config.kill_lifetime_s,
		config.kill_initial_speed,
		config.kill_spread_deg,
		config.kill_gravity,
		config.kill_scale,
		config.kill_color,
	)


func _on_block_impacted_at(speed: float, position: Vector3) -> void:
	if speed < config.dust_impact_speed_threshold:
		return
	_spawn_burst(
		position,
		config.dust_particle_amount,
		config.dust_lifetime_s,
		config.dust_initial_speed,
		config.dust_spread_deg,
		config.dust_gravity,
		config.dust_scale,
		config.dust_color,
	)


func _spawn_burst(
	world_position: Vector3,
	amount: int,
	lifetime: float,
	initial_speed: float,
	spread_deg: float,
	gravity: Vector3,
	mesh_scale: float,
	color: Color,
) -> void:
	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.amount = amount
	particles.lifetime = lifetime
	particles.explosiveness = 1.0
	particles.draw_pass_1 = _build_mesh(mesh_scale, color)
	particles.process_material = _build_process_material(spread_deg, initial_speed, gravity)
	# DECISION: global_position must be set only after add_child() -- Node3D's
	# global_position setter requires is_inside_tree() (it walks up the parent
	# chain to resolve the global transform), so setting it beforehand throws
	# "!is_inside_tree()" and silently leaves the node at the origin.
	add_child(particles)
	particles.global_position = world_position
	particles.finished.connect(particles.queue_free)
	_schedule_cleanup_fallback(particles, lifetime)
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
func _schedule_cleanup_fallback(particles: GPUParticles3D, lifetime: float) -> void:
	var timer: SceneTreeTimer = get_tree().create_timer(lifetime + config.cleanup_margin_s)
	timer.timeout.connect(_on_cleanup_fallback_timeout.bind(particles.get_instance_id()))


func _on_cleanup_fallback_timeout(particles_id: int) -> void:
	var particles: Object = instance_from_id(particles_id)
	if particles == null or not is_instance_valid(particles):
		return
	var gpu_particles: GPUParticles3D = particles as GPUParticles3D
	if gpu_particles == null or gpu_particles.is_queued_for_deletion():
		return
	gpu_particles.queue_free()


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
