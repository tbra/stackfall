class_name SandboxPanel
extends CanvasLayer
## Bontago-mv0.8's sandbox debug panel: active slot + colour, block held/next,
## timer state, the ghost's placement-validity reason under the cursor,
## territory share per slot, blocks spawned and physics step time.
##
## Reads only public Match/PlacementRules APIs, never a rule of its own — see
## game/GhostPreview.gd's apply_validity()/_apply_validity_material() for the
## same Match.preview_placement() call this panel's validity label reads —
## so a Territory v2 rewrite (docs/TERRITORY_V2_PLAN.md) needs no change here
## beyond whatever new PlacementRules.Result cases land in _reason_text()'s
## fallback branch, and a new rules-mode field on MatchConfig only needs a
## line in _refresh_rules_mode(), not a redesign.
##
## Plain Labels, updated at sandbox_config.panel_refresh_hz (CLAUDE.md: no
## magic numbers) rather than every _process() frame — none of this needs
## 60 Hz precision.
##
## DECISION (ui/SandboxPanel.gd): a CanvasLayer root with an inner
## PanelContainer, the same shape as ui/HUD.tscn and ui/NetDebugOverlay.tscn,
## rather than a bare Control root — matches the established idiom for a
## screen-space overlay in this project.

@export var sandbox_config: SandboxConfig = preload("res://config/sandbox.tres")

## DECISION (ui/SandboxPanel.gd): same Variant test seam as ui/HUD.gd's
## match_provider and ui/NetDebugOverlay.gd's net_provider — GUT cannot
## double the plain Match autoload (addons/gut/test.gd's double_singleton
## only recognizes engine singletons).
var match_provider: Variant = null

## DECISION (ui/SandboxPanel.gd): `Variant`, not a typed `Sandbox`, even
## though this file owns no test-double seam for it (unlike match_provider
## above). game/Sandbox.gd holds a `SandboxPanel` (`@onready var _panel`) and
## this file held a typed `Sandbox` back — that mutual class_name reference,
## combined with this script defining _process(), reproducibly leaked
## TextServer-shaped-text RIDs at `godot --headless --editor --path . --quit`
## (bisected line by line: removing either side of the cycle, or _process()
## itself, made the leak vanish; the panel's other typed reference, `_ghost:
## GhostPreview`, is not part of a cycle and does not reproduce it). Nothing
## else in this project has two class_name scripts typed at each other like
## this, so the seam here is narrower than match_provider's: only
## active_slot() is ever called on it.
var _sandbox: Variant = null
var _ghost: GhostPreview = null

@onready var _active_slot_label: Label = %ActiveSlotLabel
@onready var _held_block_label: Label = %HeldBlockLabel
@onready var _timer_label: Label = %TimerLabel
@onready var _validity_label: Label = %ValidityLabel
@onready var _shares_label: Label = %SharesLabel
@onready var _spawned_label: Label = %SpawnedLabel
@onready var _physics_ms_label: Label = %PhysicsMsLabel
@onready var _rules_label: Label = %RulesLabel
## Bontago-1en.24: game/Sandbox.gd's F9 sandbox_force_special hotkey.
@onready var _forced_special_label: Label = %ForcedSpecialLabel
## M6 B2: game/Sandbox.gd's F10/F11 hotkeys and the height record.
@onready var _slow_motion_label: Label = %SlowMotionLabel
@onready var _physics_paused_label: Label = %PhysicsPausedLabel
@onready var _height_record_label: Label = %HeightRecordLabel
## M6 B2: the block-picker and special-spawn dropdowns, replacing/augmenting
## the F9 cycle with a direct pick.
@onready var _block_picker: OptionButton = %BlockPicker
@onready var _special_picker: OptionButton = %SpecialPicker

var _refresh_accum: float = 0.0

## The tallest point any of the active slot's settled blocks has reached this
## match (game/BlockRegistry.gd's max_height_for_slot(), polled once per
## _refresh() -- panel_refresh_hz is plenty for a value that only ever climbs
## as fast as blocks settle). Monotone within one match; game/Sandbox.gd's F5
## reset_height_record() call is the only thing that ever lowers it.
var _height_record: float = 0.0


func _ready() -> void:
	match_provider = Match
	# M6 B2 (sandbox_pause_physics, F11): stays interactive while get_tree().
	# paused is true -- see game/Sandbox.gd's own _ready() for the matching
	# flag on that node.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_populate_block_picker()
	_populate_special_picker()
	_block_picker.item_selected.connect(_on_block_picker_selected)
	_special_picker.item_selected.connect(_on_special_picker_selected)


## Called once by game/Sandbox.gd after both children exist. `sandbox` gives
## active_slot(); `ghost` gives the world position/orientation the validity
## reason and the held-block labels read.
func configure(sandbox: Variant, ghost: GhostPreview) -> void:
	_sandbox = sandbox
	_ghost = ghost
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
	var slot_id: int = _sandbox.active_slot() if _sandbox != null else -1
	_refresh_active_slot(slot_id)
	_refresh_held_block(slot_id)
	_refresh_timer(slot_id)
	_refresh_validity(slot_id)
	_refresh_shares()
	_refresh_spawned()
	_refresh_physics_ms()
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
		_active_slot_label.modulate = Color.WHITE


func _refresh_held_block(slot_id: int) -> void:
	var held: BlockShape = match_provider.held_shape(slot_id) if slot_id >= 0 else null
	var next: BlockShape = match_provider.next_shape(slot_id) if slot_id >= 0 else null
	_held_block_label.text = "Held: %s   Next: %s" % [
		String(held.id) if held != null else "-",
		String(next.id) if next != null else "-",
	]


## Bontago-mv0.10 (spec 2.4/2.5 "[ORIGINAL target]" fixed-interval cadence):
## "locked"/"unlocked" alongside the timer, the same distinction
## game/GhostPreview.gd's grey tint draws for the held ghost -- Match.
## is_release_locked() is the one source of truth both read.
func _refresh_timer(slot_id: int) -> void:
	var enabled: bool = bool(match_provider.feed_timer_enabled())
	var left: float = float(match_provider.feed_time_left(slot_id)) if slot_id >= 0 else 0.0
	var locked: bool = bool(match_provider.is_release_locked(slot_id)) if slot_id >= 0 else false
	_timer_label.text = "Timer: %s (%.1fs) [%s]" % [
		"running" if enabled else "paused", left, "locked" if locked else "unlocked"
	]


## Bontago-1en.24: game/GhostPreview.gd's own current_state() already
## distinguishes STATE_THROW (M4 P2e's throw-aim tint, set by show_throw_hint()
## while a held special is being dragged for a throw) from the ordinary
## valid/hole/invalid tints this label used to show exclusively via a fresh
## preview_placement() call -- reading that seam here, before falling back to
## the plain validity check, means a tester aiming a throw sees "throw"
## instead of whatever stale landing-spot reason preview_placement() would
## otherwise report for a gesture that isn't a placement at all.
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


func _refresh_spawned() -> void:
	_spawned_label.text = "Blocks spawned: %d" % int(match_provider.blocks_spawned())


func _refresh_physics_ms() -> void:
	var seconds: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	_physics_ms_label.text = "Physics step: %.2f ms" % (seconds * 1000.0)


## DECISION (ui/SandboxPanel.gd): the enum key's own name
## (MatchConfig.HoleMode.keys()[...]), not a hand-written per-case string, so
## a Territory v2 addition to HoleMode (docs/TERRITORY_V2_PLAN.md mentions a
## new OFF value) shows up here for free instead of silently mislabeling it
## as "permanent" — the one place this panel would otherwise need a change
## for a rules rewrite it is meant to survive untouched.
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


## Bontago-1en.24: game/Sandbox.gd's F9 sandbox_force_special hotkey (and
## `--force-special=`). _sandbox is the same Variant test seam active_slot()
## already reads through (see this file's own DECISION on why it isn't a
## typed Sandbox); forced_special()/forced_special_queue_full() are the two
## getters game/Sandbox.gd exposes for it.
func _refresh_forced_special() -> void:
	if _sandbox == null:
		_forced_special_label.text = "Forced special: -"
		return
	var forced_id: StringName = _sandbox.forced_special()
	if forced_id == &"":
		_forced_special_label.text = "Forced special: off"
		return
	var suffix: String = "  (queue full)" if bool(_sandbox.forced_special_queue_full()) else ""
	_forced_special_label.text = "Forced special: %s%s" % [String(forced_id), suffix]


# --- M6 B2: slow-motion / pause-physics / height record ---------------------

func _refresh_slow_motion() -> void:
	var active: bool = bool(_sandbox.is_slow_motion_active()) if _sandbox != null else false
	_slow_motion_label.text = "Slow-mo: %s (%.2fx)" % ["on" if active else "off", Engine.time_scale]


func _refresh_physics_paused() -> void:
	var paused: bool = bool(_sandbox.is_physics_paused()) if _sandbox != null else false
	_physics_paused_label.text = "Physics: %s" % ("paused" if paused else "running")


func _refresh_height_record(slot_id: int) -> void:
	if slot_id >= 0:
		var registry: BlockRegistry = match_provider.registry()
		if registry != null:
			_height_record = maxf(_height_record, registry.max_height_for_slot(slot_id))
	_height_record_label.text = "Height record: %.2f m" % _height_record


## game/Sandbox.gd's sandbox_reset_field (F5): a freshly reset match starts a
## new tallest stack, so the previous match's record must not linger (the
## same reasoning game/Sandbox.gd's own DECISION gives for resetting Engine.
## time_scale there).
func reset_height_record() -> void:
	_height_record = 0.0
	_height_record_label.text = "Height record: 0.00 m"


# --- M6 B2: block picker / special spawn dropdowns --------------------------

## BlockShape.load_all_shapes()'s own id order (that function's own doc
## comment: the single source of truth for "what shapes exist") -- one item
## per shape, with the StringName id carried in item metadata rather than
## re-derived from the display text.
func _populate_block_picker() -> void:
	_block_picker.clear()
	for shape: BlockShape in BlockShape.load_all_shapes():
		_block_picker.add_item(String(shape.id))
		_block_picker.set_item_metadata(_block_picker.item_count - 1, shape.id)


func _on_block_picker_selected(index: int) -> void:
	if _sandbox == null:
		return
	var shape_id: StringName = _block_picker.get_item_metadata(index)
	_sandbox.force_next_shape(shape_id)


## "off" first (mirrors sandbox_force_special's own off/each-roster-id/off
## cycle), then SpecialDef.load_all_specials()'s own id order -- the UI-only
## front end docs/M6_PLAN.md's package B2 calls for over the existing F9
## cycle/force_special_by_id().
func _populate_special_picker() -> void:
	_special_picker.clear()
	_special_picker.add_item("off")
	_special_picker.set_item_metadata(0, &"")
	for special: SpecialDef in SpecialDef.load_all_specials():
		_special_picker.add_item(String(special.id))
		_special_picker.set_item_metadata(_special_picker.item_count - 1, special.id)


func _on_special_picker_selected(index: int) -> void:
	if _sandbox == null:
		return
	var special_id: StringName = _special_picker.get_item_metadata(index)
	if special_id == &"":
		_sandbox.force_special_off()
	else:
		_sandbox.force_special_by_id(special_id)
