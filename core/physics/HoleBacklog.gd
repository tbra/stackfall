class_name HoleBacklog
extends RefCounted
## Hole cells waiting to be applied to the disc, drained at a bounded rate per
## tick (from Field.gd:679-761). No scene tree.
## The rules' wishes net out per cell (the last wish wins); drain() applies the
## FIFO of changes up to a budget and says which cells opened.

## Returned by an idle drain(), so the per-tick call allocates nothing.
var _no_cells: PackedInt32Array = PackedInt32Array()

## 1 where the cell carries collision (is in the disk); set from want()'s in_disk.
var _in_disk_flags: PackedByteArray = PackedByteArray()
var _in_disk_count: int = -1
## 1 where the cell is currently an applied hole.
var _applied: PackedByteArray = PackedByteArray()
## 1 where the rules want the cell to be a hole; the backlog is the difference.
var _wanted: PackedByteArray = PackedByteArray()
## FIFO of (cell, wanted) pairs, consumed from _head so that draining never
## shifts a PackedInt32Array.
var _queue_cells: PackedInt32Array = PackedInt32Array()
var _queue_wanted: PackedByteArray = PackedByteArray()
var _head: int = 0
var _applied_total: int = 0


## Records the rules' wish for these cells. `in_disk` lists the cells that carry
## collision; any other cell is ignored.
func want(opened: PackedInt32Array, closed: PackedInt32Array, in_disk: PackedInt32Array) -> void:
	_sync_disk(in_disk)
	for cell: int in opened:
		_enqueue(cell, 1)
	for cell: int in closed:
		_enqueue(cell, 0)


## Applies up to `budget` (at least one) queued changes in order. Returns the
## cells that opened during this drain.
func drain(budget: int) -> PackedInt32Array:
	if _head >= _queue_cells.size():
		return _no_cells
	var opened: PackedInt32Array = PackedInt32Array()
	var limit: int = maxi(budget, 1)
	var applied: int = 0
	while _head < _queue_cells.size() and applied < limit:
		var cell: int = _queue_cells[_head]
		var open: bool = _queue_wanted[_head] == 1
		_head += 1
		if (_applied[cell] == 1) == open:
			continue
		_applied[cell] = 1 if open else 0
		_applied_total += 1 if open else -1
		applied += 1
		if open:
			opened.append(cell)
	if _head >= _queue_cells.size():
		_queue_cells = PackedInt32Array()
		_queue_wanted = PackedByteArray()
		_head = 0
	return opened


func is_applied(cell: int) -> bool:
	if cell < 0 or cell >= _applied.size():
		return false
	return _applied[cell] == 1


func applied_count() -> int:
	return _applied_total


## Closes every applied hole and drops the queue, at once.
func clear() -> void:
	_applied.fill(0)
	_wanted.fill(0)
	_applied_total = 0
	_queue_cells = PackedInt32Array()
	_queue_wanted = PackedByteArray()
	_head = 0


func _enqueue(cell: int, wanted: int) -> void:
	if cell < 0 or cell >= _in_disk_flags.size() or _in_disk_flags[cell] == 0:
		return
	if _wanted[cell] == wanted:
		return
	_wanted[cell] = wanted
	_queue_cells.append(cell)
	_queue_wanted.append(wanted)


## Rebuilds the per-cell arrays when the disk changes; the size stands in for
## identity (the disk list is built once per map).
func _sync_disk(in_disk: PackedInt32Array) -> void:
	if in_disk.size() == _in_disk_count:
		return
	var cells: int = 0
	for cell: int in in_disk:
		cells = maxi(cells, cell + 1)
	_in_disk_count = in_disk.size()
	_in_disk_flags = PackedByteArray()
	_in_disk_flags.resize(cells)
	for cell: int in in_disk:
		_in_disk_flags[cell] = 1
	_applied.resize(cells)
	_wanted.resize(cells)
