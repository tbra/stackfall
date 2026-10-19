class_name SnowClientRenderer
extends RefCounted
## Draws a client's snow caps from the host's sanitized snow state (the
## SnowGeometry wire dictionary). Visual only: it never creates a collider and
## never decides anything. It knows nothing of peers or RPCs: SnowNet validates
## the payload and hands the result to set_state() / apply().
##
## The world comes through two Callables (a Field and a BlockRegistry, either
## may answer null), so a test can build caps from a state dictionary without
## any session or Match autoload. Drawing is amortised: apply() diffs the state
## against what is drawn and queues the changes on the builder, step() draws
## them over the next frames.

var tuning: SnowTuning = null

var _field_source: Callable = Callable()
var _registry_source: Callable = Callable()
## The last applied sanitized state, the blocks drawn (net_id -> Block) and the
## records they were drawn from.
var _state: Dictionary = {}
var _rendered: Dictionary = {}
var _rendered_records: Dictionary = {}
var _rendered_disc: Dictionary = {}
var _unresolved: bool = false
var _builder: SnowCapBuilder = null


## `field_source` -> Field (or null), `registry_source` -> BlockRegistry (or null).
func _init(snow_tuning: SnowTuning, field_source: Callable, registry_source: Callable) -> void:
	tuning = snow_tuning
	_field_source = field_source
	_registry_source = registry_source


## True when the last applied state names a block whose net_id is not bound yet.
func is_unresolved() -> bool:
	return _unresolved


## Stores `data` (a SnowGeometry.sanitize_state result) and diffs it onto the world.
func apply(data: Dictionary) -> void:
	_state = data
	render()


## Removes every drawn cap and forgets the state.
func clear() -> void:
	if _builder != null:
		_builder.clear_all()
	for key: Variant in _rendered.keys():
		var held: Variant = _rendered[key]
		if is_instance_valid(held):
			SnowCaps.clear_block(held as Block)
	_rendered.clear()
	_rendered_records.clear()
	_rendered_disc.clear()
	_state = {}
	_unresolved = false
	var field: Field = _field()
	if field != null:
		SnowCaps.clear_disc(field)


## Steps the geometry builder (budgeted like the host's).
func step(budget: int) -> void:
	if _builder != null and not _builder.is_idle():
		_builder.step(budget)


## Diffs the applied state against what is drawn and hands the changes to the
## builder; drawing happens over the next frames in step().
func render() -> void:
	if _state.is_empty():
		return
	if _builder == null or _builder.tuning != tuning:
		_builder = SnowCapBuilder.new(tuning, false)
	var registry: BlockRegistry = _registry()
	var seed_value: int = int(_state["seed"])
	var blocks: Dictionary = _state["blocks"]
	for key: Variant in _rendered.keys():
		# A freed block (gift blast/despawn) is a stale key even if the host still lists it.
		if not blocks.has(key) or not is_instance_valid(_rendered[key]):
			var gone: Variant = _rendered[key]
			_builder.drop_owner("b%d" % int(key))
			if is_instance_valid(gone):
				SnowCaps.clear_block(gone as Block)
			_rendered.erase(key)
			_rendered_records.erase(key)
	_unresolved = false
	for key: Variant in blocks.keys():
		var net_id: int = int(key)
		var record: Array = blocks[key]
		var block: Block = registry.block_for_net_id(net_id) if registry != null else null
		if block == null or not is_instance_valid(block):
			_unresolved = true
			continue
		if _rendered.get(net_id) == block and _rendered_records.get(net_id) == record:
			continue
		_set_block_record(block, net_id, record, _rendered_records.get(net_id, []) as Array, seed_value)
		_rendered[net_id] = block
		_rendered_records[net_id] = record
	var field: Field = _field()
	if field == null:
		return
	var disc: Dictionary = _state["disc"]
	if disc != _rendered_disc:
		var grid: CellGrid = field.grid()
		var edge: float = SnowCaps.disc_patch_edge(grid, tuning)
		for key: Variant in _rendered_disc.keys():
			if not disc.has(key):
				_set_disc_cell(field, grid, edge, int(key), 0, seed_value)
		for key: Variant in disc.keys():
			if int(_rendered_disc.get(key, 0)) != int(disc[key]):
				_set_disc_cell(field, grid, edge, int(key), int(disc[key]), seed_value)
		_rendered_disc = disc
	SnowCaps.set_disc_cover(field, seed_value, int(_state["cover"]), tuning, _blocks)


func _field() -> Field:
	return _field_source.call() as Field if _field_source.is_valid() else null


func _registry() -> BlockRegistry:
	return _registry_source.call() as BlockRegistry if _registry_source.is_valid() else null


func _blocks() -> Array:
	var registry: BlockRegistry = _registry()
	return registry.all_blocks() if registry != null else []


func _set_block_record(block: Block, net_id: int, record: Array, previous: Array, seed_value: int) -> void:
	var axis: int = int(record[0])
	var cells: PackedInt32Array = record[1]
	var levels: PackedInt32Array = record[2]
	var cube_size: float = SnowCaps.cube_size_of(block)
	var centers: PackedVector3Array = SnowCaps.block_cells(block)
	var key: String = "b%d" % net_id
	if not previous.is_empty() and int(previous[0]) != axis:
		_builder.drop_owner(key)
		previous = []
	if not previous.is_empty():
		var old_cells: PackedInt32Array = previous[1]
		for cell: int in old_cells:
			if not cells.has(cell) and cell < centers.size():
				_builder.set_patch(key, block, -1, cell, SnowGeometry.block_patch_transform(centers[cell], axis, cube_size), 0.0, 0, 0)
	for k: int in range(cells.size()):
		var cell: int = cells[k]
		if cell >= centers.size():
			continue
		_builder.set_patch(
			key, block, -1, cell, SnowGeometry.block_patch_transform(centers[cell], axis, cube_size),
			SnowCaps.block_patch_edge(cube_size, tuning), SnowGeometry.patch_seed(seed_value, net_id, cell, axis), levels[k]
		)


func _set_disc_cell(field: Field, grid: CellGrid, edge: float, cell: int, level: int, seed_value: int) -> void:
	var region: int = SnowCaps.disc_region(grid, cell, tuning)
	_builder.set_patch(
		"d%d" % region, field, region, cell, SnowCaps.disc_patch_frame(grid, cell, tuning), edge,
		SnowGeometry.patch_seed(seed_value, SnowGeometry.DISC_OWNER, cell, SnowGeometry.AXIS_UP), level
	)
