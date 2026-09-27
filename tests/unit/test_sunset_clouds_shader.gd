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
