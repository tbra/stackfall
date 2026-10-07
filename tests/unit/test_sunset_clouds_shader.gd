extends GutTest
## Bontago-1pi.1 (owner playtest: "there are 2 suns, one built in to the
## skybox and another with the lens flares"): shaders/sunset_clouds.gdshader
## drew its own additive sun core+halo disc directly on top of the sun disc
## already painted into assets/sky/sunset-clouds-v1.png (see that shader's
## own DECISION comment on sun_core_intensity/sun_halo_intensity for the full
## reasoning) -- a visible second circle, not a second sun in a different
## place. The fix zeroes those two defaults so vfx/SunFlare.gd's
## screen-space sparkle (already coincident -- config/SunFlareConfig.gd's
## sun_direction matches this shader's own default) is the only extra sun
## element layered onto the one painted disc.
##
## Parses Shader.code the same way tests/unit/test_territory_overlay.gd's own
## _shader_source_without_comments() does, rather than trying to read a
## uniform's default value back through a ShaderMaterial/RenderingServer
## (Godot has no direct GDScript API for a shader's own declared uniform
## default) -- a plain, readable regression pin on the exact source line.

const SHADER_PATH: String = "res://shaders/sunset_clouds.gdshader"


func _shader_source_without_comments() -> String:
	var shader: Shader = load(SHADER_PATH)
	var code_lines: PackedStringArray = PackedStringArray()
	for line: String in shader.code.split("\n"):
		var stripped: String = line.strip_edges()
		if not stripped.begins_with("//"):
			code_lines.append(line.split("//")[0])
	return "\n".join(code_lines)


## The shader's declared default for a float uniform. The dummy renderer cannot report
## defaults (RenderingServer returns null headless), so the declaration is parsed: the
## number after the uniform's `=`, whatever it is, not an exact source string.
func _default(uniform_name: StringName) -> float:
	var declaration: RegEx = RegEx.new()
	declaration.compile("uniform\\s+float\\s+%s\\b[^=;]*=\\s*([-+0-9.eE]+)\\s*;" % uniform_name)
	var found: RegExMatch = declaration.search(_shader_source_without_comments())
	if found == null:
		fail_test("uniform float %s has no declared default" % uniform_name)
		return NAN
	return found.get_string(1).to_float()


## The painted panorama sun is the only disc: the shader's own additive core and halo are off
## by default (read through the shader's declared default, not its source text).
func test_sun_core_and_halo_are_off_by_default() -> void:
	assert_eq(_default(&"sun_core_intensity"), 0.0, "no second disc: core off")
	assert_eq(_default(&"sun_halo_intensity"), 0.0, "no second disc: halo off")


## The god-ray beams stay on by default (only the disc was disabled).
func test_god_rays_stay_enabled_by_default() -> void:
	assert_gt(_default(&"ray_intensity"), 0.0, "only the disc (core/halo) was disabled, not the god rays")


## The painted disc's lower cap is behind clouds. Pin its full-circle centre,
## not the visible bright pixels' centroid, against the original flare axis.
func test_panorama_disc_center_aligns_with_original_flare_direction() -> void:
	var theme: SkyThemeDef = load("res://config/sky_themes/sunset.tres")
	var config: SunFlareConfig = load("res://config/sun_flare.tres")
	var direction: Vector3 = config.sun_direction.normalized()
	var yaw: float = theme.sky_yaw_offset_deg
	var pitch: float = theme.sky_pitch_offset_deg
	var sample_uv: Vector2 = Vector2(
		fposmod(atan2(direction.x, -direction.z) / TAU + yaw / 360.0, 1.0),
		acos(direction.y) / PI + pitch / 180.0
	)
	assert_almost_eq(sample_uv.x * 1774.0, 1276.0, 0.5, "Panorama sun centre must match flare longitude.")
	assert_almost_eq(sample_uv.y * 887.0, 424.0, 0.5, "Panorama sun centre must match flare elevation.")
	assert_true(direction.is_equal_approx(Vector3(0.963087, 0.069011, -0.260192).normalized()), "Preserve the original flare axis.")


## Bontago-59o.16 P3: the far cloud sea is a shared include function, guarded
## against the horizon singularity, and never sampled in the radiance pass.
func test_procedural_sea_color_is_shared_and_guarded() -> void:
	var include_src: String = (load("res://shaders/include/cloud_common.gdshaderinc") as Shader).code \
		if load("res://shaders/include/cloud_common.gdshaderinc") is Shader \
		else FileAccess.get_file_as_string("res://shaders/include/cloud_common.gdshaderinc")
	assert_true(include_src.contains("vec3 procedural_sea_color("), "shared sea function must exist for P4 consumers.")
	assert_true(include_src.contains("max(-dir.y, 0.0005)"), "projection depth must be clamped so eyedir.y == 0 cannot divide by zero.")


func test_sea_noise_taps_are_background_pass_only() -> void:
	var lines: PackedStringArray = _shader_source_without_comments().split("
")
	var found: int = 0
	for i: int in range(lines.size()):
		if lines[i].contains("procedural_sea_color(") and not lines[i].contains("vec3 procedural_sea_color("):
			found += 1
			var context: String = "
".join(lines.slice(maxi(i - 3, 0), i + 1))
			assert_true(context.contains("AT_CUBEMAP_PASS"), "sea noise taps skip the radiance pass: " + lines[i].strip_edges())
	assert_gt(found, 0, "the sky pass samples the procedural sea")


func test_card_layer_is_background_only_and_exposed() -> void:
	var source: String = _shader_source_without_comments()
	var include_src: String = FileAccess.get_file_as_string("res://shaders/include/cloud_common.gdshaderinc")
	assert_true(include_src.contains("vec4 sky_cloud_cards("), "card layer function must exist.")
	assert_true(source.contains("!AT_CUBEMAP_PASS && eyedir.y > 0.0 && procedural_sea_mix > 0.0 && proc_cards_mix > 0.0"), "cards must be background-pass only and gated by the procedural look.")
	assert_true(source.contains("k1.rgb * exposure") and source.contains("k2.rgb * exposure"), "card layers must be multiplied by exposure.")


## Bontago-mp0.94: the additive sun terms (core, halo, god rays) all multiply
## sun_effect_scale, which Skybox drives to exactly 0 at full storm; a term that skips it
## is the "sun hidden but rays still visible" bug. Checked per use line (invariant, not an exact string).
func test_every_additive_sun_term_multiplies_the_weather_scale() -> void:
	var shader: Shader = load(SHADER_PATH)
	var names: Array = []
	for entry: Dictionary in shader.get_shader_uniform_list():
		names.append(entry["name"])
	assert_true(names.has("sun_effect_scale"), "Skybox drives the weather scale through this uniform")
	var source: String = _shader_source_without_comments()
	for token: String in ["sun_core_intensity", "sun_halo_intensity", "ray_intensity"]:
		assert_true(names.has(token), "%s is a tunable uniform" % token)
		var found: int = 0
		for line: String in source.split("
"):
			if line.contains(token) and not line.strip_edges().begins_with("uniform"):
				found += 1
				assert_true(line.contains("sun_effect_scale"), "%s must be scaled by sun_effect_scale: %s" % [token, line.strip_edges()])
		assert_gt(found, 0, "%s is used by the sky pass" % token)
