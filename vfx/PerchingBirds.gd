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

class _Slot:
	extends RefCounted
	var bird: PerchingBird = null
	var timer: float = 0.0
	var perch_left: float = 0.0
	var block: Node3D = null
	var anchor: Transform3D = Transform3D.IDENTITY
	var surface_y: float = 0.0
	var on_tower: bool = false

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
var _cursors: Dictionary = {}
var _block_track: Dictionary = {}
var _hazard_points: PackedVector3Array = PackedVector3Array()
var _hazard_radii: PackedFloat32Array = PackedFloat32Array()
## Hazards before the per-bird spacing entries (a hopping bird ignores its own).
var _static_hazard_count: int = 0
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


## Test/debug: forces slot `index`'s next spawn to happen on the next update.
func spawn_now(index: int) -> void:
	_slots[index].timer = 0.0


func perched_on_tower(index: int) -> bool:
	return _slots[index].on_tower


func _start_slots() -> void:
	_slots.clear()
	for _i: int in range(config.perch_bird_count):
		var slot: _Slot = _Slot.new()
		slot.timer = _rng.randf_range(config.spawn_delay_min_s, config.spawn_delay_max_s)
		_slots.append(slot)
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
	for slot: _Slot in _slots:
		_update_slot(slot, delta)


func _update_slot(slot: _Slot, delta: float) -> void:
	if slot.bird == null:
		slot.timer -= delta
		if slot.timer <= 0.0:
			_spawn(slot)
		return
	var bird: PerchingBird = slot.bird
	bird.update(delta)
	if slot.bird == null:
		return
	match bird.state:
		PerchingBird.State.CIRCLE:
			if bird.circle_time_left() <= 0.0:
				if not _plan_landing(slot):
					bird.extend_circle(NO_SPOT_RETRY_S)
		PerchingBird.State.PERCHED:
			slot.perch_left -= delta
			if slot.perch_left <= 0.0:
				var away: Vector3 = bird.global_position + _random_flat() * NO_THREAT_DIRECTION_JITTER_M
				_flee(slot, away)
			elif slot.on_tower and _anchor_broken(slot):
				_flee(slot, slot.anchor.origin)


func _spawn(slot: _Slot) -> void:
	_bird_serial += 1
	var bird: PerchingBird = PerchingBird.new()
	bird.name = "Bird%d" % _bird_serial
	add_child(bird)
	var length: float = _rng.randf_range(config.perch_bird_length_min_m, config.perch_bird_length_max_m)
	var colors: PackedColorArray = config.perch_body_colors
	var body_color: Color = colors[_rng.randi() % colors.size()] if colors.size() > 0 else Color.GRAY
	bird.setup(config, length, body_color, _material, _rng.randi())
	bird.landed.connect(_on_bird_landed.bind(slot))
	bird.departed.connect(_on_bird_departed.bind(slot))
	slot.bird = bird
	slot.block = null
	slot.on_tower = false
	var radius: float = _rng.randf_range(config.approach_circle_radius_min_m, config.approach_circle_radius_max_m)
	var altitude: float = _rng.randf_range(config.approach_altitude_min_m, config.approach_altitude_max_m)
	var direction: float = 1.0 if _rng.randf() < 0.5 else -1.0
	var duration: float = _rng.randf_range(config.approach_circle_time_min_s, config.approach_circle_time_max_s)
	bird.begin_circle(disc_centre, radius, altitude, _rng.randf() * TAU, direction, duration)


func _on_bird_landed(slot: _Slot) -> void:
	slot.perch_left = _rng.randf_range(config.perch_stay_min_s, config.perch_stay_max_s)
	if slot.bird != null:
		slot.surface_y = slot.bird.perch_surface.y


func _on_bird_departed(slot: _Slot) -> void:
	_release_bird(slot)
	slot.timer = _rng.randf_range(config.spawn_delay_min_s, config.spawn_delay_max_s)


func _flee(slot: _Slot, threat: Vector3) -> void:
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


func _anchor_broken(slot: _Slot) -> bool:
	if slot.block == null or not is_instance_valid(slot.block) or not slot.block.is_inside_tree():
		return true
	return PerchPlanner.block_moved(slot.anchor, slot.block.global_transform, config.flee_block_moved_epsilon_m)


# --- Threat poll -----------------------------------------------------------------

func _poll() -> void:
	_refresh_sources()
	_track_blocks()
	var cursors: PackedVector3Array = _cursor_points()
	var camera: Variant = _camera_position()
	_build_hazards(cursors, camera, true)
	for slot: _Slot in _slots:
		if slot.bird == null:
			continue
		match slot.bird.state:
			PerchingBird.State.PERCHED:
				_poll_perched(slot, cursors, camera)
			PerchingBird.State.GLIDE:
				_poll_gliding(slot, cursors, camera)


func _block_positions(exclude: Node3D) -> PackedVector3Array:
	var points: PackedVector3Array = PackedVector3Array()
	for block: Node3D in blocks:
		if is_instance_valid(block) and block != exclude:
			points.append(block.global_position)
	return points


func _poll_perched(slot: _Slot, cursors: PackedVector3Array, camera: Variant) -> void:
	var bird: PerchingBird = slot.bird
	var pos: Vector3 = bird.global_position
	var block_points: PackedVector3Array = _block_positions(slot.block)
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
	for block: Node3D in blocks:
		if not is_instance_valid(block) or block == slot.block:
			continue
		if _block_still_for(block) >= config.block_settled_window_s:
			continue
		if PerchPlanner.within(pos, block.global_position, config.flee_moving_block_radius_m):
			_flee(slot, block.global_position)
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
		var others: PackedVector3Array = _block_positions(null)
		for block: Node3D in blocks:
			if is_instance_valid(block) and _block_still_for(block) < config.block_settled_window_s \
					and PerchPlanner.within(spot, block.global_position, config.flee_moving_block_radius_m):
				_flee(slot, block.global_position)
				return
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
func _build_hazards(cursors: PackedVector3Array, camera: Variant, include_blocks: bool) -> void:
	_hazard_points = PackedVector3Array()
	_hazard_radii = PackedFloat32Array()
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
	for slot: _Slot in _slots:
		if slot.bird != null and (slot.bird.state == PerchingBird.State.GLIDE or slot.bird.state == PerchingBird.State.PERCHED):
			_add_hazard(slot.bird.target_surface(), config.perch_min_bird_spacing_m)


func _add_hazard(point: Vector3, radius: float) -> void:
	_hazard_points.append(point)
	_hazard_radii.append(radius)


## Picks a landing spot for the bird in `slot` and starts its glide. Returns
## false when no spot qualifies right now.
func _plan_landing(slot: _Slot) -> bool:
	_refresh_sources()
	_track_blocks()
	var cursors: PackedVector3Array = _cursor_points()
	var camera: Variant = _camera_position()
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
				return true
		else:
			_build_hazards(cursors, camera, true)
			var spot: Variant = pick_disc_spot()
			if spot != null:
				slot.block = null
				slot.on_tower = false
				var surface: Vector3 = surface_point.call(Vector2((spot as Vector3).x, (spot as Vector3).z)) as Vector3
				slot.bird.begin_glide(surface, Callable(self, "_hop_ok"), true)
				return true
	return false


## A random clear spot on the open disc (world Vector3 on the disc plane), or
## null. Uses the hazards last built by _build_hazards().
func pick_disc_spot() -> Variant:
	return PerchPlanner.pick_spot(
		_rng, disc_centre, disc_radius, config.perch_edge_margin_m, on_disc,
		_hazard_points, _hazard_radii, config.perch_spot_tries
	)


## A clear block-top spot: {"surface": Vector3, "block": Node3D}, or an empty
## dictionary. Uses the hazards last built by _build_hazards().
func pick_tower_spot() -> Dictionary:
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
			return {"surface": centre, "block": owners[face_boxes[i]]}
	return {}


## Hop-target vetting for a disc-perched bird (Callable target of PerchingBird).
func _hop_ok(target: Vector3) -> bool:
	if not PerchPlanner.is_on_disc(target, config.perch_edge_margin_m * 0.5, on_disc):
		return false
	return PerchPlanner.is_clear(
		target, _hazard_points.slice(0, _static_hazard_count), _hazard_radii.slice(0, _static_hazard_count)
	)
