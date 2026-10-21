class_name SoakObserver
extends RefCounted
## Reads live game state (Match, Net, the block registry, the intent counters, the sampler) into
## the observation objects SoakCheck takes. Internal to SoakMonitor; read-only.

var _config: SoakConfig = null
var _sampler: PerfSampler = null


func _init(config: SoakConfig, sampler: PerfSampler) -> void:
	_config = config
	_sampler = sampler
