// Shared helpers for the stylized (cel/banded) cloud look used by the sky
// shaders (sunset_clouds, night_sky) and the cloud-sea mesh
// (cloud_sea.gdshader). All three sample one seamless grayscale noise
// texture (config/sky_themes/cloud_noise.tres) rather than hashing math so
// the per-pixel cost is a few texture fetches.

// Three-octave value from a seamless 0..1 noise texture; returns 0..1.
float cloud_fbm(sampler2D noise_tex, vec2 p) {
	float v = texture(noise_tex, p).r * 0.5;
	v += texture(noise_tex, p * 2.03 + vec2(0.37, 0.11)).r * 0.3;
	v += texture(noise_tex, p * 4.11 + vec2(0.71, 0.43)).r * 0.2;
	return v;
}

// Snaps x (0..1) to `bands` flat steps with a narrow soft edge of half-width
// `edge` (in band units) so the cel steps stay anti-aliased.
float cel_quantize(float x, float bands, float edge) {
	float t = clamp(x, 0.0, 1.0) * bands;
	float base = floor(t);
	float f = fract(t);
	return clamp((base + smoothstep(0.5 - edge, 0.5 + edge, f)) / bands, 0.0, 1.0);
}

// Three-stop colour ramp: q 0 -> shadow, 0.5 -> mid, 1 -> lit.
vec3 cel_ramp(vec3 shadow, vec3 mid, vec3 lit, float q) {
	return q < 0.5 ? mix(shadow, mid, q * 2.0) : mix(mid, lit, q * 2.0 - 1.0);
}

// Billow "cumulus heightfield" in 0..1: |noise - 0.5| gives round lumps split
// by sharp creases (the crevices between cloud puffs); three octaves for
// big billows with smaller puffs on their flanks.
float billow(sampler2D perlin, vec2 p) {
	float n = abs(texture(perlin, p).r - 0.5) * 3.2;
	n = clamp(n, 0.0, 1.0);
	return 1.0 - (1.0 - n) * (1.0 - n);
}

float cumulus_height(sampler2D perlin, vec2 p) {
	return billow(perlin, p) * 0.7
		+ billow(perlin, p * 2.3 + vec2(0.31, 0.57)) * 0.22
		+ billow(perlin, p * 5.1 + vec2(0.7, 0.13)) * 0.08;
}
