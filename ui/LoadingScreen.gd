class_name LoadingScreen
extends Control
signal readiness_timed_out
## Bontago-1pi.32: loading finished on this instance and the ready prompt is shown
## (ui_accept: Enter or gamepad A sends the ready intent). The "Ready?" + glyph prompt
## and per-player ready list are driven by accepts_ready_input(), the lifecycle's gate
## sets and Events.loading_ready_changed / loading_gate_opened. Bontago-1pi.63: no
## loading text/bar, status line, button, timer or minimum display time.
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
## Bontago-mp0.96: the prerendered arena plate (cover-cropped), the flat darkening and
## the vignette drawn over it. Dim and Vignette are children of the Backdrop, so they
## fade in and out with the plate.
@onready var _backdrop: TextureRect = %Backdrop
@onready var _dim: ColorRect = %Dim
@onready var _vignette: TextureRect = %Vignette
@onready var _card: PanelContainer = %Card
@onready var _map_label: Label = %MapLabel
## Bontago-mp0.124: the map pictogram above the name (UiArtTable); hidden without a config.
@onready var _map_icon: TextureRect = %MapIcon
## Bontago-1pi.32 L2 (ready prompt + player ready list; presentation only).
@onready var _player_list: VBoxContainer = %PlayerList
@onready var _ready_box: VBoxContainer = %ReadyBox
@onready var _prompt_content: VBoxContainer = %PromptContent
@onready var _prompt_text: Label = %PromptText
@onready var _glyph_slot: HBoxContainer = %GlyphSlot

## The Input Map action that readies (Enter/Numpad Enter/Space and gamepad A).
const READY_ACTION: StringName = &"ui_accept"
const INPUT_GLYPH_SCENE: PackedScene = preload("res://ui/InputGlyph.tscn")
## Unit-square check mark of a ready tick (relative to the mark's radius).
const _CHECK_POINTS: PackedVector2Array = [Vector2(-0.38, 0.02), Vector2(-0.1, 0.3), Vector2(0.4, -0.3)]

## Bontago-1pi.63: the loading bar is gone; the stage fraction is only kept for
## progress() (game/Main.gd still reports it).
var _progress: float = 0.0
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
## Bontago-1pi.32 L2: the local player pressed ready on this overlay (the host's
## echo can lag behind by a round trip). One press is ever sent.
var _local_pressed: bool = false
## ready_prompt_opened fired for this match (it fires when the prompt first shows).
var _prompt_announced: bool = false
## One entry per player-list row: {slot_id: int, is_bot: bool, mark: Control}.
var _ready_rows: Array[Dictionary] = []
## Bontago-mp0.96 backdrop state. _backdrop_path is the plate chosen for the current
## match ("" = none: no config yet, or no plate on disk); _backdrop_shown_path is the
## plate whose texture the rect holds. _backdrop_requested: a threaded load of
## _backdrop_path is in flight. _backdrop_orphans: superseded requests, still to be
## collected so the loader does not keep them.
var _backdrop_path: String = ""
var _backdrop_shown_path: String = ""
var _backdrop_requested: bool = false
var _backdrop_orphans: PackedStringArray = PackedStringArray()
var _backdrop_tween: Tween = null

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
	_apply_backdrop_styles()
	_card.add_theme_stylebox_override("panel", MenuStyleFactory.make_card(menu_visual_tuning.pill_cream_color, menu_visual_tuning))
	_apply_ready_styles()
	Events.loading_ready_changed.connect(_on_loading_ready_changed)
	Events.loading_gate_opened.connect(_on_loading_gate_opened)
	Events.match_scope_reset.connect(_on_match_scope_reset)
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
	_refresh_map_icon(config)
	_select_backdrop(config)
	_rebuild_ready_rows(slots)
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


func set_stage(_stage: String, fraction: float) -> void:
	_progress = clampf(fraction, 0.0, 1.0)


func progress() -> float:
	return _progress


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
	_finish_backdrop_fade()
	_drain_backdrop_orphans()
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
	while Match._lifecycle.loading_gate_blocking():
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
	clear_player_rows()
	_refresh_ready_ui()
	_abandon_backdrop_request()
	_finish_backdrop_fade()
	_drain_backdrop_orphans()
	if _warm_viewport != null:
		_warm_viewport.queue_free()
		_warm_viewport = null


## Bontago-1pi.46 (G10; Events.match_scope_reset). ROOT CAUSE: show_for_match() rebuilds
## the player rows, but nothing took them down when the overlay faded out, so every
## finished match left its swatch/name/mark rows in the hidden PlayerList until the next
## show. Main emits the reset while the overlay is UP for the new match too (LOADING
## shows it, then builds the world, which resets), and those rows must survive that
## one, so only a hidden overlay is cleared (a cancelled load clears in cancel()).
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
	_map_icon.texture = art.map_pictogram(config.map_variant) if config != null else null
	_map_icon.visible = _map_icon.texture != null
	_map_icon.custom_minimum_size = Vector2.ONE * float(art.loading_map_icon_px)


## The pictogram currently shown on the card (null when hidden).
func map_icon_texture() -> Texture2D:
	return _map_icon.texture if _map_icon.visible else null


func _map_display_name(config: MatchConfig) -> String:
	if config == null:
		return ""
	var variant_name: String = (MatchConfig.MapVariant.keys()[config.map_variant] as String).capitalize()
	var size_name: String = (MapDef.MapSize.keys()[config.map_size] as String).capitalize()
	return "%s - %s" % [variant_name, size_name]


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


# --- Bontago-mp0.96: prerendered arena backdrop -----------------------------------

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


## The plate for this match: arena shape (map variant) x sky theme, a fallback for an
## unknown shape or theme, and "" when there is no config yet (a client's pending
## overlay), the theme is not known yet (an unresolved RANDOM sky: the host rolls it at
## match start, and show_for_match() runs again then) or no plate exists on disk.
func backdrop_path_for(config: MatchConfig) -> String:
	if config == null:
		return ""
	var theme_id: String = _backdrop_theme_id(config)
	if theme_id.is_empty():
		return ""
	var path: String = tuning.backdrop_path(config.map_variant, theme_id)
	if ResourceLoader.exists(path):
		return path
	var fallback: String = tuning.backdrop_fallback_path()
	return fallback if ResourceLoader.exists(fallback) else ""


## The concrete sky theme id the match opens with. A running cycle opens at the theme's
## cycle_start_phase, so it shows the plate nearest that phase. "" while an unresolved
## RANDOM sky has not been rolled.
func _backdrop_theme_id(config: MatchConfig) -> String:
	if config.is_sky_cycle_running():
		var sky_theme: SkyThemeDef = load(tuning.backdrop_cycle_theme_path) as SkyThemeDef
		var cycle_id: String = ""
		if sky_theme != null:
			cycle_id = tuning.backdrop_theme_for_phase(
				config.sky_start_phase if config.sky_start_phase >= 0.0 else sky_theme.cycle_start_phase, sky_theme)
		return cycle_id if not cycle_id.is_empty() else tuning.backdrop_fallback_theme
	if config.sky_theme_mode == MatchConfig.SkyThemeMode.RANDOM and config.sky_theme_resolved.is_empty():
		return ""
	return config.effective_sky_theme()


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
	var texture: Texture2D = ResourceLoader.load_threaded_get(_backdrop_path) as Texture2D
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
			ResourceLoader.load_threaded_get(path)
	_backdrop_orphans = still_loading


func _exit_tree() -> void:
	_abandon_backdrop_request()
	for path: String in _backdrop_orphans:
		ResourceLoader.load_threaded_get(path)
	_backdrop_orphans = PackedStringArray()


## Test seams: the plate chosen for this match ("" = none), the plate the rect shows
## ("" = none yet), and the texture it holds.
func backdrop_path() -> String:
	return _backdrop_path


func backdrop_shown_path() -> String:
	return _backdrop_shown_path


func backdrop_texture() -> Texture2D:
	return _backdrop.texture


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
	_prompt_text.text = tuning.ready_prompt_text
	_prompt_text.add_theme_font_size_override("font_size", tuning.ready_prompt_font_size)
	_prompt_text.add_theme_color_override("font_color", palette.ink_color)


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
		_ready_rows.append({"slot_id": slot_item.slot_id, "is_bot": slot_item.is_bot, "mark": mark, "name": name_label})


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


## Test seam: the name shown on each player row, in order.
func player_row_names() -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	for row: Dictionary in _ready_rows:
		names.append((row["name"] as Label).text)
	return names


## Test seam: whether the "Ready?" + glyph prompt is on screen.
func ready_prompt_visible() -> bool:
	return _ready_box.visible


## Test seam: the prompt's text line ("Ready?").
func ready_prompt_text() -> String:
	return _prompt_text.text


## Test seam: whether slot_id's row currently shows the ready tick.
func player_row_ready(slot_id: int) -> bool:
	for row: Dictionary in _ready_rows:
		if int(row["slot_id"]) == slot_id:
			return bool((row["mark"] as Control).get_meta(&"ready", false))
	return false


## Re-derives everything the ready gate shows from the host's state (the lifecycle
## mirrors it on clients) and the local press. Cheap; runs every frame while armed
## and on every ready/gate/device signal. Nothing here decides anything: the host
## still owns the gate. Bontago-1pi.63: only the player list (name + tick/ring) and
## the "Ready?" + device glyph prompt remain.
func _refresh_ready_ui() -> void:
	_player_list.visible = not _ready_rows.is_empty()
	if not _ready_gate_armed:
		_ready_box.visible = false
		return
	var ready_ids: PackedInt32Array = Match._lifecycle.loading_ready_peers()
	for row: Dictionary in _ready_rows:
		var slot_ready: bool = bool(row["is_bot"]) or Match._lifecycle.loading_slot_ready(int(row["slot_id"]))
		var mark: Control = row["mark"] as Control
		if bool(mark.get_meta(&"ready", false)) != slot_ready:
			mark.set_meta(&"ready", slot_ready)
			mark.queue_redraw()
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
