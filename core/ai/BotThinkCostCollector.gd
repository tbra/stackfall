class_name BotThinkCostCollector
extends RefCounted
## the opt-in sink of Hard-bot think cost records. One process-wide instance exists only
## while the report is on: `current()` is null otherwise, and BotController then takes no clock reads and
## allocates no record. It keeps a BotThinkCostReport per bot slot plus an all-bots aggregate (rolling
## windows of `window_thinks` when > 0, unbounded when 0).
## DECISION: reached through this static registry, not an autoload or a node path, so
## the F9 overlay and the headless flow both read `BotThinkCostCollector.current()` without wiring.
## Bots run on the host only: on a client nothing feeds it, current() stays null or has_data() is false.

static var _current: BotThinkCostCollector = null

var _label: String = ""
var _window: int = 0
var _aggregate: BotThinkCostReport = null
var _slots: Dictionary = {}


## Turns the collector on (idempotent: an existing one is kept, so a running overlay and the headless flow
## share it). `window_thinks` 0 = unbounded; the shipped window when negative. A new enable() starts from an
## empty window unless `keep_data` (an already-running collector, e.g. the overlay's, is then left alone).
static func enable(label: String = "live", window_thinks: int = -1, keep_data: bool = false) -> BotThinkCostCollector:
	if _current != null and not keep_data:
		_current.reset()
	if _current == null:
		var window: int = window_thinks if window_thinks >= 0 else BotThinkCostReport.SHIPPED_TUNING.window_thinks
		_current = BotThinkCostCollector.new(label, window)
	return _current


static func disable() -> void:
	_current = null


## The live collector; null while the report is off.
static func current() -> BotThinkCostCollector:
	return _current


func _init(label: String, window_thinks: int) -> void:
	_label = label
	_window = window_thinks
	_aggregate = BotThinkCostReport.new(label + ":all", window_thinks)


## Forgets every record (a new match starts clean).
func reset() -> void:
	_aggregate.clear()
	_slots.clear()


## True when at least one think has been recorded ("no data" on a client, or before the first think).
func has_data() -> bool:
	return _aggregate.has_data()


## Every bot's records together.
func aggregate() -> BotThinkCostReport:
	return _aggregate


## One slot's window (an empty report for a slot that has not thought).
func for_slot(slot_id: int) -> BotThinkCostReport:
	if not _slots.has(slot_id):
		return BotThinkCostReport.new("%s:slot%d" % [_label, slot_id], _window)
	return _slots[slot_id] as BotThinkCostReport


func slot_ids() -> PackedInt32Array:
	var ids: Array = _slots.keys()
	ids.sort()
	return PackedInt32Array(ids)


func _slot_report(slot_id: int) -> BotThinkCostReport:
	if not _slots.has(slot_id):
		_slots[slot_id] = BotThinkCostReport.new("%s:slot%d" % [_label, slot_id], _window)
	return _slots[slot_id] as BotThinkCostReport


func record_think(slot_id: int, record: Dictionary) -> void:
	_slot_report(slot_id).add_think(record)
	_aggregate.add_think(record)


func record_frame(slot_id: int, us: int) -> void:
	_slot_report(slot_id).add_frame(us)
	_aggregate.add_frame(us)
