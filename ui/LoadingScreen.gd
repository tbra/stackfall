class_name LoadingScreen
extends Control
signal readiness_timed_out
## Bontago-1pi.32: loading finished on this instance and the ready prompt is shown
## (ui_accept, a click on the prompt or gamepad A now sends the ready intent). The
## prompt, status line, safety-cap countdown and per-player ready list (L2) are
## driven by accepts_ready_input(), min_display_remaining_s(), the lifecycle's gate
## sets and Events.loading_ready_changed / loading_gate_opened.
signal ready_prompt_opened
## Bontago-1pi.8 (owner playtest 2026-09-27: "When a game round starts it
## centers around the center goal beacon for a little while before actually
## starting, let's add a proper loading screen instead.").
##
## Spec 3.7's state machine has a real LOADING state between LOBBY and
## COUNTDOWN, but autoload/match/MatchLifecycle.gd's start_match() fires
## LOBBY -> LOADING and LOADING -> COUNTDOWN synchronously, back to back, with
## no yield in between (that file's own doc: "this function runs
## synchronously start-to-finish, with no yield in between" -- load-bearing
## for net/MatchNet.gd's replication contract, so it is not touched here).
## What actually takes wall-clock time inside that instant is game/Main.gd's
## own _build_match_world() (field rebuild, flags, territory overlay upload,
## HotSeat/camera wiring) plus whatever first-touch shader/pipeline compile
## the freshly-rebuilt field and blocks trigger on the next rendered frame.
## Until now nothing covered that window, so whatever the camera already
## happened to be pointed at (game/CameraRig.gd's default _target is
## Vector3.ZERO -- the disk's centre, where the goal beacon sits -- until a
## PlayerController claims it) stayed on screen, frozen, for however long that
## took: the "idle centre beacon" the owner describes.
##
## Shown at the pending announcement, then given match details at LOADING.
## Main releases it after world build, the first applied territory result,
## material warmup and stable rendered frames.

@export var tuning: LoadingScreenTuning = preload("res://config/loading_screen_tuning.tres")
@export var menu_visual_tuning: MenuVisualTuning = preload("res://config/menu_visual_tuning.tres")
## Bontago-1pi.49 test seam: anything answering name_for_slot(slot_id) -> String
## (Net does). Null means the real Net autoload.
var name_provider: Variant = null

## Bontago-1pi.32 L3: the overlay's content sits on its own CanvasLayer so it covers
## the HUD (CanvasLayer 1) and its countdown digit. DECISION: layer, not hiding the
## HUD -- ui/HUD.gd and game/Main.gd stay untouched and the countdown simply is not
## visible until the fade starts, which only happens once the gate has opened. A
## CanvasLayer neither follows this Control's visibility nor its modulate, so the
## root's visibility is mirrored onto the layer and the fade tweens Content.
@onready var _layer: CanvasLayer = %Layer
@onready var _content: Control = %Content
@onready var _background: ColorRect = %Background
@onready var _card: PanelContainer = %Card
@onready var _map_label: Label = %MapLabel
@onready var _info_label: Label = %InfoLabel
@onready var _spinner_label: Label = %SpinnerLabel
@onready var _stage_label: Label = %StageLabel
@onready var _progress_bar: ProgressBar = %ProgressBar
## Bontago-1pi.32 L2 (ready prompt + player ready list; presentation only).
@onready var _player_list: VBoxContainer = %PlayerList
@onready var _ready_box: VBoxContainer = %ReadyBox
@onready var _status_label: Label = %StatusLabel
@onready var _ready_button: Button = %ReadyButton
@onready var _prompt_content: HBoxContainer = %PromptContent
@onready var _prompt_prefix: Label = %PromptPrefix
@onready var _glyph_slot: HBoxContainer = %GlyphSlot
@onready var _prompt_suffix: Label = %PromptSuffix
@onready var _cap_label: Label = %CapLabel

const _SPIN_FRAMES: Array[String] = ["Loading", "Loading.", "Loading..", "Loading..."]

## The Input Map action that readies (Enter/Numpad Enter/Space and gamepad A).
const READY_ACTION: StringName = &"ui_accept"
const INPUT_GLYPH_SCENE: PackedScene = preload("res://ui/InputGlyph.tscn")
## Unit-square check mark of a ready tick (relative to the mark's radius).
const _CHECK_POINTS: PackedVector2Array = [Vector2(-0.38, 0.02), Vector2(-0.1, 0.3), Vector2(0.4, -0.3)]

var _spin_index: int = 0
var _spin_elapsed_s: float = 0.0
var _is_fading: bool = false
var _fade_tween: Tween = null
## Bumped by show_for_match()/cancel() so a fade_out() coroutine still
## resuming from a held `await` after either of those runs (a fresh match
## started, or this one aborted mid-load) recognises it is stale and bails
## instead of hiding -- or later re-hiding -- a screen it no longer owns. See
## fade_out()'s own doc.
var _fade_token: int = 0
## Bontago-t8x.4: true between show_pending() and show_for_match()/cancel().
var _is_pending: bool = false
var _pending_elapsed_s: float = 0.0
var _loading_elapsed_s: float = 0.0
var _timed_out: bool = false
var _warm_viewport: SubViewport = null
## Bontago-1pi.32: the ready gate is armed for this match (see
## MatchLifecycle.arm_loading_ready_gate()), the ready input is live, and how
## long this overlay has been up for the minimum display time.
var _ready_gate_armed: bool = false
var _ready_input_enabled: bool = false
var _displayed_s: float = 0.0
## Bontago-1pi.32 L2: the local player pressed ready on this overlay (the host's
## echo can lag behind by a round trip). One press is ever sent.
var _local_pressed: bool = false
## ready_prompt_opened fired for this match (it fires when the prompt first shows).
var _prompt_announced: bool = false
## One entry per player-list row: {slot_id: int, is_bot: bool, mark: Control}.
var _ready_rows: Array[Dictionary] = []

const WARM_SHADERS: Array[String] = [
	"res://shaders/block_cell_grid.gdshader",
	"res://shaders/territory.gdshader",
	"res://shaders/disc_rim.gdshader",
	"res://shaders/weather/snow_flake.gdshader",
]


func _ready() -> void:
	visibility_changed.connect(_sync_layer_visibility)
	visible = false
	_set_opacity(1.0)
	_sync_layer_visibility()
	set_process(false)
	z_index = tuning.overlay_z_index
	_layer.layer = tuning.overlay_canvas_layer
	_background.color = tuning.background_color
	_card.add_theme_stylebox_override("panel", MenuStyleFactory.make_card(menu_visual_tuning.pill_cream_color, menu_visual_tuning))
	_apply_ready_styles()
	_prompt_content.minimum_size_changed.connect(_sync_prompt_size)
	_ready_button.pressed.connect(_on_ready_button_pressed)
	Events.loading_ready_changed.connect(_on_loading_ready_changed)
	Events.loading_gate_opened.connect(_on_loading_gate_opened)
	Events.input_device_changed.connect(_on_input_device_changed)
	_refresh_prompt_glyph()
	_refresh_ready_ui()


## Called by game/Main.gd right as the LOBBY -> LOADING transition fires,
## before the (still fully synchronous) world build below it runs. `slots`
## is whatever Main's own helper collected from Match this same frame --
## MatchLifecycle._build_slots() already ran before LOADING was emitted (see
## that file's start_match() doc), so every slot's display_name/is_bot is
## already final for this match.
func show_for_match(config: MatchConfig, slots: Array[PlayerSlot]) -> void:
	_is_pending = false
	_loading_elapsed_s = 0.0
	_timed_out = false
	_displayed_s = 0.0
	_ready_input_enabled = false
	_local_pressed = false
	_prompt_announced = false
	_fade_token += 1
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
	_is_fading = false
	# Bontago-1pi.32: only the LOADING-state call arms (show_pending() runs in the
	# lobby state and is a no-op here), and never headless.
	# DECISION: reaches Match._lifecycle directly (like net/MatchNet.gd's own
	# _authority()._lifecycle) because autoload/Match.gd is not in this package's
	# files; a Match.arm_loading_ready_gate()/loading_gate_blocking() forward is a
	# trivial follow-up.
	_ready_gate_armed = Match._lifecycle.arm_loading_ready_gate()
	_map_label.text = _map_display_name(config)
	_info_label.text = _player_list_text(slots)
	_rebuild_ready_rows(slots)
	_spin_index = 0
	_spin_elapsed_s = 0.0
	_spinner_label.text = _SPIN_FRAMES[0]
	set_stage("Building world", tuning.world_progress)
	_set_opacity(1.0)
	visible = true
	set_process(true)
	_refresh_prompt_glyph()
	_refresh_ready_ui()


## Bontago-t8x.4: the overlay before the match exists yet (host: Start was just
## pressed; client: net_match_loading arrived). `config` may be null (client).
## Hides itself after tuning.pending_timeout_s if no start follows.
func show_pending(config: MatchConfig) -> void:
	show_for_match(config, [] as Array[PlayerSlot])
	_is_pending = true
	_pending_elapsed_s = 0.0
	set_stage("Preparing match", tuning.preparing_progress)


func set_stage(stage: String, fraction: float) -> void:
	_stage_label.text = stage
	_progress_bar.value = clampf(fraction, 0.0, 1.0) * _progress_bar.max_value


func progress() -> float:
	return _progress_bar.value / _progress_bar.max_value


func timed_out() -> bool:
	return _timed_out


## DECISION: draw representative materials in a private viewport for one frame.
## The real field remains covered while its map-specific variants also render.
func warm_common_materials() -> void:
	if _warm_viewport != null:
		_warm_viewport.queue_free()
	_warm_viewport = SubViewport.new()
	_warm_viewport.size = tuning.warm_viewport_size
	# DECISION: warmup renders in a private World3D, never in the match world.
	_warm_viewport.own_world_3d = true
	_warm_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_warm_viewport)
	var root: Node3D = Node3D.new()
	_warm_viewport.add_child(root)
	var camera: Camera3D = Camera3D.new()
	camera.position = Vector3(0.0, 0.0, tuning.warm_camera_distance)
	camera.current = true
	root.add_child(camera)
	var index: int = 0
	for shader_path: String in WARM_SHADERS:
		var mesh: MeshInstance3D = MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		mesh.position = Vector3(float(index) - tuning.warm_mesh_offset, 0.0, 0.0)
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = load(shader_path) as Shader
		mesh.material_override = material
		root.add_child(mesh)
		index += 1
	var gift_mesh: MeshInstance3D = MeshInstance3D.new()
	gift_mesh.mesh = BoxMesh.new()
	gift_mesh.position = Vector3(0.0, tuning.warm_mesh_offset, 0.0)
	gift_mesh.material_override = StandardMaterial3D.new()
	root.add_child(gift_mesh)


func is_pending() -> bool:
	return _is_pending


## Bontago-1pi.32 (ready gate, L1 API for the L2 prompt). True from the moment
## loading finished on this instance until the overlay is fading, but only while the
## gate is actually blocking AND the host waits for the local peer (L3, review: a
## spectator, a mid-match joiner or a client of an ungated host has nothing to
## press, so no prompt and no ready input): ui_accept is then a ready press. The
## press goes through press_ready() / Net.
func accepts_ready_input() -> bool:
	return _ready_input_enabled and _gate_waits_for_local_peer()


## The gate is armed and not open yet, and the host's required set (a client: its
## mirror) holds the local peer.
func _gate_waits_for_local_peer() -> bool:
	if not _ready_gate_armed:
		return false
	return Match._lifecycle.loading_gate_blocking() and Match._lifecycle.loading_required_peers().has(Net.local_peer_id())


func ready_gate_armed() -> bool:
	return _ready_gate_armed


## Local clock of the minimum display time (0.0 when no gate is armed or it has
## elapsed). The host's authoritative clock is MatchLifecycle's.
func min_display_remaining_s() -> float:
	if not _ready_gate_armed:
		return 0.0
	return maxf(tuning.min_display_s - _displayed_s, 0.0)


## True once the host reports this instance's peer as ready.
func local_ready() -> bool:
	return Match._lifecycle.loading_ready_peers().has(Net.local_peer_id())


## Sends the ready intent (host-validated, idempotent). A no-op until loading has
## finished here, so nobody can ready before their own world is built. L2: only the
## first press is sent (a held A, Enter then a click, ... never re-sends the RPC);
## returns whether this call sent the intent.
func press_ready() -> bool:
	if not accepts_ready_input() or _local_pressed:
		return false
	_local_pressed = true
	Net.request_loading_ready()
	_refresh_ready_ui()
	return true


## True once this overlay sent the local player's ready intent.
func local_pressed() -> bool:
	return _local_pressed


## ui_accept (Enter/Space/gamepad A through the Input Map) is the ready button.
## _input, not _unhandled_input: a lobby control still focused behind the overlay
## must not eat the press.
func _input(event: InputEvent) -> void:
	if not visible or not accepts_ready_input():
		return
	if event.is_action_pressed(READY_ACTION):
		press_ready()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not _is_pending:
		_displayed_s += delta
	if _ready_gate_armed:
		_refresh_ready_ui()
	if _is_pending:
		_pending_elapsed_s += delta
		if _pending_elapsed_s >= tuning.pending_timeout_s:
			cancel()
			return
	elif not _is_fading:
		_loading_elapsed_s += delta
		if _loading_elapsed_s >= tuning.ready_timeout_s:
			_timed_out = true
			set_stage("Loading timed out", progress())
			cancel()
			readiness_timed_out.emit()
			return
	_spin_elapsed_s += delta
	if _spin_elapsed_s < tuning.spinner_interval_s:
		return
	_spin_elapsed_s = 0.0
	_spin_index = (_spin_index + 1) % _SPIN_FRAMES.size()
	_spinner_label.text = _SPIN_FRAMES[_spin_index]


## Called once game/Main.gd has passed every readiness stage.
##
## DECISION (ui/LoadingScreen.gd, Bontago-1pi.8): holds the overlay up for
## `tuning.warmup_frames` more rendered frames before starting the actual
## fade, rather than hiding on this same synchronous call. MatchLifecycle
## emits LOADING and COUNTDOWN back to back with no yield (see this class's
## own header doc), so hiding synchronously here would flip visible back to
## false before the engine ever presents a frame with it on -- shown and
## hidden within one logical frame is the same as never shown at all, exactly
## the bug this package exists to fix. A handful of held frames costs nothing
## against the 3 s countdown and gives the renderer a couple of real frames
## with the new field/blocks already built but still covered, so whatever
## first-touch shader/pipeline compile they trigger (the brief's own "shader/
## pipeline warm-up" case) happens behind the overlay instead of visibly
## stalling the first uncovered frame.
func fade_out() -> void:
	if _is_fading or not visible:
		return
	_is_fading = true
	var token: int = _fade_token
	await _wait_for_ready_gate(token)
	if token != _fade_token:
		return
	for _i: int in range(tuning.warmup_frames):
		await get_tree().process_frame
		if token != _fade_token:
			return
	_fade_tween = create_tween()
	_fade_tween.tween_property(_content, ^"modulate:a", 0.0, tuning.fade_out_duration_s)
	await _fade_tween.finished
	if token != _fade_token:
		return
	visible = false
	set_process(false)
	_is_fading = false
	if _warm_viewport != null:
		_warm_viewport.queue_free()
		_warm_viewport = null


## Bontago-1pi.32: loading is done here; hold the overlay (and accept ready
## presses) until the host's gate opens and the minimum display time has elapsed
## locally. The wait is capped by tuning.ready_wait_max_s so a lost message can
## never freeze a client; the host's own cap lives in MatchLifecycle. Returns
## immediately when no gate is armed (headless, sandbox).
func _wait_for_ready_gate(token: int) -> void:
	if not _ready_gate_armed:
		return
	_ready_input_enabled = true
	# _refresh_ready_ui() announces the prompt once accepts_ready_input() holds (at
	# once for a required human; a client when the host's mirror arrives).
	_refresh_ready_ui()
	var waited_s: float = 0.0
	while Match._lifecycle.loading_gate_blocking() or _displayed_s < tuning.min_display_s:
		if waited_s >= tuning.ready_wait_max_s:
			break
		await get_tree().process_frame
		if token != _fade_token:
			return
		waited_s += get_process_delta_time()
	_ready_input_enabled = false
	_refresh_ready_ui()


## Safety net for a match aborted mid-load (game/Main.gd's `to_state ==
## Match.State.LOBBY` branch): hides instantly, no fade, and invalidates
## whatever fade_out() coroutine might already be mid-flight so it cannot
## later hide -- or re-show -- a *different* match's overlay out from under
## it (see _fade_token's own doc).
func cancel() -> void:
	_is_pending = false
	_ready_input_enabled = false
	_ready_gate_armed = false
	_local_pressed = false
	_prompt_announced = false
	_fade_token += 1
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
	_is_fading = false
	visible = false
	_set_opacity(1.0)
	set_process(false)
	_refresh_ready_ui()
	if _warm_viewport != null:
		_warm_viewport.queue_free()
		_warm_viewport = null


func _map_display_name(config: MatchConfig) -> String:
	if config == null:
		return ""
	var variant_name: String = (MatchConfig.MapVariant.keys()[config.map_variant] as String).capitalize()
	var size_name: String = (MapDef.MapSize.keys()[config.map_size] as String).capitalize()
	return "%s - %s" % [variant_name, size_name]


func _player_list_text(slots: Array[PlayerSlot]) -> String:
	if slots.is_empty():
		return tuning.get_ready_text
	var lines: PackedStringArray = PackedStringArray()
	for slot_item: PlayerSlot in slots:
		lines.append(_slot_label_text(slot_item))
	return "\n".join(lines)


## Bontago-1pi.49: a human seat shows the name its player typed (the host's
## replicated roster, which both ends hold by the time LOADING starts); a bot
## keeps its slot label plus tuning.bot_suffix; an unnamed seat stays "Player N".
func _slot_label_text(slot_item: PlayerSlot) -> String:
	var shown: String = PlayerNames.label_for_slot(
		slot_item.slot_id, slot_item.display_name, slot_item.is_bot, String(_names().name_for_slot(slot_item.slot_id))
	)
	return "%s%s" % [shown, tuning.bot_suffix if slot_item.is_bot else ""]


## The roster's name lookup: the real Net unless a test installed a double.
func _names() -> Variant:
	return name_provider if name_provider != null else Net


# --- Bontago-1pi.32 L3: the overlay's own CanvasLayer ------------------------------

## The layer follows this node's visibility in the tree (a hidden parent, cancel(),
## a test or Main setting `visible` directly).
func _sync_layer_visibility() -> void:
	_layer.visible = is_visible_in_tree()


## The overlay's opacity. The root's own modulate does not reach a CanvasLayer's
## children, so the visible fade runs on Content; the root is kept in step.
func _set_opacity(alpha: float) -> void:
	modulate.a = alpha
	_content.modulate.a = alpha


## Test seam: the overlay's current opacity as drawn.
func overlay_opacity() -> float:
	return _content.modulate.a


## Test seam: the CanvasLayer index the overlay draws on (the HUD is 1).
func overlay_canvas_layer() -> int:
	return _layer.layer


## Test seam: whether the overlay's CanvasLayer is shown.
func overlay_layer_visible() -> bool:
	return _layer.visible


# --- Bontago-1pi.32 L2: ready prompt, status line, player ready list ------------

## Colours come from the menu palette (the card is the same cream pill card as the
## rest of the menus); sizes and wording from LoadingScreenTuning.
func _apply_ready_styles() -> void:
	var palette: MenuVisualTuning = menu_visual_tuning
	_player_list.add_theme_constant_override("separation", tuning.ready_list_separation_px)
	_ready_box.add_theme_constant_override("separation", tuning.ready_box_separation_px)
	_prompt_content.add_theme_constant_override("separation", tuning.ready_prompt_separation_px)
	_status_label.add_theme_font_size_override("font_size", tuning.ready_status_font_size)
	_status_label.add_theme_color_override("font_color", palette.ink_color)
	_cap_label.add_theme_font_size_override("font_size", tuning.ready_cap_font_size)
	_cap_label.add_theme_color_override("font_color", palette.label_muted_color)
	for prompt_label: Label in [_prompt_prefix, _prompt_suffix]:
		prompt_label.add_theme_font_size_override("font_size", tuning.ready_prompt_font_size)
		prompt_label.add_theme_color_override("font_color", palette.ink_color)
	_prompt_prefix.text = tuning.ready_prompt_prefix
	_prompt_suffix.text = tuning.ready_prompt_suffix
	MenuStyleFactory.apply_pill(_ready_button, palette.pill_mint_color, palette.pill_mint_hover_color, palette.ink_color, palette)
	_ready_button.add_theme_stylebox_override("disabled", _ready_button.get_theme_stylebox("normal"))
	_ready_button.add_theme_color_override("font_disabled_color", palette.ink_color)
	_prompt_content.offset_left = palette.pill_margin_x_px
	_prompt_content.offset_right = -palette.pill_margin_x_px
	_prompt_content.offset_top = palette.pill_margin_y_px
	_prompt_content.offset_bottom = -palette.pill_margin_y_px
	_sync_prompt_size()


## The Button hosts its content as a child (a glyph is not text), so it sizes
## itself to that content plus the pill margins, as ui/KeyRebindRow.gd does.
func _sync_prompt_size() -> void:
	var margins: Vector2 = Vector2(menu_visual_tuning.pill_margin_x_px, menu_visual_tuning.pill_margin_y_px) * 2.0
	_ready_button.custom_minimum_size = _prompt_content.get_combined_minimum_size() + margins


func _on_ready_button_pressed() -> void:
	press_ready()


func _on_loading_ready_changed(_ready_ids: PackedInt32Array, _required_ids: PackedInt32Array) -> void:
	_refresh_ready_ui()


func _on_loading_gate_opened() -> void:
	_refresh_ready_ui()


func _on_input_device_changed(_device: StringName) -> void:
	_refresh_prompt_glyph()


## Shows only the ui_accept bindings of the player's active device (keyboard/mouse
## by default, gamepad once a pad was used), like the Controls page does.
func _refresh_prompt_glyph() -> void:
	for child: Node in _glyph_slot.get_children():
		_glyph_slot.remove_child(child)
		child.free()
	if not InputMap.has_action(READY_ACTION):
		return
	var want_gamepad: bool = Settings.active_input_device() == Settings.DEVICE_GAMEPAD
	var shown: int = 0
	for event: InputEvent in InputMap.action_get_events(READY_ACTION):
		var is_gamepad: bool = event is InputEventJoypadButton or event is InputEventJoypadMotion
		if is_gamepad != want_gamepad:
			continue
		var glyph: InputGlyph = INPUT_GLYPH_SCENE.instantiate() as InputGlyph
		_glyph_slot.add_child(glyph)
		glyph.set_event(event)
		shown += 1
		if shown >= tuning.ready_prompt_glyph_count:
			break


## Test seam: the labels of the glyphs currently in the prompt ("Enter", "A").
func prompt_glyph_texts() -> PackedStringArray:
	var texts: PackedStringArray = PackedStringArray()
	for child: Node in _glyph_slot.get_children():
		if child is InputGlyph:
			texts.append((child as InputGlyph).label_text())
	return texts


## One row per slot: colour swatch, name, and a tick (ready) or ring (pending).
func _rebuild_ready_rows(slots: Array[PlayerSlot]) -> void:
	for child: Node in _player_list.get_children():
		_player_list.remove_child(child)
		child.free()
	_ready_rows.clear()
	for slot_item: PlayerSlot in slots:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", tuning.ready_row_separation_px)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var swatch: Panel = Panel.new()
		swatch.custom_minimum_size = Vector2.ONE * tuning.ready_swatch_size_px
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var swatch_box: StyleBoxFlat = StyleBoxFlat.new()
		swatch_box.bg_color = slot_item.color
		swatch_box.set_corner_radius_all(ceili(tuning.ready_swatch_size_px * 0.5))
		swatch.add_theme_stylebox_override("panel", swatch_box)
		var name_label: Label = Label.new()
		name_label.text = _slot_label_text(slot_item)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", tuning.ready_row_font_size)
		name_label.add_theme_color_override("font_color", menu_visual_tuning.ink_color)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mark: Control = Control.new()
		mark.custom_minimum_size = Vector2.ONE * tuning.ready_mark_size_px
		mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.set_meta(&"ready", false)
		mark.draw.connect(_draw_ready_mark.bind(mark))
		row.add_child(swatch)
		row.add_child(name_label)
		row.add_child(mark)
		_player_list.add_child(row)
		_ready_rows.append({"slot_id": slot_item.slot_id, "is_bot": slot_item.is_bot, "mark": mark})


func _draw_ready_mark(mark: Control) -> void:
	var center: Vector2 = mark.size * 0.5
	var radius: float = minf(mark.size.x, mark.size.y) * 0.5 - tuning.ready_mark_stroke_px * 0.5
	if bool(mark.get_meta(&"ready", false)):
		mark.draw_circle(center, radius, menu_visual_tuning.pill_mint_color)
		var check: PackedVector2Array = PackedVector2Array()
		for point: Vector2 in _CHECK_POINTS:
			check.append(center + point * radius)
		mark.draw_polyline(check, menu_visual_tuning.ink_color, tuning.ready_mark_stroke_px, true)
	else:
		mark.draw_arc(center, radius, 0.0, TAU, tuning.ready_mark_arc_points, menu_visual_tuning.label_muted_color, tuning.ready_mark_stroke_px, true)


## Test seam: whether slot_id's row currently shows the ready tick.
func player_row_ready(slot_id: int) -> bool:
	for row: Dictionary in _ready_rows:
		if int(row["slot_id"]) == slot_id:
			return bool((row["mark"] as Control).get_meta(&"ready", false))
	return false


## Re-derives everything the ready gate shows from the host's state (the lifecycle
## mirrors it on clients) and the local press. Cheap; runs every frame while armed
## and on every ready/gate/device signal. Nothing here decides anything: the host
## still owns the gate.
func _refresh_ready_ui() -> void:
	var show_list: bool = _ready_gate_armed and not _ready_rows.is_empty()
	_player_list.visible = show_list
	_info_label.visible = not show_list
	_ready_box.visible = _ready_gate_armed
	_ready_box.custom_minimum_size.y = tuning.ready_box_min_height_px if _ready_gate_armed else 0.0
	if not _ready_gate_armed:
		_ready_button.visible = false
		return
	var required: PackedInt32Array = Match._lifecycle.loading_required_peers()
	var ready_ids: PackedInt32Array = Match._lifecycle.loading_ready_peers()
	for row: Dictionary in _ready_rows:
		var slot_ready: bool = bool(row["is_bot"]) or Match._lifecycle.loading_slot_ready(int(row["slot_id"]))
		var mark: Control = row["mark"] as Control
		if bool(mark.get_meta(&"ready", false)) != slot_ready:
			mark.set_meta(&"ready", slot_ready)
			mark.queue_redraw()
	var blocking: bool = Match._lifecycle.loading_gate_blocking()
	var local_peer: int = Net.local_peer_id()
	var is_required: bool = required.has(local_peer)
	var pressed: bool = _local_pressed or ready_ids.has(local_peer)
	var waiting: int = maxi(required.size() - ready_ids.size(), 0)
	# The prompt: this instance finished loading, the gate is still closed, and the
	# host waits for this peer (spectators, late joiners, clients of an ungated host
	# and an all-bot match have nothing to press).
	var prompt_open: bool = accepts_ready_input()
	if prompt_open and not _prompt_announced:
		_prompt_announced = true
		ready_prompt_opened.emit()
	_ready_button.visible = prompt_open
	_ready_button.disabled = pressed
	_ready_button.modulate.a = tuning.ready_prompt_disabled_alpha if pressed else 1.0
	if (pressed or not is_required) and waiting > 0 and _ready_input_enabled and blocking:
		_status_label.text = (tuning.waiting_one_text if waiting == 1 else tuning.waiting_many_text) % waiting
	elif blocking and (min_display_remaining_s() > 0.0 or not _ready_input_enabled):
		_status_label.text = tuning.get_ready_text
	else:
		_status_label.text = ""
	# The safety cap: the host starts without a laggard once ready_wait_max_s passed.
	var cap_left_s: float = maxf(tuning.ready_wait_max_s - _displayed_s, 0.0)
	if _ready_input_enabled and blocking and waiting > 0 and cap_left_s > 0.0:
		_cap_label.text = tuning.cap_countdown_format % ceili(cap_left_s)
	else:
		_cap_label.text = ""
