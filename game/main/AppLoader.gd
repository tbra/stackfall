class_name AppLoader
extends Node
## Background prewarm, late activation and scene loading for Main. Child of Main;
## properties are set before add_child. One serial queue loads behind the menu (interactive
## launches only); headless, agent-probe and CLI-flag runs keep the synchronous on-demand loads.

signal loading_status_requested(text: String)
signal late_activated

const LOADING_STATUS_TEXT: String = "Loading..."

var queue: MenuPrewarmQueue = null
var quit: DeferredQuit = null

## True while the queue loads behind the menu.
var _background: bool = false
## The menu has been shown once, so _process may advance the queue.
var _polling: bool = false
## A Loading... click is waiting for its frame; further activations are dropped meanwhile.
var _click_pending: bool = false


func _ready() -> void:
	set_process(false)


## The in-flight chunk is never cancelled during exit cleanup.
func _exit_tree() -> void:
	queue.collect_in_flight()


## A window close once Boot has handed over is a real quit. While the prewarm owns the close
## request, the quit waits for the in-flight chunk (the message pump stays alive) and no further
## chunk starts. Once drained the engine owns the close again (one quit path).
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST:
		return
	if not _background:
		if not quit.quit_callable.is_valid():  # test seam: no real quit
			QuitFlag.mark()
		return
	queue.halt()
	quit.on_close_request(queue.has_in_flight())
	_stop_processing_when_quit()


## Drives the one serial background loader (one request in flight) once the menu is up.
func _process(_delta: float) -> void:
	# A close during the splash still finishes the in-flight chunk and quits (menu never shows).
	if not _polling and not quit.is_requested():
		return
	queue.poll()
	if quit.is_requested():
		quit.settle(queue.has_in_flight())
		_stop_processing_when_quit()
		return
	_activate_late_if_loaded()
	if not queue.has_in_flight() and queue.is_drained():
		ensure_late_active()  # drained: every LateScripts path is loaded, activation is instant
		_background = false
		_polling = false
		get_tree().auto_accept_quit = true
		set_process(false)


## True when the queue should load behind the menu: a real window, no CLI flag that implies a
## synchronous startup. DECISION: an agent-probe run is synchronous (probes expect today's
## startup order) except `--quit-on-menu`, the boot-timing check, which must measure this path.
func wants_background() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	if AgentProbe.is_active() and not AgentProbe.wants_quit_on_menu(OS.get_cmdline_user_args()):
		return false
	if queue.config == null:
		return false
	return not queue.config.wants_eager(OS.get_cmdline_user_args())


## True from begin() until the queue has drained.
func is_background() -> bool:
	return _background


## Starts the queue (the Lobby chunk first) while the splash plays and takes the close request.
func begin(_lobby_path: String) -> void:
	_background = true
	get_tree().auto_accept_quit = false  # Boot restored it at hand-over; the queue owns close now
	queue.start(get_tree())
	set_process(true)


## Menu hand-off (after the splash, or at once without one): the Lobby chunk is collected first
## so Host/Join never wait, then the remaining chunks prewarm behind the menu.
## False when a close arrived during the splash: never flash the menu up.
func menu_shown(lobby_path: String) -> bool:
	if quit.is_requested():
		queue.collect_in_flight()
		quit.settle(false)
		_stop_processing_when_quit()
		return false
	if _background:
		queue.ensure(lobby_path)
	_polling = true
	return true


## Match + MatchNet late_activate (WeatherNet child included) must exist before any session
## starts or a replicated packet can arrive, so every flow calls this first (idempotent).
## Blocks only for what the background queue has not delivered yet: the in-flight request is
## collected (never cancelled), the rest loads synchronously.
func ensure_late_active() -> void:
	if is_late_active():
		return
	queue.collect_in_flight()
	for path: String in _late_paths_in_queue():
		queue.ensure(path)
	LateScripts.activate_autoloads(get_tree())
	late_activated.emit()


## A menu click whose target is still prewarming: asks for "Loading...", lets one frame render
## it, then the caller's ensure() blocks for at most the remaining chunk. No wait once loaded.
## Returns false when this activation must be dropped (another one is already waiting).
func await_prewarmed(paths: PackedStringArray) -> bool:
	if _click_pending:
		return false
	if not _background:
		ensure_late_active()
		return true
	var waiting: bool = not is_late_active()
	for path: String in paths:
		if not queue.is_ready(path):
			waiting = true
	if waiting:
		loading_status_requested.emit(LOADING_STATUS_TEXT)
		_click_pending = true
		await get_tree().process_frame
		_click_pending = false
	ensure_late_active()
	return true


## Rarely used scenes load on first use instead of at parse time. No member keeps the
## PackedScene: the resource cache holds it while an instance is alive and releases it afterwards.
func load_scene(path: String) -> PackedScene:
	if _background and queue.config != null and queue.config.all_paths().has(path):
		return queue.ensure(path) as PackedScene  # never load() beside an in-flight chunk
	return load(path) as PackedScene


func ensure_script(path: String) -> GDScript:
	return queue.ensure_script(path)


## True once both autoload facades built their late state.
func is_late_active() -> bool:
	return Match.is_late_active() and MatchNet.is_late_active()


## Background path: once the queue holds every LateScripts path, activation costs no load.
func _activate_late_if_loaded() -> void:
	if is_late_active():
		return
	for path: String in _late_paths_in_queue():
		if not queue.is_ready(path):
			return
	ensure_late_active()


## The LateScripts paths the queue is configured to load (a test queue may omit them).
func _late_paths_in_queue() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	if queue.config == null:
		return result
	var known: PackedStringArray = queue.config.all_paths()
	for path: String in LateScripts.paths():
		if known.has(path):
			result.append(path)
	return result


func _stop_processing_when_quit() -> void:
	if quit.is_done():
		set_process(false)
