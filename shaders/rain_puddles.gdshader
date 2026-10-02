shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// Bontago-mp0.21: cel puddles on the disc top (vfx/weather/RainPuddles.gd draws
// one MultiMesh of flat quads). Presentation only. Per instance
// INSTANCE_CUSTOM: x = appear threshold 0..1 (patches grow in at different
// wetness), y = random seed, z = ripple phase, w = glint offset.

uniform float wetness = 0.0;
uniform vec4 water_color : source_color = vec4(0.06, 0.1, 0.17, 1.0);
uniform vec4 rim_color : source_color = vec4(0.3, 0.42, 0.55, 1.0);
uniform vec4 glint_color : source_color = vec4(0.8, 0.9, 1.0, 1.0);
uniform float alpha_scale = 0.8;
uniform float ripples = 1.0;
uniform float rain_density = 0.0;

varying vec2 quad_uv;
varying vec4 custom;
varying float grow;

void vertex() {
	custom = INSTANCE_CUSTOM;
	grow = smoothstep(custom.x * 0.7, custom.x * 0.7 + 0.3, wetness);
	quad_uv = VERTEX.xz * 0.5;
	VERTEX.xz *= max(grow, 0.0001);
}

void fragment() {
	if (grow <= 0.001) {
		discard;
	}
	// quad_uv spans -0.5..0.5 of the full-size patch; p is -1..1.
	vec2 p = quad_uv * 2.0;
	float angle = atan(p.y, p.x);
	float d = length(p) / max(grow, 0.0001);
	// Lumpy outline: a few low sine lobes per puddle (hard cel edge below).
	float lump = 0.14 * sin(angle * 3.0 + custom.y * 40.0) + 0.09 * sin(angle * 5.0 + custom.y * 17.0);
	float edge = 0.86 + lump;
	if (d > edge) {
		discard;
	}
	vec3 col = water_color.rgb;
	// Lighter cel rim band.
	if (d > edge - 0.1) {
		col = rim_color.rgb;
	}
	// Hard-edged sky glint: a diagonal band that shifts per puddle.
	float band = p.x * 0.8 + p.y * 0.55 + (custom.w - 0.5) * 0.6;
	if (abs(band - 0.18) < 0.07 && d < edge - 0.12) {
		col = glint_color.rgb;
	}
	// Raindrop ripple ring (one per puddle, restarts), hard-edged.
	if (ripples > 0.5 && rain_density > 0.05) {
		float t = fract(TIME * 0.45 + custom.z);
		float ring = abs(d - t * (edge - 0.15));
		if (ring < 0.035 && t < 0.85) {
			col = glint_color.rgb;
		}
	}
	ALBEDO = col;
	ALPHA = alpha_scale * clamp(grow * 1.5, 0.0, 1.0);
}
