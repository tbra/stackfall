extends Node
## Bontago-1pi.11.53 probe: main-thread frame gaps from process start through the main menu.
## User args: seconds=<n> boot (use game/Boot.tscn instead of Main directly) splash (also builds a SplashScreen over Main, which probe mode skips)
##   godot --path . --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy res://tools/probe_startup_gaps.tscn -- --agent-probe seconds=12
const REPORT_GAP_MS: int = 100
const DEFAULT_SECONDS: float = 8.0

var _last_ms: int = 0
var _frame: int = 0
var _elapsed_s: float = 0.0
var _limit_s: float = DEFAULT_SECONDS
var _gaps: Array[String] = []


func _ready() -> void:
	var with_splash: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("seconds="):
			_limit_s = float(arg.trim_prefix("seconds="))
		elif arg == "splash":
			with_splash = true
	var t0: int = Time.get_ticks_msec()
	if "boot" in OS.get_cmdline_user_args():
		add_child((load("res://game/Boot.tscn") as PackedScene).instantiate())
		_gaps.append("boot_to_probe_ready t=%d ms; Boot added (Main loads on a worker)" % t0)
		_last_ms = Time.get_ticks_msec()
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


func _process(delta: float) -> void:
	var now: int = Time.get_ticks_msec()
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
