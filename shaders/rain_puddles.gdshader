shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// Bontago-mp0.21: cel puddles on the disc top (vfx/weather/RainPuddles.gd draws
// one MultiMesh of flat quads). Presentation only. Per instance
// INSTANCE_CUSTOM: x = appear threshold 0..1 (patches grow in at different
// wetness), y = outline/ripple seed, z = darkness tint random, w = ripple phase.
// The old diagonal sky-glint band (the "line down the middle") and the global
// expanding ring are gone: rings are small, sparse and per-puddle random.

uniform float wetness = 0.0;
uniform vec4 water_color : source_color = vec4(0.06, 0.1, 0.17, 1.0);
uniform vec4 rim_color : source_color = vec4(0.3, 0.42, 0.55, 1.0);
uniform vec4 glint_color : source_color = vec4(0.8, 0.9, 1.0, 1.0);
uniform float alpha_scale = 0.8;
uniform float ripples = 1.0;
uniform float rain_density = 0.0;
uniform float ripple_period_min = 3.0;
uniform float ripple_period_max = 7.0;
uniform float ripple_radius = 0.16;
uniform float outline_irregularity = 0.18;
uniform float tint_variation = 0.18;

varying vec2 quad_uv;
varying vec4 custom;
varying float grow;

void vertex() {
	custom = INSTANCE_CUSTOM;
	grow = smoothstep(custom.x * 0.7, custom.x * 0.7 + 0.3, wetness);
	quad_uv = VERTEX.xz * 0.5;
	VERTEX.xz *= max(grow, 0.0001);
}

float hash11(float n) {
	return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

// Raindrop ring of one slot: a random spot inside the puddle, a small thin ring
// that widens and is gone before the next drop. Returns 1 on the ring.
float drop_ring(vec2 p, float edge, float seed, float slot) {
	float period = mix(ripple_period_min, ripple_period_max, hash11(seed + slot * 7.3));
	float t = TIME / period + hash11(seed * 3.1 + slot * 1.9);
	float id = floor(t);
	float ph = fract(t);
	float h = id * 13.7 + seed * 91.0 + slot * 5.1;
	vec2 centre = vec2(cos(hash11(h) * 6.2831853), sin(hash11(h) * 6.2831853)) * sqrt(hash11(h + 1.0)) * (edge - ripple_radius - 0.14);
	float r = ph * ripple_radius;
	float ring = abs(length(p - centre) - r);
	return (ring < 0.012 + 0.008 * (1.0 - ph) && ph < 0.75) ? 1.0 : 0.0;
}

void fragment() {
	if (grow <= 0.001) {
		discard;
	}
	// quad_uv spans -0.5..0.5 of the full-size patch; p is -1..1.
	vec2 p = quad_uv * 2.0;
	float angle = atan(p.y, p.x);
	float d = length(p) / max(grow, 0.0001);
	// Organic outline: whole-number lobes (so the angle seam stays continuous)
	// with per-puddle seeded amplitude and phase.
	float s = custom.y;
	float lump = 0.4 * sin(angle * 2.0 + hash11(s) * 6.28) * (0.4 + hash11(s + 1.0))
		+ 0.3 * sin(angle * 3.0 + hash11(s + 2.0) * 6.28) * (0.4 + hash11(s + 3.0))
		+ 0.2 * sin(angle * 5.0 + hash11(s + 4.0) * 6.28) * (0.4 + hash11(s + 5.0))
		+ 0.1 * sin(angle * 8.0 + hash11(s + 6.0) * 6.28);
	float edge = 0.76 + outline_irregularity * lump;
	if (d > edge) {
		discard;
	}
	float shade = 1.0 + (custom.z - 0.5) * 2.0 * tint_variation;
	vec3 col = water_color.rgb * shade;
	// Lighter cel rim band.
	if (d > edge - 0.1) {
		col = rim_color.rgb * mix(1.0, shade, 0.5);
	}
	// Sparse little raindrop rings, only while it rains and once the puddle is full-size.
	if (ripples > 0.5 && rain_density > 0.05 && grow > 0.95 && d < edge - 0.1) {
		float on = max(drop_ring(p, edge, s, 0.0), drop_ring(p, edge, s, 1.0));
		col = mix(col, glint_color.rgb, on * 0.55);
	}
	ALBEDO = col;
	ALPHA = alpha_scale * clamp(grow * 1.5, 0.0, 1.0);
}
