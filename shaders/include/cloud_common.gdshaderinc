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

// Bontago-59o.16 (procedural sky P2): pure helpers for the painted-panorama-free
// sunset. No texture taps, so they are safe in the radiance (cubemap) pass and
// never divide by eyedir.y (no NaN at the horizon).

// Three-stop vertical ramp on elevation `y` (= EYEDIR.y, -1..1). 0 -> horizon,
// `mid_height` -> mid, 1 -> zenith. The lower segment is linear, the upper one
// bends by `power`. Below the horizon the horizon colour is returned (the sea
// layer paints over it). `bands` > 0 snaps the ramp parameter into flat cel
// steps with soft edge `edge`; 0 keeps it smooth.
vec3 sky_gradient(float y, vec3 horizon, vec3 mid, vec3 zenith, float mid_height, float power, float bands, float edge) {
	float h = clamp(y, 0.0, 1.0);
	float m = clamp(mid_height, 0.001, 0.999);
	float t = h < m ? 0.5 * (h / m) : 0.5 + 0.5 * pow((h - m) / (1.0 - m), max(power, 0.001));
	if (bands > 0.5) {
		t = cel_quantize(t, bands, edge);
	}
	return t < 0.5 ? mix(horizon, mid, t * 2.0) : mix(mid, zenith, t * 2.0 - 1.0);
}

// Sun disc + halo mask around the sun direction. x = hard-edged disc (0..1,
// edge width `edge_deg`), y = cel-banded halo falloff (0..1) that reaches 0 at
// `halo_deg` and is snapped to `halo_bands` steps. `cos_angle` is dot(eyedir, sun_dir).
vec2 sun_disc(float cos_angle, float core_deg, float edge_deg, float halo_deg, float halo_bands, float band_edge) {
	float angle_deg = degrees(acos(clamp(cos_angle, -1.0, 1.0)));
	float disc = 1.0 - smoothstep(core_deg - edge_deg, core_deg + edge_deg, angle_deg);
	float falloff = 1.0 - smoothstep(core_deg, max(halo_deg, core_deg + 0.001), angle_deg);
	float halo = cel_quantize(falloff * falloff, halo_bands, band_edge);
	return vec2(disc, halo);
}

// Bontago-59o.16 (procedural sky P3): one plane-projected cel cloud stratum
// seen from above (dir.y < 0). `height` is the camera height above the stratum
// plane, so a smaller height is a nearer, faster-parallaxing sheet. Four noise
// taps (3 for the lumps, 1 for the sun-facing probe). Returns rgb + coverage
// alpha; `depth` must already be guarded > 0 by the caller.
vec4 procedural_sea_stratum(sampler2D noise_tex, vec3 dir, vec2 to_sun, float depth, float time, float height,
		float scale, vec2 drift_dir, float drift_speed, float coverage, float softness, float bands, float band_edge,
		float probe, float contrast, vec3 shadow, vec3 mid, vec3 lit, vec3 rim_color, bool lumpy) {
	vec2 q = dir.xz / depth * height * scale + drift_dir * drift_speed * time;
	float d = lumpy ? cumulus_height(noise_tex, q) : cloud_fbm(noise_tex, q);
	float d_sun = texture(noise_tex, q + to_sun * probe).r;
	float d_here = texture(noise_tex, q).r;
	float body = smoothstep(coverage, coverage + softness, d);
	float height01 = clamp((d - coverage) / max(1.0 - coverage, 0.001), 0.0, 1.0);
	float facing = clamp(0.5 + (d_here - d_sun) * contrast, 0.0, 1.0);
	float shade = clamp(height01 * 0.55 + facing * 0.45, 0.0, 1.0);
	vec3 col = cel_ramp(shadow, mid, lit, cel_quantize(shade, bands, band_edge));
	float rim = (1.0 - smoothstep(0.0, 0.2, height01)) * smoothstep(0.55, 0.85, facing);
	return vec4(mix(col, rim_color, rim * 0.6), body);
}

// Far cloud sea below the horizon for procedural_sea_mix: warm sun-lit tops,
// violet shadowed undersides, cel banding, slow drift, two parallax strata over
// a flat base. `dir` is the (normalised) view direction, `time` seconds.
// Guards dir.y == 0: the projection depth is clamped and the result fades to
// `haze` (the horizon colour) over `horizon_fade` of elevation, so no
// infinite/NaN coordinate is ever produced. Never call it from the radiance
// (cubemap) pass: it samples noise. `sea_params`: x far-stratum scale,
// y near-stratum scale, z drift speed, w cel bands. `heights`: x far, y near.
vec3 procedural_sea_color(sampler2D noise_tex, vec3 dir, vec3 sun_dir, float time, vec4 sea_params, vec2 heights,
		vec2 wind, float coverage, float softness, float band_edge, float horizon_fade,
		vec3 base_near, vec3 base_far, vec3 shadow, vec3 mid, vec3 lit, vec3 rim_color, vec3 haze) {
	float depth = max(-dir.y, 0.0005);
	float fade = 1.0 - smoothstep(0.0, max(horizon_fade, 0.001), depth);
	vec3 col = mix(base_near, base_far, smoothstep(0.0, 1.0, depth));
	if (fade < 0.999) {
		// DECISION (Bontago-59o.19): the 3D puffs (incl. the far ring added for the
		// procedural look) carry the bright lit cumulus tops; this shader deck is
		// only the violet-rose cloud floor between them, so its ramp tops out just
		// above `mid` and never paints flat white puddles.
		vec3 deck_lit = mix(mid, lit, 0.2);
		vec2 to_sun = normalize(sun_dir.xz + vec2(0.0001));
		vec4 far_s = procedural_sea_stratum(noise_tex, dir, to_sun, depth, time, heights.x, sea_params.x,
			wind, sea_params.z, coverage, softness, sea_params.w, band_edge, 0.04, 6.0,
			shadow, mid, deck_lit, deck_lit, false);
		// One low-contrast stratum only: a soft mottled cloud floor (the second
		// stratum was dropped; it read as flat puddles and cost 4 more taps).
		col = mix(col, far_s.rgb, far_s.a * 0.55);
	}
	return mix(col, haze, fade);
}

// Bontago-59o.19 (procedural sky pass 2): one upper cloud layer for the
// procedural look. Replaces the old stretched fbm strata, whose per-axis stretch
// read as radial streaks/spirals. The view direction is projected onto a high
// plane with a horizon lift (no divide by zero), rotated by `rot` radians
// (isotropic: layers differ by rotation and scale, never by stretch), domain
// warped, and shaped as broken cumulus/altocumulus: fbm blobs grouped by a
// low-frequency bank mask. Eight taps. Returns rgb + coverage alpha.
// `shape`: x warp amount, y bank-mask weight (0..1), z sun probe, w light contrast.
vec4 procedural_upper_clouds(sampler2D noise_tex, vec3 dir, vec2 to_sun, float time, float scale, float lift,
		float rot, vec2 wind, float speed, float coverage, float softness, float bands, float band_edge, vec4 shape,
		vec3 shadow, vec3 mid, vec3 lit, vec3 rim_color) {
	vec2 dp = dir.xz / (max(dir.y, 0.0) + max(lift, 0.05));
	float c = cos(rot);
	float s = sin(rot);
	vec2 q = vec2(dp.x * c - dp.y * s, dp.x * s + dp.y * c) * scale + wind * speed * time;
	vec2 w = vec2(texture(noise_tex, q * 0.6 + vec2(0.3, 0.7)).r, texture(noise_tex, q * 0.6 + vec2(0.9, 0.2)).r) - 0.5;
	q += w * shape.x;
	float bank = texture(noise_tex, q * 0.35 + vec2(0.17, 0.43)).r;
	// Smooth fbm blobs (billow creases read as marbled veins, not cumulus), grouped
	// into banks by the low-frequency mask.
	float lump = cloud_fbm(noise_tex, q);
	float d = mix(lump, bank, shape.y);
	float d_sun = mix(texture(noise_tex, q + to_sun * shape.z).r, bank, shape.y);
	float d_here = mix(texture(noise_tex, q).r, bank, shape.y);
	float body = smoothstep(coverage, coverage + softness, d);
	float height01 = clamp((d - coverage) / max(1.0 - coverage, 0.001), 0.0, 1.0);
	float facing = clamp(0.5 + (d_here - d_sun) * shape.w, 0.0, 1.0);
	float shade = clamp(height01 * 0.45 + facing * 0.5 + 0.1, 0.0, 1.0);
	vec3 col = cel_ramp(shadow, mid, lit, cel_quantize(shade, bands, band_edge));
	float rim = (1.0 - smoothstep(0.0, 0.18, height01)) * smoothstep(0.55, 0.85, facing);
	return vec4(mix(col, rim_color, rim * 0.6), body);
}

// Bontago-59o.20: authored cloud-card layer. `atlas` is the 4x2 Blender card
// atlas (tools/blender/make_cloud_cards.py): rg = camera-space normal xy,
// b = openness (AO), a = coverage. The view ray is projected onto a high plane
// (horizon lift avoids a divide by zero), jittered per grid cell, and each
// card is oriented so its up axis points at the zenith. Cards are cel-shaded
// with the live sun direction: lit tops, shadowed undersides, bright rim when
// backlit. Nine cells are tested; only cells that cover the pixel cost a tap.
// `layout`: x plane scale, y horizon lift, z density (0..1), w card half-size
// in cells. `contrast` stretches the wrapped lambert term around 0.5. `light`: x openness floor, y skylight up-bias, z rim power, w rim
// strength. `seed` decorrelates layers. Returns rgb + coverage alpha.
vec4 sky_cloud_cards(sampler2D atlas, vec3 dir, vec3 sun_dir, float time, vec4 layout, float seed,
		vec2 wind, float bands, float band_edge, vec4 light, float contrast,
		vec3 shadow, vec3 mid, vec3 lit, vec3 rim_color) {
	vec2 shift = wind * time;
	vec2 base = dir.xz / (max(dir.y, 0.0) + max(layout.y, 0.05)) * layout.x;
	vec2 dp = base + shift;
	float px = max(length(fwidth(base)), 0.00001);
	vec3 right_v = normalize(vec3(-dir.z, 0.0, dir.x) + vec3(0.00001, 0.0, 0.0));
	vec3 up_v = cross(right_v, dir);
	vec3 sun_v = vec3(dot(sun_dir, right_v), dot(sun_dir, up_v), dot(sun_dir, -dir));
	vec3 lh = normalize(sun_v + vec3(0.0, light.y, 0.0));
	float back = clamp(-sun_v.z, 0.0, 1.0);
	vec2 cell0 = floor(dp);
	vec3 acc = vec3(0.0);
	float acc_a = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 id = cell0 + vec2(float(i), float(j)) + vec2(seed);
			vec4 h = fract(sin(vec4(dot(id, vec2(127.1, 311.7)), dot(id, vec2(269.5, 183.3)),
				dot(id, vec2(419.2, 371.9)), dot(id, vec2(97.3, 53.1)))) * 43758.5453);
			if (h.x > layout.z) {
				continue;
			}
			vec2 centre = id - vec2(seed) + 0.5 + (h.yz - 0.5) * 0.5;
			float hs = layout.w * (0.65 + 0.7 * h.w);
			vec2 r = normalize(centre - shift + vec2(0.0001));
			vec2 q = dp - centre;
			float flip = h.y > 0.5 ? 1.0 : -1.0;
			float cu = dot(q, vec2(-r.y, r.x)) / hs * flip;
			float cv = dot(q, -r) / hs;
			if (abs(cu) >= 1.0 || abs(cv) >= 1.0) {
				continue;
			}
			float idx = floor(fract(h.x * 91.7 + h.z * 13.3) * 8.0);
			vec2 tile = vec2(mod(idx, 4.0), floor(idx / 4.0));
			vec2 uv = (tile + vec2(cu * 0.5 + 0.5, 0.5 - cv * 0.5)) / vec2(4.0, 2.0);
			float lod = max(log2(px / hs * 256.0), 0.0);
			vec4 d = textureLod(atlas, uv, lod);
			if (d.a < 0.01) {
				continue;
			}
			vec3 n = vec3((d.r * 2.0 - 1.0) * flip, d.g * 2.0 - 1.0, 0.0);
			n.z = sqrt(max(1.0 - dot(n.xy, n.xy), 0.0));
			float wrap = dot(n, lh) * 0.5 + 0.5;
			float shade = clamp((wrap - 0.5) * contrast + 0.5, 0.0, 1.0) * mix(light.x, 1.0, d.b) + cv * 0.08;
			vec3 col = cel_ramp(shadow, mid, lit, cel_quantize(shade, bands, band_edge));
			float rim = pow(1.0 - n.z, max(light.z, 0.1)) * back * light.w;
			col = mix(col, rim_color, clamp(rim, 0.0, 1.0));
			float a = d.a * (1.0 - acc_a);
			acc += col * a;
			acc_a += a;
		}
	}
	return vec4(acc / max(acc_a, 0.0001), acc_a);
}
