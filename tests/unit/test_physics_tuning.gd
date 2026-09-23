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


# --- rebound_damping's default is a byte-identical no-op --------------------

func test_rebound_damping_defaults_to_one_a_no_op_multiplier() -> void:
	var fresh: PhysicsTuning = PhysicsTuning.new()
	assert_almost_eq(fresh.rebound_damping, 1.0, 0.0001)


# --- The shipped presets ------------------------------------------------------

## "current" must stay byte-identical to config/physics_tuning.tres's own
## defaults (CLAUDE.md/the design brief: "Keep default behaviour byte-
## identical unless the owner picks a preset"), field for field, not just on
## the fields this package happened to touch.
func test_current_preset_matches_the_shipped_physics_tuning() -> void:
	var live: PhysicsTuning = load("res://config/physics_tuning.tres")
	var current: PhysicsTuning = load("res://config/physics_presets/current.tres")
	var checked_any: bool = false
	for prop: Dictionary in live.get_property_list():
		if not _is_exported_field(prop):
			continue
		checked_any = true
		var prop_name: String = str(prop.get("name", ""))
		assert_almost_eq(
			float(live.get(prop_name)), float(current.get(prop_name)), 0.0001,
			"%s should be byte-identical between physics_tuning.tres and the 'current' preset" % prop_name
		)
	assert_true(checked_any, "fixture: PhysicsTuning must have at least one exported field.")


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
