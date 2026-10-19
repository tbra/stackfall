extends GutTest
## CloudSea.apply_frame() writes the puff channel of an evaluated SkyFrame. The expected uniforms are
## pinned as literals in fixtures/cloud_sea_frame_expected.json (captured from the theme-based writers
## that apply_frame replaced), with quirks Q1 (the storm re-copies the shared sky set) and Q3 (the
## far-fade gradient is only copied at configure_cycle() and on a storm). configure_cycle() duplicates
## the def's puff material.

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


func _decode_shared(key: String) -> Dictionary[StringName, Variant]:
	var shared: Dictionary[StringName, Variant] = {}
	var texture: Variant = SkyTestKit.cycle().sky_material.get_shader_parameter(&"noise_tex")
	var source: Dictionary = _fixture[key] as Dictionary
	for entry: String in source:
		var raw: Variant = source[entry]
		shared[StringName(entry)] = texture if raw is String and raw == TEXTURE_MARK else _decode(raw)
	return shared


func _snapshot() -> SkyFrame:
	var snapshot: SkyFrame = SkyFrame.new()
	snapshot.puff_shared = _decode_shared("snapshot_shared")
	return snapshot


## A frame from the fixture ("tick_frame" or "storm_frame").
func _frame(key: String) -> SkyFrame:
	var data: Dictionary = _fixture[key] as Dictionary
	var frame: SkyFrame = SkyFrame.new()
	for color_name: String in FRAME_COLORS:
		frame.set(color_name, _decode(data[color_name]) as Color)
	frame.night = float(data["night"])
	frame.puff_grade_amount = float(data["puff_grade_amount"])
	frame.puff_exposure = float(data["puff_exposure"])
	frame.puff_sea_coverage = float(data["puff_sea_coverage"])
	frame.puff_light_direction = _decode(data["puff_light_direction"]) as Vector3
	frame.puff_sun_direction = _decode(data["puff_sun_direction"]) as Vector3
	frame.storm_amount = float(data["storm_amount"])
	return frame


func _sea(snapshot: SkyFrame) -> CloudSea:
	var sea: CloudSea = CloudSea.new()
	add_child_autofree(sea)
	var def: SkyCycleDef = SkyTestKit.cycle()
	def.cloud_clump_count = SEA_COUNT
	def.cloud_bank_count = 0
	def.proc_far_count = 0
	sea.configure_cycle(def, snapshot, 1.0, 1)
	return sea


## The cycle's sky material with the storm-blended overrides the old storm test used.
func _blended_sky() -> ShaderMaterial:
	var sky: ShaderMaterial = (SkyTestKit.cycle().sky_material as ShaderMaterial).duplicate() as ShaderMaterial
	sky.set_shader_parameter(&"exposure", 0.37)
	sky.set_shader_parameter(&"proc_sea_color_near", Color(0.2, 0.3, 0.4))
	sky.set_shader_parameter(&"proc_sea_color_far", Color(0.5, 0.1, 0.2))
	sky.set_shader_parameter(&"proc_zenith_color", Color(0.1, 0.1, 0.3))
	sky.set_shader_parameter(&"sun_direction", Vector3(0.0, 0.0, 1.0))
	return sky


func _snapshot_of(sky: ShaderMaterial) -> SkyFrame:
	var snapshot: SkyFrame = SkyFrame.new()
	for parameter: StringName in CloudSea.SHARED_SKY_PARAMETERS:
		var value: Variant = sky.get_shader_parameter(parameter)
		if value != null:
			snapshot.puff_shared[parameter] = value
	return snapshot


func _compared_names() -> Array[StringName]:
	var names: Array[StringName] = []
	names.append_array(TONES)
	names.append_array(SKY_TONES)
	names.append_array(GRADE)
	names.append_array([&"grade_amount", &"light_direction"])
	for parameter: StringName in CloudSea.SHARED_SKY_PARAMETERS:
		# Exposure and sea coverage are the sky's per-tick variation: apply_frame writes them from
		# the frame (checked on their own), the old appearance writer never did.
		if parameter != &"exposure" and parameter != &"proc_sea_coverage":
			names.append(parameter)
	return names


## Every captured uniform of `key` ("expected_no_storm" / "expected_storm") equals the sea's, to the
## fixture's stored precision.
func _assert_matches_fixture(sea: CloudSea, key: String, label: String) -> void:
	var expected: Dictionary = _fixture[key] as Dictionary
	var checked: Dictionary = {}
	for parameter: StringName in _compared_names():
		if not expected.has(String(parameter)):
			assert_null(sea.puff_material().get_shader_parameter(parameter), "%s: %s was not captured, so not written" % [label, parameter])
			continue
		checked[parameter] = true
		var raw: Variant = expected[String(parameter)]
		var actual: Variant = sea.puff_material().get_shader_parameter(parameter)
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
	var sea: CloudSea = _sea(_snapshot())
	sea.apply_frame(_frame("tick_frame"))
	_assert_matches_fixture(sea, "expected_no_storm", "no storm")
	assert_eq(sea.puff_material().get_shader_parameter(&"grade_amount"), NIGHT_WEIGHT)
	assert_eq(sea.puff_material().get_shader_parameter(&"light_direction"), DIRECTION)
	assert_eq(sea.puff_material().get_shader_parameter(&"exposure"), TICK_EXPOSURE, "the far fade of the puffs tracks the sky exposure")
	assert_eq(sea.puff_material().get_shader_parameter(&"proc_sea_coverage"), TICK_SEA_COVERAGE, "and its sea coverage")


func test_apply_frame_in_a_storm_matches_the_captured_storm_tint_including_the_shared_copy() -> void:
	var frame: SkyFrame = _frame("storm_frame")
	# Step 7: the storm frame carries the lerped tones and the blended sky's shared set (Q1).
	frame.puff_shared = _decode_shared("blended_shared")
	assert_eq(frame.storm_amount, STORM_AMOUNT)
	var sea: CloudSea = _sea(_snapshot())
	sea.apply_frame(frame)
	_assert_matches_fixture(sea, "expected_storm", "storm")
	assert_eq(sea.puff_material().get_shader_parameter(&"exposure"), 0.37, "Q1: the storm copies the overcast-scaled sky exposure")
	assert_eq(sea.puff_material().get_shader_parameter(&"proc_sea_color_near"), Color(0.2, 0.3, 0.4), "Q1: day-only sea colour wins at storm start")


func test_without_a_storm_the_shared_far_fade_set_is_not_rewritten() -> void:
	# Q3: the far-fade gradient is copied at configure_cycle() only; a frame's puff_shared
	# changes nothing until a storm runs.
	var sea: CloudSea = _sea(_snapshot())
	var before: Variant = sea.puff_material().get_shader_parameter(&"proc_zenith_color")
	var frame: SkyFrame = _frame("tick_frame")
	frame.puff_shared = _snapshot_of(_blended_sky()).puff_shared
	sea.apply_frame(frame)
	assert_eq(sea.puff_material().get_shader_parameter(&"proc_zenith_color"), before, "Q3: stale gradient kept")
	assert_eq(sea.puff_material().get_shader_parameter(&"exposure"), TICK_EXPOSURE, "exposure follows the frame, not the snapshot")
	frame.storm_amount = STORM_AMOUNT
	sea.apply_frame(frame)
	assert_eq(sea.puff_material().get_shader_parameter(&"proc_zenith_color"), Color(0.1, 0.1, 0.3), "a storm re-copies the set")


func test_configure_cycle_takes_the_snapshot_and_duplicates_the_material() -> void:
	var def: SkyCycleDef = SkyTestKit.cycle()
	var shared_material: ShaderMaterial = def.cloud_puff_material
	var snapshot: SkyFrame = SkyFrame.new()
	snapshot.puff_shared[&"exposure"] = 0.42
	var sea: CloudSea = CloudSea.new()
	add_child_autofree(sea)
	sea.configure_cycle(def, snapshot, 1.0, 1)
	assert_ne(sea.puff_material(), shared_material, "the def's material is duplicated before it is written")
	assert_eq(sea.puff_material().get_shader_parameter(&"exposure"), 0.42, "the snapshot is the far-fade copy")
	sea.apply_frame(_frame("tick_frame"))
	assert_ne(shared_material.get_shader_parameter(&"grade_amount"), NIGHT_WEIGHT, "the shipped material is untouched")
	sea.configure_cycle(null, null, 1.0)
	assert_false(sea.visible, "no def hides the cloud sea")
	sea.apply_frame(_frame("tick_frame"))
	assert_null(sea.puff_material())


func test_missing_snapshot_keys_fall_back_to_the_cycles_static_sky_material() -> void:
	var def: SkyCycleDef = SkyTestKit.cycle()
	var sea: CloudSea = CloudSea.new()
	add_child_autofree(sea)
	sea.configure_cycle(def, SkyFrame.new(), 1.0, 1)
	var static_value: Variant = def.sky_material.get_shader_parameter(&"proc_sea_softness")
	if static_value != null:
		assert_eq(sea.puff_material().get_shader_parameter(&"proc_sea_softness"), static_value, "static sea key copied")
	assert_eq(sea.puff_material().get_shader_parameter(&"procedural_sea_mix"), SkyDomeWriter.PROCEDURAL_SEA_MIX, "the cycle's constant sea mix")
