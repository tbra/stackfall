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

// Equirect panorama UV for a world direction, matching Godot's SKY_COORDS
// (U = atan(x, -z) / TAU wrapped, V = acos(y) / PI) plus the theme's
// yaw/pitch sampling offsets (see sunset_clouds.gdshader). Used by the
// cloud-puff mesh shader to fade distant puffs into exactly the sky colour
// drawn behind them, and by night_sky.gdshader for its far cloud sea.
vec2 sky_panorama_uv(vec3 dir, float yaw_deg, float pitch_deg) {
	vec3 d = normalize(dir);
	vec2 uv = vec2(atan(d.x, -d.z) / TAU, acos(clamp(d.y, -1.0, 1.0)) / PI);
	uv.x = fract(uv.x + yaw_deg / 360.0);
	uv.y = clamp(uv.y + pitch_deg / 180.0, 0.0, 1.0);
	return uv;
}

// Gradient map: the painted sunset panorama's luminance mapped onto a
// moonlit three-stop ramp (dark -> mid -> light), keeping every painted
// cloud form but none of its warm hue or sun glow. `amount` 0 returns `c`.
vec3 moonlit_grade(vec3 c, float amount, vec3 dark, vec3 mid, vec3 light, float gamma) {
	float l = pow(clamp(dot(c, vec3(0.299, 0.587, 0.114)), 0.0, 1.0), gamma);
	vec3 graded = cel_ramp(dark, mid, light, l);
	return mix(c, graded, amount);
}

// Two-phase flow sampling offset (the classic flow-map trick): the returned
// xy are the two UV displacements to sample, z the blend weight of the second.
// Each phase slides `flow` * `span` over one period, then fades out while the
// other (half a period apart) fades in, so the image drifts continuously with
// no accumulating smear. `jitter` (0..1, e.g. low-frequency noise) staggers
// the phase across the image so the cross-fade never pulses in unison.
vec3 flow_phases(float time, float period, float jitter) {
	float t = time / max(period, 0.001) + jitter;
	float a = fract(t);
	float b = fract(t + 0.5);
	return vec3(a - 0.5, b - 0.5, abs(1.0 - 2.0 * a));
}

// Panorama colour at mip 0 with the same symmetric edge blend as
// sunset_clouds.gdshader's sample_panorama(), for shaders that sample the
// panorama from a computed direction (no screen-space derivatives needed:
// the panorama is magnified at every in-game field of view).
vec3 panorama_lod(sampler2D pano, vec2 uv, float seam_width) {
	vec3 color = textureLod(pano, uv, 0.0).rgb;
	float seam = 1.0 - smoothstep(0.0, seam_width, min(uv.x, 1.0 - uv.x));
	return mix(color, textureLod(pano, vec2(1.0 - uv.x, uv.y), 0.0).rgb, seam * 0.5);
}
