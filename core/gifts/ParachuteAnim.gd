class_name ParachuteAnim
extends RefCounted
## Pure animation state of a gift crate's parachute (Bontago-mp0.139). No scene
## tree, no autoloads, no randomness: the whole pose is a function of the phase
## and the seconds elapsed, so it is identical on host and client and can be
## unit-tested with plain numbers. COSMETIC ONLY -- the descent speed, landing
## time, claims and network messages all live in MatchGifts and are untouched.
##
## HIDDEN      no canopy (never fell yet, or fully collapsed)
## DEPLOYING   inflating from a narrow stream (ease-out-back, slight overshoot)
## DESCENDING  fully open: pendulum lean about the riser + gentle breathing
## COLLAPSING  deflates, sinks and fades, then returns to HIDDEN
##
## game/GiftParachute.gd owns one of these and applies the sampled values;
## game/GiftCrate.gd drives it from the replicated falling/landed state through
## deploy()/collapse() (its set_falling()).

enum Phase { HIDDEN, DEPLOYING, DESCENDING, COLLAPSING }

## Lower bound for a configured duration so a zero/negative value completes
## the phase at once instead of dividing by zero.
const MIN_DURATION_S: float = 0.001
## Golden angle (radians): spreads per-crate phase offsets evenly, the same
## idea as MatchGifts._flight_position()'s per-id sway offset.
const PHASE_STRIDE: float = 2.39996323
## The second lean axis runs a quarter-turn out of phase with the first.
const AXIS_PHASE: float = PI * 0.5

var phase: Phase = Phase.HIDDEN

var _config: GiftConfig = null
var _phase_seed: float = 0.0
var _time: float = 0.0
var _phase_time: float = 0.0
var _from_radius: float = 1.0
var _from_height: float = 1.0


func configure(config: GiftConfig) -> void:
	_config = config


## Offsets the sway/breath phase so two crates do not lean in lockstep.
func set_phase_seed(seed_value: float) -> void:
	_phase_seed = seed_value * PHASE_STRIDE


## Starts inflating. Ignored while already DEPLOYING or DESCENDING (a repeated
## "falling" notification must not restart the animation); from HIDDEN or
## COLLAPSING it restarts from the collapsed stream.
func deploy() -> void:
	if phase == Phase.DEPLOYING or phase == Phase.DESCENDING:
		return
	phase = Phase.DEPLOYING
	_phase_time = 0.0


## Starts deflating from whatever pose the canopy has right now. Ignored when
## there is nothing to collapse (HIDDEN) or it is already collapsing.
func collapse() -> void:
	if phase == Phase.HIDDEN or phase == Phase.COLLAPSING:
		return
	_from_radius = _open_radius()
	_from_height = _open_height()
	phase = Phase.COLLAPSING
	_phase_time = 0.0


func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	_time += delta
	_phase_time += delta
	match phase:
		Phase.DEPLOYING:
			if _phase_time >= _deploy_s():
				phase = Phase.DESCENDING
				_phase_time = 0.0
		Phase.COLLAPSING:
			if _phase_time >= _collapse_s():
				phase = Phase.HIDDEN
				_phase_time = 0.0


func is_visible() -> bool:
	return phase != Phase.HIDDEN


## True from deploy() until collapse() (the crate is airborne).
func is_falling() -> bool:
	return phase == Phase.DEPLOYING or phase == Phase.DESCENDING


## Opening shock: the canopy streams out slowly, snaps open, overshoots past 1
## when `overshoot` > 0 and settles (ease-out-back on a squared time, so the
## first moments are slow). 0 at t=0, 1 at t=1; `t` is clamped to [0, 1].
static func deploy_curve(t: float, overshoot: float) -> float:
	var clamped: float = clampf(t, 0.0, 1.0)
	var u: float = clamped * clamped - 1.0
	return 1.0 + u * u * u * (overshoot + 1.0) + u * u * overshoot


## 0..1 progress of the current DEPLOYING/COLLAPSING phase.
func phase_progress() -> float:
	match phase:
		Phase.DEPLOYING:
			return clampf(_phase_time / _deploy_s(), 0.0, 1.0)
		Phase.COLLAPSING:
			return clampf(_phase_time / _collapse_s(), 0.0, 1.0)
		Phase.DESCENDING:
			return 1.0
	return 0.0


## How open the canopy is: 0 collapsed stream, 1 fully open (overshoots past 1
## while deploying). Collapsing reports the remaining openness.
func openness() -> float:
	match phase:
		Phase.DEPLOYING:
			return deploy_curve(phase_progress(), _config.chute_deploy_overshoot)
		Phase.DESCENDING:
			return 1.0
		Phase.COLLAPSING:
			return 1.0 - _collapse_ease()
	return 0.0


func radius_scale() -> float:
	return _pose_radius() * (1.0 + _breath())


func height_scale() -> float:
	return _pose_height() * (1.0 - _breath())


## Lean about the riser, radians: x = rotation about X, y = rotation about Z.
func tilt() -> Vector2:
	var amplitude: float = _config.chute_sway_tilt_rad * _envelope()
	var angle: float = TAU * _config.chute_sway_hz * _time + _phase_seed
	var second: float = TAU * _config.chute_sway_hz * _config.chute_sway_axis_ratio * _time + _phase_seed + AXIS_PHASE
	return Vector2(sin(angle), sin(second)) * amplitude


## Vertical offset of the whole parachute (0, or negative while it sinks).
func drop_offset() -> float:
	if phase == Phase.COLLAPSING:
		return -_config.chute_collapse_drop_m * _collapse_ease()
	return 0.0


## 1 while falling; fades to 0 over the tail of the collapse.
func alpha() -> float:
	if phase != Phase.COLLAPSING:
		return 1.0
	var start: float = clampf(_config.chute_collapse_fade_start, 0.0, 1.0)
	var span: float = maxf(1.0 - start, MIN_DURATION_S)
	return 1.0 - clampf((phase_progress() - start) / span, 0.0, 1.0)


# --- internals -------------------------------------------------------------

func _deploy_s() -> float:
	return maxf(_config.chute_deploy_s, MIN_DURATION_S)


func _collapse_s() -> float:
	return maxf(_config.chute_collapse_s, MIN_DURATION_S)


## Air rushes out fast and the fabric then settles: ease-out quad.
func _collapse_ease() -> float:
	var remaining: float = 1.0 - phase_progress()
	return 1.0 - remaining * remaining


## Scale applied to sway and breathing: none while a stream, full once open.
func _envelope() -> float:
	match phase:
		Phase.DEPLOYING:
			return clampf(openness(), 0.0, 1.0)
		Phase.DESCENDING:
			return 1.0
		Phase.COLLAPSING:
			return 1.0 - _collapse_ease()
	return 0.0


func _breath() -> float:
	var swell: float = sin(TAU * _config.chute_breath_hz * _time + _phase_seed)
	return swell * _config.chute_breath_amount * _envelope()


## Open-pose scales (before breathing) while the canopy is DEPLOYING/DESCENDING.
func _open_radius() -> float:
	return lerpf(_config.chute_deploy_start_radius_scale, 1.0, openness())


func _open_height() -> float:
	return lerpf(_config.chute_deploy_start_height_scale, 1.0, openness())


func _pose_radius() -> float:
	if phase == Phase.COLLAPSING:
		return lerpf(_from_radius, _config.chute_collapse_end_radius_scale, _collapse_ease())
	return _open_radius() if phase != Phase.HIDDEN else _config.chute_deploy_start_radius_scale


func _pose_height() -> float:
	if phase == Phase.COLLAPSING:
		return lerpf(_from_height, _config.chute_collapse_end_height_scale, _collapse_ease())
	return _open_height() if phase != Phase.HIDDEN else _config.chute_deploy_start_height_scale
