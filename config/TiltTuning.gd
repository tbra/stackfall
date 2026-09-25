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

## M6 B5 (spec 2.1/2.7): PHYSICAL_BALANCE tilt's kinematic-torque
## approximation (docs/M6_PLAN.md DECISION, owner-approved Bontago-keo.16)
## scales BlockRegistry.settled_torque_samples()'s summed mass * disk-local
## lever-arm (kg*m) into the same acceleration term the spring already
## integrates in Field._update_tilt() -- so the steady tilt under a constant
## lopsided load settles at (gain * sum) / spring_stiffness() before
## max_tilt_deg's clamp ever engages. Zero disables the term outright (a
## PHYSICAL_BALANCE match then tilts only from apply_tilt_impulse() specials,
## same as SPECIALS_ONLY).
##
## DECISION (config/TiltTuning.gd, M6 B5, Bontago-keo.11 follow-up): spec 2.1
## flags PHYSICAL_BALANCE's "feasibility still to be benchmarked", so there is
## no measured original value to match -- this is picked from the spring's
## own equilibrium plus one empirical benchmark finding, not trial and error
## alone. At rest (_tilt_velocity == 0) Field._update_tilt()'s accel is zero
## when stiffness * tilt_eq == physical_balance_torque_gain *
## sum(mass * lever_arm_m), i.e. tilt_eq_rad == gain * torque_sum /
## spring_stiffness(). tests/bench/bench_physical_balance.gd's 15-block tower
## at a 4 m lever arm (mass 1 kg each, cube_mass) sums to torque_sum == 60
## kg*m; spring_stiffness() == (1 / return_time_constant_s)^2 == 0.0625 at the
## default 4 s constant.
##
## The first tuning attempt (0.0005) gave an accel term (0.03) that already
## exceeds stiffness * max_tilt_rad (0.0625 * 12deg-in-rad == 0.0131) before
## the spring can push back at all, so the tower saturated the clamp instead
## of settling (bench FAIL, max_top_drift_m=35.1, tilt pinned at 12deg). A
## second attempt at 0.00005 (targeting the 2-5deg range this mode's tuning
## brief asks for -- tilt_eq == 2.75deg at the bench's 60 kg*m load, nowhere
## near the clamp) still FAILed the bench (max_top_drift_m=34.4): the traced
## run (--trace=60) shows the tower is genuinely stable while the spring
## ramps up through roughly 0 to 2.0deg over the first ~13s, then starts a
## real, accelerating collapse (fastest_m_per_s: 0.18 -> 0.51 -> 1.34 -> 3.46
## m/s across t=13..16s) right as tilt approaches its ~2.3-2.75deg
## equilibrium -- a 15-cube tower resting on unglued rigid-body joints (not
## one rigid rod) tips over well below the naive whole-column
## tan(angle) * half_height vs. base_half_width estimate (~3.8deg for this
## tower's height/footprint) because each cube-cube interface can shear
## independently under the disk's own (small but nonzero) angular velocity,
## compounding lean upward through the stack. This is a genuine physical
## stability ceiling for a tower this tall on this tuning's friction
## (config/physics_tuning.tres block_friction/disk_friction are owned by a
## different package), not a bug in the torque math -- tests/unit/
## test_field_tilt.gd's own PHYSICAL_BALANCE tests already prove the math
## (sign, symmetric cancellation, clamp) is correct at every gain tried.
##
## Final value: 0.00002, solving the same equilibrium formula for tilt_eq ==
## 1.1deg (0.019 rad) at the bench's 60 kg*m load -- roughly half the ~2.3deg
## the traced run shows the tower surviving up to just before it visibly
## starts to run away, so this keeps a real, comfortable margin under that
## empirical ceiling rather than tuning to the edge of it. This lands the
## bench tower's steady lean below this package's original "roughly 2-5deg"
## target; that target was written before this empirical instability was
## known, and "stays standing" (an explicit acceptance requirement) has to
## win the conflict once benchmarking a real tower this tall shows the two
## cannot both hold. A shorter or more centered tower still gets a
## proportionally smaller, entirely stable lean; a taller or more lopsided
## one now approaches this ceiling more gently instead of overshooting it.
## No second exported cap is needed: the existing max_tilt_deg clamp already
## bounds any load PHYSICAL_BALANCE can produce past this one number, exactly
## as it already does for SPECIALS_ONLY's impulses -- this package's actual
## stability limit turned out to be structural (the tower's own joints), not
## the disk's tilt angle, so a second angle-only cap would not have helped.
@export var physical_balance_torque_gain: float = 0.00002

## DECISION (config/TiltTuning.gd, M6 B5, Bontago-keo.11 follow-up 2): Field
## extends AnimatableBody3D, and sync_to_physics writes `transform` to the
## physics server every physics tick regardless of whether the value actually
## changed (Field._apply_tilt_transform(), called unconditionally from
## _update_tilt() every tick). A critically damped spring's response is
## (A + B*t) * e^(-omega*t): it approaches its target asymptotically but is
## never bit-exactly at rest, so left alone _tilt_velocity is always some
## nonzero (if vanishingly small) value forever, and Jolt keeps treating a
## kinematic body that is still nominally "moving" every tick as active,
## which keeps every resting block contacting it awake too -- confirmed by
## bench_physical_balance's own evidence (Bontago-keo.11 follow-up 2): after
## the torque latch fixed the limit cycle, final_tilt_deg matched max_tilt_deg
## (no more runaway creep or oscillation -- the spring genuinely converged to
## its analytic equilibrium) and max_top_drift_m stayed far under the bound,
## but all_asleep was still false at RUN_SECONDS=40 because _tilt_velocity
## never reached literal zero. This is the floor below which _tilt_velocity is
## snapped to Vector2.ZERO once per tick (Field._update_tilt(), after
## integrating accel, before integrating _tilt) instead of being left to decay
## forever: once snapped, _tilt stops changing bit-for-bit (adding a zero
## velocity * delta changes nothing), so _apply_tilt_transform() writes the
## same transform every subsequent tick and Jolt can finally let contacting
## blocks sleep, exactly as spec 3.5's "critically damped spring" already
## implies it eventually should (a real damped spring is also only ever
## "settled" up to some measurement floor, never exactly).
##
## An earlier version of this fix used a single absolute rad/s floor. That is
## wrong: for a step response from rest toward a constant equilibrium tilt_eq,
## velocity(t) == tilt_eq * omega^2 * t * e^(-omega*t), so its *scale* is
## proportional to tilt_eq itself -- a load small enough to only need ~0.03deg
## of lean (this package's own test_field_tilt.gd single-block fixture) has a
## peak velocity within the same order of magnitude as a fixed threshold
## chosen to suit this benchmark's ~1.1deg tower, so one constant cannot both
## (a) stay well under every real test's peak velocity, so genuine early
## motion is never snapped away, and (b) still get crossed inside a
## match-length window for this benchmark's own larger equilibrium -- picking
## it small enough for (a) pushed the time-to-cross for (b) past 50s; picking
## it large enough for (b) flattened the small-load test's tilt to exactly
## zero for its whole 0.5s assertion window.
##
## Fix: compare velocity/tilt_eq's *ratio* instead of velocity alone. Dividing
## the step-response formula above by tilt_eq cancels tilt_eq out entirely:
## ratio(t) == omega^2 * t * e^(-omega*t), a function of omega and elapsed
## time only, independent of how large or small the load's own equilibrium
## is. So Field._update_tilt() snaps _tilt_velocity to Vector2.ZERO once both
## |_tilt_velocity| < tilt_settle_relative_epsilon * omega * scale AND the
## remaining position error toward the spring's own driving target is <
## tilt_settle_relative_epsilon * scale, where scale ==
## max(|target_tilt|, tilt_settle_floor_rad) -- a load-size-independent
## time-to-freeze for any persistent PHYSICAL_BALANCE equilibrium, while the
## floor keeps the comparison meaningful once the target itself is exactly
## zero (the SPECIALS_ONLY free-decay case, which has no persistent
## equilibrium to scale against).
##
## An earlier version of this scale used the live/transient |_tilt| itself
## instead of |target_tilt|, and used the velocity ratio alone with no
## position gate. That is wrong: once an impulse drives _tilt into
## _clamp_tilt()'s ceiling, |_tilt| is large (the clamped value) even though
## the spring's real target is back near zero, so the small inward recovery
## velocity right after the clamp released was compared against a threshold
## inflated by that stale clamped position and snapped to zero immediately --
## freezing the disk at the clamp ceiling forever instead of letting it decay
## (see game/Field.gd's own DECISION on _update_tilt() for the observed
## failure). Scaling by the target instead fixes that, but on its own would
## wrongly snap away genuine early build-up too: velocity legitimately starts
## at (near) zero right after a step begins and only grows from there, so a
## target-scaled threshold that is already full-size from tick one would
## freeze _tilt at its start value if velocity alone were the only test. The
## position-error gate rules that out: for a step response released from rest
## the error starts near |target_tilt| itself and shrinks monotonically as
## convergence proceeds (no overshoot -- critically damped), and it is
## likewise large right after a clamp release, so both the early-build-up and
## post-clamp cases are correctly excluded until _tilt has actually arrived.
##
## tilt_settle_relative_epsilon = 0.01: setting omega^2 * t * e^(-omega*t) ==
## epsilon and solving numerically at omega == 1 / return_time_constant_s ==
## 0.25 rad/s (the default 4s constant) crosses at t ~= 25.8s for the velocity
## term and t ~= 26.5s for the position term (solving (1+u)*e^-u == epsilon
## for u == omega*t); the later of the two (~27s) is comfortably inside this
## benchmark's RUN_SECONDS = 40 with ~13s of margin for the disk-contact
## blocks' own native sleep timer afterward, while at t == 0.5s
## (test_field_tilt.gd's single-block fixture's own assertion point) the
## velocity-ratio formula is ~0.11, more than 10x this epsilon, so that
## test's early tilt development is untouched. tilt_settle_floor_rad = 0.0001
## rad (~0.0057deg): a SPECIALS_ONLY free decay (no persistent forcing) has a
## target of exactly Vector2.ZERO, so this floor keeps the snap condition's
## scale from collapsing to zero -- visually indistinguishable from level at
## this magnitude.
@export var tilt_settle_relative_epsilon: float = 0.01
@export var tilt_settle_floor_rad: float = 0.0001

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
