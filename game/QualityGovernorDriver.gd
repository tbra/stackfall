class_name QualityGovernorDriver
extends Node
## Bontago-1pi.11.37: feeds core/QualityGovernor.gd at a low rate and hands the level
## to Settings, which resolves the effective preset (stored settings never change).
## Per frame it only adds the frame time; the awake-block walk and the evaluation run
## once per config.sample_interval_s. Idle (process off) while the option is off.
## Frame time is measured here, not read from PerfSampler: that node only exists in
## debug mode.

var config: QualityGovernorConfig = preload("res://config/quality_governor.tres")
var governor: QualityGovernor = null
## Test seam: null reads Settings, Match.registry().
var settings_node: Node = null
var _acc_s: float = 0.0
var _acc_frames: int = 0
var _acc_real_s: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if governor == null:
		governor = QualityGovernor.new(config)
	if settings_node == null:
		settings_node = Settings
	settings_node.adaptive_quality_setting_changed.connect(_on_setting_changed)
	_on_setting_changed(bool(settings_node.adaptive_quality_enabled()))


func _on_setting_changed(enabled: bool) -> void:
	governor.reset()
	_acc_s = 0.0
	_acc_frames = 0
	_acc_real_s = 0.0
	set_process(enabled)


func _process(delta: float) -> void:
	var real: float = delta / maxf(Engine.time_scale, 0.0001)
	if real > config.ignore_delta_above_s:
		return
	_acc_real_s += real
	_acc_frames += 1
	if _acc_real_s >= config.sample_interval_s:
		sample(_acc_real_s / float(_acc_frames) * 1000.0, _awake_count(), _acc_real_s)
		_acc_real_s = 0.0
		_acc_frames = 0


## One governor sample (also the test seam).
func sample(frame_ms: float, awake: int, dt_s: float) -> void:
	if not bool(settings_node.adaptive_quality_enabled()):
		return
	if governor.evaluate(frame_ms, awake, dt_s):
		settings_node.set_governor_level(governor.level)


func _awake_count() -> int:
	var registry: BlockRegistry = Match.registry()
	if registry == null:
		return 0
	var awake: int = 0
	for block: Block in registry.all_blocks():
		if not (block.sleeping or block.freeze):
			awake += 1
	return awake
