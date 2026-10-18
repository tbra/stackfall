extends GutTest
## game/sky/SkyAmbientLife.gd: the day/night swap of the ambient life with hysteresis
## thresholds read from the SkyCycleDef.

const SUNSET_PATH: String = "res://config/sky/themes/sunset.tres"
const NIGHT_PATH: String = "res://config/sky/themes/night.tres"
const DISC_RADIUS_M: float = 30.0
const MIX_BETWEEN: float = 0.5
const MIX_FULL_NIGHT: float = 1.0


func _def() -> SkyCycleDef:
	var sunset: SkyThemeDef = load(SUNSET_PATH) as SkyThemeDef
	var night: SkyThemeDef = load(NIGHT_PATH) as SkyThemeDef
	return SkyThemeMigration.cycle_from_themes(sunset, sunset, night)


func _built() -> Array:
	var parent: Node3D = Node3D.new()
	add_child_autofree(parent)
	var life: SkyAmbientLife = SkyAmbientLife.new()
	life.build(parent, null, null)
	return [life, parent]


func test_build_creates_the_three_named_children() -> void:
	var parent: Node3D = (_built()[1] as Node3D)
	assert_true(parent.get_node_or_null("DistantBirds") is DistantBirds)
	assert_true(parent.get_node_or_null("PerchingBirds") is PerchingBirds)
	assert_true(parent.get_node_or_null("Fireflies") is Fireflies)


func test_swap_uses_hysteresis_thresholds_from_the_def() -> void:
	var made: Array = _built()
	var life: SkyAmbientLife = made[0] as SkyAmbientLife
	var def: SkyCycleDef = _def()
	life.configure(def, null, DISC_RADIUS_M)
	assert_false(life.is_night())
	life.update_night(def, def.life_night_on_mix - 0.01, null, DISC_RADIUS_M)
	assert_false(life.is_night(), "below the on threshold stays day")
	life.update_night(def, def.life_night_on_mix + 0.01, null, DISC_RADIUS_M)
	assert_true(life.is_night())
	life.update_night(def, def.life_night_off_mix + 0.01, null, DISC_RADIUS_M)
	assert_true(life.is_night(), "between the thresholds keeps night")
	life.update_night(def, def.life_night_off_mix - 0.01, null, DISC_RADIUS_M)
	assert_false(life.is_night())


func test_birds_hide_at_night_and_configure_resets_to_day() -> void:
	var made: Array = _built()
	var life: SkyAmbientLife = made[0] as SkyAmbientLife
	var birds: DistantBirds = (made[1] as Node3D).get_node("DistantBirds") as DistantBirds
	var def: SkyCycleDef = _def()
	life.configure(def, null, DISC_RADIUS_M)
	assert_true(birds.visible)
	life.update_night(def, MIX_FULL_NIGHT, null, DISC_RADIUS_M)
	assert_false(birds.visible, "no distant birds at night")
	life.configure(def, null, DISC_RADIUS_M)
	assert_false(life.is_night(), "configure restarts from the day set")
	assert_true(birds.visible)
