extends GutTest
## SkyDomeWriter: one material duplicate per lifetime, the shipped template is never written,
## and an unchanged frame writes nothing (every sky uniform write dirties the radiance).

const TEMPLATE_PATH: String = "res://config/sky/themes/sunset.tres"
const CHANGED_EXPOSURE: float = 0.5
const CHANGED_ZENITH: Color = Color(0.9, 0.1, 0.2, 1.0)
const NUDGE: float = 1e-4


func _template() -> ShaderMaterial:
	var theme: SkyThemeDef = load(TEMPLATE_PATH) as SkyThemeDef
	return theme.sky_material as ShaderMaterial


func _frame() -> SkyFrame:
	var frame: SkyFrame = SkyFrame.new()
	frame.exposure = 0.8
	frame.proc_zenith_color = Color(0.2, 0.3, 0.4, 1.0)
	frame.sun_direction = Vector3(0.6, 0.5, 0.2).normalized()
	return frame


func _snapshot(material: ShaderMaterial) -> Dictionary:
	var out: Dictionary = {}
	for info: Dictionary in material.shader.get_shader_uniform_list():
		var name: StringName = StringName(info["name"] as String)
		out[name] = material.get_shader_parameter(name)
	return out


func test_bind_makes_one_duplicate_and_installs_it() -> void:
	var writer: SkyDomeWriter = SkyDomeWriter.new()
	var sky: Sky = Sky.new()
	var template: ShaderMaterial = _template()
	var bound: ShaderMaterial = writer.bind(sky, template)
	assert_ne(bound, template, "a duplicate, never the template")
	assert_eq(sky.sky_material, bound)
	assert_eq(writer.material(), bound)
	writer.stage(_frame())
	writer.flush()
	assert_eq(writer.material(), bound, "still the same duplicate after writes")


func test_first_flush_writes_then_unchanged_frame_writes_nothing() -> void:
	var writer: SkyDomeWriter = SkyDomeWriter.new()
	writer.bind(null, _template())
	var frame: SkyFrame = _frame()
	writer.stage(frame)
	assert_gt(writer.flush(), 0, "first flush writes the whole channel")
	writer.stage(frame)
	assert_eq(writer.flush(), 0, "identical frame: zero material writes")
	var copy: SkyFrame = SkyFrame.new()
	copy.copy_from(frame)
	writer.stage(copy)
	assert_eq(writer.flush(), 0, "equal values in a new frame object: zero writes")


func test_only_changed_uniforms_are_written() -> void:
	var writer: SkyDomeWriter = SkyDomeWriter.new()
	writer.bind(null, _template())
	var frame: SkyFrame = _frame()
	writer.stage(frame)
	writer.flush()
	frame.exposure = CHANGED_EXPOSURE
	writer.stage(frame)
	assert_eq(writer.flush(), 1)
	assert_eq(writer.material().get_shader_parameter(&"exposure"), CHANGED_EXPOSURE)
	frame.proc_zenith_color = CHANGED_ZENITH
	writer.stage(frame)
	assert_eq(writer.flush(), 1)
	assert_eq(writer.material().get_shader_parameter(&"proc_zenith_color"), CHANGED_ZENITH)


func test_equality_is_exact_not_approximate() -> void:
	var writer: SkyDomeWriter = SkyDomeWriter.new()
	writer.bind(null, _template())
	var frame: SkyFrame = _frame()
	writer.stage(frame)
	writer.flush()
	frame.exposure += NUDGE
	frame.sun_direction = Vector3(frame.sun_direction.x + NUDGE, frame.sun_direction.y, frame.sun_direction.z)
	writer.stage(frame)
	assert_eq(writer.flush(), 2, "a tiny float and Vector3 change is still written")


func test_variation_never_writes_the_template_material() -> void:
	var template: ShaderMaterial = _template()
	var before: Dictionary = _snapshot(template)
	var writer: SkyDomeWriter = SkyDomeWriter.new()
	var bound: ShaderMaterial = writer.bind(Sky.new(), template)
	var frame: SkyFrame = _frame()
	for i: int in 5:
		# a different exposure and sea coverage per frame, like a variation seed moving them
		frame.exposure = 0.8 + 0.01 * float(i)
		frame.proc_sea_coverage = 0.3 + 0.02 * float(i)
		writer.stage(frame)
		writer.flush()
	var after: Dictionary = _snapshot(template)
	assert_gt(before.size(), 0)
	for key: Variant in before:
		assert_eq(after[key], before[key], "template uniform %s unchanged" % str(key))
	assert_ne(bound.get_shader_parameter(&"exposure"), template.get_shader_parameter(&"exposure"),
		"only the bound duplicate moved")


func test_forget_rewrites_everything() -> void:
	var writer: SkyDomeWriter = SkyDomeWriter.new()
	writer.bind(null, _template())
	writer.stage(_frame())
	var first: int = writer.flush()
	writer.forget()
	writer.stage(_frame())
	assert_eq(writer.flush(), first)


func test_publish_globals_sets_sun_and_opposite_moon() -> void:
	var writer: SkyDomeWriter = SkyDomeWriter.new()
	var sun: Vector3 = Vector3(0.0, 1.0, 0.0)
	writer.publish_globals(sun, 12.5)
	if RenderingServer.global_shader_parameter_get(SkyDomeWriter.SKY_TIME_GLOBAL) == null:
		pending("the dummy renderer does not store shader globals")
		return
	assert_eq(RenderingServer.global_shader_parameter_get(SkyDomeWriter.SKY_SUN_DIR_GLOBAL), sun)
	assert_eq(RenderingServer.global_shader_parameter_get(SkyDomeWriter.SKY_MOON_DIR_GLOBAL), -sun)
	assert_eq(RenderingServer.global_shader_parameter_get(SkyDomeWriter.SKY_TIME_GLOBAL), 12.5)


func test_bind_writes_the_constant_uniforms_on_the_duplicate_only() -> void:
	var writer: SkyDomeWriter = SkyDomeWriter.new()
	var template: ShaderMaterial = _template()
	var bound: ShaderMaterial = writer.bind(null, template)
	assert_eq(bound.get_shader_parameter(&"moon_disc_tex"), SkyDomeWriter.MOON_DISC_TEXTURE, "moon disc")
	assert_eq(bound.get_shader_parameter(&"moon_halo_tex"), SkyDomeWriter.MOON_HALO_TEXTURE, "moon halo")
	assert_eq(bound.get_shader_parameter(&"procedural_sea_mix"), SkyDomeWriter.PROCEDURAL_SEA_MIX, "sea mix")
	assert_null(template.get_shader_parameter(&"moon_disc_tex"), "the template is untouched")


func test_aurora_look_is_staged_only_while_visible() -> void:
	var writer: SkyDomeWriter = SkyDomeWriter.new()
	var bound: ShaderMaterial = writer.bind(null, _template())
	var frame: SkyFrame = _frame()
	frame.aurora_visibility = 0.0
	frame.aurora_intensity = 1.7
	writer.stage(frame)
	writer.flush()
	assert_null(bound.get_shader_parameter(&"aurora_intensity"), "hidden aurora: no look written")
	frame.aurora_visibility = 0.5
	writer.stage(frame)
	writer.flush()
	assert_eq(bound.get_shader_parameter(&"aurora_intensity"), 1.7, "visible aurora: look written")


## The static look (view offsets, strata, overhead/cards mix, cloud coverage) left the shader: a
## bound, staged and flushed dome never writes a retired uniform, and every staged name exists.
const RETIRED_UNIFORMS: Array[StringName] = [
	&"proc_overhead_mix", &"proc_cards_mix", &"proc_cards_opacity", &"proc_cards_layout",
	&"sky_yaw_offset_deg", &"sky_pitch_offset_deg", &"proc_strata_scale", &"proc_strata_strength",
	&"cloud_coverage",
]


func test_flush_writes_no_retired_uniform_and_only_shader_uniforms() -> void:
	var writer: SkyDomeWriter = SkyDomeWriter.new()
	var bound: ShaderMaterial = writer.bind(null, _template())
	var frame: SkyFrame = _frame()
	frame.aurora_visibility = 1.0
	writer.stage(frame)
	writer.flush()
	var known: Dictionary = {}
	for info: Dictionary in bound.shader.get_shader_uniform_list():
		known[StringName(info["name"] as String)] = true
	for key: StringName in RETIRED_UNIFORMS:
		assert_false(known.has(key), "%s is retired from the shader" % key)
		assert_null(bound.get_shader_parameter(key), "%s is never written" % key)
	for key: Variant in writer._written:
		assert_true(known.has(key), "written %s exists in the shader" % key)
