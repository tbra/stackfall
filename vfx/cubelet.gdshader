shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;
// Bontago-mp0.3.4 fix round (owner: "make them actual tiny 3D cubes...
// with the cel look"): a cheap unshaded 2-tone shade, not a full lit
// material -- a fixed faux light direction decides whether each face is
// "lit" or "shadow" and picks one of exactly two brightness levels (a hard
// step, not a smooth gradient), the same cel/toon read the rest of the
// block visuals use, without needing this tiny, short-lived particle mesh
// to carry real scene lighting.

uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float shade_mix = 0.35;

void fragment() {
	float lit = dot(normalize(NORMAL), normalize(vec3(0.4, 0.85, 0.3)));
	float tone = lit > 0.15 ? 1.0 : (1.0 - shade_mix);
	ALBEDO = base_color.rgb * tone;
	// COLOR.a carries this particle's own remaining-lifetime fade
	// (ParticleProcessMaterial.color_ramp) -- "fading out"; the mesh's own
	// per-particle scale_curve handles "shrinking" separately.
	ALPHA = base_color.a * COLOR.a;
}
