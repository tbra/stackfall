class_name Sandbox
extends Node
## The unlisted `godot --path . -- --sandbox [--players=N]` debug entry point
## (Bontago-mv0.8): a HotSeat-shaped controller/ghost/HUD subtree (same shape
## as game/HotSeat.tscn, reused rather than duplicated) plus the extra
## hotkeys and the debug panel a manual rules/physics tester needs.
##
## Every slot is locally controllable offline (autoload/Net.gd's
## is_local_slot() is already true for every slot there); this instance
## drives whichever one is "active" and sandbox_next_slot cycles it through
## game/PlayerController.gd's set_sandbox_slot() seam. It decides nothing
## about the rules itself — sandbox_spawn_tower still goes through
## Match.request_place() like every other placement, and sandbox_reset_field
## goes through Match.start_match() — so it survives a rules rewrite
## (docs/TERRITORY_V2_PLAN.md) untouched.

@export var sandbox_config: SandboxConfig = preload("res://config/sandbox.tres")

@onready var _controller: PlayerController = $PlayerController
@onready var _ghost: GhostPreview = $GhostPreview
@onready var _hud: HUD = $HUDLayer
@onready var _panel: SandboxPanel = $SandboxPanel
## Bontago-mv0.18: the in-game tuning panel (F4), self-contained here the
## same way SandboxPanel is above -- see game/HotSeat.gd's matching field for
## why this lives inside the subtree rather than being instanced separately
## by game/Main.gd.
@onready var _tuning_panel: TuningPanel = $TuningPanel

var _field: Field = null
var _active_slot: int = 0

## Bontago-1en.24: SpecialDef.load_all_specials()'s own id order, cached once
## at _ready() rather than re-scanning res://config/specials/ on every F9
## press -- a plain Array[SpecialDef] there is the roster's authority; this
## file only needs the ids, and only ever reads them (never mutates the
## roster), so a cached copy cannot drift from a rewrite mid-match (nothing
## in this package edits config/specials/ at runtime).
var _special_roster_ids: Array[StringName] = []

## -1 is "off"; otherwise an index into _special_roster_ids. sandbox_force_
## special (F9) cycles this: off -> each id in roster order -> off.
var _forced_special_index: int = -1
## The forced id ui/SandboxPanel.gd shows, or &"" when off. Kept alongside
## _forced_special_index rather than derived on every panel refresh so a
## garbage index (there is none today, but see _apply_forced_special()'s own
## bounds check) can never read out of range.
var _forced_special_id: StringName = &""
## True when the last _apply_forced_special() call's debug_queue_special()
## refused because the active slot's queue was already at GiftConfig.
## max_pending_specials -- ui/SandboxPanel.gd surfaces this so a tester knows
## why F9 didn't visibly hand out anything, rather than looking like a bug.
var _forced_special_queue_full: bool = false


func _ready() -> void:
	Events.turn_changed.connect(_on_turn_changed)
	_panel.configure(self, _ghost)
	_tuning_panel.set_controller(_controller)
	_special_roster_ids = _load_special_roster_ids()
	# Bontago-mv0.14 (spec 1.5): see HotSeat.gd's matching _ready() comment --
	# safe headless (a silent no-op with no window to capture).
	_controller.enable_mouse_capture()


func _load_special_roster_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for def: SpecialDef in SpecialDef.load_all_specials():
		ids.append(def.id)
	return ids


## Called once by game/Main.gd, the same way HotSeat.set_camera_rig() is —
## CameraRig lives outside this subtree.
func set_camera_rig(rig: CameraRig) -> void:
	_controller.set_camera_rig(rig)
	_tuning_panel.set_camera_rig(rig)


## Called once by game/Main.gd. Only sandbox_reset_field/sandbox_spawn_tower
## need it (Field.place_flags()/set_overlay_source() after a reset; the
## ghost already gets its own placement ray from PlayerController without
## this) -- and, from Bontago-mv0.18, the tuning panel's Territory tab.
func set_field(field: Field) -> void:
	_field = field
	_tuning_panel.set_field(field)


func controller() -> PlayerController:
	return _controller


func ghost() -> GhostPreview:
	return _ghost


func hud() -> HUD:
	return _hud


func panel() -> SandboxPanel:
	return _panel


## The slot this instance is currently driving. ui/SandboxPanel.gd reads
## this every refresh.
func active_slot() -> int:
	return _active_slot


## The forced special's id, or &"" when off (sandbox_force_special is
## currently cycled to "off"). ui/SandboxPanel.gd reads this every refresh.
func forced_special() -> StringName:
	return _forced_special_id


## Whether the last F9/--force-special apply refused to seed the active
## slot's queue because it was already full. ui/SandboxPanel.gd reads this
## every refresh.
func forced_special_queue_full() -> bool:
	return _forced_special_queue_full


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"sandbox_next_slot"):
		_cycle_active_slot()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"sandbox_reset_field"):
		_reset_field()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"sandbox_spawn_tower"):
		_spawn_tower()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"sandbox_toggle_timer"):
		Match.set_feed_timer_enabled(not Match.feed_timer_enabled())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"sandbox_toggle_overlay"):
		_toggle_overlay()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"sandbox_force_special"):
		_cycle_forced_special()
		get_viewport().set_input_as_handled()


# --- Hotkeys ------------------------------------------------------------

## sandbox_next_slot (Tab / gamepad Back): the one seam PlayerController
## exposes for this (set_sandbox_slot()), cycling 0..player_count-1. Wraps
## rather than stopping at the last slot so repeated presses are a simple
## round-robin.
func _cycle_active_slot() -> void:
	var count: int = Match.config.player_count if Match.config != null else 0
	if count <= 0:
		return
	_set_active_slot((_active_slot + 1) % count)


func _set_active_slot(slot_id: int) -> void:
	_active_slot = slot_id
	_controller.set_sandbox_slot(slot_id)
	# Bontago-mv0.9: the HUD only re-reads Events.turn_changed's slot, which
	# in sandbox (config.hot_seat == false) fires exactly once at match start
	# (autoload/Match.gd's advance_turn() no-ops outside hot-seat) -- without
	# this, cycling which slot this instance drives would leave the HUD
	# pointed at whichever slot happened to go first.
	_hud.set_local_slot(slot_id)


## sandbox_reset_field (F5): "clear blocks, rebuild territory/flags for the
## same config" (Bontago-mv0.8) — Match.start_match() already does exactly
## that for any config, including a repeat of the one currently running (see
## its own doc comment on a start from any state), so this only has to
## replay the two calls game/Main.gd makes right after start_match() for
## every other entry point: Field.place_flags()/set_overlay_source() need
## the fresh raster and slots that only exist once start_match() returns.
func _reset_field() -> void:
	if Match.config == null:
		return
	Match.start_match(Match.config)
	var config: MatchConfig = Match.config
	if _field != null:
		_field.place_flags(config.player_count, config.player_colors, config.goal_flag_count)
		_field.set_overlay_source(Match.raster(), config.player_colors)
	_set_active_slot(0)


## sandbox_spawn_tower (F7): drops sandbox_config.tower_block_count blocks,
## stacked sandbox_config.tower_spacing apart, at the ghost's current (x, z)
## — through Match.request_place() so PlacementRules still decides whether
## each one lands, exactly like a real click.
##
## DECISION (game/Sandbox.gd): request_place() has no shape parameter — it
## always spawns whatever the target slot is currently holding
## (autoload/Match.gd) — and this package does not own core/ rule logic, so
## there is no in-scope way to force every drop to a fixed cube shape
## without either reaching into Match's private _held_shapes (breaking its
## encapsulation for a debug feature) or duplicating the bag/feed system
## here. Each call in the loop below still lands the slot's real held block
## and immediately
## refeeds (_consume_and_refeed() runs inside request_place() itself), so in
## practice this builds a tower of whatever the bag deals next, not
## literally N cubes — the debugging value (a fast physical stack to test
## territory/physics against) is the same either way.
func _spawn_tower() -> void:
	if _ghost == null or Match.state() != Match.State.PLAYING:
		return
	var origin: Vector3 = _ghost.global_position
	for i: int in range(sandbox_config.tower_block_count):
		var drop_origin: Vector3 = origin + Vector3.UP * (sandbox_config.tower_spacing * float(i))
		Match.request_place(_active_slot, drop_origin, 0, Quaternion.IDENTITY, false)


## sandbox_toggle_overlay (F8): Field.overlay() is a plain node reference
## (game/Field.gd's public getter); toggling its own `visible` is a generic
## Node property write, not new Field behavior, so this stays inside this
## package's ownership of Sandbox-only files.
func _toggle_overlay() -> void:
	if _field == null:
		return
	var overlay: TerritoryOverlay = _field.overlay()
	if overlay != null:
		overlay.visible = not overlay.visible


# --- sandbox_force_special: F9 -----------------------------------------------
#
# Bontago-1en.24: forces the next drawn special to a fixed id so a tester can
# exercise each of the seven specials on demand instead of waiting on the
# crate roll's RNG (spec 2.6/2.8). F9 cycles off -> each SpecialDef.
# load_all_specials() id, in that order -> off; `--force-special=<id>`
# (game/Main.gd) sets the same state at startup. Both converge on
# _apply_forced_special() below, so the hotkey and the CLI flag can never
# diverge in behaviour.

## sandbox_force_special (F9 / gamepad): advances _forced_special_index one
## step, wrapping "off" (-1) back in after the last roster id -- see this
## field's own doc comment for the off/on-roster/off shape.
func _cycle_forced_special() -> void:
	if _special_roster_ids.is_empty():
		return
	_forced_special_index += 1
	if _forced_special_index >= _special_roster_ids.size():
		_forced_special_index = -1
	_apply_forced_special()


## `--force-special=<id>` (game/Main.gd's own CLI parsing) converges here:
## `special_id` must be one of _special_roster_ids' own ids or this is a
## no-op with a warning, never a silent ignore -- the CLI flag is a debug
## convenience, not a second source of truth for the roster load_all_
## specials() already built.
func force_special_by_id(special_id: StringName) -> void:
	var index: int = _special_roster_ids.find(special_id)
	if index < 0:
		push_warning("Sandbox: --force-special=%s is not a known special id; ignoring" % [special_id])
		return
	_forced_special_index = index
	_apply_forced_special()


## The one place both _cycle_forced_special() and force_special_by_id()
## install state: "off" restores whatever drawer a real match would be
## running (Match.restore_default_special_drawer()); any roster index installs
## a Callable that always returns that one id (Match.set_special_drawer()) so
## every future crate claim/on_feed_block_issued() roll keeps handing out the
## forced special for as long as this stays on, and immediately seeds the
## active slot's queue via Match.debug_queue_special() so a tester need not
## wait on a crate at all. A full queue leaves _forced_special_queue_full
## true for the panel and otherwise does nothing (debug_queue_special()'s own
## contract) -- the forced drawer is still installed either way.
func _apply_forced_special() -> void:
	if _forced_special_index < 0 or _forced_special_index >= _special_roster_ids.size():
		_forced_special_id = &""
		_forced_special_queue_full = false
		Match.restore_default_special_drawer()
		return
	var special_id: StringName = _special_roster_ids[_forced_special_index]
	_forced_special_id = special_id
	Match.set_special_drawer(func() -> StringName: return special_id)
	_forced_special_queue_full = not Match.debug_queue_special(_active_slot, special_id)


func _on_turn_changed(slot_id: int) -> void:
	# Match._begin_playing() emits this once when every match starts (hot-seat
	# or not) to seed whoever acts first; sandbox has no real "turn" after
	# that (config.hot_seat is false), so this only sets the initial active
	# slot. sandbox_next_slot/_reset_field() own every change after this.
	_active_slot = slot_id
	# Bontago-mv0.17 item 4: this is sandbox's equivalent of HotSeat.
	# bind_local_slot() -- the one-time "a controller is now bound to a real
	# slot" moment -- so the very first frame looks from that slot's home
	# flag toward the disk centre instead of the generic yaw = 0 default.
	# DECISION (game/Sandbox.gd): deliberately not repeated from
	# sandbox_next_slot's _cycle_active_slot()/_set_active_slot() -- re-homing
	# the camera on every debug Tab cycle would be a surprising jump for a
	# tester mid-session; this only fires once, at match start.
	_controller.set_home_position(Match.default_ghost_origin(slot_id))
