class_name PerfLogger
extends Node
## Bontago-470.8: writes one CSV per debug session to
## <DebugConfig.log_dir>/<timestamp>.csv, a row every DebugConfig.log_interval_s
## fed by game/PerfSampler.gd's newest snapshot. Flushes every
## log_flush_every_rows rows, closes on tree exit, and keeps only the newest
## log_keep_files files. Summarise with tools/perf_log_summary.py.

const COLUMNS: PackedStringArray = [
	"time_s", "match_state", "players", "fps", "frame_ms", "frame_ms_max", 
	"physics_ms", "physics_ms_max", "territory_ms", "territory_peak_ms", "weather_ms", "gifts_ms",
	"registry_ms", "block_effects_ms", "snapshot_ms", "blocks_total", "blocks_awake",
	"blocks_sleeping", "draw_calls", "objects_in_frame",
	"primitives", "vram_mb", "static_mem_mb", "node_count", "object_count", "orphan_nodes",
	"weather_id", "weather_intensity", "net_peers", "net_ping_ms", "net_snapshot_bps",
]

var sampler: PerfSampler = null
var config: DebugConfig = null
var path: String = ""
## Set false by tests that call open_log() themselves.
var auto_open: bool = true

var _file: FileAccess = null
var _since_log_s: float = 0.0
var _rows_since_flush: int = 0
var _rows_written: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if config == null:
		config = DebugConfig.new()
	if auto_open and config.log_enabled and DebugMode.is_enabled() and not is_automated_run():
		open_log()


## Bontago-1pi.11.15: headless and agent-probe runs (tests, benches, bots)
## must not write session logs -- each open_log() prunes to log_keep_files,
## so a burst of automated runs deleted the owner's own playtest log.
static func is_automated_run() -> bool:
	return DisplayServer.get_name() == "headless" or AgentProbe.is_active()


func _process(delta: float) -> void:
	if _file == null or sampler == null or sampler.latest.is_empty():
		return
	_since_log_s += delta / maxf(Engine.time_scale, 0.0001)
	if _since_log_s < config.log_interval_s:
		return
	_since_log_s = 0.0
	write_row(sampler.latest)


func _exit_tree() -> void:
	close_log()


func rows_written() -> int:
	return _rows_written


## Creates the session file (and log dir), prunes old logs and prints the path.
func open_log() -> bool:
	if _file != null:
		return true
	DirAccess.make_dir_recursive_absolute(config.log_dir)
	var stamp: String = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	path = config.log_dir.path_join("%s.csv" % stamp)
	# Two sessions in the same second must not clobber each other.
	var suffix: int = 1
	while FileAccess.file_exists(path):
		suffix += 1
		path = config.log_dir.path_join("%s_%d.csv" % [stamp, suffix])
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		push_warning("PerfLogger: cannot open %s (error %d)" % [path, FileAccess.get_open_error()])
		return false
	_file.store_line(",".join(COLUMNS))
	_file.flush()
	prune_old_logs()
	print("PerfLogger: logging to %s" % ProjectSettings.globalize_path(path))
	return true


func write_row(m: Dictionary) -> void:
	if _file == null:
		return
	var cells: PackedStringArray = PackedStringArray()
	for column: String in COLUMNS:
		cells.append(format_cell(m.get(column, "")))
	_file.store_line(",".join(cells))
	_rows_written += 1
	_rows_since_flush += 1
	if _rows_since_flush >= config.log_flush_every_rows:
		_file.flush()
		_rows_since_flush = 0


func close_log() -> void:
	if _file == null:
		return
	_file.flush()
	_file.close()
	_file = null


## Keeps the newest `log_keep_files` .csv files (names sort chronologically).
func prune_old_logs() -> void:
	var names: PackedStringArray = PackedStringArray()
	for file_name: String in DirAccess.get_files_at(config.log_dir):
		if file_name.ends_with(".csv"):
			names.append(file_name)
	names.sort()
	var excess: int = names.size() - config.log_keep_files
	for i: int in range(maxi(excess, 0)):
		DirAccess.remove_absolute(config.log_dir.path_join(names[i]))


static func format_cell(value: Variant) -> String:
	if value is float:
		return "%.3f" % float(value)
	# Strings (state, weather id) never contain commas, but be safe.
	return str(value).replace(",", ";").replace("\n", " ")
