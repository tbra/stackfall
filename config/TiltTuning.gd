class_name TiltTuning
extends Resource
## Spring-damper tunables for the SPECIALS_ONLY disk tilt (spec 2.1, 2.7, 3.5).
## Loaded once as config/tilt_tuning.tres and read only by Field; nothing else
## should reach into a special's own params to tilt the disk directly -- that
## is exactly what Field.apply_tilt_impulse() is for.

## Spec 3.5 "12 deg maximum... implementation choice, not an original
## measurement". No single impulse, or any number of impulses landing in one
## physics frame, may push the tilt vector's magnitude past this.
@export var max_tilt_deg: float = 12.0

## Spec 3.5 "approximately 4 s return". The tilt vector is driven by a
## critically damped spring (spec 3.5: "a critically damped spring on its
## tilt vector"), so this is read as the spring's characteristic decay time,
## not a literal settle-to-zero deadline -- a real damped exponential never
## reaches exactly zero.
@export var return_time_constant_s: float = 4.0

## DECISION (config/TiltTuning.gd, Bontago M4 P0b): "critically damped" fixes
## the damping ratio (zeta = 1) but return_time_constant_s alone doesn't by
## itself fix a natural frequency unless a convention is picked for what
## "return time constant" means for a critically damped system -- unlike an
## underdamped one, there is no single oscillation period to point at. This
## reads it the way control theory usually does: for x'' + 2*omega*x'
## + omega^2*x = 0 (unit mass, damping ratio 1, x the 2-axis tilt vector
## Field integrates), the free response is (A + B*t) * e^(-omega*t) -- every
## term decays at rate omega, so 1/omega is the exponential's time constant.
## Setting omega = 1 / return_time_constant_s and reading the ODE's own
## coefficients off as stiffness = omega^2, damping = 2*omega (both per unit
## "mass" of the dimensionless tilt vector) gives exactly one stiffness/
## damping pair for any return_time_constant_s, with no second exported
## number that could ever fall out of sync with the one the design actually
## calls out.

func angular_frequency() -> float:
	return 1.0 / return_time_constant_s


func spring_stiffness() -> float:
	var omega: float = angular_frequency()
	return omega * omega


func spring_damping() -> float:
	return 2.0 * angular_frequency()


func max_tilt_rad() -> float:
	return deg_to_rad(max_tilt_deg)
