class_name PerchingBirds
extends Node3D
## Bontago-adt.3: a few cosmetic cel-shaded birds that circle far off, glide in,
## perch on the open disc or on top of settled blocks, idle, and fly away when
## anything comes near; new ones return later. Purely local and visual: nothing
## here is networked, touches physics or feeds back into gameplay. It only reads
## what every client already has (the camera, the local ghost, remote cursors
## from Events, home/goal flags, block transforms).
##
## Theme-gated: game/Skybox.gd calls configure() with the active theme's
## AmbientLifeConfig (null or perch_bird_count 0 = no birds) and the graphics
## preset's ambient-life switch. All tunables live in config/AmbientLifeConfig.gd;
## the pure selection/flee rules are in core/ambient/PerchPlanner.gd.
##
## Bontago-6fc.3: birds are social. They arrive in flocks (a random size within
## AmbientLifeConfig.flock_size_min..max, capped in total by perch_bird_count):
## members join the same arrival circle with loose spacing and jitter, perch near
## the flock's first landing spot (same block top or nearby block tops, or the
## disc within flock_perch_radius_m), play while perched (swap perches, short
## chase flights) and leave together: when one is spooked the rest follow after a
## short random stagger, and when the flock's stay ends it takes off as one.
##
## DECISION (owner 2026-09-30, replaces the disc-only note): birds may perch on the
## top faces of settled blocks. Tower spots need a block that has been motionless
## for AmbientLifeConfig.perch_tower_min_settle_s, a wide-enough top face and
## clear space above; a bird on a block leaves the moment that block moves, is
## hit, is removed, or a block lands on or next to it.

const BIRD_SHADER: Shader = preload("res://shaders/perching_bird.gdshader")
const OUTLINE_SHADER: Shader = preload("res://shaders/perching_bird_outline.gdshader")
## Distance (m) beyond which a hop target is not even considered on the disc.
const NO_THREAT_DIRECTION_JITTER_M: float = 3.0
## Minimum height (m) a block centre must sit above a bird to count as overhead.
const OVERHEAD_MIN_HEIGHT_M: float = 0.4
## Vertical drift (m) of the disc surface under a perched bird that counts as
## the field tilting (the bird takes off).
const SURFACE_DRIFT_M: float = 0.08
## Retry delay (s) when no landing spot was found for a circling bird.
const NO_SPOT_RETRY_S: float = 2.0
## Fraction of the top face's shorter side used as the bird footprint half-size.
const FOOTPRINT_FRACTION: float = 0.35
## Landing attempts a flock member makes near its flock before it just leaves.
const MEMBER_LAND_RETRIES: int = 4
## Smallest hazard radius (m) kept when shrinking hazards for flock members.
const MEMBER_MIN_HAZARD_M: float = 0.5
## Fraction of a bird's length kept clear of a block-top edge for flockmates.
const FACE_EDGE_FRACTION: float = 0.35
## Chase: the second bird starts this far (rad) ahead of the first on the loop.
const CHASE_LEAD_RAD: float = 1.4

class _Slot:
	extends RefCounted
	var bird: PerchingBird = null
	## Seconds until this slot's pending flock member spawns.
	var timer: float = 0.0
	var flock: _Flock = null
	## >= 0: a staggered group takeoff is pending in this many seconds.
	var flee_delay: float = -1.0
	var flee_threat: Vector3 = Vector3.ZERO
	var land_fails: int = 0
	var block: Node3D = null
	var anchor: Transform3D = Transform3D.IDENTITY
	var surface_y: float = 0.0
	var on_tower: bool = false

class _Flock:
	extends RefCounted
	var members: Array[_Slot] = []
	## Members not yet spawned.
	var pending: int = 0
	var age: float = 0.0
	var spooked: bool = false
	# Shared arrival circle.
	var circle_radius: float = 0.0
	var circle_altitude: float = 0.0
	var circle_dir: float = 1.0
	var circle_angle: float = 0.0
	var circle_time: float = 0.0
	# The first landing, which later members settle near.
	var anchor_set: bool = false
	var anchor: Vector3 = Vector3.ZERO
	var on_tower: bool = false
	var block: Node3D = null
	var anchor_xf: Transform3D = Transform3D.IDENTITY
	var face_size: float = 0.0
	var stay_started: bool = false
	var stay_left: float = 0.0
	var social_left: float = 0.0

var config: AmbientLifeConfig = null

## World model. game/Skybox.gd binds a Field and BlockRegistry; tests set these
## directly.
var disc_centre: Vector3 = Vector3.ZERO
var disc_radius: float = 30.0
## Callable(Vector2 world_xz) -> bool: is that point on solid disc.
var on_disc: Callable = Callable()
## Callable(Vector2 world_xz) -> Vector3: the disc surface point there.
var surface_point: Callable = Callable()
var home_points: PackedVector3Array = PackedVector3Array()
var goal_points: PackedVector3Array = PackedVector3Array()
var blocks: Array[Node3D] = []
## Test hook: when non-null (a Vector3) replaces the viewport camera position.
var camera_override: Variant = null

var _field: Field = null
var _registry: BlockRegistry = null
var _enabled: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _clock: float = 0.0
var _poll_left: float = 0.0
var _slots: Array[_Slot] = []
var _flocks: Array[_Flock] = []
var _flock_timer: float = 0.0
## Per-poll block samples shared by every bird (no per-bird block scans).
var _poll_blocks: PackedVector3Array = PackedVector3Array()
var _unsettled_points: PackedVector3Array = PackedVector3Array()
var _unsettled_ids: PackedInt64Array = PackedInt64Array()
var _cursors: Dictionary = {}
var _block_track: Dictionary = {}
var _hazard_points: PackedVector3Array = PackedVector3Array()
var _hazard_radii: PackedFloat32Array = PackedFloat32Array()
## Hazards before the per-bird spacing entries (a hopping bird ignores its own).
var _static_hazard_count: int = 0
var _hazard_shrink: float = 0.0
var _bird_serial: int = 0
var _material: ShaderMaterial = null
var _outline: ShaderMaterial = null


func _ready() -> void:
	_rng.randomize()
	Events.remote_cursor_updated.connect(_on_remote_cursor_updated)
	Events.player_eliminated.connect(_on_player_eliminated)
	Events.block_impacted_at.connect(_on_block_impacted_at)
	Events.match_state_changed.connect(_on_match_state_changed)
	set_process(false)


func _exit_tree() -> void:
	if Events.remote_cursor_updated.is_connected(_on_remote_cursor_updated):
		Events.remote_cursor_updated.disconnect(_on_remote_cursor_updated)
	if Events.player_eliminated.is_connected(_on_player_eliminated):
		Events.player_eliminated.disconnect(_on_player_eliminated)
	if Events.block_impacted_at.is_connected(_on_block_impacted_at):
		Events.block_impacted_at.disconnect(_on_block_impacted_at)
	if Events.match_state_changed.is_connected(_on_match_state_changed):
		Events.match_state_changed.disconnect(_on_match_state_changed)


## Binds the live Field and BlockRegistry (either may be null: the disc model
## then stays whatever the fields above hold).
func bind_scene(field: Field, registry: BlockRegistry) -> void:
	_field = field
	_registry = registry


## Rebuilds the birds from `life` (none when null, perch_bird_count is 0 or
## `enabled` is false). Safe to call repeatedly: never leaves duplicates.
func configure(life: AmbientLifeConfig, enabled: bool) -> void:
	_clear_birds()
	config = life
	_enabled = enabled and life != null and life.perch_bird_count > 0
	visible = _enabled
	set_process(_enabled)
	if not _enabled:
		_slots.clear()
		_flocks.clear()
		return
	_ensure_materials()
	_outline.set_shader_parameter(&"outline_color", life.perch_outline_color)
	_start_slots()


## Removes every bird and restarts the return timers (a match ended or began).
func reset() -> void:
	_clear_birds()
	_cursors.clear()
	_block_track.clear()
	if _enabled:
		_start_slots()


func is_enabled() -> bool:
	return _enabled


## Birds currently in the scene (flying in, perched or fleeing).
func active_bird_count() -> int:
	var count: int = 0
	for slot: _Slot in _slots:
		if slot.bird != null:
			count += 1
	return count


func slot_count() -> int:
	return _slots.size()


## The bird in slot `index`, or null while that slot waits to spawn.
func bird_at(index: int) -> PerchingBird:
	return _slots[index].bird if index >= 0 and index < _slots.size() else null


## Test/debug: forces the next flock arrival on the next update (`_index` is
## kept for the old per-slot API and ignored).
func spawn_now(_index: int = 0) -> void:
	_flock_timer = 0.0


func flock_count() -> int:
	return _flocks.size()


## Slot indices of the flock that slot `index` belongs to (empty when none).
func flock_slot_indices(index: int) -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	var flock: _Flock = _slots[index].flock
	if flock == null:
		return result
	for member: _Slot in flock.members:
		result.append(_slots.find(member))
	return result


func perched_on_tower(index: int) -> bool:
	return _slots[index].on_tower


func _start_slots() -> void:
	_slots.clear()
	_flocks.clear()
	for _i: int in range(config.perch_bird_count):
		_slots.append(_Slot.new())
	_flock_timer = _rng.randf_range(config.spawn_delay_min_s, config.spawn_delay_max_s)
	_poll_left = 0.0


func _clear_birds() -> void:
	for slot: _Slot in _slots:
		_release_bird(slot, true)
	for child: Node in get_children():
		remove_child(child)
		child.free()


## `immediate` frees the bird now; a bird finishing its own update() must be
## freed deferred instead.
func _release_bird(slot: _Slot, immediate: bool = false) -> void:
	if slot.bird != null and is_instance_valid(slot.bird):
		if slot.bird.get_parent() == self:
			remove_child(slot.bird)
		if immediate:
			slot.bird.free()
		else:
			slot.bird.queue_free()
	slot.bird = null
	slot.block = null
	slot.on_tower = false
	slot.flee_delay = -1.0
	slot.land_fails = 0


func _ensure_materials() -> void:
	if _material != null:
		return
	_outline = ShaderMaterial.new()
	_outline.shader = OUTLINE_SHADER
	_material = ShaderMaterial.new()
	_material.shader = BIRD_SHADER
	_material.next_pass = _outline


# --- Frame loop ------------------------------------------------------------------

func _process(delta: float) -> void:
	if not _enabled:
		return
	_clock += delta
	_poll_left -= delta
	if _poll_left <= 0.0:
		_poll_left = config.threat_poll_interval_s
		_poll()
	_flock_timer -= delta
	if _flock_timer <= 0.0:
		_flock_timer = _rng.randf_range(config.spawn_delay_min_s, config.spawn_delay_max_s)
		_spawn_flock()
	for flock: _Flock in _flocks:
		_update_flock(flock, delta)
	for slot: _Slot in _slots:
		_update_slot(slot, delta)
	for index: int in range(_flocks.size() - 1, -1, -1):
		if _flock_done(_flocks[index]):
			_flocks.remove_at(index)


func _flock_done(flock: _Flock) -> bool:
	if flock.pending > 0:
		return false
	for member: _Slot in flock.members:
		if member.bird != null:
			return false
	for member: _Slot in flock.members:
		if member.flock == flock:
			member.flock = null
	return true


func _update_slot(slot: _Slot, delta: float) -> void:
	if slot.bird == null:
		var flock: _Flock = slot.flock
		if flock != null and flock.pending > 0 and flock.members.has(slot):
			slot.timer -= delta
			if slot.timer <= 0.0:
				_spawn_member(slot)
		return
	var bird: PerchingBird = slot.bird
	bird.update(delta)
	if slot.bird == null:
		return
	if slot.flee_delay >= 0.0:
		slot.flee_delay -= delta
		if slot.flee_delay <= 0.0:
			_begin_flee_now(slot, slot.flee_threat)
			return
	match bird.state:
		PerchingBird.State.CIRCLE:
			if bird.circle_time_left() <= 0.0:
				if not _plan_landing(slot):
					bird.extend_circle(NO_SPOT_RETRY_S)
		PerchingBird.State.PERCHED, PerchingBird.State.ORBIT:
			if slot.on_tower and _anchor_broken(slot):
				_flee(slot, slot.anchor.origin)


# --- Flocks ----------------------------------------------------------------------

## Starts a new flock when a flock slot and free birds are available.
func _spawn_flock() -> void:
	if _flocks.size() >= maxi(config.flock_count_max, 1):
		return
	var free: Array[_Slot] = []
	for slot: _Slot in _slots:
		if slot.bird == null and slot.flock == null:
			free.append(slot)
	var low: int = maxi(config.flock_size_min, 1)
	var high: int = maxi(config.flock_size_max, low)
	var size: int = mini(_rng.randi_range(low, high), free.size())
	if size < 1:
		return
	var flock: _Flock = _Flock.new()
	flock.circle_radius = _rng.randf_range(config.approach_circle_radius_min_m, config.approach_circle_radius_max_m)
	flock.circle_altitude = _rng.randf_range(config.approach_altitude_min_m, config.approach_altitude_max_m)
	flock.circle_dir = 1.0 if _rng.randf() < 0.5 else -1.0
	flock.circle_angle = _rng.randf() * TAU
	flock.circle_time = _rng.randf_range(config.approach_circle_time_min_s, config.approach_circle_time_max_s)
	flock.pending = size
	for i: int in range(size):
		var slot: _Slot = free[i]
		slot.flock = flock
		slot.land_fails = 0
		slot.flee_delay = -1.0
		slot.timer = float(i) * config.flock_arrival_stagger_s * _rng.randf_range(0.6, 1.4)
		flock.members.append(slot)
	_flocks.append(flock)


func _update_flock(flock: _Flock, delta: float) -> void:
	flock.age += delta
	if flock.spooked or not flock.stay_started:
		return
	flock.stay_left -= delta
	if flock.stay_left <= 0.0:
		_flock_leave(flock)
		return
	flock.social_left -= delta
	if flock.social_left <= 0.0:
		flock.social_left = _rng.randf_range(config.flock_social_interval_min_s, config.flock_social_interval_max_s)
		_social_act(flock)


## The whole flock takes off together (staggered), away from a common point.
func _flock_leave(flock: _Flock) -> void:
	for member: _Slot in flock.members:
		if member.bird != null and member.bird.state != PerchingBird.State.FLEE:
			var threat: Vector3 = member.bird.global_position + _random_flat() * NO_THREAT_DIRECTION_JITTER_M
			_flee(member, threat)
			return
	flock.spooked = true


## Marks the flock spooked and schedules every other member's takeoff.
func _spook_flock(source: _Slot, threat: Vector3) -> void:
	var flock: _Flock = source.flock
	if flock == null or flock.spooked:
		return
	flock.spooked = true
	flock.pending = 0
	for member: _Slot in flock.members.duplicate():
		if member == source:
			continue
		if member.bird == null:
			member.flock = null
			flock.members.erase(member)
		elif member.bird.state != PerchingBird.State.FLEE and member.flee_delay < 0.0:
			member.flee_delay = _rng.randf_range(0.0, config.flock_takeoff_stagger_max_s)
			member.flee_threat = threat


## One playful act between two perched flockmates.
func _social_act(flock: _Flock) -> void:
	var perched: Array[_Slot] = []
	for member: _Slot in flock.members:
		if member.bird != null and member.bird.state == PerchingBird.State.PERCHED and member.flee_delay < 0.0:
			perched.append(member)
	if perched.size() < 2:
		return
	var first: int = _rng.randi() % perched.size()
	var second: int = (first + 1 + _rng.randi() % (perched.size() - 1)) % perched.size()
	var a: _Slot = perched[first]
	var b: _Slot = perched[second]
	var roll: float = _rng.randf()
	if roll < config.flock_chase_chance:
		_start_chase(a, b)
	elif roll < config.flock_chase_chance + config.flock_swap_chance:
		_swap_perches(a, b)


func _swap_perches(a: _Slot, b: _Slot) -> void:
	var surface_a: Vector3 = a.bird.perch_surface
	var surface_b: Vector3 = b.bird.perch_surface
	var block: Node3D = a.block
	var anchor: Transform3D = a.anchor
	var tower: bool = a.on_tower
	var surface_y: float = a.surface_y
	a.block = b.block
	a.anchor = b.anchor
	a.on_tower = b.on_tower
	a.surface_y = b.surface_y
	b.block = block
	b.anchor = anchor
	b.on_tower = tower
	b.surface_y = surface_y
	a.bird.begin_hop_flight(surface_b)
	b.bird.begin_hop_flight(surface_a)


func _start_chase(a: _Slot, b: _Slot) -> void:
	var centre: Vector3 = (a.bird.perch_surface + b.bird.perch_surface) * 0.5
	var offset: Vector3 = a.bird.global_position - centre
	var angle: float = atan2(offset.z, offset.x) if Vector2(offset.x, offset.z).length() > 0.01 else _rng.randf() * TAU
	var direction: float = 1.0 if _rng.randf() < 0.5 else -1.0
	var duration: float = config.flock_chase_duration_s
	a.bird.begin_orbit(centre, config.flock_chase_radius_m, angle, direction, duration, config.flock_chase_height_m)
	b.bird.begin_orbit(centre, config.flock_chase_radius_m, angle + direction * CHASE_LEAD_RAD, direction, duration, config.flock_chase_height_m)


func _spawn_member(slot: _Slot) -> void:
	var flock: _Flock = slot.flock
	flock.pending -= 1
	_bird_serial += 1
	var bird: PerchingBird = PerchingBird.new()
	bird.name = "Bird%d" % _bird_serial
	add_child(bird)
	var length: float = _rng.randf_range(config.perch_bird_length_min_m, config.perch_bird_length_max_m) * config.perch_bird_scale
	var colors: PackedColorArray = config.perch_body_colors
	var body_color: Color = colors[_rng.randi() % colors.size()] if colors.size() > 0 else Color.GRAY
	bird.setup(config, length, body_color, _material, _rng.randi())
	bird.landed.connect(_on_bird_landed.bind(slot))
	bird.departed.connect(_on_bird_departed.bind(slot))
	slot.bird = bird
	slot.block = null
	slot.on_tower = false
	slot.flee_delay = -1.0
	# Loose cohesion: the member joins the flock's circle a little behind where
	# the flock has flown to, with its own radius, altitude and landing delay.
	var jitter: float = 0.0 if flock.members.find(slot) == 0 else 1.0
	var radius: float = maxf(flock.circle_radius + jitter * _rng.randf_range(-1.0, 1.0) * config.flock_circle_radius_jitter_m, 10.0)
	var altitude: float = maxf(flock.circle_altitude + jitter * _rng.randf_range(-1.0, 1.0) * config.flock_circle_altitude_jitter_m, 4.0)
	var advance: float = flock.circle_dir * config.flight_speed_mps / maxf(flock.circle_radius, 1.0) * flock.age
	var spread: float = deg_to_rad(config.flock_arrival_spread_deg) * jitter * _rng.randf_range(0.5, 1.5)
	var angle: float = flock.circle_angle + advance - flock.circle_dir * spread
	var remaining: float = maxf(flock.circle_time - flock.age, 0.0)
	var duration: float = remaining + jitter * _rng.randf_range(0.0, config.flock_landing_stagger_s)
	bird.begin_circle(disc_centre, radius, altitude, angle, flock.circle_dir, duration)


func _on_bird_landed(slot: _Slot) -> void:
	if slot.bird != null:
		slot.surface_y = slot.bird.perch_surface.y
	var flock: _Flock = slot.flock
	if flock != null and not flock.stay_started:
		flock.stay_started = true
		flock.stay_left = _rng.randf_range(config.perch_stay_min_s, config.perch_stay_max_s)
		flock.social_left = _rng.randf_range(config.flock_social_interval_min_s, config.flock_social_interval_max_s)


func _on_bird_departed(slot: _Slot) -> void:
	_release_bird(slot)


## A bird that sees a threat flies off; its flockmates follow, staggered.
func _flee(slot: _Slot, threat: Vector3) -> void:
	if slot.bird == null or slot.bird.state == PerchingBird.State.FLEE:
		return
	_spook_flock(slot, threat)
	_begin_flee_now(slot, threat)


func _begin_flee_now(slot: _Slot, threat: Vector3) -> void:
	slot.flee_delay = -1.0
	if slot.bird == null or slot.bird.state == PerchingBird.State.FLEE:
		return
	slot.bird.begin_flee(threat, disc_centre)
	slot.block = null
	slot.on_tower = false


func _random_flat() -> Vector3:
	var angle: float = _rng.randf() * TAU
	return Vector3(cos(angle), 0.0, sin(angle))


# --- Sources ---------------------------------------------------------------------

func _refresh_sources() -> void:
	if _field != null and is_instance_valid(_field):
		var map: MapDef = _field.map_definition()
		disc_centre = _field.global_position
		disc_radius = map.field_radius
		on_disc = Callable(self, "_field_contains")
		surface_point = Callable(self, "_field_surface")
		home_points = PackedVector3Array()
		for flag: HomeFlag in _field.home_flags():
			home_points.append(flag.global_position)
		goal_points = PackedVector3Array()
		for flag: GoalFlag in _field.goal_flags():
			goal_points.append(flag.global_position)
	if _registry != null and is_instance_valid(_registry):
		blocks = []
		for block: Block in _registry.all_blocks():
			blocks.append(block)
	_prune_freed_blocks()
	if not on_disc.is_valid():
		on_disc = Callable(self, "_circle_contains")
	if not surface_point.is_valid():
		surface_point = Callable(self, "_flat_surface")


func _circle_contains(world_xz: Vector2) -> bool:
	return Vector2(world_xz.x - disc_centre.x, world_xz.y - disc_centre.z).length() <= disc_radius


func _flat_surface(world_xz: Vector2) -> Vector3:
	return Vector3(world_xz.x, disc_centre.y, world_xz.y)


func _field_contains(world_xz: Vector2) -> bool:
	var local: Vector2 = _field.disk_local_from_world(Vector3(world_xz.x, _field.global_position.y, world_xz.y))
	if not _field.map_definition().shape_contains(local):
		return false
	var grid: CellGrid = _field.grid()
	var cell: Vector2i = grid.world_to_cell(local)
	if not grid.in_bounds(cell.x, cell.y):
		return false
	return not _field.is_hole_cell(grid.cell_index(cell.x, cell.y))


func _field_surface(world_xz: Vector2) -> Vector3:
	var local: Vector2 = _field.disk_local_from_world(Vector3(world_xz.x, _field.global_position.y, world_xz.y))
	return _field.world_from_disk_local(local, 0.0)


func _camera_position() -> Variant:
	if camera_override != null:
		return camera_override
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return null
	var camera: Camera3D = viewport.get_camera_3d()
	return camera.global_position if camera != null else null


func _cursor_points() -> PackedVector3Array:
	var points: PackedVector3Array = PackedVector3Array()
	for cursor: Variant in _cursors.values():
		points.append(cursor as Vector3)
	if is_inside_tree():
		var ghost: Node3D = get_tree().get_first_node_in_group(GhostPreview.LOCAL_HELD_GROUP) as Node3D
		if ghost != null and ghost.is_visible_in_tree():
			points.append(ghost.global_position)
	return points


func _on_remote_cursor_updated(slot_id: int, origin: Vector3, _orientation: int, _free_quat: Quaternion) -> void:
	_cursors[slot_id] = origin


func _on_player_eliminated(slot_id: int, _team_id: int) -> void:
	_cursors.erase(slot_id)


func _on_match_state_changed(_from_state: int, _to_state: int) -> void:
	reset()


func _on_block_impacted_at(_speed: float, impact_pos: Vector3) -> void:
	if not _enabled:
		return
	for slot: _Slot in _slots:
		if slot.bird == null or slot.bird.state == PerchingBird.State.FLEE or slot.bird.state == PerchingBird.State.CIRCLE:
			continue
		if PerchPlanner.within(slot.bird.global_position, impact_pos, config.flee_impact_radius_m):
			_flee(slot, impact_pos)


# --- Block tracking --------------------------------------------------------------

func _track_blocks() -> void:
	var seen: Dictionary = {}
	for block: Node3D in blocks:
		if not is_instance_valid(block):
			continue
		var id: int = block.get_instance_id()
		seen[id] = true
		var current: Transform3D = block.global_transform
		var entry: Dictionary = _block_track.get(id, {}) as Dictionary
		if entry.is_empty():
			_block_track[id] = {"xf": current, "still": _clock}
		else:
			var previous: Transform3D = entry["xf"] as Transform3D
			if PerchPlanner.block_moved(previous, current, config.flee_block_moved_epsilon_m):
				entry["still"] = _clock
			entry["xf"] = current
	for id: Variant in _block_track.keys():
		if not seen.has(id):
			_block_track.erase(id)


func _block_still_for(block: Node3D) -> float:
	var entry: Dictionary = _block_track.get(block.get_instance_id(), {}) as Dictionary
	if entry.is_empty():
		return 0.0
	return _clock - float(entry["still"])


## Drops freed blocks (collapse, edge fall, gift despawn) so no typed loop
## variable or parameter ever receives a freed object.
func _prune_freed_blocks() -> void:
	var live: Array[Node3D] = []
	for entry: Variant in blocks:
		if is_instance_valid(entry):
			live.append(entry as Node3D)
	if live.size() != blocks.size():
		blocks = live


func _anchor_broken(slot: _Slot) -> bool:
	if slot.block == null or not is_instance_valid(slot.block) or not slot.block.is_inside_tree():
		return true
	return PerchPlanner.block_moved(slot.anchor, slot.block.global_transform, config.flee_block_moved_epsilon_m)


# --- Threat poll -----------------------------------------------------------------

func _poll() -> void:
	_refresh_sources()
	_track_blocks()
	_sample_blocks()
	var cursors: PackedVector3Array = _cursor_points()
	var camera: Variant = _camera_position()
	_build_hazards(cursors, camera, true)
	for slot: _Slot in _slots:
		if slot.bird == null:
			continue
		match slot.bird.state:
			PerchingBird.State.PERCHED, PerchingBird.State.ORBIT:
				_poll_perched(slot, cursors, camera)
			PerchingBird.State.GLIDE:
				_poll_gliding(slot, cursors, camera)


func _block_positions(exclude: Variant) -> PackedVector3Array:
	var points: PackedVector3Array = PackedVector3Array()
	var skip: Node3D = exclude as Node3D if is_instance_valid(exclude) else null
	for block: Node3D in blocks:
		if is_instance_valid(block) and block != skip:
			points.append(block.global_position)
	return points


## One pass over the blocks per poll: every position, and the unsettled ones
## (with their ids), so the per-bird checks below never rescan the blocks.
func _sample_blocks() -> void:
	_poll_blocks = PackedVector3Array()
	_unsettled_points = PackedVector3Array()
	_unsettled_ids = PackedInt64Array()
	for block: Node3D in blocks:
		if not is_instance_valid(block):
			continue
		_poll_blocks.append(block.global_position)
		if _block_still_for(block) < config.block_settled_window_s:
			_unsettled_points.append(block.global_position)
			_unsettled_ids.append(block.get_instance_id())


## The first unsettled block (not `own`) within `radius` of `pos`, as a one-item
## array; empty when none.
## `own` may be a freed block (hence Variant).
func _unsettled_near(pos: Vector3, radius: float, own: Variant) -> Array[Vector3]:
	var own_id: int = (own as Node3D).get_instance_id() if is_instance_valid(own) else 0
	var found: Array[Vector3] = []
	for i: int in range(_unsettled_points.size()):
		if _unsettled_ids[i] != own_id and PerchPlanner.within(pos, _unsettled_points[i], radius):
			found.append(_unsettled_points[i])
			break
	return found


func _poll_perched(slot: _Slot, cursors: PackedVector3Array, camera: Variant) -> void:
	var bird: PerchingBird = slot.bird
	var pos: Vector3 = bird.global_position
	# The bird's own block is never overhead (its centre is below its feet), so
	# the shared sample serves every bird.
	var block_points: PackedVector3Array = _poll_blocks
	var reason: StringName = PerchPlanner.flee_reason(
		pos, camera, cursors, block_points,
		config.flee_camera_radius_m, config.flee_cursor_radius_m,
		config.flee_overhead_radius_m, OVERHEAD_MIN_HEIGHT_M
	)
	if reason == &"camera":
		_flee(slot, camera as Vector3)
		return
	if reason == &"cursor":
		_flee(slot, _nearest(pos, cursors))
		return
	if reason == &"overhead":
		_flee(slot, _nearest(pos, block_points))
		return
	# An unsettled block (falling, sliding, just landed) close by.
	var moving: Array[Vector3] = _unsettled_near(pos, config.flee_moving_block_radius_m, slot.block)
	if not moving.is_empty():
		_flee(slot, moving[0])
		return
	if slot.on_tower:
		if _anchor_broken(slot):
			_flee(slot, slot.anchor.origin)
	elif surface_point.is_valid():
		var ground: Vector3 = surface_point.call(Vector2(pos.x, pos.z)) as Vector3
		if absf(ground.y - slot.surface_y) > SURFACE_DRIFT_M:
			_flee(slot, pos + _random_flat())


func _poll_gliding(slot: _Slot, cursors: PackedVector3Array, camera: Variant) -> void:
	var bird: PerchingBird = slot.bird
	var spot: Vector3 = bird.target_surface()
	if camera != null and PerchPlanner.within(bird.global_position, camera as Vector3, config.flee_camera_radius_m):
		_flee(slot, camera as Vector3)
		return
	if PerchPlanner.any_within(spot, cursors, config.flee_cursor_radius_m):
		_flee(slot, _nearest(spot, cursors))
		return
	if slot.on_tower and _anchor_broken(slot):
		_flee(slot, spot)
		return
	if not slot.on_tower:
		var moving: Array[Vector3] = _unsettled_near(spot, config.flee_moving_block_radius_m, null)
		if not moving.is_empty():
			_flee(slot, moving[0])
			return
		var others: PackedVector3Array = _poll_blocks
		if others.size() > 0 and not PerchPlanner.is_clear(
				spot, others, _uniform_radii(others.size(), config.perch_min_block_distance_m * 0.5)):
			_flee(slot, _nearest(spot, others))


static func _uniform_radii(count: int, radius: float) -> PackedFloat32Array:
	var radii: PackedFloat32Array = PackedFloat32Array()
	radii.resize(count)
	radii.fill(radius)
	return radii


func _nearest(from: Vector3, points: PackedVector3Array) -> Vector3:
	var best: Vector3 = from + _random_flat()
	var best_distance: float = INF
	for point: Vector3 in points:
		var distance: float = from.distance_squared_to(point)
		if distance < best_distance:
			best_distance = distance
			best = point
	return best


# --- Landing selection -------------------------------------------------------------

## Fills _hazard_points/_hazard_radii with the spots a bird keeps away from:
## cursors and home beacons (player distance), goal beacons, the camera, other
## birds, and (when `include_blocks`) every block.
## For a flock member (`own_flock` set) the fixed hazards shrink by the flock's
## perch radius (its first landing already cleared them), and flockmates only
## keep flock_member_spacing_m apart.
func _build_hazards(cursors: PackedVector3Array, camera: Variant, include_blocks: bool, own_flock: _Flock = null) -> void:
	_hazard_points = PackedVector3Array()
	_hazard_radii = PackedFloat32Array()
	_hazard_shrink = config.flock_perch_radius_m if own_flock != null else 0.0
	for point: Vector3 in cursors:
		_add_hazard(point, config.perch_min_player_distance_m)
	for point: Vector3 in home_points:
		_add_hazard(point, config.perch_min_player_distance_m)
	for point: Vector3 in goal_points:
		_add_hazard(point, config.perch_min_goal_distance_m)
	if camera != null:
		_add_hazard(camera as Vector3, config.perch_min_camera_distance_m)
	if include_blocks:
		for block: Node3D in blocks:
			if is_instance_valid(block):
				_add_hazard(block.global_position, config.perch_min_block_distance_m)
	_static_hazard_count = _hazard_points.size()
	_hazard_shrink = 0.0
	for slot: _Slot in _slots:
		if slot.bird == null:
			continue
		var state: PerchingBird.State = slot.bird.state
		if state == PerchingBird.State.GLIDE or state == PerchingBird.State.PERCHED or state == PerchingBird.State.ORBIT:
			var own: bool = own_flock != null and slot.flock == own_flock
			_add_hazard(slot.bird.target_surface(), config.flock_member_spacing_m if own else config.perch_min_bird_spacing_m)


func _add_hazard(point: Vector3, radius: float) -> void:
	_hazard_points.append(point)
	_hazard_radii.append(maxf(radius - _hazard_shrink, MEMBER_MIN_HAZARD_M) if _hazard_shrink > 0.0 else radius)


## Picks a landing spot for the bird in `slot` and starts its glide. Returns
## false when no spot qualifies right now.
func _plan_landing(slot: _Slot) -> bool:
	_refresh_sources()
	_track_blocks()
	var cursors: PackedVector3Array = _cursor_points()
	var camera: Variant = _camera_position()
	var flock: _Flock = slot.flock
	if flock != null and flock.anchor_set:
		if _flock_anchor_valid(flock):
			if _plan_member_landing(slot, flock, cursors, camera):
				return true
			slot.land_fails += 1
			if slot.land_fails >= MEMBER_LAND_RETRIES:
				# No room near the flock: this bird just goes on its way.
				_begin_flee_now(slot, slot.bird.global_position + _random_flat() * NO_THREAT_DIRECTION_JITTER_M)
				return true
			return false
		flock.anchor_set = false
	var prefer_tower: bool = _rng.randf() < config.perch_tower_fraction
	var order: Array[bool] = [prefer_tower, not prefer_tower]
	for tower: bool in order:
		if tower:
			_build_hazards(cursors, camera, false)
			var pick: Dictionary = pick_tower_spot()
			if not pick.is_empty():
				slot.block = pick["block"] as Node3D
				slot.anchor = slot.block.global_transform
				slot.on_tower = true
				slot.bird.begin_glide(pick["surface"] as Vector3, Callable(), false)
				_set_flock_anchor(flock, pick["surface"] as Vector3, true, slot.block, float(pick["size"]))
				return true
		else:
			_build_hazards(cursors, camera, true)
			var spot: Variant = pick_disc_spot()
			if spot != null:
				slot.block = null
				slot.on_tower = false
				var surface: Vector3 = surface_point.call(Vector2((spot as Vector3).x, (spot as Vector3).z)) as Vector3
				slot.bird.begin_glide(surface, Callable(self, "_hop_ok"), true)
				_set_flock_anchor(flock, surface, false, null, 0.0)
				return true
	return false


func _set_flock_anchor(flock: _Flock, surface: Vector3, tower: bool, block: Node3D, face_size: float) -> void:
	if flock == null:
		return
	flock.anchor_set = true
	flock.anchor = surface
	flock.on_tower = tower
	flock.block = block
	flock.anchor_xf = block.global_transform if block != null else Transform3D.IDENTITY
	flock.face_size = face_size


func _flock_anchor_valid(flock: _Flock) -> bool:
	if not flock.on_tower:
		return true
	if flock.block == null or not is_instance_valid(flock.block) or not flock.block.is_inside_tree():
		return false
	return not PerchPlanner.block_moved(flock.anchor_xf, flock.block.global_transform, config.flee_block_moved_epsilon_m)


## Lands a later flock member near the flock's first landing: on the same block
## top, on another block top close by, or on the disc within the flock radius.
func _plan_member_landing(slot: _Slot, flock: _Flock, cursors: PackedVector3Array, camera: Variant) -> bool:
	_build_hazards(cursors, camera, not flock.on_tower, flock)
	if flock.on_tower:
		var reach: float = minf(config.flock_perch_radius_m, flock.face_size * 0.5 - slot.bird.length_m * FACE_EDGE_FRACTION)
		var spot: Variant = _pick_member_spot(flock.anchor, reach, false)
		if spot != null:
			slot.block = flock.block
			slot.anchor = flock.block.global_transform
			slot.on_tower = true
			slot.bird.begin_glide(spot as Vector3, Callable(), false)
			return true
		var pick: Dictionary = pick_tower_spot(flock.anchor, config.flock_tower_radius_m)
		if pick.is_empty():
			return false
		slot.block = pick["block"] as Node3D
		slot.anchor = slot.block.global_transform
		slot.on_tower = true
		slot.bird.begin_glide(pick["surface"] as Vector3, Callable(), false)
		return true
	var disc_spot: Variant = _pick_member_spot(flock.anchor, config.flock_perch_radius_m, true)
	if disc_spot == null:
		return false
	slot.block = null
	slot.on_tower = false
	var surface: Vector3 = surface_point.call(Vector2((disc_spot as Vector3).x, (disc_spot as Vector3).z)) as Vector3
	slot.bird.begin_glide(surface, Callable(self, "_hop_ok"), true)
	return true


## A random spot within `reach` of `centre` that is clear of the current hazards
## (and on the disc when `needs_disc`), or null. Block-top spots keep the
## centre's height.
func _pick_member_spot(centre: Vector3, reach: float, needs_disc: bool) -> Variant:
	if reach <= 0.0:
		return null
	for _attempt: int in range(maxi(config.perch_spot_tries, 1)):
		var angle: float = _rng.randf() * TAU
		var distance: float = sqrt(_rng.randf()) * reach
		var spot: Vector3 = centre + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
		if needs_disc and not PerchPlanner.is_on_disc(spot, config.perch_edge_margin_m * 0.5, on_disc):
			continue
		if not PerchPlanner.is_clear(spot, _hazard_points, _hazard_radii):
			continue
		return spot
	return null


## A random clear spot on the open disc (world Vector3 on the disc plane), or
## null. Uses the hazards last built by _build_hazards().
func pick_disc_spot() -> Variant:
	return PerchPlanner.pick_spot(
		_rng, disc_centre, disc_radius, config.perch_edge_margin_m, on_disc,
		_hazard_points, _hazard_radii, config.perch_spot_tries
	)


## A clear block-top spot: {"surface": Vector3, "block": Node3D, "size": float
## (shorter side of the top face)}, or an empty dictionary. `near`/`near_radius`
## (flock members) restrict it to tops within that horizontal distance. Uses the hazards last built by _build_hazards().
func pick_tower_spot(near: Variant = null, near_radius: float = 0.0) -> Dictionary:
	# Every box of every block occupies space; only long-settled blocks offer tops.
	var inverses: Array[Transform3D] = []
	var halves: PackedVector3Array = PackedVector3Array()
	var origins: PackedVector3Array = PackedVector3Array()
	var bounds: PackedFloat32Array = PackedFloat32Array()
	var owners: Array[Node3D] = []
	var face_centres: PackedVector3Array = PackedVector3Array()
	var face_boxes: PackedInt32Array = PackedInt32Array()
	var face_sizes: PackedFloat32Array = PackedFloat32Array()
	for block: Node3D in blocks:
		if not is_instance_valid(block) or not block.is_inside_tree():
			continue
		var settled: bool = _block_still_for(block) >= config.perch_tower_min_settle_s
		for child: Node in block.get_children():
			var shape_node: CollisionShape3D = child as CollisionShape3D
			if shape_node == null or shape_node.disabled:
				continue
			var box: BoxShape3D = shape_node.shape as BoxShape3D
			if box == null:
				continue
			var half: Vector3 = box.size * 0.5
			var world: Transform3D = shape_node.global_transform
			var index: int = inverses.size()
			inverses.append(world.affine_inverse())
			halves.append(half)
			origins.append(world.origin)
			bounds.append((half * world.basis.get_scale()).length())
			owners.append(block)
			if not settled:
				continue
			var face: Variant = PerchPlanner.top_face(world, half)
			if face == null:
				continue
			var face_size: Vector2 = (face as Dictionary)["size"] as Vector2
			if minf(face_size.x, face_size.y) < config.perch_tower_min_top_size_m:
				continue
			if near != null and not PerchPlanner.within((face as Dictionary)["center"] as Vector3, near as Vector3, near_radius):
				continue
			face_centres.append((face as Dictionary)["center"] as Vector3)
			face_boxes.append(index)
			face_sizes.append(minf(face_size.x, face_size.y))
	if face_centres.is_empty():
		return {}
	# Try random faces, up to the configured number of attempts.
	var tries: int = mini(maxi(int(ceil(float(config.perch_spot_tries) * 0.25)), 1), face_centres.size())
	var start: int = _rng.randi() % face_centres.size()
	var checked: int = 0
	for step: int in range(face_centres.size()):
		if checked >= tries:
			break
		var i: int = (start + step) % face_centres.size()
		var centre: Vector3 = face_centres[i]
		if not PerchPlanner.is_clear(centre, _hazard_points, _hazard_radii):
			continue
		checked += 1
		if PerchPlanner.top_is_free(
				centre, face_sizes[i] * FOOTPRINT_FRACTION, config.perch_tower_clear_height_m,
				inverses, halves, origins, bounds, face_boxes[i]):
			return {"surface": centre, "block": owners[face_boxes[i]], "size": face_sizes[i]}
	return {}


## Hop-target vetting for a disc-perched bird (Callable target of PerchingBird).
func _hop_ok(target: Vector3) -> bool:
	if not PerchPlanner.is_on_disc(target, config.perch_edge_margin_m * 0.5, on_disc):
		return false
	return PerchPlanner.is_clear(
		target, _hazard_points.slice(0, _static_hazard_count), _hazard_radii.slice(0, _static_hazard_count)
	)
