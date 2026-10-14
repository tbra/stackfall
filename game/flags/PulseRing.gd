class_name PulseRing
extends MeshInstance3D
## Shared pulsing ground ring (Bontago-1pi.85.57): the flat, unshaded, emissive
## annulus whose radius and emission breathe on one sine wave. HomeFlag's beacon ring
## and the landed gift crate's ring are both this node; each caller passes its own
## period/amplitudes from its own tuning Resource. Presentation only.

## Fewest segments that still close a ring.
const MIN_SEGMENTS: int = 3

var _material: StandardMaterial3D = null
var _time_s: float = 0.0


## Builds the annulus mesh and the unshaded emissive material. Call once.
func build(outer: float, inner: float, segments: int, color: Color) -> void:
	mesh = HomeFlag.build_annulus_mesh(outer, inner, TAU, maxi(segments, MIN_SEGMENTS))
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.emission_enabled = true
	material_override = _material
	set_color(color)


func set_color(color: Color) -> void:
	if _material == null:
		return
	_material.albedo_color = color
	_material.emission = color


func is_built() -> bool:
	return _material != null


func emission_energy() -> float:
	return _material.emission_energy_multiplier if _material != null else 0.0


## Sine wave in -1..1 for the pulse phase; 0 when the period is not positive.
static func wave_at(time_s: float, period_s: float) -> float:
	if period_s <= 0.0:
		return 0.0
	return sin(TAU * time_s / period_s)


## Advances the phase by delta and applies radius scale and emission energy.
## extra_scale / emission_boost are the caller's overlays (GoalFlag's claim flash).
## Returns the wave so the caller can drive its own parts (the crystal) from it.
func advance(delta: float, period_s: float, scale_amplitude: float, emission_amplitude: float,
		emission_base: float, extra_scale: float = 0.0, emission_boost: float = 1.0) -> float:
	_time_s += delta
	var wave: float = wave_at(_time_s, period_s)
	var ring_scale: float = 1.0 + wave * scale_amplitude + extra_scale
	scale = Vector3(ring_scale, 1.0, ring_scale)
	if _material != null:
		_material.emission_energy_multiplier = emission_base * (1.0 + wave * emission_amplitude) * emission_boost
	return wave
