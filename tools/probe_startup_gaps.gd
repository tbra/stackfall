extends Node
## Bontago-1pi.11.53 probe: main-thread frame gaps from process start through the main menu.
## User args: seconds=<n> splash (also builds a SplashScreen over Main, which probe mode skips)
##   godot --path . --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy res://tools/probe_startup_gaps.tscn -- --agent-probe seconds=12
## Real Boot path (Bontago-fca.82): run res://tools/startup_gaps_boot.tscn instead. Its root IS
## game/Boot.tscn (inherited), so Boot is current_scene at autoload _ready exactly as in the game
## (LateScripts deferral, threaded load and prewarm all run unchanged). This node is a child of
## that Boot, moves itself under the root so it survives Boot's queue_free, then logs the
## first-frame time (comparable to Boot._ready in the game) and when Main replaces Boot.
## CAVEAT (Bontago-1pi.11.80): the "Could not preload resource file" SCRIPT ERROR cascade seen
## when this probe quits mid-load is exit-time cancellation of Boot's in-flight threaded load, not a
## game race; Boot now collects that request in _exit_tree, and the probe's fixed timer does not matter.
const BOOT_FIRST_FRAME_LINE: String = "first_frame t=%d ms (Boot is current_scene; Main loads on a worker)"
const BOOT_SWAP_LINE: String = "main_is_current_scene t=%d ms (%d ms after first frame)"
const MAIN_NODE_NAME: String = "Main"
const REPORT_GAP_MS: int = 100
const DEFAULT_SECONDS: float = 8.0

var _last_ms: int = 0
var _frame: int = 0
var _elapsed_s: float = 0.0
var _limit_s: float = DEFAULT_SECONDS
var _gaps: Array[String] = []
var _boot_mode: bool = false
var _first_frame_ms: int = -1
var _swap_logged: bool = false


func _ready() -> void:
	var with_splash: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("seconds="):
			_limit_s = float(arg.trim_prefix("seconds="))
		elif arg == "splash":
			with_splash = true
	var t0: int = Time.get_ticks_msec()
	if get_parent() is Boot:
		_boot_mode = true
		_adopt_by_root.call_deferred()
		_last_ms = t0
		return
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	var t1: int = Time.get_ticks_msec()
	add_child(main)
	var t2: int = Time.get_ticks_msec()
	_gaps.append("boot_to_probe_ready t=%d ms; load+instantiate Main %d ms; Main._ready %d ms" % [t0, t1 - t0, t2 - t1])
	if with_splash:
		var t3: int = Time.get_ticks_msec()
		add_child(SplashScreen.new())
		_gaps.append("SplashScreen._ready %d ms" % (Time.get_ticks_msec() - t3))
	_last_ms = Time.get_ticks_msec()


## Boot queue_frees itself when Main takes over; move out from under it first.
func _adopt_by_root() -> void:
	var root: Window = get_tree().root
	get_parent().remove_child(self)
	root.add_child(self)


func _process(delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	if _boot_mode:
		if _first_frame_ms < 0:
			_first_frame_ms = now
			_gaps.append(BOOT_FIRST_FRAME_LINE % now)
		elif not _swap_logged and get_tree().current_scene != null and get_tree().current_scene.name == MAIN_NODE_NAME:
			_swap_logged = true
			_gaps.append(BOOT_SWAP_LINE % [now, now - _first_frame_ms])
	var gap: int = now - _last_ms
	_last_ms = now
	_frame += 1
	_elapsed_s += delta
	if gap >= REPORT_GAP_MS:
		_gaps.append("frame %d at t=%d ms gap %d ms" % [_frame, now, gap])
	if _elapsed_s >= _limit_s:
		for line: String in _gaps:
			print("STARTUP_GAP ", line)
		get_tree().quit()
