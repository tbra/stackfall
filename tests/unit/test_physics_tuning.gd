extends GutTest
## Bontago-xtq.17 (owner playtest 2026-09-23: "heavier and more bouncy, but a
## dropped block shouldn't just bounce straight up again"): config/
## PhysicsTuning.gd's new rebound_damping field, the shipped config/
## physics_presets/*.tres the owner can A/B from ui/TuningPanel.gd's Physics
## tab (see test_tuning_panel.gd for the panel-level tests), and Block.
## _damp_rebound()'s pure scaling rule.

const EXPORT_USAGE_MASK: int = PROPERTY_USAGE_STORAGE | PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_SCRIPT_VARIABLE


func _is_exported_field(prop: Dictionary) -> bool:
	return (int(prop.get("usage", 0)) & EXPORT_USAGE_MASK) == EXPORT_USAGE_MASK


# --- rebound_damping ---------------------------------------------------------

func test_rebound_damping_default_is_a_valid_damping_factor() -> void:
	var fresh: PhysicsTuning = PhysicsTuning.new()
	assert_gte(fresh.rebound_damping, 0.0, "a scale factor is never negative")
	assert_lte(fresh.rebound_damping, 1.0, "a factor above 1 would amplify the bounce")
	var live: PhysicsTuning = load("res://config/physics_tuning.tres")
	assert_between(live.rebound_damping, 0.0, 1.0, "the shipped tuning is a valid factor too")
	# The default drives Block._damp_rebound: the result is the fresh bounce scaled by it.
	assert_almost_eq(Block._damp_rebound(-2.0, 4.0, fresh.rebound_damping, 0.15), 4.0 * fresh.rebound_damping, 0.0001)


# --- The shipped presets ------------------------------------------------------

## Every shipped preset must supply a sane value for every exported field of the live
## tuning, so an A/B swap from the Physics tab can never leave a field NaN, negative
## where a magnitude is expected, or missing (a stale preset after a new field).
func test_every_shipped_preset_covers_every_tuning_field_with_finite_values() -> void:
	var live: PhysicsTuning = load("res://config/physics_tuning.tres")
	var dir: DirAccess = DirAccess.open("res://config/physics_presets")
	assert_not_null(dir, "fixture: the presets directory opens")
	var presets: int = 0
	for file: String in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var preset: PhysicsTuning = load("res://config/physics_presets/%s" % file) as PhysicsTuning
		assert_not_null(preset, "%s loads as PhysicsTuning" % file)
		if preset == null:
			continue
		presets += 1
		var checked_any: bool = false
		for prop: Dictionary in live.get_property_list():
			if not _is_exported_field(prop):
				continue
			checked_any = true
			var prop_name: String = str(prop.get("name", ""))
			var value: Variant = preset.get(prop_name)
			assert_not_null(value, "%s defines %s" % [file, prop_name])
			if value is float:
				assert_true(is_finite(float(value)), "%s.%s is finite" % [file, prop_name])
		assert_true(checked_any, "fixture: PhysicsTuning must have at least one exported field.")
		assert_between(preset.rebound_damping, 0.0, 1.0, "%s: rebound_damping is a valid factor" % file)
		assert_gt(preset.cube_mass, 0.0, "%s: bodies have mass" % file)
	assert_gt(presets, 0, "fixture: presets found")


func test_heavy_presets_are_heavier_and_damp_the_rebound() -> void:
	var current: PhysicsTuning = load("res://config/physics_presets/current.tres")
	var bouncy: PhysicsTuning = load("res://config/physics_presets/heavy_bouncy.tres")
	var damped: PhysicsTuning = load("res://config/physics_presets/heavy_damped.tres")
	for preset: PhysicsTuning in [bouncy, damped]:
		assert_gt(preset.cube_mass, current.cube_mass, "a 'heavy' preset must raise cube_mass.")
		assert_gt(preset.gravity_multiplier, current.gravity_multiplier, "a 'heavy' preset must raise gravity_multiplier.")
		assert_lt(preset.rebound_damping, 1.0, "a 'heavy' preset must damp the straight-up rebound below the pass-through default.")
	assert_gt(bouncy.block_bounce, current.block_bounce, "heavy_bouncy should lean on more restitution for its liveliness.")


# --- Block._damp_rebound()'s pure scaling rule (no physics step required) ---
#
# noise_floor is PhysicsTuning.sleep_linear_threshold (0.15 by default) --
# see game/Block._integrate_forces()'s DECISION for why a noise floor is
# required at all (bench_tower.tscn's 40-cube tower collapsed without one:
# a resting stack's solver-noise velocity flickers across zero every step,
## and reacting to that as "a bounce" fed it a stream of unwanted scripted
# velocity writes).

func test_damp_rebound_scales_a_fresh_bounce() -> void:
	assert_almost_eq(
		Block._damp_rebound(-2.0, 4.0, 0.25, 0.15), 1.0, 0.0001,
		"a falling-to-rising transition past the noise floor should be scaled by rebound_damping."
	)


func test_damp_rebound_leaves_a_continued_fall_alone() -> void:
	assert_almost_eq(Block._damp_rebound(-2.0, -1.0, 0.25, 0.15), -1.0, 0.0001, "still falling must not be touched.")


func test_damp_rebound_leaves_a_continued_rise_alone() -> void:
	assert_almost_eq(
		Block._damp_rebound(1.0, 2.0, 0.25, 0.15), 2.0, 0.0001,
		"already rising (a later tick of the same bounce, not a fresh one) must not be re-scaled."
	)


func test_damp_rebound_leaves_rest_alone() -> void:
	assert_almost_eq(Block._damp_rebound(0.0, 0.0, 0.25, 0.15), 0.0, 0.0001)


func test_damp_rebound_is_a_no_op_at_the_default_multiplier() -> void:
	assert_almost_eq(Block._damp_rebound(-5.0, 4.0, 1.0, 0.15), 4.0, 0.0001)


## Regression for the bench_tower.tscn collapse: a sign flip that never
## clears the noise floor on either side (a resting stack's solver jitter)
## must not be treated as a bounce, however small rebound_damping is.
func test_damp_rebound_ignores_a_flicker_within_the_noise_floor() -> void:
	assert_almost_eq(Block._damp_rebound(-0.01, 0.01, 0.0, 0.15), 0.01, 0.0001)
	assert_almost_eq(Block._damp_rebound(-0.2, 0.1, 0.0, 0.15), 0.1, 0.0001, "prev crosses the floor but current doesn't.")
	assert_almost_eq(Block._damp_rebound(-0.1, 0.2, 0.0, 0.15), 0.2, 0.0001, "current crosses the floor but prev doesn't.")


func test_damp_rebound_scales_once_both_sides_clear_the_noise_floor() -> void:
	assert_almost_eq(Block._damp_rebound(-0.2, 0.2, 0.0, 0.15), 0.0, 0.0001)
