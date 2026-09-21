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

var _field: Field = null
var _active_slot: int = 0


func _ready() -> void:
	Events.turn_changed.connect(_on_turn_changed)
	_panel.configure(self, _ghost)
	# Bontago-mv0.14 (spec 1.5): see HotSeat.gd's matching _ready() comment --
	# safe headless (a silent no-op with no window to capture).
	_controller.enable_mouse_capture()


## Called once by game/Main.gd, the same way HotSeat.set_camera_rig() is —
## CameraRig lives outside this subtree.
func set_camera_rig(rig: CameraRig) -> void:
	_controller.set_camera_rig(rig)


## Called once by game/Main.gd. Only sandbox_reset_field/sandbox_spawn_tower
## need it (Field.place_flags()/set_overlay_source() after a reset; the
## ghost already gets its own placement ray from PlayerController without
## this).
func set_field(field: Field) -> void:
	_field = field


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


func _on_turn_changed(slot_id: int) -> void:
	# Match._begin_playing() emits this once when every match starts (hot-seat
	# or not) to seed whoever acts first; sandbox has no real "turn" after
	# that (config.hot_seat is false), so this only sets the initial active
	# slot. sandbox_next_slot/_reset_field() own every change after this.
	_active_slot = slot_id
