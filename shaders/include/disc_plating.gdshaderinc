// The territory disc's procedural cel plating, shared by shaders/territory/territory.gdshader (the top)
// and shaders/territory/arena_side_shell.gdshader (the SHADER_DOME side/underside look)
// so both draw the very same plates, seams and rivets.

// -- procedural cel plating (DiscSurfaceDef.Mode.PROCEDURAL) --
// Concentric rings of plates (plate count per ring grows with radius, random
// per-ring stagger and count jitter, so nothing tiles), crisp constant-pixel
// seams with a sun-facing lip, toon rivets, banded per-plate sheen. Detail
// fades with the camera's height above the disc (rivets first, then seams),
// uniformly across the whole disc, leaving a calm glossy disc from high up;
// a small per-pixel guard drops only sub-pixel detail at the grazing horizon. See proc_plating() below; the values are
// pushed from config/territory/DiscSurfaceDef.gd by game/field/TerritoryOverlay.gd.
uniform bool disc_procedural = false;
uniform vec3 disc_proc_base_tint = vec3(0.14, 0.155, 0.25);
uniform float disc_proc_hub_radius_m = 3.5;
uniform float disc_proc_ring_width_m = 4.5;
uniform float disc_proc_plate_length_m = 5.0;
uniform float disc_proc_plate_count_jitter = 0.3;
uniform float disc_proc_split_chance = 0.3;
uniform float disc_proc_tone_variation = 0.12;
uniform float disc_proc_hatch_chance = 0.06;
uniform float disc_proc_hatch_inset_m = 0.7;
uniform float disc_proc_hatch_tone = 0.88;
uniform float disc_proc_seam_width_px = 1.3;
uniform float disc_proc_seam_darkness = 0.85;
uniform float disc_proc_lip_width_px = 1.2;
uniform float disc_proc_lip_strength = 0.35;
uniform float disc_proc_lip_highlight = 0.07;
uniform float disc_proc_rivet_radius_m = 0.085;
uniform float disc_proc_rivet_spacing_m = 0.32;
uniform float disc_proc_rivet_inset_m = 0.3;
uniform float disc_proc_rivet_row_spacing_m = 0.75;
// Pattern weights: none, corner pairs, 2x2 corner clusters, edge rows.
uniform vec4 disc_proc_rivet_weights = vec4(0.1, 0.35, 0.35, 0.2);
uniform float disc_proc_rivet_tone = 2.4;
uniform float disc_proc_rivet_highlight = 0.14;
uniform float disc_proc_rivet_shadow = 0.75;
uniform float disc_proc_rivet_shade = 0.35;
uniform float disc_proc_rivet_shadow_offset = 0.6;
uniform vec3 disc_proc_highlight_color : source_color = vec3(1.0, 0.84, 0.62);
uniform float disc_proc_plate_tilt = 0.08;
uniform float disc_proc_sheen_strength = 0.08;
uniform float disc_proc_sky_sheen_power = 4.0;
uniform float disc_proc_sky_sheen_weight = 0.8;
uniform float disc_proc_sheen_exponent = 4.0;
uniform int disc_proc_sheen_bands = 3;
uniform float disc_proc_sheen_band_softness = 0.15;
uniform float disc_proc_brush_strength = 0.35;
uniform float disc_proc_brush_scale_m = 0.05;
uniform float disc_proc_roughness = 0.22;
uniform float disc_proc_roughness_variation = 0.08;
// Detail fades with the camera's HEIGHT above the disc top only, so the whole
// disc fades in and out together.
uniform float disc_proc_rivet_fade_height_start_m = 14.0;
uniform float disc_proc_rivet_fade_height_end_m = 22.0;
uniform float disc_proc_seam_fade_height_start_m = 24.0;
uniform float disc_proc_seam_fade_height_end_m = 40.0;
// Per-pixel anti-alias guard only (not a distance fade): detail smaller than
// this on screen is dropped so grazing horizon pixels never moire.
uniform float disc_proc_aa_rivet_min_px = 1.5;
uniform float disc_proc_aa_plate_min_px = 6.0;
uniform float disc_proc_brush_fade_px = 3.0;
// GraphicsPreset.disc_fine_detail_enabled. false (Low)
// drops the rivets and the brushed streaks, the two most expensive per-pixel
// details of proc_plating(); plates, seams, lips, hatches, tone and sheen stay.
uniform bool disc_fine_detail = true;

float hash11(float n) {
	return fract(sin(n) * 43758.5453123);
}

float value_noise_1d(float x) {
	float i = floor(x);
	float f = fract(x);
	float a = hash11(i);
	float b = hash11(i + 1.0);
	return mix(a, b, f * f * (3.0 - 2.0 * f));
}

// -- procedural cel plating -----------------------------------
// Fixed toon shape constants (the look's geometry, not tunables): where the
// lit/shaded crescents start on a rivet dome (dot with the sun, -1..1), the
// catchlight's offset/radius as fractions of the rivet radius, and the
// facing range over which a seam lip turns from shaded to lit.
const float PROC_RIVET_CRESCENT = 0.45;
const float PROC_GLINT_OFFSET = 0.35;
const float PROC_GLINT_RADIUS = 0.22;
const float PROC_LIP_FACING_RAMP = 0.3;
// Sine-free hash (hash12 by Dave Hoskins) of a small integer plate id + salt;
// no precision loss for the id range used here.
float proc_hash(vec2 id, float salt) {
	vec3 p3 = fract(vec3(id.x, id.y, salt) * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

// One toon rivet. `o` = offset of this pixel from the rivet centre (disc-local
// metres), `sun2` = horizontal direction toward the sun, `fw` = metres per
// pixel. Multiplies tone and adds to highlight.
void proc_rivet(vec2 o, vec2 sun2, float fw, float fade, inout float tone, inout float highlight) {
	float radius = max(disc_proc_rivet_radius_m, 0.001);
	float d = length(o);
	// Exact early-out. Past this reach the head
	// (radius + fw / 2), its cast shadow (head offset by radius * shadow_offset
	// along the unit sun2) and its outline (radius + outline_w + fw / 2) all
	// smoothstep to exactly 0, so every factor below is exactly 1.0 and the
	// highlight term exactly 0: skipping them leaves the pixel bit-identical.
	// Most plate pixels are nowhere near a rivet.
	float reach = radius * (1.0 + abs(disc_proc_rivet_shadow_offset))
		+ 0.5 * abs(disc_proc_seam_width_px) * fw + fw;
	if (d > reach) {
		return;
	}
	float body = 1.0 - smoothstep(radius - fw * 0.5, radius + fw * 0.5, d);
	vec2 shadow_o = o + sun2 * radius * disc_proc_rivet_shadow_offset;
	float cast_shadow = (1.0 - body)
		* (1.0 - smoothstep(radius - fw * 0.5, radius + fw * 0.5, length(shadow_o)));
	// Dome facing: -1 on the side away from the sun, +1 toward it. Crisp toon
	// thresholds, anti-aliased over about one pixel (fw / radius here).
	// Three toon tones on the head: a lit crescent toward the sun, a shaded
	// crescent away from it and the plain mid-tone cap between them, plus a
	// small catchlight dot on the lit side so the head reads as a dome.
	float facing = dot(o / radius, sun2);
	float aa = clamp(fw / radius, 0.02, 1.0);
	float lit = smoothstep(PROC_RIVET_CRESCENT - aa, PROC_RIVET_CRESCENT + aa, facing) * body;
	float shaded = smoothstep(PROC_RIVET_CRESCENT - aa, PROC_RIVET_CRESCENT + aa, -facing) * body;
	vec2 glint_o = o / radius - sun2 * PROC_GLINT_OFFSET;
	float glint = (1.0 - smoothstep(PROC_GLINT_RADIUS - aa, PROC_GLINT_RADIUS + aa, length(glint_o))) * body;
	// Thin dark toon outline around the head (the seam line width).
	float outline_w = 0.5 * disc_proc_seam_width_px * fw;
	float outline = 1.0 - smoothstep(outline_w - 0.5 * fw, outline_w + 0.5 * fw, abs(d - radius));
	tone *= mix(1.0, disc_proc_rivet_tone, body * fade);
	tone *= 1.0 - shaded * disc_proc_rivet_shade * fade;
	tone *= 1.0 - clamp(cast_shadow + outline, 0.0, 1.0) * disc_proc_rivet_shadow * fade;
	highlight += (lit + glint) * disc_proc_rivet_highlight * fade;
}

// Seam line + sun-facing lip for a groove `d` metres from this pixel;
// `into_plate` = unit direction from the groove toward the pixel. Width is
// constant in screen pixels (fwidth), like the block cell-grid seams.
void proc_groove(float d, vec2 into_plate, vec2 sun2, float fade, inout float tone, inout float highlight, inout float seam_occ) {
	float fw = max(fwidth(d), 0.00001);
	float half_w = 0.5 * disc_proc_seam_width_px * fw;
	float lip_end = half_w + disc_proc_lip_width_px * fw;
	// Exact early-out (after the fwidth above, which
	// must stay in uniform control flow). Past both the seam (half_w + fw / 2)
	// and the lip (lip_end + fw / 2) both masks smoothstep to exactly 0: tone
	// is multiplied by exactly 1.0, highlight gains 0 and seam_occ keeps its
	// value (it starts at 0), so the skip is bit-identical. Most pixels are
	// plate interior, not groove.
	if (d > max(half_w, lip_end) + fw) {
		return;
	}
	float seam = 1.0 - smoothstep(half_w - 0.5 * fw, half_w + 0.5 * fw, d);
	float lip = smoothstep(half_w - 0.5 * fw, half_w + 0.5 * fw, d)
		* (1.0 - smoothstep(lip_end - 0.5 * fw, lip_end + 0.5 * fw, d));
	// The plate edge beside a groove faces back toward the groove: lit when
	// that points at the sun, in shade when it points away.
	float edge_facing = dot(-into_plate, sun2);
	float lip_lit = smoothstep(0.0, PROC_LIP_FACING_RAMP, edge_facing);
	float lip_shade = smoothstep(0.0, PROC_LIP_FACING_RAMP, -edge_facing);
	tone *= 1.0 - seam * disc_proc_seam_darkness * fade;
	tone *= 1.0 - lip * lip_shade * disc_proc_lip_strength * fade;
	highlight += lip * lip_lit * disc_proc_lip_highlight * fade;
	seam_occ = max(seam_occ, seam * fade);
}

// The plating at disc-local point p (x, z): an albedo/fill multiplier, an
// additive highlight amount, a seam mask for the reflection, the per-plate
// sheen normal (disc-local), roughness and the brushed-streak value.
void proc_plating(vec2 p, vec2 sun2, float cam_height, out float tone, out float highlight, out float seam_occ,
		out vec3 plate_n, out float rough, out float brush) {
	tone = 1.0;
	highlight = 0.0;
	seam_occ = 0.0;
	float m_per_px = max(max(length(dFdx(p)), length(dFdy(p))), 0.00001);
	// Height fade: one value for the whole disc (camera height above the top).
	float seam_height_fade = 1.0 - smoothstep(
		disc_proc_seam_fade_height_start_m, disc_proc_seam_fade_height_end_m, cam_height);
	float rivet_height_fade = 1.0 - smoothstep(
		disc_proc_rivet_fade_height_start_m, disc_proc_rivet_fade_height_end_m, cam_height);
	// Anti-alias guard: drops only genuinely sub-resolution detail (plates a
	// few pixels across, sub-pixel rivets), i.e. the grazing horizon band.
	float plate_px = disc_proc_plate_length_m / m_per_px;
	float rivet_px = 2.0 * disc_proc_rivet_radius_m / m_per_px;
	float seam_fade = seam_height_fade
		* smoothstep(0.5 * disc_proc_aa_plate_min_px, disc_proc_aa_plate_min_px, plate_px);
	float rivet_fade = rivet_height_fade * seam_fade
		* smoothstep(0.5 * disc_proc_aa_rivet_min_px, disc_proc_aa_rivet_min_px, rivet_px);

	float r = max(length(p), 0.0001);
	vec2 r_hat = p / r;
	vec2 t_hat = vec2(-r_hat.y, r_hat.x);
	float hub = max(disc_proc_hub_radius_m, 0.0);
	float ring_w = max(disc_proc_ring_width_m, 0.1);

	vec2 plate_id = vec2(-1.0, 0.0);
	float u_c = p.x;
	float v_c = p.y;
	float half_u = 0.0;
	float half_v = 0.0;
	bool is_hub = r < hub;
	// Groove distance/direction and the hatch field are computed without
	// divergent branches around the derivative calls (fwidth in proc_groove),
	// so screen-space widths stay valid across plate and hub boundaries.
	float d_seam = hub - r;
	vec2 into_seam = -r_hat;
	float hatch_sd = 1000.0;
	vec2 hatch_grad = r_hat;
	if (!is_hub) {
		float ring = floor((r - hub) / ring_w);
		float r_in = hub + ring * ring_w;
		float circumference = TAU * (r_in + 0.5 * ring_w);
		float jitter = (proc_hash(vec2(ring, 0.0), 1.0) - 0.5) * 2.0 * disc_proc_plate_count_jitter;
		float count = max(3.0, round(circumference / max(disc_proc_plate_length_m, 0.1) * (1.0 + jitter)));
		float stagger = proc_hash(vec2(ring, 0.0), 2.0);
		// Integer count: the atan() wrap at +-PI shifts s by exactly `count`,
		// so fract(s) and mod(floor(s), count) stay continuous across it.
		float s = atan(p.y, p.x) / TAU * count + stagger;
		float plate = mod(floor(s), count);
		half_u = PI * r / count;
		u_c = (fract(s) - 0.5) * 2.0 * half_u;
		half_v = 0.5 * ring_w;
		v_c = r - (r_in + half_v);
		plate_id = vec2(ring, plate);
		if (proc_hash(plate_id, 3.0) < disc_proc_split_chance) {
			// Split lengthwise into an inner and an outer strip.
			float outer = v_c > 0.0 ? 1.0 : 0.0;
			half_v *= 0.5;
			v_c -= (outer * 2.0 - 1.0) * half_v;
			plate_id.y += 1000.0 * (outer + 1.0);
		}
		float d_u = half_u - abs(u_c);
		float d_v = half_v - abs(v_c);
		d_seam = min(d_u, d_v);
		into_seam = d_u < d_v ? -sign(u_c) * t_hat : -sign(v_c) * r_hat;
		// Access hatch: an inset groove loop with a slightly different cover.
		float inset = disc_proc_hatch_inset_m;
		if (proc_hash(plate_id, 4.0) < disc_proc_hatch_chance
			&& half_u > 2.0 * inset && half_v > 1.5 * inset) {
			vec2 q = vec2(abs(u_c) - (half_u - inset), abs(v_c) - (half_v - inset));
			hatch_sd = max(q.x, q.y);
			hatch_grad = q.x > q.y ? sign(u_c) * t_hat : sign(v_c) * r_hat;
		}
	}
	float fw_sd = max(fwidth(hatch_sd), 0.00001);
	tone *= mix(1.0, disc_proc_hatch_tone, (1.0 - smoothstep(-fw_sd, fw_sd, hatch_sd)) * seam_fade);
	if (abs(hatch_sd) < d_seam) {
		d_seam = abs(hatch_sd);
		into_seam = (hatch_sd > 0.0 ? 1.0 : -1.0) * hatch_grad;
	}
	proc_groove(d_seam, into_seam, sun2, seam_fade, tone, highlight, seam_occ);

	// Rivets: one pattern per plate, chosen by disc_proc_rivet_weights.
	if (disc_fine_detail && rivet_fade > 0.0) {
		float inset = disc_proc_rivet_inset_m;
		float spacing = disc_proc_rivet_spacing_m;
		if (is_hub) {
			float ring_r = hub - inset;
			if (ring_r > inset) {
				float n = max(3.0, floor(TAU * ring_r / max(disc_proc_rivet_row_spacing_m, 0.05)));
				float ang = round(atan(p.y, p.x) / TAU * n) / n * TAU;
				proc_rivet(p - vec2(cos(ang), sin(ang)) * ring_r, sun2, m_per_px, rivet_fade, tone, highlight);
			}
		} else {
			vec4 w = max(disc_proc_rivet_weights, vec4(0.0));
			float pick = proc_hash(plate_id, 5.0) * max(w.x + w.y + w.z + w.w, 0.0001);
			// Folded corner coordinates: distance from the nearest plate corner
			// along each edge; dir_a/dir_b point into the plate.
			float a = half_u - abs(u_c);
			float b = half_v - abs(v_c);
			vec2 dir_a = -sign(u_c) * t_hat;
			vec2 dir_b = -sign(v_c) * r_hat;
			bool any_rivet = true;
			vec2 o = vec2(0.0);
			if (pick < w.x) {
				any_rivet = false;
			} else if (pick < w.x + w.y) {
				float ka = clamp(round((a - inset) / spacing), 0.0, 1.0);
				o = dir_a * (inset + ka * spacing - a) + dir_b * (inset - b);
			} else if (pick < w.x + w.y + w.z) {
				float ka = clamp(round((a - inset) / spacing), 0.0, 1.0);
				float kb = clamp(round((b - inset) / spacing), 0.0, 1.0);
				o = dir_a * (inset + ka * spacing - a) + dir_b * (inset + kb * spacing - b);
			} else {
				float span = max(2.0 * (half_u - inset), 0.0);
				float n = max(1.0, floor(span / max(disc_proc_rivet_row_spacing_m, 0.05)));
				float step_u = span / n;
				float k = clamp(round((u_c + half_u - inset) / max(step_u, 0.0001)), 0.0, n);
				float cu = -half_u + inset + k * step_u;
				o = t_hat * (cu - u_c) + dir_b * (inset - b);
			}
			// o above points from the pixel to the rivet; proc_rivet wants the
			// pixel's offset from the rivet centre.
			if (any_rivet) {
				proc_rivet(-o, sun2, m_per_px, rivet_fade, tone, highlight);
			}
		}
	}

	tone *= 1.0 + (proc_hash(plate_id, 6.0) - 0.5) * 2.0 * disc_proc_tone_variation * seam_fade;
	vec2 tilt = (vec2(proc_hash(plate_id, 7.0), proc_hash(plate_id, 8.0)) - 0.5)
		* 2.0 * disc_proc_plate_tilt * seam_fade;
	plate_n = normalize(vec3(tilt.x, 1.0, tilt.y));

	// Brushed streaks along or across each plate (sheen/roughness only).
	brush = 0.0;
	if (disc_fine_detail) {
		float brush_coord = proc_hash(plate_id, 9.0) < 0.5 ? u_c : v_c;
		float scale = max(disc_proc_brush_scale_m, 0.001);
		float brush_fade = smoothstep(disc_proc_brush_fade_px, 2.0 * disc_proc_brush_fade_px, scale / m_per_px);
		brush = (value_noise_1d(brush_coord / scale + proc_hash(plate_id, 10.0) * 97.0) - 0.5)
			* 2.0 * disc_proc_brush_strength * brush_fade;
	}
	rough = disc_proc_roughness
		+ (proc_hash(plate_id, 11.0) - 0.5) * 2.0 * disc_proc_roughness_variation * seam_fade
		+ brush * disc_proc_roughness_variation;
}
