extends GutTest
## CloudSea.apply_frame() writes the puff channel of an evaluated SkyFrame: the same uniforms
## set_cycle_appearance() + apply_storm_tint() wrote from the themes (plan 4.1 steps 6-7), with
## quirks Q1 (the storm re-copies the shared sky set) and Q3 (the far-fade gradient is only copied
## at configure_cycle() and on a storm). configure_cycle() duplicates the def's puff material.

const TONES: Array[StringName] = [&"shadow_color", &"mid_color", &"lit_color", &"rim_color"]
const SKY_TONES: Array[StringName] = [&"cloud_shadow_color", &"cloud_mid_color", &"cloud_lit_color", &"cloud_rim_color"]
const GRADE: Array[StringName] = [&"grade_dark", &"grade_mid", &"grade_light"]
const NIGHT_WEIGHT: float = 0.6
const STORM_AMOUNT: float = 0.5
const DIRECTION: Vector3 = Vector3(0.3, 0.8, 0.2)
const SEA_COUNT: int = 2

var _day: SkyThemeDef = null
var _night: SkyThemeDef = null
var _storm: SkyThemeDef = null


func before_each() -> void:
	_day = Skybox.load_theme("sunset")
	_night = Skybox.load_theme("night")
	_storm = Skybox.load_theme("storm")


func _cycle() -> SkyCycleDef:
	return SkyThemeMigration.cycle_from_themes(_day, Skybox.load_theme("dawn"), _night)


func _sea(snapshot: SkyFrame) -> CloudSea:
	var sea: CloudSea = CloudSea.new()
	add_child_autofree(sea)
	var def: SkyCycleDef = _cycle()
	def.cloud_clump_count = SEA_COUNT
	def.cloud_bank_count = 0
	def.proc_far_count = 0
	sea.configure_cycle(def, snapshot, 1.0, 1)
	return sea


func _snapshot_of(sky: ShaderMaterial) -> SkyFrame:
	var snapshot: SkyFrame = SkyFrame.new()
	for parameter: StringName in CloudSea.SHARED_SKY_PARAMETERS:
		var value: Variant = sky.get_shader_parameter(parameter)
		if value != null:
			snapshot.puff_shared[parameter] = value
	return snapshot


## The cycle frame at night weight NIGHT_WEIGHT, built field by field from the theme materials the
## way plan 4.1 step 6 says (lerp toward night by `night`).
func _tick_frame() -> SkyFrame:
	var frame: SkyFrame = SkyFrame.new()
	var day_puff: ShaderMaterial = _day.cloud_puff_material as ShaderMaterial
	var night_puff: ShaderMaterial = _night.cloud_puff_material as ShaderMaterial
	var day_sky: ShaderMaterial = _day.sky_material as ShaderMaterial
	var night_sky: ShaderMaterial = _night.sky_material as ShaderMaterial
	frame.night = NIGHT_WEIGHT
	frame.puff_shadow_color = _mix(day_puff, night_puff, &"shadow_color")
	frame.puff_mid_color = _mix(day_puff, night_puff, &"mid_color")
	frame.puff_lit_color = _mix(day_puff, night_puff, &"lit_color")
	frame.puff_rim_color = _mix(day_puff, night_puff, &"rim_color")
	frame.puff_cloud_shadow_color = _mix(day_sky, night_sky, &"cloud_shadow_color")
	frame.puff_cloud_mid_color = _mix(day_sky, night_sky, &"cloud_mid_color")
	frame.puff_cloud_lit_color = _mix(day_sky, night_sky, &"cloud_lit_color")
	frame.puff_cloud_rim_color = _mix(day_sky, night_sky, &"cloud_rim_color")
	frame.puff_grade_dark = night_sky.get_shader_parameter(&"grade_dark") as Color
	frame.puff_grade_mid = night_sky.get_shader_parameter(&"grade_mid") as Color
	frame.puff_grade_light = night_sky.get_shader_parameter(&"grade_light") as Color
	frame.puff_grade_amount = NIGHT_WEIGHT
	frame.puff_sea_color_near = _day.proc_sea_color_near.lerp(_night.proc_sea_color_near, NIGHT_WEIGHT)
	frame.puff_sea_color_far = _day.proc_sea_color_far.lerp(_night.proc_sea_color_far, NIGHT_WEIGHT)
	frame.puff_light_direction = DIRECTION
	frame.puff_sun_direction = DIRECTION
	return frame


func _mix(day: ShaderMaterial, night: ShaderMaterial, parameter: StringName) -> Color:
	return (day.get_shader_parameter(parameter) as Color).lerp(night.get_shader_parameter(parameter) as Color, NIGHT_WEIGHT)


## The same frame as the old writers produced them, applied to a second sea for comparison.
func _old_writers_sea(snapshot: SkyFrame, storm: bool, blended_sky: ShaderMaterial) -> CloudSea:
	var sea: CloudSea = _sea(snapshot)
	sea.set_cycle_appearance(_day, _night, NIGHT_WEIGHT, DIRECTION)
	if storm:
		sea.apply_storm_tint(_day, _storm, STORM_AMOUNT, blended_sky)
	return sea


func _blended_sky() -> ShaderMaterial:
	var sky: ShaderMaterial = (_day.sky_material as ShaderMaterial).duplicate() as ShaderMaterial
	sky.set_shader_parameter(&"exposure", 0.37)
	sky.set_shader_parameter(&"proc_sea_color_near", Color(0.2, 0.3, 0.4))
	sky.set_shader_parameter(&"proc_sea_color_far", Color(0.5, 0.1, 0.2))
	sky.set_shader_parameter(&"proc_zenith_color", Color(0.1, 0.1, 0.3))
	sky.set_shader_parameter(&"sun_direction", Vector3(0.0, 0.0, 1.0))
	return sky


func _assert_same_uniforms(a: CloudSea, b: CloudSea, names: Array[StringName], label: String) -> void:
	for parameter: StringName in names:
		assert_eq(a.puff_material().get_shader_parameter(parameter), b.puff_material().get_shader_parameter(parameter),
				"%s: %s" % [label, parameter])


func _compared_names() -> Array[StringName]:
	var names: Array[StringName] = []
	names.append_array(TONES)
	names.append_array(SKY_TONES)
	names.append_array(GRADE)
	names.append_array([&"grade_amount", &"light_direction"])
	names.append_array(CloudSea.SHARED_SKY_PARAMETERS)
	return names


func test_apply_frame_writes_what_the_cycle_appearance_wrote() -> void:
	var snapshot: SkyFrame = _snapshot_of(_day.sky_material as ShaderMaterial)
	var old_sea: CloudSea = _old_writers_sea(snapshot, false, null)
	var sea: CloudSea = _sea(snapshot)
	sea.apply_frame(_tick_frame())
	_assert_same_uniforms(sea, old_sea, _compared_names(), "no storm")
	assert_eq(sea.puff_material().get_shader_parameter(&"grade_amount"), NIGHT_WEIGHT)
	assert_eq(sea.puff_material().get_shader_parameter(&"light_direction"), DIRECTION)


func test_apply_frame_in_a_storm_matches_apply_storm_tint_including_the_shared_copy() -> void:
	var blended: ShaderMaterial = _blended_sky()
	var snapshot: SkyFrame = _snapshot_of(_day.sky_material as ShaderMaterial)
	var old_sea: CloudSea = _old_writers_sea(snapshot, true, blended)
	var frame: SkyFrame = _tick_frame()
	# Step 7: the storm frame carries the lerped tones and the blended sky's shared set (Q1).
	frame.storm_amount = STORM_AMOUNT
	frame.puff_shared = _snapshot_of(blended).puff_shared
	var puffs: ShaderMaterial = _storm.cloud_puff_material as ShaderMaterial
	var storm_sky: ShaderMaterial = _storm.sky_material as ShaderMaterial
	frame.puff_shadow_color = frame.puff_shadow_color.lerp(puffs.get_shader_parameter(&"shadow_color") as Color, STORM_AMOUNT)
	frame.puff_mid_color = frame.puff_mid_color.lerp(puffs.get_shader_parameter(&"mid_color") as Color, STORM_AMOUNT)
	frame.puff_lit_color = frame.puff_lit_color.lerp(puffs.get_shader_parameter(&"lit_color") as Color, STORM_AMOUNT)
	frame.puff_rim_color = frame.puff_rim_color.lerp(puffs.get_shader_parameter(&"rim_color") as Color, STORM_AMOUNT)
	frame.puff_cloud_shadow_color = frame.puff_cloud_shadow_color.lerp(storm_sky.get_shader_parameter(&"cloud_shadow_color") as Color, STORM_AMOUNT)
	frame.puff_cloud_mid_color = frame.puff_cloud_mid_color.lerp(storm_sky.get_shader_parameter(&"cloud_mid_color") as Color, STORM_AMOUNT)
	frame.puff_cloud_lit_color = frame.puff_cloud_lit_color.lerp(storm_sky.get_shader_parameter(&"cloud_lit_color") as Color, STORM_AMOUNT)
	frame.puff_cloud_rim_color = frame.puff_cloud_rim_color.lerp(storm_sky.get_shader_parameter(&"cloud_rim_color") as Color, STORM_AMOUNT)
	# The blended sky's sea colours reach the puffs through the copy, not the tick values.
	frame.puff_sea_color_near = Color(0.2, 0.3, 0.4)
	frame.puff_sea_color_far = Color(0.5, 0.1, 0.2)
	frame.puff_sun_direction = Vector3(0.0, 0.0, 1.0)
	var sea: CloudSea = _sea(snapshot)
	sea.apply_frame(frame)
	_assert_same_uniforms(sea, old_sea, _compared_names(), "storm")
	assert_eq(sea.puff_material().get_shader_parameter(&"exposure"), 0.37, "Q1: the storm copies the overcast-scaled sky exposure")
	assert_eq(sea.puff_material().get_shader_parameter(&"proc_sea_color_near"), Color(0.2, 0.3, 0.4), "Q1: day-only sea colour wins at storm start")


func test_without_a_storm_the_shared_far_fade_set_is_not_rewritten() -> void:
	# Q3: the far-fade gradient is copied at configure_cycle() only; a frame's puff_shared
	# changes nothing until a storm runs.
	var snapshot: SkyFrame = _snapshot_of(_day.sky_material as ShaderMaterial)
	var sea: CloudSea = _sea(snapshot)
	var before: Variant = sea.puff_material().get_shader_parameter(&"proc_zenith_color")
	var frame: SkyFrame = _tick_frame()
	frame.puff_shared = _snapshot_of(_blended_sky()).puff_shared
	sea.apply_frame(frame)
	assert_eq(sea.puff_material().get_shader_parameter(&"proc_zenith_color"), before, "Q3: stale gradient kept")
	assert_eq(sea.puff_material().get_shader_parameter(&"exposure"), snapshot.puff_shared[&"exposure"], "exposure not written per tick")
	frame.storm_amount = STORM_AMOUNT
	sea.apply_frame(frame)
	assert_eq(sea.puff_material().get_shader_parameter(&"proc_zenith_color"), Color(0.1, 0.1, 0.3), "a storm re-copies the set")


func test_configure_cycle_takes_the_snapshot_and_duplicates_the_material() -> void:
	var def: SkyCycleDef = _cycle()
	var shared_material: ShaderMaterial = def.cloud_puff_material
	var snapshot: SkyFrame = SkyFrame.new()
	snapshot.puff_shared[&"exposure"] = 0.42
	var sea: CloudSea = CloudSea.new()
	add_child_autofree(sea)
	sea.configure_cycle(def, snapshot, 1.0, 1)
	assert_ne(sea.puff_material(), shared_material, "the def's material is duplicated before it is written")
	assert_eq(sea.puff_material().get_shader_parameter(&"exposure"), 0.42, "the snapshot is the far-fade copy")
	sea.apply_frame(_tick_frame())
	assert_ne(shared_material.get_shader_parameter(&"grade_amount"), NIGHT_WEIGHT, "the shipped material is untouched")
	sea.configure_cycle(null, null, 1.0)
	assert_false(sea.visible, "no def hides the cloud sea")
	sea.apply_frame(_tick_frame())
	assert_null(sea.puff_material())
