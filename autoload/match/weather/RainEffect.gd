class_name RainEffect
extends WeatherEffect
## Host-side rain physics (Bontago-22y.5): wet friction on the disc and on every
## block, existing and newly spawned, ramping with the framework intensity.
##
## Cost: no contact monitors, no per-frame work per body. Each body already owns
## a PhysicsMaterial (BlockFactory.build(), Field), so "wet" is one float write
## per material when the intensity moved by more than RainTuning.apply_epsilon,
## plus a cheap registry scan every RainTuning.rescan_interval_s to catch
## blocks that spawned during rain.
##
## DECISION (RainEffect.gd): rain MULTIPLIES the baseline it finds instead of
## overwriting with a fixed wet value, so it composes with other effects. The
## baseline of a material is captured when rain first touches it. If a material's
## friction no longer equals what rain last wrote (Freeze, a tuning-panel change
## or a physics preset applied it meanwhile), that new value becomes the baseline
## and rain rescales it. On restore a material whose friction is still what rain
## wrote returns to its baseline exactly; one someone else has since rewritten is
## left alone (their value already is the intended one).

class _Wet:
	extends RefCounted
	var material: PhysicsMaterial = null
	var baseline: float = 0.0
	var written: float = 0.0
	var is_disc: bool = false

var _wet: Dictionary = {}  ## material instance id (int) -> _Wet
var _last_intensity: float = 0.0
var _scan_left: float = 0.0
## Test seam: Callable returning Array of CollisionObject3D (blocks) and
## Callable returning the disc body (or null). Null = read the live Match.
var _blocks_provider: Callable = Callable()
var _disc_provider: Callable = Callable()


func set_providers(blocks_provider: Callable, disc_provider: Callable) -> void:
	_blocks_provider = blocks_provider
	_disc_provider = disc_provider


func apply(intensity: float) -> void:
	var rain: RainTuning = tuning as RainTuning
	if rain == null:
		return
	_scan()
	if not _wet.is_empty() and absf(intensity - _last_intensity) < rain.apply_epsilon and intensity > 0.0 and intensity < 1.0:
		return
	_last_intensity = intensity
	_write_all(intensity, rain)


func tick(delta: float, intensity: float) -> void:
	var rain: RainTuning = tuning as RainTuning
	if rain == null:
		return
	_apply_slide(rain, intensity)
	_scan_left -= delta
	if _scan_left > 0.0:
		return
	_scan_left = rain.rescan_interval_s
	var before: int = _wet.size()
	_scan()
	if _wet.size() != before:
		_write_all(intensity, rain)


## DECISION (Bontago-mp0.21, round 2): the "negative friction" feel. Each awake
## block already sliding faster than RainTuning.wet_slide_min_speed_mps gets a
## force along its own horizontal velocity, scaled by the ramped intensity, and
## none once it is past wet_slide_max_speed_mps (the cap). Direction follows the
## block, not the disc centre, so RING and TWIN maps are not biased toward a hole
## or a far rim; resting and settling blocks sit under the threshold and are not
## nudged. Nothing to restore (Jolt clears applied forces each step). Iterates
## Block.awake_blocks() (awake set only; sleeping blocks are never touched).
func _apply_slide(rain: RainTuning, intensity: float) -> void:
	if rain.wet_slide_accel_mps2 <= 0.0 or intensity <= 0.0:
		return
	var level: float = clampf(intensity, 0.0, 1.0)
	var min_sq: float = rain.wet_slide_min_speed_mps * rain.wet_slide_min_speed_mps
	var max_sq: float = rain.wet_slide_max_speed_mps * rain.wet_slide_max_speed_mps
	var awake: Array = _slide_candidates()
	for item: Variant in awake:
		var body: RigidBody3D = item as RigidBody3D
		if body == null or not is_instance_valid(body) or body.freeze or body.sleeping or not body.is_inside_tree():
			continue
		var velocity: Vector3 = body.linear_velocity
		velocity.y = 0.0
		var speed_sq: float = velocity.length_squared()
		if speed_sq < min_sq or speed_sq >= max_sq:
			continue
		body.apply_central_force(velocity / sqrt(speed_sq) * body.mass * rain.wet_slide_accel_mps2 * level)


func _slide_candidates() -> Array:
	if _blocks_provider.is_valid():
		return _blocks_provider.call() as Array
	return Block.awake_blocks()


func restore() -> void:
	for key: Variant in _wet.keys():
		var entry: _Wet = _wet[key]
		if entry.material != null and is_equal_approx(entry.material.friction, entry.written):
			entry.material.friction = entry.baseline
	_wet.clear()
	_last_intensity = 0.0
	_scan_left = 0.0


## Adopts every material not tracked yet (baseline = its current friction).
func _scan() -> void:
	for body: Variant in _blocks():
		_adopt(body as CollisionObject3D, false)
	var disc: Variant = _disc()
	if disc != null:
		_adopt(disc as CollisionObject3D, true)


func _adopt(body: CollisionObject3D, is_disc: bool) -> void:
	if body == null or not is_instance_valid(body):
		return
	var material: PhysicsMaterial = body.physics_material_override
	if material == null:
		return
	var key: int = material.get_instance_id()
	if _wet.has(key):
		return
	var entry: _Wet = _Wet.new()
	entry.material = material
	entry.baseline = material.friction
	entry.written = material.friction
	entry.is_disc = is_disc
	_wet[key] = entry


func _write_all(intensity: float, rain: RainTuning) -> void:
	var level: float = clampf(intensity, 0.0, 1.0)
	for key: Variant in _wet.keys():
		var entry: _Wet = _wet[key]
		if entry.material == null:
			continue
		# Someone else rewrote it: their value is the new baseline.
		if not is_equal_approx(entry.material.friction, entry.written):
			entry.baseline = entry.material.friction
		var factor: float = rain.wet_disc_friction_factor if entry.is_disc else rain.wet_block_friction_factor
		var wet_friction: float = entry.baseline * lerpf(1.0, factor, level)
		if level > 0.0:
			wet_friction = minf(entry.baseline, maxf(wet_friction, rain.min_friction))
		entry.material.friction = wet_friction
		entry.written = entry.material.friction


func _blocks() -> Array:
	if _blocks_provider.is_valid():
		return _blocks_provider.call() as Array
	if context == null or context.registry() == null:
		return []
	return (context.registry() as BlockRegistry).all_blocks()


func _disc() -> Variant:
	if _disc_provider.is_valid():
		return _disc_provider.call()
	if context == null:
		return null
	return context.field() as Field
