class_name DebugTools
extends Node
## Debug tool composition: the perf sampler and the F1 overlay in every build, and with session_extras the CSV logger, soak monitor and fuzzer.
## Main adds one instance for the whole session. The per-round panels (F2, F3, F9) are not built here.

const SOAK_MONITOR_PATH: String = "res://game/debug/SoakMonitor.gd"
const SOAK_FUZZER_PATH: String = "res://game/debug/SoakIntentFuzzer.gd"
const SOAK_CONFIG_PATH: String = "res://config/soak/soak_config.tres"

## Debug tuning; DebugMode.config() is the default once built.
var config: DebugConfig = null
## Build the soak monitor (the "soak" command-line flag).
var soak_enabled: bool = false
## Build the soak intent fuzzer (the "soak-fuzz" command-line flag).
var soak_fuzz_enabled: bool = false
## Session extras on: logger, soak, fuzzer and continuous sampling (Main sets it from DebugMode.is_enabled()).
var session_extras: bool = false


func _ready() -> void:
	if config == null:
		config = DebugMode.config()
	var sampler: PerfSampler = PerfSampler.new()
	sampler.config = config
	# A hidden F1 costs nothing unless the logger or soak monitor need continuous samples.
	sampler.demand_driven = not session_extras
	add_child(sampler)
	var overlay: PerfOverlay = PerfOverlay.new()
	overlay.config = config
	overlay.sampler = sampler
	add_child(overlay)
	if not session_extras:
		return
	# Continuous samples need the probe sites on from the start (a demand-driven sampler toggles them itself).
	PerfProbe.enabled = true
	var logger: PerfLogger = PerfLogger.new()
	logger.config = config
	logger.sampler = sampler
	add_child(logger)
	if soak_enabled:
		_add_soak(sampler)


## Loaded by path like the bot overlay: the soak code stays out of Main's compile closure.
## DECISION: the soak classes are set through set(&"x", ...) seams so no typed reference to them exists here.
func _add_soak(sampler: PerfSampler) -> void:
	var soak_script: GDScript = load(SOAK_MONITOR_PATH) as GDScript
	var soak: Node = soak_script.new() as Node
	soak.set(&"config", load(SOAK_CONFIG_PATH))
	# DECISION: Net.apply_command_line() runs after this, so Net.is_host() would read the
	# offline default; the role comes from the same parser Net uses.
	var joining: bool = NetCommandLine.parse(OS.get_cmdline_user_args()).has_join
	soak.set(&"role", &"client" if joining else &"host")
	soak.set(&"sampler", sampler)
	add_child(soak)
	# DECISION: the plan does not say client-only; the launcher passes --soak-fuzz to the client
	# alone and the fuzzer does nothing without a seat, so no role check is added here.
	if not soak_fuzz_enabled:
		return
	var fuzzer_script: GDScript = load(SOAK_FUZZER_PATH) as GDScript
	var fuzzer: Node = fuzzer_script.new() as Node
	fuzzer.set(&"config", load(SOAK_CONFIG_PATH))
	var seams_script: GDScript = fuzzer_script.get_script_constant_map()[&"Seams"] as GDScript
	var seams: RefCounted = seams_script.new() as RefCounted
	seams.set(&"playing", func() -> bool: return Match.state() == Match.State.PLAYING)
	seams.set(&"local_slot", Net.local_slot)
	seams.set(&"feed_seq", Match.feed_seq)
	seams.set(&"field_radius", func() -> float: return Match.config.map_def().field_radius)
	seams.set(&"submit_place", MatchNet.submit_place)
	seams.set(&"line", func(text: String) -> void: print(text))
	fuzzer.set(&"seams", seams)
	add_child(fuzzer)
