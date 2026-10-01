class_name BlockDissolveFx
extends Node
## Bontago-1pi.11.42 (owner decision Bontago-gdb): the visual half of a hole
## dissolve. On Events.block_dissolve_started (emitted by HoleDissolver on the
## host and by MatchNet for the clients' copy) this drives the block's
## `dissolve_amount` *instance* shader parameter from 0 to 1 over the event's
## duration (HoleDissolveTuning.dissolve_delay_s): shaders/block_cell_grid.
## gdshader and block_outline.gdshader eat the block away with 3D noise and a
## glowing void-coloured edge. Instance parameters leave the shared per-colour
## materials untouched; only the dissolving blocks cost any CPU (one float
## write per mesh per frame).
##
## Owned by game/Field.tscn next to BlockEffectsManager. Presentation only:
## the removal itself stays HoleDissolver's, and a removed block just drops out
## of the table. Disabled by GraphicsPreset.block_dissolve_effect_enabled.

const PARAM: StringName = &"dissolve_amount"

@export var visuals: HoleVisualTuning = preload("res://config/hole_visual_tuning.tres")

class _Entry:
	var block: Block = null
	var elapsed: float = 0.0
	var duration: float = 0.0

## instance id -> _Entry
var _entries: Dictionary = {}
var _enabled: bool = true


func _ready() -> void:
	Events.block_dissolve_started.connect(_on_dissolve_started)
	Events.block_removed.connect(_on_block_removed)
	var preset: GraphicsPreset = Settings.current_graphics_preset()
	_enabled = preset == null or preset.block_dissolve_effect_enabled
	Settings.graphics_preset_changed.connect(_on_graphics_preset_changed)
	set_process(false)


func _exit_tree() -> void:
	if Settings.graphics_preset_changed.is_connected(_on_graphics_preset_changed):
		Settings.graphics_preset_changed.disconnect(_on_graphics_preset_changed)
	if Events.block_dissolve_started.is_connected(_on_dissolve_started):
		Events.block_dissolve_started.disconnect(_on_dissolve_started)
	if Events.block_removed.is_connected(_on_block_removed):
		Events.block_removed.disconnect(_on_block_removed)


func is_effect_enabled() -> bool:
	return _enabled


func active_count() -> int:
	return _entries.size()


## Current dissolve progress (0..1) of `block`, or 0.0 when it is not fading.
func amount_for(block: Block) -> float:
	if block == null:
		return 0.0
	var entry: _Entry = _entries.get(block.get_instance_id()) as _Entry
	return 0.0 if entry == null else _progress(entry)


func _on_graphics_preset_changed(preset: GraphicsPreset) -> void:
	_enabled = preset == null or preset.block_dissolve_effect_enabled
	if not _enabled:
		for entry: _Entry in _entries.values():
			_apply(entry.block, 0.0)
		_entries.clear()
		set_process(false)


func _on_dissolve_started(block: RigidBody3D, _net_id: int, duration_s: float) -> void:
	var typed: Block = block as Block
	if not _enabled or typed == null or not is_instance_valid(typed):
		return
	var id: int = typed.get_instance_id()
	if _entries.has(id):
		return
	var entry: _Entry = _Entry.new()
	entry.block = typed
	entry.duration = maxf(duration_s, 0.0)
	_entries[id] = entry
	_apply(typed, _progress(entry))
	set_process(true)


## A removed block leaves the table; one that survives its removal event (a
## pooled or reused body) is reset so it never keeps a half-eaten look.
func _on_block_removed(block: RigidBody3D, _reason: String) -> void:
	if block == null:
		return
	var id: int = block.get_instance_id()
	var entry: _Entry = _entries.get(id) as _Entry
	if entry == null:
		return
	_entries.erase(id)
	if is_instance_valid(block) and not block.is_queued_for_deletion():
		_apply(entry.block, 0.0)
	if _entries.is_empty():
		set_process(false)


func _process(delta: float) -> void:
	step(delta)


## Advances every fade by `delta` seconds (public so tests drive it).
func step(delta: float) -> void:
	var gone: Array[int] = []
	for id: int in _entries:
		var entry: _Entry = _entries[id]
		if entry.block == null or not is_instance_valid(entry.block) or entry.block.is_queued_for_deletion():
			gone.append(id)
			continue
		entry.elapsed += delta
		_apply(entry.block, _progress(entry))
	for id: int in gone:
		_entries.erase(id)
	if _entries.is_empty():
		set_process(false)


func _progress(entry: _Entry) -> float:
	if entry.duration <= 0.0:
		return 1.0
	var t: float = clampf(entry.elapsed / entry.duration, 0.0, 1.0)
	return pow(t, visuals.dissolve_progress_power)


static func _apply(block: Block, amount: float) -> void:
	if block == null or not is_instance_valid(block):
		return
	for child: Node in block.get_children():
		var mesh_instance: MeshInstance3D = child as MeshInstance3D
		if mesh_instance != null:
			mesh_instance.set_instance_shader_parameter(PARAM, amount)
