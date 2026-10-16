extends GutTest
## "heavier and more bouncy, but a
## dropped block shouldn't just bounce straight up again": config/
## PhysicsTuning.gd's new rebound_damping field, the shipped config/
## physics_presets/*.tres the owner can A/B from ui/debug/TuningPanel.gd's Physics
## tab (see test_tuning_panel.gd for the panel-level tests).

const EXPORT_USAGE_MASK: int = PROPERTY_USAGE_STORAGE | PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_SCRIPT_VARIABLE


func _is_exported_field(prop: Dictionary) -> bool:
	return (int(prop.get("usage", 0)) & EXPORT_USAGE_MASK) == EXPORT_USAGE_MASK


# --- rebound_damping ---------------------------------------------------------

## Every shipped preset must supply a sane value for every exported field of the live
## tuning, so an A/B swap from the Physics tab can never leave a field NaN, negative
## where a magnitude is expected, or missing (a stale preset after a new field).
func test_every_shipped_preset_covers_every_tuning_field_with_finite_values() -> void:
	var live: PhysicsTuning = load("res://config/physics/physics_tuning.tres")
	var dir: DirAccess = DirAccess.open("res://config/physics/presets")
	assert_not_null(dir, "fixture: the presets directory opens")
	var presets: int = 0
	for file: String in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var preset: PhysicsTuning = load("res://config/physics/presets/%s" % file) as PhysicsTuning
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
	var current: PhysicsTuning = load("res://config/physics/presets/current.tres")
	var bouncy: PhysicsTuning = load("res://config/physics/presets/heavy_bouncy.tres")
	var damped: PhysicsTuning = load("res://config/physics/presets/heavy_damped.tres")
	for preset: PhysicsTuning in [bouncy, damped]:
		assert_gt(preset.cube_mass, current.cube_mass, "a 'heavy' preset must raise cube_mass.")
		assert_gt(preset.gravity_multiplier, current.gravity_multiplier, "a 'heavy' preset must raise gravity_multiplier.")
		assert_lt(preset.rebound_damping, 1.0, "a 'heavy' preset must damp the straight-up rebound below the pass-through default.")
	assert_gt(bouncy.block_bounce, current.block_bounce, "heavy_bouncy should lean on more restitution for its liveliness.")
