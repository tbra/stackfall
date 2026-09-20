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

var _refresh_accum: float = 0.0


func _ready() -> void:
	match_provider = Match


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


func _refresh_timer(slot_id: int) -> void:
	var enabled: bool = bool(match_provider.feed_timer_enabled())
	var left: float = float(match_provider.feed_time_left(slot_id)) if slot_id >= 0 else 0.0
	_timer_label.text = "Timer: %s (%.1fs)" % ["running" if enabled else "paused", left]


func _refresh_validity(slot_id: int) -> void:
	if _ghost == null or slot_id < 0:
		_validity_label.text = "Ghost: -"
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
