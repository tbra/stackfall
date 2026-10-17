class_name TiltTuning
extends Resource
## Spring-damper tunables for the SPECIALS_ONLY disk tilt (spec 1.7, 1.2, 2.7).
## Loaded once as config/physics/tilt_tuning.tres and read only by Field; nothing else
## should reach into a special's own params to tilt the disk directly -- that
## is exactly what Field.apply_tilt_impulse() is for.

## Spec 2.7 "12 deg maximum... implementation choice, not an original
## measurement". No single impulse, or any number of impulses landing in one
## physics frame, may push the tilt vector's magnitude past this.
@export var max_tilt_deg: float = 12.0

## Spec 2.7 "approximately 4 s return". The tilt vector is driven by a
## critically damped spring (spec 2.7: "a critically damped spring on its
## tilt vector"), so this is read as the spring's characteristic decay time,
## not a literal settle-to-zero deadline -- a real damped exponential never
## reaches exactly zero.
@export var return_time_constant_s: float = 4.0

## PHYSICAL_BALANCE tilt (spec 1.7/1.2), a DECISION: a kinematic-torque approximation
## that scales BlockRegistry.settled_torque_samples()'s summed mass * disk-local
## lever-arm (kg*m) into the acceleration term the spring already integrates in
## Field._update_tilt(), so the steady tilt under a constant lopsided load settles
## at (gain * sum) / spring_stiffness() before max_tilt_deg's clamp engages. Zero
## disables the term (the match then tilts only from apply_tilt_impulse() specials,
## as SPECIALS_ONLY does).
##
## DECISION: spec 1.7 flags PHYSICAL_BALANCE's feasibility as still to be
## benchmarked, so there is no original value to match. At rest the spring's
## equilibrium is tilt_eq_rad == gain * torque_sum / spring_stiffness(); a 15-block
## tower at a 4 m lever arm sums to 60 kg*m, and spring_stiffness() is 0.0625 at the
## default 4 s constant. Gains of 0.0005 (tilt pinned at the clamp) and 0.00005
## (tilt_eq 2.75 deg) both toppled the benchmark tower: a 15-cube tower on unglued
## rigid-body joints starts a runaway collapse near 2.3 deg, well below the naive
## whole-column tipping angle, because each cube-cube interface shears
## independently. 0.00002 gives tilt_eq about 1.1 deg, roughly half that ceiling;
## "stays standing" wins over the original 2-5 deg target. The max_tilt_deg clamp
## already bounds any load, and the limit is structural (the tower's joints), so a
## second angle cap would not help.
@export var physical_balance_torque_gain: float = 0.00002

## DECISION: Field extends AnimatableBody3D, and sync_to_physics writes `transform`
## every physics tick (Field._apply_tilt_transform(), called unconditionally from
## _update_tilt()). A critically damped spring only approaches its target
## asymptotically, so _tilt_velocity stays nonzero forever, Jolt keeps treating the
## kinematic body as moving, and every block resting on it stays awake. So
## _update_tilt() snaps _tilt_velocity to Vector2.ZERO once it is below a floor;
## then _tilt stops changing bit-for-bit, the transform write is identical each
## tick, and blocks can sleep.
##
## The floor must be relative, not an absolute rad/s: a step response toward tilt_eq
## has velocity(t) == tilt_eq * omega^2 * t * e^(-omega*t), so its scale follows the
## load. Dividing by tilt_eq gives ratio(t) == omega^2 * t * e^(-omega*t), a function
## of omega and time only. So the snap needs BOTH |_tilt_velocity| <
## tilt_settle_relative_epsilon * omega * scale AND the remaining position error to
## the spring's target < tilt_settle_relative_epsilon * scale, where scale ==
## max(|target_tilt|, tilt_settle_floor_rad). Scale uses the target, not the live
## |_tilt|: after a clamp release |_tilt| is large while the target is near zero,
## and scaling by it snapped the disk to zero velocity at the clamp ceiling forever
## (see Field._update_tilt()'s DECISION). The position gate keeps the early
## build-up of a step response (velocity starts near zero) from being snapped away.
##
## tilt_settle_relative_epsilon = 0.01 crosses at about 27 s for the default 4 s
## constant (omega 0.25 rad/s), inside the benchmark's 40 s run, while at 0.5 s the
## ratio is about 0.11, so early tilt in small-load tests is untouched.
## tilt_settle_floor_rad = 0.0001 rad (~0.0057 deg) keeps the scale from collapsing
## to zero when the target is exactly zero (SPECIALS_ONLY free decay); it is
## visually level.
@export var tilt_settle_relative_epsilon: float = 0.01
@export var tilt_settle_floor_rad: float = 0.0001

## Rest deadband. Once |_tilt_velocity| < rest_velocity_rad_s and the
## error toward the spring's target is < rest_position_rad for rest_hold_s, Field
## zeroes the velocity and stops writing its transform (the kinematic disc is truly
## static, so blocks on it can sleep). It wakes only when the target moves more than
## rest_wake_position_rad from the tilt (hysteresis: wake > rest) or on an impulse.
## Defaults: 0.0002 rad = 0.011 deg (2 mm at the 10 m rim), 0.0012 rad/s = 0.07 deg/s,
## wake 0.0006 rad = 0.034 deg. All far below any visible tilt motion.
@export var rest_velocity_rad_s: float = 0.0012
@export var rest_position_rad: float = 0.0002
@export var rest_wake_position_rad: float = 0.0006
@export var rest_hold_s: float = 0.5

## DECISION: "critically damped" fixes the damping ratio (zeta = 1) but not a natural
## frequency; a critically damped system has no oscillation period to point at. This
## reads return_time_constant_s the control-theory way: for x'' + 2*omega*x' +
## omega^2*x = 0, the free response (A + B*t) * e^(-omega*t) decays at rate omega, so
## 1/omega is the time constant. omega = 1 / return_time_constant_s, stiffness =
## omega^2 and damping = 2*omega, giving one pair for any constant with no second
## exported number that could fall out of sync.

func angular_frequency() -> float:
	return 1.0 / return_time_constant_s


func spring_stiffness() -> float:
	var omega: float = angular_frequency()
	return omega * omega


func spring_damping() -> float:
	return 2.0 * angular_frequency()


func max_tilt_rad() -> float:
	return deg_to_rad(max_tilt_deg)
