class_name LoadingBackdrop extends TextureRect
## Loading-screen backdrop plate: one of the main menu's images, picked at random once per
## loading screen and shown through `texture`. It loads on a worker thread (the main thread
## headless), fades in, and is released again by clear().

const MENU_TUNING_PATH: String = "res://config/ui/main_menu_tuning.tres"
## Frames a fetched plate stays referenced so queued RenderingServer commands drain.
const TEXTURE_RELEASE_FRAMES: int = 3
## DisplayServer.get_name() of a --headless run, which renders with the dummy rasterizer.
const HEADLESS_DISPLAY: String = "headless"

## The plate chosen for the current show ("" = none: no config yet, or no plate on disk).
var _path: String = ""
## The plate picked for this loading screen; kept until clear() so a repeat show reuses it.
var _session_path: String = ""
## The plate whose texture this rect holds.
var _shown_path: String = ""
## A threaded load of _path is in flight.
var _requested: bool = false
## Superseded requests, still to be collected so the loader does not keep them.
var _orphans: PackedStringArray = PackedStringArray()
var _fade_in_s: float = 0.0
var _tween: Tween = null


func _ready() -> void:
	set_process(false)


func _process(_delta: float) -> void:
	_poll(true)
	set_process(_requested or not _orphans.is_empty())


## The backdrop for this screen: one of MainMenuTuning.backdrop_paths, chosen once per loading
## screen (until clear()). "" when there is no config yet (a client's pending overlay: show_for()
## runs again with it) or no image is listed.
## DECISION: the pick may differ from the main menu's.
func path_for(config: MatchConfig) -> String:
	if config == null:
		return ""
	if _session_path.is_empty():
		var menu_tuning: MainMenuTuning = load(MENU_TUNING_PATH) as MainMenuTuning
		_session_path = MenuBackdrop.pick_path(menu_tuning.backdrop_paths, randf())
	return _session_path if ResourceLoader.exists(_session_path) else ""


## Chooses the plate and starts loading it, so showing the overlay never stalls on a 1920x1080
## decode. The same plate as the previous show is kept as it is; a different one drops the stale
## texture at once so it never flashes, and appears (fading in over `fade_in_s`) when loaded.
func show_for(config: MatchConfig, fade_in_s: float) -> void:
	_fade_in_s = fade_in_s
	var path: String = path_for(config)
	if path == _path and (path.is_empty() or _requested or _shown_path == path):
		return
	_abandon_request()
	_path = path
	if path != _shown_path:
		_drop_texture()
	if path.is_empty() or path == _shown_path:
		return
	var orphan_index: int = _orphans.find(path)
	if orphan_index >= 0:
		_orphans.remove_at(orphan_index)
	if not threaded_texture_loads_safe():
		_show(load(path) as Texture2D, false)
		return
	if ResourceLoader.load_threaded_request(path, "Texture2D") != OK:
		push_warning("LoadingBackdrop: could not request the backdrop %s." % path)
		return
	_requested = true
	set_process(true)
	# A plate still cached from an earlier match lands now, with no fade.
	_poll(false)


## A hidden overlay keeps its plate fully visible, so the next show of the same plate
## (a rematch) is not left mid fade-in.
func finish_fade() -> void:
	if _shown_path.is_empty():
		return
	_kill_tween()
	modulate.a = 1.0


## Ends this loading screen: drops the plate and any fade, abandons a load in flight, collects
## finished orphans, and lets the next show pick a new plate.
func clear() -> void:
	_abandon_request()
	_drain_orphans()
	_drop_texture()
	_path = ""
	_session_path = ""
	set_process(not _orphans.is_empty())


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


func _exit_tree() -> void:
	_abandon_request()
	for path: String in _orphans:
		release_later(ResourceLoader.load_threaded_get(path))
	_orphans = PackedStringArray()


## Collects the in-flight plate once the worker thread has it. `animate` fades it in; a plate
## that was already loaded appears at once.
func _poll(animate: bool) -> void:
	_drain_orphans()
	if not _requested:
		return
	var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(_path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	_requested = false
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		push_warning("LoadingBackdrop: the backdrop %s failed to load." % _path)
		return
	_show(ResourceLoader.load_threaded_get(_path) as Texture2D, animate)


## Shows a fetched plate (null: nothing to show); `animate` fades it in.
func _show(plate: Texture2D, animate: bool) -> void:
	if plate == null:
		return
	texture = plate
	visible = true
	_shown_path = _path
	_kill_tween()
	if animate and _fade_in_s > 0.0:
		modulate.a = 0.0
		_tween = create_tween()
		_tween.tween_property(self, ^"modulate:a", 1.0, _fade_in_s)
	else:
		modulate.a = 1.0


## Drops the shown plate (and any fade), leaving only the plain background.
func _drop_texture() -> void:
	_kill_tween()
	release_later(texture)
	texture = null
	visible = false
	modulate.a = 0.0
	_shown_path = ""


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


## A load in flight for a plate this match no longer wants is collected later (a
## threaded request holds its result until it is fetched).
func _abandon_request() -> void:
	if _requested and not _orphans.has(_path):
		_orphans.append(_path)
	_requested = false


## Fetches (and drops) every abandoned plate whose worker has finished.
func _drain_orphans() -> void:
	var still_loading: PackedStringArray = PackedStringArray()
	for path: String in _orphans:
		if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			still_loading.append(path)
		else:
			release_later(ResourceLoader.load_threaded_get(path))
	_orphans = still_loading
