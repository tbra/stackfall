class_name CloudDriftState
extends RefCounted
## Bontago-mp0.92: the one running cloud wind (no scene tree). Skybox steps it every frame;
## the puff shader, the sun-occlusion bounds and CloudShadows all read it, so they cannot
## disagree. `offset` integrates the eased wind (m per m/s of clump speed): a clump moves by
## offset * its own speed, so nothing jumps when the wind turns or the storm arrives.

const DEFAULT_CONFIG: CloudDriftConfig = preload("res://config/cloud_drift.tres")

var config: CloudDriftConfig = DEFAULT_CONFIG
## Unit wind direction now (x, z) and the speed multiplier now.
var heading: Vector2 = Vector2.RIGHT
var speed_mult: float = 1.0
var offset: Vector2 = Vector2.ZERO
var _calm: Vector2 = Vector2.RIGHT
var _storm_wind: Vector2 = Vector2.ZERO


func _init(drift_config: CloudDriftConfig = null) -> void:
	if drift_config != null:
		config = drift_config


## Starts a match: calm heading from the sky variation seed, wind and offset reset.
func reset(seed_value: int) -> void:
	_calm = CloudDriftMath.calm_heading(seed_value, config)
	_storm_wind = Vector2.ZERO
	heading = _calm
	speed_mult = 1.0
	offset = Vector2.ZERO


## The storm's live wind heading (unit x, z; StormPresentation pushes it each frame).
func set_storm_wind(direction: Vector2) -> void:
	_storm_wind = direction.normalized() if direction.length_squared() > 0.0 else Vector2.ZERO


func calm_heading() -> Vector2:
	return _calm


## Advances by `delta` seconds at `storm_amount` 0..1 (the already eased storm blend).
func step(delta: float, storm_amount: float) -> void:
	var target: Vector2 = CloudDriftMath.target_heading(_calm, _storm_wind, storm_amount)
	heading = CloudDriftMath.follow_heading(heading, target, config.heading_follow_rate, delta)
	var wanted: float = CloudDriftMath.speed_multiplier(storm_amount, config)
	speed_mult = lerpf(speed_mult, wanted, 1.0 - exp(-config.speed_follow_rate * maxf(delta, 0.0)))
	offset += heading * speed_mult * delta


## Wind velocity (m/s) of a clump whose own speed is `clump_speed_mps`.
func velocity(clump_speed_mps: float) -> Vector2:
	return heading * speed_mult * clump_speed_mps
