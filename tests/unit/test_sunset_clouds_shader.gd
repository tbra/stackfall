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


func test_sun_core_and_halo_intensity_default_to_zero() -> void:
	var source: String = _shader_source_without_comments()
	assert_true(
		source.contains("uniform float sun_core_intensity = 0.0;"),
		"sun_core_intensity must default to 0.0 -- the painted panorama sun is the only disc; " +
		"see this shader's own sun_core_intensity DECISION."
	)
	assert_true(
		source.contains("uniform float sun_halo_intensity = 0.0;"),
		"sun_halo_intensity must default to 0.0 for the same reason."
	)


## The god-ray beams (a fix round the owner separately requested, "move god
## rays into the sky") are untouched by this package -- pins that ray_intensity
## keeps its own non-zero default rather than having been zeroed alongside
## the disc by mistake.
func test_ray_intensity_default_is_unchanged() -> void:
	var source: String = _shader_source_without_comments()
	assert_true(
		source.contains("uniform float ray_intensity = 0.35;"),
		"ray_intensity must keep its own default -- only the disc (core/halo) was disabled, not the god rays."
	)


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


func test_sea_and_second_strata_skip_the_radiance_pass() -> void:
	var source: String = _shader_source_without_comments()
	var call_at: int = source.find("pcol = procedural_sea_color(")
	var before: String = source.substr(maxi(call_at - 80, 0), mini(80, call_at))
	assert_true(call_at > 0 and before.contains("!AT_CUBEMAP_PASS"), "sea noise taps must be background-pass only.")
	assert_true(source.contains("procedural_sea_mix > 0.0 && proc_cards_mix <= 0.0 && proc_overhead_mix > 0.0)"), "second strata layer must be background-pass only.")
	assert_true(source.contains("u2.rgb * exposure") and source.contains("u1.rgb * exposure"), "procedural strata must be multiplied by exposure.")


func test_card_layer_is_background_only_and_exposed() -> void:
	var source: String = _shader_source_without_comments()
	var include_src: String = FileAccess.get_file_as_string("res://shaders/include/cloud_common.gdshaderinc")
	assert_true(include_src.contains("vec4 sky_cloud_cards("), "card layer function must exist.")
	assert_true(source.contains("!AT_CUBEMAP_PASS && eyedir.y > 0.0 && procedural_sea_mix > 0.0 && proc_cards_mix > 0.0"), "cards must be background-pass only and gated by the procedural look.")
	assert_true(source.contains("k1.rgb * exposure") and source.contains("k2.rgb * exposure"), "card layers must be multiplied by exposure.")
