extends GutTest
## CloudSea.apply_frame() writes the puff channel of an evaluated SkyFrame. The expected uniforms are
## pinned as literals in fixtures/cloud_sea_frame_expected.json (captured from the theme-based writers
## that apply_frame replaced). The far-fade gradient is not in the fixture: it is written from the
## frame every call, a storm included (the retired sky-set copy at storm start and the stale gradient
## are fixed). configure_cycle() duplicates the def's puff material.

const FIXTURE_PATH: String = "res://tests/unit/sky/fixtures/cloud_sea_frame_expected.json"
const TONES: Array[StringName] = [&"shadow_color", &"mid_color", &"lit_color", &"rim_color"]
const SKY_TONES: Array[StringName] = [&"cloud_shadow_color", &"cloud_mid_color", &"cloud_lit_color", &"cloud_rim_color"]
const GRADE: Array[StringName] = [&"grade_dark", &"grade_mid", &"grade_light"]
const NIGHT_WEIGHT: float = 0.6
const STORM_AMOUNT: float = 0.5
const DIRECTION: Vector3 = Vector3(0.3, 0.8, 0.2)
const SEA_COUNT: int = 2
const TICK_EXPOSURE: float = 0.64
const TICK_SEA_COVERAGE: float = 0.33
const TEXTURE_MARK: String = "@texture"
const FIXTURE_EPSILON: float = 0.00001
## Far-fade gradient uniform -> the frame field apply_frame() writes it from.
const GRADIENT_FIELDS: Dictionary[StringName, StringName] = {
	&"proc_zenith_color": &"proc_zenith_color", &"proc_mid_color": &"proc_mid_color",
	&"proc_horizon_color": &"proc_horizon_color", &"proc_gradient_mid_height": &"proc_gradient_mid_height",
	&"proc_gradient_power": &"proc_gradient_power", &"proc_horizon_glow_color": &"proc_horizon_glow_color",
	&"proc_horizon_glow_width": &"proc_horizon_glow_width", &"proc_sea_horizon_fade": &"proc_sea_horizon_fade",
}
const FRAME_COLORS: Array[String] = [
	"puff_shadow_color", "puff_mid_color", "puff_lit_color", "puff_rim_color",
	"puff_cloud_shadow_color", "puff_cloud_mid_color", "puff_cloud_lit_color", "puff_cloud_rim_color",
	"puff_grade_dark", "puff_grade_mid", "puff_grade_light", "puff_sea_color_near", "puff_sea_color_far",
]

var _fixture: Dictionary = {}


func before_each() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_PATH))
	_fixture = parsed as Dictionary if parsed is Dictionary else {}
	assert_false(_fixture.is_empty(), "the fixture parses")


## A fixture value as the engine value it was captured from.
func _decode(value: Variant) -> Variant:
	if value is Dictionary:
		var tagged: Dictionary = value as Dictionary
		if tagged.has("v2"):
			var pair: Array = tagged["v2"] as Array
			return Vector2(float(pair[0]), float(pair[1]))
		var quad: Array = tagged["v4"] as Array
		return Vector4(float(quad[0]), float(quad[1]), float(quad[2]), float(quad[3]))
	if value is Array:
		var parts: Array = value as Array
		if parts.size() == 4:
			return Color(float(parts[0]), float(parts[1]), float(parts[2]), float(parts[3]))
		return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
	return value


## A frame from the fixture ("tick_frame" or "storm_frame").
func _frame(key: String) -> SkyFrame:
	var data: Dictionary = _fixture[key] as Dictionary
	var frame: SkyFrame = SkyFrame.new()
	for color_name: String in FRAME_COLORS:
		frame.set(color_name, _decode(data[color_name]) as Color)
	frame.night = float(data["night"])
	frame.puff_grade_amount = float(data["puff_grade_amount"])
	frame.puff_exposure = float(data["puff_exposure"])
	_set_gradient(frame, 0.0)
	frame.puff_sea_coverage = float(data["puff_sea_coverage"])
	frame.puff_light_direction = _decode(data["puff_light_direction"]) as Vector3
	frame.puff_sun_direction = _decode(data["puff_sun_direction"]) as Vector3
	frame.storm_amount = float(data["storm_amount"])
	return frame


func _sea(frame: SkyFrame) -> CloudSea:
	var sea: CloudSea = CloudSea.new()
	add_child_autofree(sea)
	var def: SkyCycleDef = SkyTestKit.cycle()
	def.cloud_clump_count = SEA_COUNT
	def.cloud_bank_count = 0
	def.proc_far_count = 0
	sea.configure_cycle(def, frame, 1.0, 1)
	return sea


## Sets the far-fade gradient fields of `frame` to values that depend on `seed_value` (0..1), so two
## frames differ in every gradient uniform.
func _set_gradient(frame: SkyFrame, seed_value: float) -> void:
	frame.proc_zenith_color = Color(0.1 + seed_value, 0.2, 0.3, 1.0)
	frame.proc_mid_color = Color(0.4, 0.5 + seed_value * 0.4, 0.6, 1.0)
	frame.proc_horizon_color = Color(0.7, 0.6, 0.5 + seed_value * 0.4, 1.0)
	frame.proc_horizon_glow_color = Color(0.9 - seed_value * 0.5, 0.8, 0.2, 1.0)
	frame.proc_gradient_mid_height = 0.3 + seed_value * 0.2
	frame.proc_gradient_power = 1.2 + seed_value
	frame.proc_horizon_glow_width = 0.1 + seed_value * 0.2
	frame.proc_sea_horizon_fade = 0.05 + seed_value * 0.1


func _assert_gradient_matches(sea: CloudSea, frame: SkyFrame, label: String) -> void:
	for parameter: StringName in GRADIENT_FIELDS:
		assert_eq(SkyTestKit.puff_material(sea).get_shader_parameter(parameter), frame.get(GRADIENT_FIELDS[parameter]),
			"%s: %s follows the frame" % [label, parameter])


func _compared_names() -> Array[StringName]:
	var names: Array[StringName] = []
	names.append_array(TONES)
	names.append_array(SKY_TONES)
	names.append_array(GRADE)
	names.append_array([&"grade_amount", &"light_direction"])
	for parameter: StringName in CloudSea.SHARED_SKY_PARAMETERS:
		# Exposure, sea coverage and the gradient are the sky's per-tick values: apply_frame writes
		# them from the frame (checked on their own), the old appearance writer never did.
		if parameter != &"exposure" and parameter != &"proc_sea_coverage" and not GRADIENT_FIELDS.has(parameter):
			names.append(parameter)
	return names


## Every captured uniform of `key` ("expected_no_storm" / "expected_storm") equals the sea's, to the
## fixture's stored precision.
func _assert_matches_fixture(sea: CloudSea, key: String, label: String) -> void:
	var expected: Dictionary = _fixture[key] as Dictionary
	var checked: Dictionary = {}
	for parameter: StringName in _compared_names():
		if not expected.has(String(parameter)):
			assert_null(SkyTestKit.puff_material(sea).get_shader_parameter(parameter), "%s: %s was not captured, so not written" % [label, parameter])
			continue
		checked[parameter] = true
		var raw: Variant = expected[String(parameter)]
		var actual: Variant = SkyTestKit.puff_material(sea).get_shader_parameter(parameter)
		if raw is String and raw == TEXTURE_MARK:
			assert_true(actual is Texture2D, "%s: %s" % [label, parameter])
			continue
		var want: Variant = _decode(raw)
		if want is Color:
			assert_true((actual as Color).is_equal_approx(want as Color), "%s: %s %s != %s" % [label, parameter, actual, want])
		elif want is Vector3:
			assert_true((actual as Vector3).is_equal_approx(want as Vector3), "%s: %s" % [label, parameter])
		elif want is Vector2:
			assert_true((actual as Vector2).is_equal_approx(want as Vector2), "%s: %s" % [label, parameter])
		elif want is Vector4:
			assert_true((actual as Vector4).is_equal_approx(want as Vector4), "%s: %s" % [label, parameter])
		else:
			assert_almost_eq(float(actual), float(want), FIXTURE_EPSILON, "%s: %s" % [label, parameter])
	assert_eq(checked.size(), expected.size(), "%s: every captured uniform was compared" % label)


func test_apply_frame_writes_what_the_cycle_appearance_wrote() -> void:
	var sea: CloudSea = _sea(null)
	var frame: SkyFrame = _frame("tick_frame")
	sea.apply_frame(frame)
	_assert_matches_fixture(sea, "expected_no_storm", "no storm")
	assert_eq(SkyTestKit.puff_material(sea).get_shader_parameter(&"grade_amount"), NIGHT_WEIGHT)
	assert_eq(SkyTestKit.puff_material(sea).get_shader_parameter(&"light_direction"), DIRECTION)
	assert_eq(SkyTestKit.puff_material(sea).get_shader_parameter(&"exposure"), TICK_EXPOSURE, "the far fade of the puffs tracks the sky exposure")
	assert_eq(SkyTestKit.puff_material(sea).get_shader_parameter(&"proc_sea_coverage"), TICK_SEA_COVERAGE, "and its sea coverage")
	_assert_gradient_matches(sea, frame, "no storm")


func test_apply_frame_in_a_storm_writes_the_frames_tones_sea_colours_and_exposure() -> void:
	var frame: SkyFrame = _frame("storm_frame")
	assert_eq(frame.storm_amount, STORM_AMOUNT)
	var sea: CloudSea = _sea(null)
	sea.apply_frame(frame)
	_assert_matches_fixture(sea, "expected_storm", "storm")
	# Q1 fixed: the storm no longer re-copies the sky's shared set; the sea colours and exposure are
	# the frame's own (the evaluator keeps the tick's night-mixed values there).
	assert_eq(SkyTestKit.puff_material(sea).get_shader_parameter(&"exposure"), frame.puff_exposure)
	assert_eq(SkyTestKit.puff_material(sea).get_shader_parameter(&"proc_sea_color_near"), frame.puff_sea_color_near)
	assert_eq(SkyTestKit.puff_material(sea).get_shader_parameter(&"proc_sea_color_far"), frame.puff_sea_color_far)
	_assert_gradient_matches(sea, frame, "storm")


func test_the_far_fade_gradient_follows_every_frame() -> void:
	# Q3 fixed: the gradient is rewritten from each frame, not copied once at configure_cycle().
	var sea: CloudSea = _sea(null)
	var first: SkyFrame = _frame("tick_frame")
	_set_gradient(first, 0.0)
	sea.apply_frame(first)
	_assert_gradient_matches(sea, first, "first frame")
	var second: SkyFrame = _frame("tick_frame")
	_set_gradient(second, 0.5)
	sea.apply_frame(second)
	_assert_gradient_matches(sea, second, "second frame")
	var stormed: SkyFrame = _frame("storm_frame")
	_set_gradient(stormed, 1.0)
	sea.apply_frame(stormed)
	_assert_gradient_matches(sea, stormed, "storm frame")


func test_configure_cycle_writes_the_live_frame_and_duplicates_the_material() -> void:
	var def: SkyCycleDef = SkyTestKit.cycle()
	var shared_material: ShaderMaterial = def.cloud_puff_material
	var live: SkyFrame = SkyFrame.new()
	live.puff_exposure = 0.42
	_set_gradient(live, 0.5)
	var sea: CloudSea = CloudSea.new()
	add_child_autofree(sea)
	sea.configure_cycle(def, live, 1.0, 1)
	assert_ne(SkyTestKit.puff_material(sea), shared_material, "the def's material is duplicated before it is written")
	assert_eq(SkyTestKit.puff_material(sea).get_shader_parameter(&"exposure"), 0.42, "the live frame is the far-fade start")
	_assert_gradient_matches(sea, live, "configure")
	sea.apply_frame(_frame("tick_frame"))
	assert_ne(shared_material.get_shader_parameter(&"grade_amount"), NIGHT_WEIGHT, "the shipped material is untouched")
	sea.configure_cycle(null, null, 1.0)
	assert_false(sea.visible, "no def hides the cloud sea")
	sea.apply_frame(_frame("tick_frame"))
	assert_null(SkyTestKit.puff_material(sea))


func test_configure_cycle_copies_the_cycles_static_sky_material() -> void:
	var def: SkyCycleDef = SkyTestKit.cycle()
	var sea: CloudSea = CloudSea.new()
	add_child_autofree(sea)
	sea.configure_cycle(def, null, 1.0, 1)
	var static_value: Variant = def.sky_material.get_shader_parameter(&"proc_sea_softness")
	if static_value != null:
		assert_eq(SkyTestKit.puff_material(sea).get_shader_parameter(&"proc_sea_softness"), static_value, "static sea key copied")
	assert_eq(SkyTestKit.puff_material(sea).get_shader_parameter(&"procedural_sea_mix"), SkyDomeWriter.PROCEDURAL_SEA_MIX, "the cycle's constant sea mix")
