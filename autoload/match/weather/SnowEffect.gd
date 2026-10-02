class_name SnowEffect
extends WeatherEffect
## Snow's host physics (Bontago-22y.6): bounded, colliding accumulation on the
## tops of settled blocks and on the disc, melted away by the event's ramp-out.
## Named by config/weather/snow.tres `effect_script`; MatchWeather creates one
## per snow event on the host only. Clients never run this: they draw the
## replicated patch list (net/SnowNet.gd) with the same SnowCapBuilder code,
## without colliders.
##
## Per physics frame (tick), all bounded by SnowTuning:
##   1. while snowing, a growth clock (seconds_per_level / intensity) queues a
##      growth pass over every patch; while the ramp-out runs, a melt pass
##      caps every patch at the remaining fraction of the peak;
##   2. discover newly settled blocks' exposed cell tops (a few blocks/frame);
##   3. work the queue: at most patch_checks_per_frame patches, each one shape
##      query (is anything resting on or hovering just above it?); a level
##      change only records the new level in the builder;
##   4. the builder computes at most rebuild_patches_per_frame domes and
##      swaps each block / disc region to its new snow in one commit, holding
##      a sleeping block frozen around its collider swap so the pile it rests
##      in is not woken;
##   5. publish the compact state to SnowRelay for replication once a pass
##      has been worked.
##
## DECISION (autoload/match/weather/SnowEffect.gd, accepted by the owner via
## the orchestrator): a block landing on existing snow keeps that snow under
## it (the block rests on the dome, which is the point of snow: "hitboxes
## aren't flat anymore"); a covered patch only stops growing, so snow never
## grows into a resting body and never pops it.
## DECISION: only settled blocks (asleep, or frozen) collect snow, and only on
## the cell faces of the local axis nearest world up; a block that tips past
## max_up_tilt_deg loses its snow (it slides off).
## DECISION: a block with no replicated net_id (none in a real match) never
## collects snow, so every collider the host builds is one clients can draw.

enum Work { GROW, MELT }

## Owner id of disc work items (block items use the block's instance id).
const DISC_ITEM: int = -1
const WORK_STRIDE: int = 3
## Disc drift placement: tries per wanted drift, and the share of tries
## taken on the rim band (the rest around block bases).
const DRIFT_SAMPLE_ATTEMPTS: int = 24
## Drifts keep this share of their stretched length between centres.
const DRIFT_SPACING_SHARE: float = 0.7
const DRIFT_RIM_SHARE: float = 0.5
## Lift of a coverage query above the snow base, so the owner's own surface
## is never touched. Geometry epsilon, not a tunable.
const QUERY_BASE_LIFT_M: float = 0.002
## A coverage query needs one hit to answer.
const COVER_QUERY_RESULTS: int = 1
## Bodies woken above one melting patch at most.
const WAKE_QUERY_RESULTS: int = 8
## Intensity drop below the peak that counts as the ramp-out having begun.
const MELT_DETECT_EPS: float = 0.0005


class BlockSnow:
	var block: Block = null
	var net_id: int = -1
	var axis: int = -1
	var cube_size: float = 1.0
	var cell_centers: PackedVector3Array = PackedVector3Array()
	var cells: PackedInt32Array = PackedInt32Array()
	var levels: PackedInt32Array = PackedInt32Array()

	func active_count() -> int:
		var count: int = 0
		for level: int in levels:
			if level > 0:
				count += 1
		return count


var _snow: SnowTuning = null
var _seed: int = 0
var _field: Field = null
var _blocks_source: Callable = Callable()
var _world_overridden: bool = false
var _blocks: Dictionary = {}
var _disc: Dictionary = {}
var _disc_prepared: bool = false
## Work items as (kind, owner, index) triplets. PackedInt64Array because an
## owner is a 64-bit instance id (a Vector3i would truncate it).
var _queue: PackedInt64Array = PackedInt64Array()
var _queue_head: int = 0
var _growth_acc: float = 0.0
var _growth_owed: bool = false
var _peak: float = 0.0
var _melting: bool = false
var _cap: int = 0
var _cover: int = 0
var _active_block_patches: int = 0
var _state_dirty: bool = false
var _sweep: Array[Block] = []
var _sweep_pos: int = 0
var _query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
var _query_box: BoxShape3D = BoxShape3D.new()
var _builder: SnowCapBuilder = null
var _restored: bool = false

## Counters for tests and the bench.
var queries_run: int = 0
var states_published: int = 0


func bind(match_owner: MatchAutoload, weather_tuning: WeatherTuning) -> void:
	super.bind(match_owner, weather_tuning)
	_snow = weather_tuning as SnowTuning
	if _snow == null:
		_snow = SnowTuning.new()
	_cap = _snow.depth_levels
	_builder = SnowCapBuilder.new(_snow, true)
	_query.shape = _query_box
	_query.collide_with_areas = false
	_query.collide_with_bodies = true
	if match_owner != null and match_owner.weather() != null:
		_seed = match_owner.weather().seed_value()
	if not Events.block_removed.is_connected(_on_block_removed):
		Events.block_removed.connect(_on_block_removed)


## Test seam: the field and a Callable returning Array[Block] replace Match's
## field()/registry().all_blocks().
func set_world(field: Field, blocks_source: Callable) -> void:
	_field = field
	_blocks_source = blocks_source
	_world_overridden = true


func set_seed(seed_value: int) -> void:
	_seed = seed_value


func tick(delta: float, current_intensity: float) -> void:
	if _restored or _snow == null:
		return
	_resolve_world()
	_update_melt(current_intensity)
	if not _melting:
		_prepare_disc()
		_advance_growth_clock(delta, current_intensity)
		_discover()
	_work()
	_builder.step(_snow.rebuild_patches_per_frame)
	_start_owed_pass()
	if _state_dirty and pending_work() == 0:
		_state_dirty = false
		_publish()


## Removes every snow collider and mesh this effect built and publishes an
## empty state. Safe twice and after the world was freed.
func restore() -> void:
	if _restored:
		return
	_restored = true
	if Events.block_removed.is_connected(_on_block_removed):
		Events.block_removed.disconnect(_on_block_removed)
	for key: Variant in _blocks.keys():
		var entry: BlockSnow = _blocks[key]
		if is_instance_valid(entry.block) and _block_alive(entry.block):
			for k: int in range(entry.cells.size()):
				if entry.levels[k] > 0:
					_wake_above(_block_patch_world(entry, k), _block_edge(entry), entry.levels[k], _rids(entry.block))
	if is_instance_valid(_field):
		for key: Variant in _disc.keys():
			var level: int = int(_disc[key])
			if level > 0:
				_wake_above(_disc_patch_world(int(key)), _disc_edge(), level, _disc_exclude(), _snow.disc_drift_stretch)
	if _builder != null:
		_builder.clear_all()
	for key: Variant in _blocks.keys():
		var snow_block: Block = (_blocks[key] as BlockSnow).block if is_instance_valid((_blocks[key] as BlockSnow).block) else null
		if snow_block != null:
			SnowCaps.clear_block(snow_block)
	_blocks.clear()
	_active_block_patches = 0
	if is_instance_valid(_field):
		SnowCaps.clear_disc(_field)
	_disc.clear()
	_cover = 0
	_queue.clear()
	_queue_head = 0
	_publish()


# --- Queries (tests, bench, debug) ---------------------------------------------------

func is_melting() -> bool:
	return _melting


func active_block_patches() -> int:
	return _active_block_patches


func tracked_block_count() -> int:
	return _blocks.size()


func cover_level() -> int:
	return _cover


func builder() -> SnowCapBuilder:
	return _builder


## Levels per exposed patch of `block` (empty when it is not tracked).
func block_levels(block: Block) -> PackedInt32Array:
	var entry: BlockSnow = _blocks.get(block.get_instance_id()) as BlockSnow
	return entry.levels.duplicate() if entry != null else PackedInt32Array()


func block_axis(block: Block) -> int:
	var entry: BlockSnow = _blocks.get(block.get_instance_id()) as BlockSnow
	return entry.axis if entry != null else -1


## Disc cell index -> level for every chosen disc drift (level 0 = not yet).
func disc_levels() -> Dictionary:
	return _disc.duplicate()


## Snow colliders on every tracked block plus the disc bodies.
func collider_count() -> int:
	var total: int = 0
	for key: Variant in _blocks.keys():
		var entry: BlockSnow = _blocks[key]
		total += SnowCaps.lump_colliders(entry.block).size()
	return total + SnowCaps.disc_collider_count(_field)


func pending_work() -> int:
	return (_queue.size() - _queue_head) / WORK_STRIDE


## True while geometry is still being rebuilt.
func is_building() -> bool:
	return _builder != null and not _builder.is_idle()


## The compact replicated state (SnowGeometry wire format).
func state() -> Dictionary:
	var b: PackedInt32Array = PackedInt32Array()
	var ids: Array = []
	for key: Variant in _blocks.keys():
		ids.append(key)
	ids.sort_custom(func(x: Variant, y: Variant) -> bool:
		return (_blocks[x] as BlockSnow).net_id < (_blocks[y] as BlockSnow).net_id)
	for key: Variant in ids:
		var entry: BlockSnow = _blocks[key]
		var cells: PackedInt32Array = PackedInt32Array()
		var levels: PackedInt32Array = PackedInt32Array()
		for k: int in range(entry.cells.size()):
			if entry.levels[k] > 0:
				cells.append(entry.cells[k])
				levels.append(entry.levels[k])
		if not cells.is_empty():
			SnowGeometry.append_block_record(b, entry.net_id, entry.axis, cells, levels)
	var d: PackedInt32Array = PackedInt32Array()
	var disc_cells: Array = _disc.keys()
	disc_cells.sort()
	for key: Variant in disc_cells:
		var level: int = int(_disc[key])
		if level > 0:
			d.append(int(key))
			d.append(level)
	return SnowGeometry.make_state(_seed, _cover, b, d)


# --- World ------------------------------------------------------------------------------

func _resolve_world() -> void:
	if _world_overridden or match_ref == null:
		return
	if not is_instance_valid(_field):
		_field = match_ref.field()


func _live_blocks() -> Array[Block]:
	if _blocks_source.is_valid():
		var result: Array[Block] = []
		result.assign(_blocks_source.call())
		return result
	if match_ref != null and match_ref.registry() != null:
		return match_ref.registry().all_blocks()
	var none: Array[Block] = []
	return none


func _space() -> PhysicsDirectSpaceState3D:
	if not is_instance_valid(_field) or not _field.is_inside_tree():
		return null
	var world: World3D = _field.get_world_3d()
	return world.direct_space_state if world != null else null


static func _block_alive(block: Block) -> bool:
	return is_instance_valid(block) and block.is_inside_tree() and not block.is_queued_for_deletion()


static func _rids(block: Block) -> Array[RID]:
	var out: Array[RID] = [block.get_rid()]
	return out


static func _settled(block: Block) -> bool:
	return block.sleeping or block.freeze


static func _block_key(entry: BlockSnow) -> String:
	return "b%d" % entry.net_id


func _up_axis(block: Block) -> int:
	var local_up: Vector3 = block.global_transform.basis.inverse() * Vector3.UP
	return SnowGeometry.best_up_axis(local_up, cos(deg_to_rad(_snow.max_up_tilt_deg)))


func _on_block_removed(block: RigidBody3D, _reason: String) -> void:
	if block == null:
		return
	var id: int = block.get_instance_id()
	var entry: BlockSnow = _blocks.get(id) as BlockSnow
	if entry == null:
		return
	_active_block_patches -= entry.active_count()
	_builder.drop_owner(_block_key(entry))
	_blocks.erase(id)
	_state_dirty = true


# --- Growth and melt clocks ---------------------------------------------------------

func _update_melt(current_intensity: float) -> void:
	if current_intensity > _peak:
		_peak = current_intensity
	if not _melting and _peak > 0.0 and current_intensity < _peak - MELT_DETECT_EPS:
		_melting = true
		# Pending growth work is void once the ramp-out begins.
		_queue.clear()
		_queue_head = 0
		_growth_owed = false
	if not _melting:
		return
	var cap: int = _snow.melt_cap(current_intensity, _peak)
	if cap >= _cap:
		return
	_cap = cap
	if _cover > _cap:
		_cover = _cap
		_apply_cover()
		_state_dirty = true
	for key: Variant in _blocks.keys():
		var entry: BlockSnow = _blocks[key]
		for k: int in range(entry.levels.size()):
			if entry.levels[k] > _cap:
				_enqueue(Work.MELT, int(key), k)
	for key: Variant in _disc.keys():
		if int(_disc[key]) > _cap:
			_enqueue(Work.MELT, DISC_ITEM, int(key))


func _advance_growth_clock(delta: float, current_intensity: float) -> void:
	if current_intensity <= 0.0 or _snow.seconds_per_level <= 0.0:
		return
	_growth_acc += delta * current_intensity / _snow.seconds_per_level
	if _growth_acc < 1.0:
		return
	_growth_acc -= floorf(_growth_acc)
	_growth_owed = true
	_start_owed_pass()


## True while a pass is queued or its geometry is still being rebuilt.
func _busy() -> bool:
	return pending_work() > 0 or (_builder != null and not _builder.is_idle())


func _start_owed_pass() -> void:
	if _growth_owed and not _melting and not _busy():
		_growth_owed = false
		_enqueue_growth_pass()


func _enqueue_growth_pass() -> void:
	_queue.clear()
	_queue_head = 0
	var ceiling: int = mini(_snow.depth_levels, _cap)
	if _cover < ceiling:
		_cover += 1
		_apply_cover()
		_state_dirty = true
	for key: Variant in _blocks.keys():
		var entry: BlockSnow = _blocks[key]
		for k: int in range(entry.levels.size()):
			if entry.levels[k] < ceiling:
				_enqueue(Work.GROW, int(key), k)
	var disc_cells: Array = _disc.keys()
	disc_cells.sort()
	for key: Variant in disc_cells:
		if int(_disc[key]) < ceiling:
			_enqueue(Work.GROW, DISC_ITEM, int(key))


func _apply_cover() -> void:
	SnowCaps.set_disc_cover(_field, _seed, _cover, _snow, _live_blocks)


# --- Discovery ----------------------------------------------------------------------------

func _discover() -> void:
	var budget: int = maxi(_snow.discover_blocks_per_frame, 0)
	while budget > 0:
		if _sweep_pos >= _sweep.size():
			_sweep = _live_blocks()
			_sweep_pos = 0
			_prune_blocks()
			if _sweep.is_empty():
				return
		var raw: Variant = _sweep[_sweep_pos]
		_sweep_pos += 1
		budget -= 1
		# A block freed since the sweep list was built cannot go into a typed Block.
		if not is_instance_valid(raw):
			continue
		var block: Block = raw as Block
		if not _block_alive(block):
			continue
		var id: int = block.get_instance_id()
		var entry: BlockSnow = _blocks.get(id) as BlockSnow
		if entry != null:
			if _settled(block) and _up_axis(block) != entry.axis:
				_drop_block(entry, id)
			continue
		if block.net_id <= 0 or not _settled(block):
			continue
		var axis: int = _up_axis(block)
		if axis < 0:
			continue
		entry = BlockSnow.new()
		entry.block = block
		entry.net_id = block.net_id
		entry.axis = axis
		entry.cube_size = SnowCaps.cube_size_of(block)
		entry.cell_centers = SnowCaps.block_cells(block)
		entry.cells = SnowGeometry.exposed_cells(entry.cell_centers, axis, entry.cube_size, _snow.max_patches_per_block)
		entry.levels = PackedInt32Array()
		entry.levels.resize(entry.cells.size())
		_blocks[id] = entry


## Forgets entries whose block is gone without a block_removed signal.
func _prune_blocks() -> void:
	for key: Variant in _blocks.keys():
		var entry: BlockSnow = _blocks[key]
		if not is_instance_valid(entry.block) or entry.block.is_queued_for_deletion():
			_active_block_patches -= entry.active_count()
			_builder.drop_owner(_block_key(entry))
			_blocks.erase(key)
			_state_dirty = true


## A tipped block loses its snow (bodies resting on it are woken).
func _drop_block(entry: BlockSnow, id: int) -> void:
	for k: int in range(entry.cells.size()):
		if entry.levels[k] > 0:
			_wake_above(_block_patch_world(entry, k), _block_edge(entry), entry.levels[k], _rids(entry.block))
	_active_block_patches -= entry.active_count()
	_builder.drop_owner(_block_key(entry))
	_blocks.erase(id)
	_state_dirty = true


func _prepare_disc() -> void:
	if _disc_prepared or not is_instance_valid(_field):
		return
	_disc_prepared = true
	if _snow.max_disc_patches <= 0:
		return
	var grid: CellGrid = _field.grid()
	var flags: PackedVector2Array = PackedVector2Array()
	for flag: HomeFlag in _field.home_flags():
		if is_instance_valid(flag):
			flags.append(_field.disk_local_from_world(flag.global_position))
	for flag: GoalFlag in _field.goal_flags():
		if is_instance_valid(flag):
			flags.append(_field.disk_local_from_world(flag.global_position))
	var blocks: Array[Block] = _live_blocks()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SnowGeometry.mix(SnowGeometry.mix(0, _seed), SnowGeometry.DISC_OWNER)
	var wanted: int = _snow.max_disc_patches
	var attempts: int = wanted * DRIFT_SAMPLE_ATTEMPTS
	var clear_radius: float = _snow.disc_flag_clear_radius_m + _disc_edge() * 0.5
	# Drifts never overlap (one per spacing bucket, checked against the 3x3
	# neighbouring buckets): overlapping hulls would hide each other's rims.
	var spacing: float = _disc_query_edge() * DRIFT_SPACING_SHARE
	var buckets: Dictionary = {}
	while _disc.size() < wanted and attempts > 0:
		attempts -= 1
		var cell: int = _sample_drift_cell(grid, blocks, rng)
		if cell < 0 or _disc.has(cell) or _disc_over_hole(cell):
			continue
		var center: Vector2 = grid.index_center(cell)
		var bucket: Vector2i = Vector2i(floori(center.x / spacing), floori(center.y / spacing))
		var crowded: bool = false
		for by: int in range(-1, 2):
			for bx: int in range(-1, 2):
				var other: Variant = buckets.get(bucket + Vector2i(bx, by))
				if other != null and center.distance_to(other as Vector2) < spacing:
					crowded = true
		if crowded:
			continue
		var near_flag: bool = false
		for flag_pos: Vector2 in flags:
			if center.distance_to(flag_pos) < clear_radius:
				near_flag = true
				break
		if not near_flag:
			_disc[cell] = 0
			buckets[bucket] = center


## DECISION (autoload/match/weather/SnowEffect.gd): colliding disc drifts
## only form where the visual snow layer gathers first, near the rim and
## around block bases (the same biases the disc shader uses), so a drift
## always sits inside visible snow instead of reading as a lone white spot.
## Sampled directly (a random rim point or a random offset from a random
## block), never by scanning every disc cell, so event start costs no spike.
func _sample_drift_cell(grid: CellGrid, blocks: Array[Block], rng: RandomNumberGenerator) -> int:
	var radius: float = _field.map_definition().field_radius
	if blocks.is_empty() or rng.randf() < DRIFT_RIM_SHARE:
		var angle: float = rng.randf_range(0.0, TAU)
		var r: float = rng.randf_range(radius * _snow.cover_rim_start, radius)
		var at: Vector2i = grid.world_to_cell(Vector2(cos(angle), sin(angle)) * r)
		return grid.cell_index(at.x, at.y) if grid.in_bounds(at.x, at.y) and grid.is_in_disk(at.x, at.y) else -1
	var block: Block = blocks[rng.randi_range(0, blocks.size() - 1)]
	if not _block_alive(block):
		return -1
	var reach: int = maxi(ceili(_snow.cover_base_radius_cells), 1)
	# Lee side: the offset is sampled on the downwind half of the block's
	# surroundings, with a small cross-wind spread.
	var wind: Vector2 = Vector2.from_angle(deg_to_rad(_snow.cover_wind_angle_deg))
	var lee_start: float = _disc_query_edge() * 0.5 + 1.0
	var along: float = rng.randf_range(lee_start, lee_start + float(reach))
	var across: float = rng.randf_range(-1.0, 1.0)
	var offset: Vector2 = wind * along + Vector2(-wind.y, wind.x) * across
	var dx: int = roundi(offset.x)
	var dy: int = roundi(offset.y)
	if dx == 0 and dy == 0:
		return -1
	var center: Vector2i = grid.world_to_cell(_field.disk_local_from_world(block.global_position))
	var cx: int = center.x + dx
	var cy: int = center.y + dy
	return grid.cell_index(cx, cy) if grid.in_bounds(cx, cy) and grid.is_in_disk(cx, cy) else -1


## True when any cell under a drift's footprint is a hole or off the disc.
func _disc_over_hole(cell: int) -> bool:
	var grid: CellGrid = _field.grid()
	var center: Vector2 = grid.index_center(cell)
	var wind: Vector2 = Vector2.from_angle(deg_to_rad(_snow.cover_wind_angle_deg))
	var side: Vector2 = Vector2(-wind.y, wind.x)
	var half_edge: float = _disc_edge() * 0.5
	var half_len: float = half_edge * maxf(_snow.disc_drift_stretch, 1.0)
	var step: float = grid.cell_size
	var t: float = -half_len
	while t <= half_len + 0.0001:
		var w: float = -half_edge
		while w <= half_edge + 0.0001:
			var at: Vector2i = grid.world_to_cell(center + wind * t + side * w)
			if not grid.in_bounds(at.x, at.y) or not grid.is_in_disk(at.x, at.y):
				return true
			if _field.is_hole_cell(grid.cell_index(at.x, at.y)):
				return true
			w += step
		t += step
	return false


# --- Work queue -----------------------------------------------------------------------------

func _enqueue(kind: int, owner_id: int, index: int) -> void:
	_queue.append(kind)
	_queue.append(owner_id)
	_queue.append(index)


func _work() -> void:
	var budget: int = maxi(_snow.patch_checks_per_frame, 1)
	while budget > 0 and _queue_head < _queue.size():
		var kind: int = _queue[_queue_head]
		var owner_id: int = _queue[_queue_head + 1]
		var index: int = _queue[_queue_head + 2]
		_queue_head += WORK_STRIDE
		budget -= 1
		if kind == Work.GROW:
			_grow(owner_id, index)
		else:
			_melt(owner_id, index)
	if _queue_head >= _queue.size():
		_queue.clear()
		_queue_head = 0


func _grow(owner_id: int, index: int) -> void:
	var ceiling: int = mini(_snow.depth_levels, _cap)
	if owner_id == DISC_ITEM:
		if not _disc.has(index) or not is_instance_valid(_field):
			return
		var level: int = int(_disc[index])
		if _disc_over_hole(index):
			if level > 0:
				_wake_above(_disc_patch_world(index), _disc_edge(), level, _disc_exclude(), _snow.disc_drift_stretch)
				_set_disc_level(index, 0)
			return
		if level >= ceiling or _cover < _snow.disc_drift_min_cover:
			return
		if _occupied(_disc_patch_world(index), _disc_edge(), level + 1, _disc_exclude(), _snow.disc_drift_stretch):
			return
		_set_disc_level(index, level + 1)
		return
	var entry: BlockSnow = _blocks.get(owner_id) as BlockSnow
	if entry == null or index >= entry.levels.size() or not _block_alive(entry.block):
		return
	if not _settled(entry.block):
		return
	var current: int = entry.levels[index]
	if current >= ceiling:
		return
	if current == 0 and _active_block_patches >= _snow.max_block_patches:
		return
	if _occupied(_block_patch_world(entry, index), _block_edge(entry), current + 1, _rids(entry.block)):
		return
	if current == 0:
		_active_block_patches += 1
	_set_block_level(entry, index, current + 1)


func _melt(owner_id: int, index: int) -> void:
	if owner_id == DISC_ITEM:
		if not _disc.has(index):
			return
		var level: int = int(_disc[index])
		if level <= _cap:
			return
		if is_instance_valid(_field):
			_wake_above(_disc_patch_world(index), _disc_edge(), level, _disc_exclude(), _snow.disc_drift_stretch)
		_set_disc_level(index, _cap)
		return
	var entry: BlockSnow = _blocks.get(owner_id) as BlockSnow
	if entry == null or index >= entry.levels.size():
		return
	var current: int = entry.levels[index]
	if current <= _cap:
		return
	if _block_alive(entry.block):
		_wake_above(_block_patch_world(entry, index), _block_edge(entry), current, _rids(entry.block))
	if _cap == 0:
		_active_block_patches -= 1
	_set_block_level(entry, index, _cap)


func _set_block_level(entry: BlockSnow, index: int, level: int) -> void:
	entry.levels[index] = level
	var cell: int = entry.cells[index]
	var frame: Transform3D = SnowGeometry.block_patch_transform(entry.cell_centers[cell], entry.axis, entry.cube_size)
	var seed_value: int = SnowGeometry.patch_seed(_seed, entry.net_id, cell, entry.axis)
	_builder.set_patch(_block_key(entry), entry.block, -1, cell, frame, _block_edge(entry), seed_value, level)
	_state_dirty = true


func _set_disc_level(cell: int, level: int) -> void:
	_disc[cell] = level
	var grid: CellGrid = _field.grid()
	var region: int = SnowCaps.disc_region(grid, cell, _snow)
	var seed_value: int = SnowGeometry.patch_seed(_seed, SnowGeometry.DISC_OWNER, cell, SnowGeometry.AXIS_UP)
	_builder.set_patch("d%d" % region, _field, region, cell, SnowCaps.disc_patch_frame(grid, cell, _snow), _disc_edge(), seed_value, level)
	_state_dirty = true


# --- Patch frames and physics queries ---------------------------------------------------

func _block_patch_world(entry: BlockSnow, index: int) -> Transform3D:
	var cell: int = entry.cells[index]
	return entry.block.global_transform * SnowGeometry.block_patch_transform(entry.cell_centers[cell], entry.axis, entry.cube_size)


func _block_edge(entry: BlockSnow) -> float:
	return SnowCaps.block_patch_edge(entry.cube_size, _snow)


func _disc_patch_world(cell: int) -> Transform3D:
	return _field.global_transform * SnowCaps.disc_patch_frame(_field.grid(), cell, _snow)


## Edge of the box that covers a stretched drift (queries and wake-ups).
func _disc_query_edge() -> float:
	return _disc_edge() * maxf(_snow.disc_drift_stretch, 1.0)


func _disc_edge() -> float:
	return SnowCaps.disc_patch_edge(_field.grid(), _snow)


func _disc_exclude() -> Array[RID]:
	var exclude: Array[RID] = []
	if is_instance_valid(_field):
		exclude.append(_field.get_rid())
		for body: StaticBody3D in SnowCaps.disc_bodies(_field):
			exclude.append(body.get_rid())
	return exclude


func _prepare_query(patch_world: Transform3D, edge: float, height: float, exclude: Array[RID], stretch: float = 1.0) -> void:
	var tall: float = height + _snow.cover_clearance_m
	_query_box.size = Vector3(edge * maxf(stretch, 1.0), tall, edge)
	_query.transform = patch_world * Transform3D(Basis.IDENTITY, Vector3(0.0, QUERY_BASE_LIFT_M + tall * 0.5, 0.0))
	_query.exclude = exclude


## True when any body sits in the space a dome of `level` would take.
func _occupied(patch_world: Transform3D, edge: float, level: int, exclude: Array[RID], stretch: float = 1.0) -> bool:
	var space: PhysicsDirectSpaceState3D = _space()
	if space == null:
		return true
	_prepare_query(patch_world, edge, SnowGeometry.dome_max_height(level, _snow), exclude, stretch)
	queries_run += 1
	return not space.intersect_shape(_query, COVER_QUERY_RESULTS).is_empty()


## Wakes every rigid body resting on or above a patch that is about to shrink
## or vanish (a sleeping body would otherwise hover on removed snow). A block
## held by the stable-block auto-freeze is released for the same reason.
func _wake_above(patch_world: Transform3D, edge: float, level: int, exclude: Array[RID], stretch: float = 1.0) -> void:
	var space: PhysicsDirectSpaceState3D = _space()
	if space == null:
		return
	_prepare_query(patch_world, edge, SnowGeometry.dome_max_height(level, _snow), exclude, stretch)
	queries_run += 1
	for hit: Dictionary in space.intersect_shape(_query, WAKE_QUERY_RESULTS):
		var body: RigidBody3D = hit.get("collider") as RigidBody3D
		if body == null:
			continue
		var block: Block = body as Block
		if block != null:
			block.wake_for_impulse()
		if block != null:
			block.wake()
		else:
			body.sleeping = false


func _publish() -> void:
	states_published += 1
	SnowRelay.instance().publish(state())
