class_name LoadingScreen
extends Control
signal readiness_timed_out
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

@onready var _background: ColorRect = %Background
@onready var _card: PanelContainer = %Card
@onready var _map_label: Label = %MapLabel
@onready var _info_label: Label = %InfoLabel
@onready var _spinner_label: Label = %SpinnerLabel
@onready var _stage_label: Label = %StageLabel
@onready var _progress_bar: ProgressBar = %ProgressBar

const _SPIN_FRAMES: Array[String] = ["Loading", "Loading.", "Loading..", "Loading..."]

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

const WARM_SHADERS: Array[String] = [
	"res://shaders/block_cell_grid.gdshader",
	"res://shaders/territory.gdshader",
	"res://shaders/disc_rim.gdshader",
	"res://shaders/weather/snow_flake.gdshader",
]


func _ready() -> void:
	visible = false
	modulate.a = 1.0
	set_process(false)
	z_index = tuning.overlay_z_index
	_background.color = tuning.background_color
	_card.add_theme_stylebox_override("panel", MenuStyleFactory.make_card(menu_visual_tuning.pill_cream_color, menu_visual_tuning))


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
	_fade_token += 1
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
	_is_fading = false
	_map_label.text = _map_display_name(config)
	_info_label.text = _player_list_text(slots)
	_spin_index = 0
	_spin_elapsed_s = 0.0
	_spinner_label.text = _SPIN_FRAMES[0]
	set_stage("Building world", tuning.world_progress)
	modulate.a = 1.0
	visible = true
	set_process(true)


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


func _process(delta: float) -> void:
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
	for _i: int in range(tuning.warmup_frames):
		await get_tree().process_frame
		if token != _fade_token:
			return
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, ^"modulate:a", 0.0, tuning.fade_out_duration_s)
	await _fade_tween.finished
	if token != _fade_token:
		return
	visible = false
	set_process(false)
	_is_fading = false
	if _warm_viewport != null:
		_warm_viewport.queue_free()
		_warm_viewport = null


## Safety net for a match aborted mid-load (game/Main.gd's `to_state ==
## Match.State.LOBBY` branch): hides instantly, no fade, and invalidates
## whatever fade_out() coroutine might already be mid-flight so it cannot
## later hide -- or re-show -- a *different* match's overlay out from under
## it (see _fade_token's own doc).
func cancel() -> void:
	_is_pending = false
	_fade_token += 1
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
	_is_fading = false
	visible = false
	modulate.a = 1.0
	set_process(false)
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
		return "Get ready..."
	var lines: PackedStringArray = PackedStringArray()
	for slot_item: PlayerSlot in slots:
		lines.append("%s%s" % [slot_item.display_name, " (bot)" if slot_item.is_bot else ""])
	return "\n".join(lines)
