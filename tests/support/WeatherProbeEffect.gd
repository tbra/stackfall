class_name WeatherProbeEffect
extends WeatherEffect
## Test-only effect (Bontago-22y.10): scales a "friction" entry in a shared
## Dictionary by the ramped intensity, so a test can prove apply()/restore()
## round-trip the baseline. Never referenced by shipped config.

const FRICTION_KEY: String = "friction"
const FRICTION_DROP_AT_FULL: float = 0.5

var world: Dictionary = {}
var baseline: float = 0.0
var apply_calls: int = 0
var tick_calls: int = 0
var restore_calls: int = 0


func _init(shared_world: Dictionary = {}) -> void:
	world = shared_world
	baseline = float(world.get(FRICTION_KEY, 1.0))


func apply(intensity: float) -> void:
	apply_calls += 1
	world[FRICTION_KEY] = baseline * (1.0 - FRICTION_DROP_AT_FULL * intensity)


func tick(_delta: float, _intensity: float) -> void:
	tick_calls += 1


func restore() -> void:
	restore_calls += 1
	world[FRICTION_KEY] = baseline
