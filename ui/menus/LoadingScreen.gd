class_name LoadingScreen
extends Control
## Emitted when the readiness wait times out; Main returns to the lobby.
signal readiness_timed_out
## Emitted when loading finished on this instance and the ready prompt is shown.
signal ready_prompt_opened
## Overlay shown from the pending announcement until the match is visible. It covers the
## window in which start_match() fires LOBBY -> LOADING -> COUNTDOWN synchronously (no yield, which
## net/MatchNet.gd's replication contract relies on): the wall-clock time goes to Main's
## _build_match_world() plus first-touch shader/pipeline compile, and without the overlay the
## camera stays frozen on the idle centre beacon (CameraRig's default target) for that time.
##
## Once loading finished on this instance the ready prompt shows (ui_accept: Enter or gamepad A
## sends the ready intent); the "Ready?" + glyph prompt and per-player ready list are driven by
## accepts_ready_input() and Events.loading_ready_changed / loading_gate_opened.
##
## Shown at the pending announcement, then given match details at LOADING.
## Main releases it after world build, the first applied territory result,
## material warmup and stable rendered frames.

@export var tuning: LoadingScreenTuning = preload("res://config/ui/loading_screen_tuning.tres")
@export var menu_visual_tuning: MenuVisualTuning = preload("res://config/ui/menu_visual_tuning.tres")
@export var tip_table: LoadingTipTable = preload("res://config/ui/loading_tip_table.tres")
## test seam: anything answering name_for_slot(slot_id) -> String
## (Net does). Null means the real Net autoload.
var name_provider: Variant = null

## The overlay's content sits on its own CanvasLayer so it covers the HUD (CanvasLayer 1) and its
## countdown digit. DECISION: layer, not hiding the HUD -- the countdown simply is not
## visible until the fade starts, which only happens once the gate has opened. A
## CanvasLayer neither follows this Control's visibility nor its modulate, so the
## root's visibility is mirrored onto the layer and the fade tweens Content.
@onready var _layer: CanvasLayer = %Layer
@onready var _content: Control = %Content
@onready var _background: ColorRect = %Background
## the prerendered arena plate (cover-cropped), the flat darkening and
## the vignette drawn over it. Dim and Vignette are children of the Backdrop, so they
## fade in and out with the plate.
@onready var _backdrop: TextureRect = %Backdrop
@onready var _dim: ColorRect = %Dim
@onready var _vignette: TextureRect = %Vignette
@onready var _card: PanelContainer = %Card
@onready var _map_label: Label = %MapLabel
@onready var _tip_label: Label = %TipLabel
## the map pictogram above the name (UiArtTable); hidden without a config.
@onready var _map_icon: TextureRect = %MapIcon
## Ready prompt and player ready list (presentation only).
@onready var _player_list: VBoxContainer = %PlayerList
@onready var _ready_box: VBoxContainer = %ReadyBox
@onready var _prompt_content: VBoxContainer = %PromptContent
@onready var _prompt_text: Label = %PromptText
@onready var _glyph_slot: HBoxContainer = %GlyphSlot

## The Input Map action that readies (Enter/Numpad Enter/Space and gamepad A).
const READY_ACTION: StringName = &"ui_accept"
## Accessible tooltips of a player row's ready mark (the mark itself shows only its icon).
const READY_TEXT: String = "Ready"
const NOT_READY_TEXT: String = "Not ready"
## the loading backdrop is one of the main menu's images (MainMenuTuning.backdrop_paths).
const MENU_TUNING_PATH: String = "res://config/ui/main_menu_tuning.tres"
## Frames a fetched plate stays referenced so queued RenderingServer commands drain.
const TEXTURE_RELEASE_FRAMES: int = 3
## DisplayServer.get_name() of a --headless run, which renders with the dummy rasterizer.
const HEADLESS_DISPLAY: String = "headless"

## Stage fraction, kept only for progress() (game/main/Main.gd still reports it).
var _progress: float = 0.0
var _is_fading: bool = false
var _fade_tween: Tween = null
## Bumped by show_for_match()/cancel() so a fade_out() coroutine still
## resuming from a held `await` after either of those runs (a fresh match
## started, or this one aborted mid-load) recognises it is stale and bails
## instead of hiding -- or later re-hiding -- a screen it no longer owns. See
## fade_out()'s own doc.
var _fade_token: int = 0
## true between show_pending() and show_for_match()/cancel().
var _is_pending: bool = false
var _pending_elapsed_s: float = 0.0
var _loading_elapsed_s: float = 0.0
var _timed_out: bool = false
var _warm_viewport: SubViewport = null
## the ready gate is armed for this match (see
## MatchLifecycle.arm_loading_ready_gate()), the ready input is live, and how
## long this overlay has been up for the minimum display time.
var _ready_gate_armed: bool = false
var _ready_input_enabled: bool = false
## The local player pressed ready on this overlay (the host's echo can lag a round trip). One press is ever sent.
var _local_pressed: bool = false
## ready_prompt_opened fired for this match (it fires when the prompt first shows).
var _prompt_announced: bool = false
## Index of the tip last shown, so the next load never repeats it.
var _last_tip_index: int = -1
## One entry per player-list row: {slot_id: int, is_bot: bool, mark: Control}.
var _ready_rows: Array[Dictionary] = []
## backdrop state. _backdrop_path is the plate chosen for the current
## match ("" = none: no config yet, or no plate on disk); _backdrop_shown_path is the
## plate whose texture the rect holds. _backdrop_requested: a threaded load of
## _backdrop_path is in flight. _backdrop_orphans: superseded requests, still to be
## collected so the loader does not keep them.
var _backdrop_path: String = ""
## The image picked for this loading screen; forgotten when the overlay hides so the next one re-rolls.
var _backdrop_session_path: String = ""
var _backdrop_shown_path: String = ""
var _backdrop_requested: bool = false
var _backdrop_orphans: PackedStringArray = PackedStringArray()
var _backdrop_tween: Tween = null

const WARM_SHADERS: Array[String] = [
	"res://shaders/blocks/block_cell_grid.gdshader",
	"res://shaders/territory/territory.gdshader",
	"res://shaders/territory/disc_rim.gdshader",
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
	_apply_backdrop_styles()
	_apply_card_style()
	_apply_ready_styles()
	Events.loading_ready_changed.connect(_on_loading_ready_changed)
	Events.loading_gate_opened.connect(_on_loading_gate_opened)
	Events.match_scope_reset.connect(_on_match_scope_reset)
	Events.input_device_changed.connect(_on_input_device_changed)
	_refresh_prompt_glyph()
	_refresh_ready_ui()


## Called by game/main/Main.gd right as the LOBBY -> LOADING transition fires, before the
## synchronous world build runs. `slots` is what Main collected from Match this frame, so every
## slot's display_name/is_bot is already final.
func show_for_match(config: MatchConfig, slots: Array[PlayerSlot]) -> void:
	var keep_tip: bool = _is_pending and visible
	_is_pending = false
	_loading_elapsed_s = 0.0
	_timed_out = false
	_ready_input_enabled = false
	_local_pressed = false
	_prompt_announced = false
	_fade_token += 1
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
	_is_fading = false
	# only the LOADING-state call arms (show_pending() runs in the
	# lobby state and is a no-op here), and never headless.
	# DECISION: reaches Match._lifecycle directly (like net/MatchNet.gd's _authority()._lifecycle) rather than through a Match forward.
	_ready_gate_armed = Match._lifecycle.arm_loading_ready_gate()
	_map_label.text = _map_display_name(config)
	if not keep_tip:
		_show_next_tip()
	_refresh_map_icon(config)
	_select_backdrop(config)
	_rebuild_ready_rows(slots)
	set_stage("Building world", tuning.world_progress)
	_set_opacity(1.0)
	visible = true
	set_process(true)
	_refresh_prompt_glyph()
	_refresh_ready_ui()


## the overlay before the match exists yet (host: Start was just
## pressed; client: net_match_loading arrived). `config` may be null (client).
## Hides itself after tuning.pending_timeout_s if no start follows.
func show_pending(config: MatchConfig) -> void:
	show_for_match(config, [] as Array[PlayerSlot])
	_is_pending = true
	_pending_elapsed_s = 0.0
	set_stage("Preparing match", tuning.preparing_progress)


func set_stage(_stage: String, fraction: float) -> void:
	_progress = clampf(fraction, 0.0, 1.0)
	# the rows show a Ready / Not ready pill, not stage progress.


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


## True from the moment loading finished on this instance until the overlay is fading, but only
## while the gate is actually blocking AND the host waits for the local peer (a
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


## Sends the ready intent (host-validated, idempotent). A no-op until loading has
## finished here, so nobody can ready before their own world is built. Only the
## first press is sent (a held A, Enter then a click, ... never re-sends the RPC);
## returns whether this call sent the intent.
func press_ready() -> bool:
	if not accepts_ready_input() or _local_pressed:
		return false
	_local_pressed = true
	Net.request_loading_ready()
	_refresh_ready_ui()
	return true


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
	_poll_backdrop(true)
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
			cancel()
			readiness_timed_out.emit()
			return


## Called once game/main/Main.gd has passed every readiness stage.
##
## DECISION: hold the overlay up for `tuning.warmup_frames` more rendered frames before fading, not hide synchronously: MatchLifecycle emits LOADING and COUNTDOWN back to back with no yield, so an immediate hide would never present a frame with the overlay on. The held frames cost nothing against the countdown and let first-touch shader/pipeline compile happen behind the overlay.
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
	_finish_backdrop_fade()
	_drain_backdrop_orphans()
	# the plate is only needed while the screen is up; drop it so the 1920x1080 art leaves memory
	# (the next show_for_match() re-requests it because the shown path is cleared).
	_clear_backdrop()
	_backdrop_session_path = ""
	if _warm_viewport != null:
		_warm_viewport.queue_free()
		_warm_viewport = null


## loading is done here; hold the overlay (and accept ready
## presses) until the host's gate opens and the minimum display time has elapsed
## locally. There is no time cap: a client is released by the host's
## open message, the match moving past the countdown, or a disconnect. Returns
## immediately when no gate is armed (headless, sandbox).
func _wait_for_ready_gate(token: int) -> void:
	if not _ready_gate_armed:
		return
	_ready_input_enabled = true
	# _refresh_ready_ui() announces the prompt once accepts_ready_input() holds (at
	# once for a required human; a client when the host's mirror arrives).
	_refresh_ready_ui()
	# DECISION: no wait cap -- the overlay stays until the host's gate opens
	# (everyone ready), the match leaves the pre-play window, or cancel() bumps the token.
	while Match._lifecycle.loading_gate_blocking():
		await get_tree().process_frame
		if token != _fade_token:
			return
	_ready_input_enabled = false
	_refresh_ready_ui()


## Safety net for a match aborted mid-load (game/main/Main.gd's `to_state ==
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
	clear_player_rows()
	_refresh_ready_ui()
	_abandon_backdrop_request()
	_finish_backdrop_fade()
	_drain_backdrop_orphans()
	_backdrop_session_path = ""
	if _warm_viewport != null:
		_warm_viewport.queue_free()
		_warm_viewport = null


## Clears the player rows when the overlay is hidden (Events.match_scope_reset): show_for_match()
## rebuilds them and nothing else took them down, so finished matches left rows in the hidden
## PlayerList. Main also emits the reset while the overlay is UP for the new match (LOADING shows
## it, then the world build resets), and those rows must survive, so only a hidden overlay is
## cleared (a cancelled load clears in cancel()).
func _on_match_scope_reset() -> void:
	if not visible:
		clear_player_rows()


## Drops every player-list row and its ready-mark bookkeeping.
func clear_player_rows() -> void:
	for child: Node in _player_list.get_children():
		_player_list.remove_child(child)
		child.free()
	_ready_rows.clear()


func _refresh_map_icon(config: MatchConfig) -> void:
	var art: UiArtTable = UiArtTable.shared()
	_map_icon.texture = art.map_pictogram() if config != null else null
	_map_icon.visible = _map_icon.texture != null
	_map_icon.custom_minimum_size = Vector2.ONE * float(art.loading_map_icon_px)


## The card title is the resolved game mode's display name only; the map pictogram stays beside it.
func _map_display_name(config: MatchConfig) -> String:
	if config == null:
		return ""
	return DisplayNames.mode(MatchConfig.resolve_game_mode(config.game_mode))


## a human seat shows the name its player typed (the host's
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


# --- prerendered arena backdrop -----------------------------------

## Colours and the vignette gradient come from LoadingScreenTuning.
func _apply_backdrop_styles() -> void:
	_dim.color = tuning.backdrop_dim_color
	var gradient: Gradient = Gradient.new()
	var clear: Color = Color(tuning.backdrop_vignette_color, 0.0)
	gradient.offsets = PackedFloat32Array([0.0, tuning.backdrop_vignette_start, 1.0])
	gradient.colors = PackedColorArray([clear, clear, tuning.backdrop_vignette_color])
	var vignette: GradientTexture2D = GradientTexture2D.new()
	vignette.gradient = gradient
	vignette.fill = GradientTexture2D.FILL_RADIAL
	vignette.fill_from = Vector2(0.5, 0.5)
	vignette.fill_to = Vector2(1.0, 0.5)
	vignette.width = tuning.backdrop_vignette_size_px
	vignette.height = tuning.backdrop_vignette_size_px
	_vignette.texture = vignette


## The backdrop for this match: one of the main menu's images (MainMenuTuning.backdrop_paths,
## the single list), chosen at random once per loading screen. "" when there is no config yet
## (a client's pending overlay: show_for_match() runs again with it) or no image is listed.
## DECISION: the pick may differ from the main menu's.
func backdrop_path_for(config: MatchConfig) -> String:
	if config == null:
		return ""
	if _backdrop_session_path.is_empty():
		var menu_tuning: MainMenuTuning = load(MENU_TUNING_PATH) as MainMenuTuning
		_backdrop_session_path = MenuBackdrop.pick_path(menu_tuning.backdrop_paths, randf())
	return _backdrop_session_path if ResourceLoader.exists(_backdrop_session_path) else ""


## Chooses the plate and starts loading it on a worker thread, so showing the overlay
## never stalls on a 1920x1080 decode. The same plate as the previous show (or as the
## pending overlay's) is kept as it is; a different one drops the stale texture at once
## so it never flashes, and appears (fading in) when loaded.
func _select_backdrop(config: MatchConfig) -> void:
	var path: String = backdrop_path_for(config)
	if path == _backdrop_path and (path.is_empty() or _backdrop_requested or _backdrop_shown_path == path):
		return
	_abandon_backdrop_request()
	_backdrop_path = path
	if path != _backdrop_shown_path:
		_clear_backdrop()
	if path.is_empty() or path == _backdrop_shown_path:
		return
	var orphan_index: int = _backdrop_orphans.find(path)
	if orphan_index >= 0:
		_backdrop_orphans.remove_at(orphan_index)
	if not threaded_texture_loads_safe():
		_show_backdrop(load(path) as Texture2D, false)
		return
	if ResourceLoader.load_threaded_request(path, "Texture2D") != OK:
		push_warning("LoadingScreen: could not request the backdrop %s." % path)
		return
	_backdrop_requested = true
	# A plate still cached from an earlier match lands now, with no fade.
	_poll_backdrop(false)


## Collects the in-flight plate once the worker thread has it (called every frame while
## the overlay runs). `animate` fades it in; a plate that was already loaded appears at
## once.
func _poll_backdrop(animate: bool) -> void:
	_drain_backdrop_orphans()
	if not _backdrop_requested:
		return
	var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(_backdrop_path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	_backdrop_requested = false
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		push_warning("LoadingScreen: the backdrop %s failed to load." % _backdrop_path)
		return
	_show_backdrop(ResourceLoader.load_threaded_get(_backdrop_path) as Texture2D, animate)


## Headless loads on the main thread: Godot's dummy rasterizer keeps texture RIDs in a RID_PtrOwner
## without a lock ('Parameter "t" is null', texture_storage.h:85; RD/GLES3 use a thread-safe owning
## handle), and RenderingServer allocates a
## texture's RID on the calling thread. A plate decoded on a loader thread allocated its RID
## while the main thread created or freed textures; both threads took the same slot and one
## texture lost it. A sequential load has no second thread, so headless (the dummy
## rasterizer) loads the plate on the main thread; a real renderer keeps the worker.
## DECISION: headless only (tests, dedicated hosts): nobody sees the plate there, and the
## lossless decode is a one-off main-thread cost.
static func threaded_texture_loads_safe() -> bool:
	return DisplayServer.get_name() != HEADLESS_DISPLAY


## Shows a fetched plate (null: nothing to show); `animate` fades it in.
func _show_backdrop(texture: Texture2D, animate: bool) -> void:
	if texture == null:
		return
	_backdrop.texture = texture
	_backdrop.visible = true
	_backdrop_shown_path = _backdrop_path
	_kill_backdrop_tween()
	if animate and tuning.backdrop_fade_in_s > 0.0:
		_backdrop.modulate.a = 0.0
		_backdrop_tween = create_tween()
		_backdrop_tween.tween_property(_backdrop, ^"modulate:a", 1.0, tuning.backdrop_fade_in_s)
	else:
		_backdrop.modulate.a = 1.0


## Drops the shown plate (and any fade), leaving only the plain background.
func _clear_backdrop() -> void:
	_kill_backdrop_tween()
	release_later(_backdrop.texture)
	_backdrop.texture = null
	_backdrop.visible = false
	_backdrop.modulate.a = 0.0
	_backdrop_shown_path = ""


## A hidden overlay keeps its plate fully visible, so the next show of the same plate
## (a rematch) is not left mid fade-in.
func _finish_backdrop_fade() -> void:
	if _backdrop_shown_path.is_empty():
		return
	_kill_backdrop_tween()
	_backdrop.modulate.a = 1.0


func _kill_backdrop_tween() -> void:
	if _backdrop_tween != null and _backdrop_tween.is_valid():
		_backdrop_tween.kill()
	_backdrop_tween = null


## A load in flight for a plate this match no longer wants is collected later (a
## threaded request holds its result until it is fetched).
func _abandon_backdrop_request() -> void:
	if _backdrop_requested and not _backdrop_orphans.has(_backdrop_path):
		_backdrop_orphans.append(_backdrop_path)
	_backdrop_requested = false


## Fetches (and drops) every abandoned plate whose worker has finished.
func _drain_backdrop_orphans() -> void:
	var still_loading: PackedStringArray = PackedStringArray()
	for path: String in _backdrop_orphans:
		if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			still_loading.append(path)
		else:
			release_later(ResourceLoader.load_threaded_get(path))
	_backdrop_orphans = still_loading


func _exit_tree() -> void:
	_abandon_backdrop_request()
	for path: String in _backdrop_orphans:
		release_later(ResourceLoader.load_threaded_get(path))
	_backdrop_orphans = PackedStringArray()


## Holds the last reference to a just-fetched plate for a few frames so the RenderingServer
## commands its loader thread queued drain before the texture is freed. A cheap guard (a
## main-thread free flushes that queue first). A static coroutine: it outlives the node that
## called it.
static func release_later(resource: Resource) -> void:
	if resource == null:
		return
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	for _frame: int in TEXTURE_RELEASE_FRAMES:
		await tree.process_frame


# --- the overlay's own CanvasLayer ------------------------------

## The layer follows this node's visibility in the tree (a hidden parent, cancel(),
## a test or Main setting `visible` directly).
func _sync_layer_visibility() -> void:
	_layer.visible = is_visible_in_tree()


## The overlay's opacity. The root's own modulate does not reach a CanvasLayer's
## children, so the visible fade runs on Content; the root is kept in step.
func _set_opacity(alpha: float) -> void:
	modulate.a = alpha
	_content.modulate.a = alpha


# --- ready prompt, status line, player ready list ------------

## Colours come from the menu palette (the card is the same cream pill card as the
## rest of the menus); sizes and wording from LoadingScreenTuning.
func _apply_ready_styles() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	_player_list.add_theme_constant_override("separation", tuning.ready_list_separation_px)
	_ready_box.add_theme_constant_override("separation", tuning.ready_box_separation_px)
	_prompt_content.add_theme_constant_override("separation", tuning.ready_prompt_separation_px)
	_prompt_text.text = tuning.ready_prompt_text
	_prompt_text.add_theme_font_size_override("font_size", tuning.ready_prompt_font_size)
	_prompt_text.add_theme_color_override("font_color", arcade.cream_color)


## Stackfall Arcade LoadingCard:
## mode name in Bungee, one diamond + progress-cell row per player. No spinners.
func _apply_card_style() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	_card.add_theme_stylebox_override("panel", MenuStyleFactory.make_plate())
	_card.custom_minimum_size.x = float(tuning.loading_card_min_width_px)
	_map_label.theme_type_variation = &"DisplayLabel"
	_map_label.add_theme_font_size_override("font_size", tuning.loading_title_font_size_px)
	_map_label.add_theme_color_override("font_color", arcade.cream_color)


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
	InputGlyph.build_for_action(_glyph_slot, READY_ACTION, tuning.ready_prompt_glyph_count)


## One row per slot: colour swatch, name and the Ready / Not ready pill.
func _rebuild_ready_rows(slots: Array[PlayerSlot]) -> void:
	for child: Node in _player_list.get_children():
		_player_list.remove_child(child)
		child.free()
	_ready_rows.clear()
	for slot_item: PlayerSlot in slots:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", tuning.ready_row_separation_px)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var marker: SlotDiamond = SlotDiamond.create(slot_item.color, tuning.loading_marker_size_px)
		marker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var name_label: Label = Label.new()
		name_label.text = _slot_label_text(slot_item)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", tuning.loading_name_font_size_px)
		name_label.add_theme_color_override("font_color", MenuStyleFactory.arcade_tuning().cream_color)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# the lobby's Ready / Not ready pill, not a progress bar.
		var mark: UiStatusBadge = _make_ready_mark(slot_item.is_bot)
		mark.visible = _ready_gate_armed
		row.add_child(marker)
		row.add_child(name_label)
		row.add_child(mark)
		_player_list.add_child(row)
		_ready_rows.append({"slot_id": slot_item.slot_id, "is_bot": slot_item.is_bot, "mark": mark, "name": name_label})


## The Ready / Not ready tile of a player row: an icon-only UiStatusBadge (tick / hourglass faces),
## the words kept as the accessible tooltip. Compact vertical margin and size from LoadingScreenTuning.
func _make_ready_mark(slot_ready: bool) -> UiStatusBadge:
	var mark: UiStatusBadge = UiStatusBadge.new()
	mark.icon_only = true
	mark.pad_y_override_px = float(tuning.loading_pill_margin_y_px)
	mark.custom_minimum_size = _pill_size()
	_set_ready_mark(mark, slot_ready)
	return mark


## Restyles a ready mark for the new state (cheap).
static func _set_ready_mark(mark: UiStatusBadge, slot_ready: bool) -> void:
	mark.variant = UiStatusBadge.Look.READY if slot_ready else UiStatusBadge.Look.NOT_READY
	mark.text = READY_TEXT if slot_ready else NOT_READY_TEXT


## The pill's size (LoadingScreenTuning): the lobby's pill, a little smaller so eight rows fit.
func _pill_size() -> Vector2:
	return Vector2(float(tuning.loading_pill_width_px), float(tuning.loading_pill_height_px))


## Re-derives everything the ready gate shows from the host's state (the lifecycle
## mirrors it on clients) and the local press. Cheap; runs every frame while armed
## and on every ready/gate/device signal. Nothing here decides anything: the host
## still owns the gate.
func _refresh_ready_ui() -> void:
	_player_list.visible = not _ready_rows.is_empty()
	if not _ready_gate_armed:
		_ready_box.visible = false
		return
	var ready_ids: PackedInt32Array = Match._lifecycle.loading_ready_peers()
	for row: Dictionary in _ready_rows:
		var slot_ready: bool = bool(row["is_bot"]) or Match._lifecycle.loading_slot_ready(int(row["slot_id"]))
		var mark: UiStatusBadge = row["mark"] as UiStatusBadge
		mark.visible = true
		if (mark.variant == UiStatusBadge.Look.READY) != slot_ready:
			_set_ready_mark(mark, slot_ready)
	var pressed: bool = _local_pressed or ready_ids.has(Net.local_peer_id())
	# The prompt: this instance finished loading, the gate is still closed, and the
	# host waits for this peer (spectators, late joiners, clients of an ungated host
	# and an all-bot match have nothing to press).
	var prompt_open: bool = accepts_ready_input()
	if prompt_open and not _prompt_announced:
		_prompt_announced = true
		ready_prompt_opened.emit()
	_ready_box.visible = prompt_open
	_ready_box.modulate.a = tuning.ready_prompt_disabled_alpha if pressed else 1.0


## One tip per load: the pending overlay's tip carries over into the real load (see show_for_match).
func _show_next_tip() -> void:
	_tip_label.theme_type_variation = &"CaptionLabel"
	_tip_label.custom_minimum_size.x = float(tip_table.tip_width_px)
	var index: int = tip_table.pick_index(_last_tip_index, randi())
	if index < 0:
		_tip_label.visible = false
		return
	_last_tip_index = index
	_tip_label.text = tip_table.tips[index]
	_tip_label.visible = true
