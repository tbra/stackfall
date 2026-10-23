class_name SandboxPanel
extends CanvasLayer
## The sandbox debug panel: active slot + colour, block held/next,
## timer state, the ghost's placement-validity reason under the cursor and
## territory share per slot. Block count and physics step time live in the F1
## PerfOverlay (ui/debug/PerfOverlay.gd), not here.
##
## Reads only public Match/PlacementRules APIs, never a rule of its own (the validity label reads
## the same Match.preview_placement() as game/player/GhostPreview.gd), so a rules rewrite needs a
## change only for new PlacementRules.Result cases in _reason_text()'s fallback and new rules-mode
## fields in _refresh_rules_mode().
##
## Plain Labels, updated at sandbox_config.panel_refresh_hz rather than every _process() frame.
##
## DECISION (ui/debug/SandboxPanel.gd): a CanvasLayer root with an inner PanelContainer, the same
## shape as ui/hud/HUD.tscn and ui/debug/NetDebugOverlay.tscn, rather than a bare Control root.

@export var sandbox_config: SandboxConfig = preload("res://config/match/sandbox.tres")

## DECISION (ui/debug/SandboxPanel.gd): same Variant test seam as ui/hud/HUD.gd's match_provider
## and ui/debug/NetDebugOverlay.gd's net_provider; GUT cannot double the plain Match autoload.
var match_provider: Variant = null

## Emitted by the block-picker / special-spawn dropdowns; game/sandbox/Sandbox.gd connects them. An
## empty special id is the "off" entry.
signal block_picked(shape_id: StringName)
signal special_picked(special_id: StringName)

## Sandbox state, pushed in by game/sandbox/Sandbox.gd through set_sandbox_state() (the panel holds no
## Sandbox reference).
var _slot_id: int = -1
var _forced_special_id: StringName = &""
var _forced_special_queue_full: bool = false
var _slow_motion_active: bool = false
var _physics_paused: bool = false
var _has_state: bool = false
var _ghost: GhostPreview = null

@onready var _active_slot_label: Label = %ActiveSlotLabel
@onready var _held_block_label: Label = %HeldBlockLabel
@onready var _timer_label: Label = %TimerLabel
@onready var _validity_label: Label = %ValidityLabel
@onready var _shares_label: Label = %SharesLabel
@onready var _rules_label: Label = %RulesLabel
## The F9 sandbox_force_special hotkey (game/sandbox/Sandbox.gd).
@onready var _forced_special_label: Label = %ForcedSpecialLabel
## The F10/F11 hotkeys (game/sandbox/Sandbox.gd) and the height record.
@onready var _slow_motion_label: Label = %SlowMotionLabel
@onready var _physics_paused_label: Label = %PhysicsPausedLabel
@onready var _height_record_label: Label = %HeightRecordLabel
## The block-picker and special-spawn dropdowns: a direct pick alongside the F9 cycle.
@onready var _block_picker: OptionButton = %BlockPicker
@onready var _special_picker: OptionButton = %SpecialPicker

var _refresh_accum: float = 0.0

## The tallest point any of the active slot's settled blocks has reached this match
## (BlockRegistry.max_height_for_slot(), polled once per _refresh()). Monotone within one match;
## a rebuilt panel starts from zero.
var _height_record: float = 0.0


func _ready() -> void:
	match_provider = Match
	# Stays interactive while get_tree().paused is true (sandbox_pause_physics, F11).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_populate_block_picker()
	_populate_special_picker()
	_block_picker.item_selected.connect(_on_block_picker_selected)
	_special_picker.item_selected.connect(_on_special_picker_selected)


## Called once by game/sandbox/Sandbox.gd after both children exist. `ghost` gives the world
## position/orientation the validity reason and the held-block labels read.
func configure(ghost: GhostPreview) -> void:
	_ghost = ghost
	_refresh()


## Sandbox pushes its state here on attach and after every change.
func set_sandbox_state(
	slot_id: int, forced_special_id: StringName, queue_full: bool, slow_motion: bool, physics_paused: bool
) -> void:
	_slot_id = slot_id
	_forced_special_id = forced_special_id
	_forced_special_queue_full = queue_full
	_slow_motion_active = slow_motion
	_physics_paused = physics_paused
	_has_state = true
	if is_node_ready():
		_refresh()


func _process(delta: float) -> void:
	_refresh_accum += delta
	var interval: float = 1.0 / maxf(sandbox_config.panel_refresh_hz, 0.001)
	if _refresh_accum < interval:
		return
	_refresh_accum = fmod(_refresh_accum, interval)
	_refresh()


func _refresh() -> void:
	if match_provider == null:
		return
	var slot_id: int = _slot_id if _has_state else -1
	_refresh_active_slot(slot_id)
	_refresh_held_block(slot_id)
	_refresh_timer(slot_id)
	_refresh_validity(slot_id)
	_refresh_shares()
	_refresh_rules_mode()
	_refresh_forced_special()
	_refresh_slow_motion()
	_refresh_physics_paused()
	_refresh_height_record(slot_id)


func _refresh_active_slot(slot_id: int) -> void:
	var slot: PlayerSlot = match_provider.slot(slot_id) if slot_id >= 0 else null
	if slot != null:
		_active_slot_label.text = "Active: P%d" % (slot_id + 1)
		_active_slot_label.modulate = slot.color
	else:
		_active_slot_label.text = "Active: -"
		# DECISION: no-slot label uses the arcade cream token, not raw white.
		_active_slot_label.modulate = MenuStyleFactory.arcade_tuning().cream_color


func _refresh_held_block(slot_id: int) -> void:
	var held: BlockShape = match_provider.held_shape(slot_id) if slot_id >= 0 else null
	var next: BlockShape = match_provider.next_shape(slot_id) if slot_id >= 0 else null
	_held_block_label.text = "Held: %s   Next: %s" % [
		String(held.id) if held != null else "-",
		String(next.id) if next != null else "-",
	]


## Spec 1.4 fixed-interval cadence: "locked"/"unlocked" alongside the timer, the same distinction
## the ghost's grey tint draws; Match.is_release_locked() is the one source of truth for both.
func _refresh_timer(slot_id: int) -> void:
	var enabled: bool = bool(match_provider.feed_timer_enabled())
	var left: float = float(match_provider.feed_time_left(slot_id)) if slot_id >= 0 else 0.0
	var locked: bool = bool(match_provider.is_release_locked(slot_id)) if slot_id >= 0 else false
	_timer_label.text = "Timer: %s (%.1fs) [%s]" % [
		"running" if enabled else "paused", left, "locked" if locked else "unlocked"
	]


## GhostPreview.current_state() is read before the plain validity check so a tester aiming a throw
## (STATE_THROW) sees "throw" instead of a stale landing-spot reason for a gesture that is not a
## placement.
func _refresh_validity(slot_id: int) -> void:
	if _ghost == null or slot_id < 0:
		_validity_label.text = "Ghost: -"
		return
	if _ghost.current_state() == GhostPreview.STATE_THROW:
		_validity_label.text = "Ghost: throw"
		return
	var result: PlacementRules.Result = match_provider.preview_placement(
		slot_id, _ghost.global_position, _ghost.orientation_index, _ghost.free_quaternion
	)
	_validity_label.text = "Ghost: %s" % _reason_text(result)


func _reason_text(result: PlacementRules.Result) -> String:
	if result == PlacementRules.Result.VALID:
		return "valid"
	var reason: StringName = PlacementRules.reason_for(result)
	return String(reason) if reason != PlacementRules.REASON_OK else "valid"


func _refresh_shares() -> void:
	var count: int = int(match_provider.slot_count())
	var parts: PackedStringArray = PackedStringArray()
	for i: int in range(count):
		var team_id: int = int(match_provider.team_of(i))
		parts.append("P%d %.0f%%" % [i + 1, float(match_provider.territory_share(team_id)) * 100.0])
	_shares_label.text = "Territory: -" if parts.is_empty() else "Territory: %s" % ", ".join(parts)


## DECISION (ui/debug/SandboxPanel.gd): the enum key's own name (MatchConfig.HoleMode.keys()[...]),
## not a hand-written per-case string, so a new HoleMode value shows up here for free instead of
## being mislabelled.
func _refresh_rules_mode() -> void:
	var config: MatchConfig = match_provider.config
	if config == null:
		_rules_label.text = "Rules: -"
		return
	var hole_mode_names: PackedStringArray = MatchConfig.HoleMode.keys()
	var hole_mode_name: String = (
		hole_mode_names[config.hole_mode].to_lower() if config.hole_mode < hole_mode_names.size() else "?"
	)
	_rules_label.text = "Rules: holes %s" % hole_mode_name


## The F9 sandbox_force_special hotkey (and `--force-special=`), from the pushed sandbox state.
func _refresh_forced_special() -> void:
	if not _has_state:
		_forced_special_label.text = "Forced special: -"
		return
	var forced_id: StringName = _forced_special_id
	if forced_id == &"":
		_forced_special_label.text = "Forced special: off"
		return
	var suffix: String = "  (queue full)" if _forced_special_queue_full else ""
	_forced_special_label.text = "Forced special: %s%s" % [String(forced_id), suffix]


# --- Slow-motion / pause-physics / height record ---------------------

func _refresh_slow_motion() -> void:
	_slow_motion_label.text = "Slow-mo: %s (%.2fx)" % ["on" if _slow_motion_active else "off", Engine.time_scale]


func _refresh_physics_paused() -> void:
	_physics_paused_label.text = "Physics: %s" % ("paused" if _physics_paused else "running")


func _refresh_height_record(slot_id: int) -> void:
	if slot_id >= 0:
		var registry: BlockRegistry = match_provider.registry()
		if registry != null:
			_height_record = maxf(_height_record, registry.max_height_for_slot(slot_id))
	_height_record_label.text = "Height record: %.2f m" % _height_record


# --- Block picker / special spawn dropdowns --------------------------

## One item per bag shape in BlockShape's id order, with the StringName id carried in item metadata
## rather than re-derived from the display text.
func _populate_block_picker() -> void:
	_block_picker.clear()
	for shape: BlockShape in BlockShape.load_bag_shapes():
		_block_picker.add_item(DisplayNames.shape(shape.id))
		_block_picker.set_item_metadata(_block_picker.item_count - 1, shape.id)


func _on_block_picker_selected(index: int) -> void:
	var shape_id: StringName = _block_picker.get_item_metadata(index)
	block_picked.emit(shape_id)


## "off" first (mirrors the sandbox_force_special off/each-id/off cycle), then
## SpecialDef.load_all_specials()'s id order.
func _populate_special_picker() -> void:
	_special_picker.clear()
	_special_picker.add_item("off")
	_special_picker.set_item_metadata(0, &"")
	for special: SpecialDef in SpecialDef.load_all_specials():
		_special_picker.add_item(String(special.id))
		_special_picker.set_item_metadata(_special_picker.item_count - 1, special.id)


func _on_special_picker_selected(index: int) -> void:
	var special_id: StringName = _special_picker.get_item_metadata(index)
	special_picked.emit(special_id)
