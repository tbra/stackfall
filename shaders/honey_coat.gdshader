shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Honey glaze (Bontago-1pi.85.64, simplified from 85.51): a smooth, glossy,
// slightly translucent amber skin. Three uses via two switches:
//   drip_mesh = false, ghost_mode = false : the glaze on a placed glued block.
//   drip_mesh = false, ghost_mode = true  : the preview on the held ghost; a faint
//     stable amber tint so the validity colour below stays readable.
//   drip_mesh = true : the few small hanging drips under a placed block's bottom edges.
// Tunables come from config/honey_coat_tuning.tres via HoneyCoatTuning.

uniform vec4 honey_color : source_color = vec4(0.98, 0.66, 0.1, 0.5);
uniform vec3 deep_amber : source_color = vec3(0.7, 0.32, 0.0);
uniform float thickness = 0.012;
uniform float roughness_value = 0.05;
uniform float rim_power = 2.5;
uniform float rim_strength = 0.6;
uniform float clearcoat_amount = 1.0;
uniform float clearcoat_roughness = 0.03;
uniform float shine_power = 28.0;
uniform float shine_strength = 0.9;
uniform vec3 shine_color : source_color = vec3(1.0, 0.96, 0.75);
uniform bool drip_mesh = false;
uniform bool ghost_mode = false;
uniform float ghost_alpha = 0.22;
uniform float drip_alpha = 0.85;
uniform float drip_length = 0.12;
uniform float drip_speed = 0.2;
uniform float sag_base = 0.5;
uniform float tear_narrow = 0.55;
uniform float patch_scale = 2.5;
uniform float patch_coverage = 0.85;
uniform float patch_edge = 0.06;
uniform float tongue_chance = 0.65;
uniform float tongue_min_len = 0.2;
uniform float tongue_max_len = 0.6;
uniform float tongue_width = 0.16;
uniform float lip_depth = 0.07;
uniform float top_swell = 0.035;
instance uniform vec3 lattice_origin = vec3(0.0);

// DECISION: hash seeds, the highlight direction and the sag root are shader math, not looks.
const vec3 SHINE_DIR = vec3(-0.35, 0.75, 0.55);
const float TAU_VALUE = 6.2831;
const vec3 PHASE_HASH = vec3(12.9898, 78.233, 37.719);
const float PHASE_SCALE = 43758.5453;
const float SAG_ROOT = 0.06;
const float TOP_NORMAL_Y = 0.7;
const float TONGUE_SLOTS = 3.0;
const float SLOT_JITTER = 0.12;
const float LIP_WOBBLE = 0.04;
const float WOBBLE_FREQ = 9.0;
const float EDGE_DARKEN = 0.55;

varying vec3 local_pos;
varying vec3 local_normal;

float hash31(vec3 p) {
	return fract(sin(dot(p, PHASE_HASH)) * PHASE_SCALE);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash31(i);
	float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash31(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
	if (drip_mesh) {
		// Sphere lobe on its anchor: the lower half sags slowly into a teardrop.
		float seed = fract(sin(dot(MODEL_MATRIX[3].xyz, PHASE_HASH)) * PHASE_SCALE);
		float sag = sag_base + (1.0 - sag_base) * (0.5 + 0.5 * sin(TIME * drip_speed * TAU_VALUE + seed * TAU_VALUE));
		float below = max(-VERTEX.y, 0.0);
		float reach = drip_length * sag * (0.5 + seed);
		float lower = step(0.0, -VERTEX.y);
		VERTEX.y -= lower * reach * smoothstep(0.0, 1.0, below / SAG_ROOT);
		float taper = mix(1.0, tear_narrow, lower * clamp(below / max(reach, 0.001), 0.0, 1.0));
		VERTEX.x *= taper;
		VERTEX.z *= taper;
	} else {
		// A thin constant swell keeps the glaze off the block surface (no z-fight).
		VERTEX += NORMAL * (thickness + top_swell * step(TOP_NORMAL_Y, NORMAL.y));
	}
}

// Distance to a vertical capsule (rounded tongue) hanging from d = 0 down to d = len.
float tongue_sdf(vec2 hd, float centre, float len, float radius) {
	float tip = max(len - radius, 0.0);
	vec2 q = vec2(hd.x - centre, hd.y - clamp(hd.y, 0.0, tip));
	return length(q) - radius;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float ndv = clamp(dot(n, normalize(VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - ndv, rim_power);
	float shine = pow(max(dot(n, normalize(SHINE_DIR)), 0.0), shine_power);
	float mask = 1.0;
	float edge_band = 0.0;
	if (!drip_mesh) {
		vec3 world_n = normalize((INV_VIEW_MATRIX * vec4(n, 0.0)).xyz);
		mask = 0.0;
		if (world_n.y > TOP_NORMAL_Y) {
			// Pool across the top: wobbly cut so it covers most of the face.
			float field = value_noise(local_pos * patch_scale) ;
			float cut = 1.0 - patch_coverage;
			mask = smoothstep(cut - patch_edge, cut + patch_edge, field);
			edge_band = 1.0 - smoothstep(cut + patch_edge, cut + patch_edge * 4.0, field);
		} else if (world_n.y > -TOP_NORMAL_Y) {
			// Side face: find which uv axis points up in the world, then the depth
			// below this face's top edge (d) and the position along it (h).
			vec2 uv = UV;
			vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
			mat2 m = transpose(mat2(dFdx(uv), dFdy(uv)));
			vec2 rhs = vec2(dFdx(wp.y), dFdy(wp.y));
			float det = m[0][0] * m[1][1] - m[1][0] * m[0][1];
			vec2 g = vec2(m[1][1] * rhs.x - m[1][0] * rhs.y, -m[0][1] * rhs.x + m[0][0] * rhs.y) / (abs(det) < 1e-9 ? 1e-9 : det);
			float d;
			float h;
			if (abs(g.x) > abs(g.y)) {
				d = g.x > 0.0 ? 1.0 - uv.x : uv.x;
				h = uv.y;
			} else {
				d = g.y > 0.0 ? 1.0 - uv.y : uv.y;
				h = uv.x;
			}
			vec3 cell = floor((local_pos - lattice_origin) - local_normal * 0.1 + vec3(0.001));
			vec3 axis = abs(round(local_normal));
			float face_seed = hash31(cell + axis * 7.0 + sign(local_normal) * 3.0);
			float lip = lip_depth + LIP_WOBBLE * (value_noise(vec3(h * WOBBLE_FREQ, face_seed * 10.0, 0.0)) - 0.5);
			float sdf = d - lip;
			for (int i = 0; i < 3; i++) {
				float fi = float(i);
				float hs = hash31(vec3(face_seed * 91.0, fi, 1.7));
				float ls = hash31(vec3(face_seed * 53.0, fi, 4.1));
				float ws = hash31(vec3(face_seed * 17.0, fi, 8.3));
				float on = step(1.0 - tongue_chance, hs);
				float centre = (fi + 0.5) / TONGUE_SLOTS + (ls - 0.5) * 2.0 * SLOT_JITTER;
				float len = mix(tongue_min_len, tongue_max_len, ls);
				float radius = tongue_width * (0.7 + 0.6 * ws) * 0.5;
				float t = tongue_sdf(vec2(h, d), centre, len, radius);
				sdf = on > 0.5 ? min(sdf, t) : sdf;
			}
			mask = 1.0 - smoothstep(-patch_edge * 0.25, patch_edge * 0.25, sdf);
			edge_band = 1.0 - smoothstep(0.0, -patch_edge, sdf);
		}
		if (mask < 0.01) {
			discard;
		}
	}
	vec3 body = mix(honey_color.rgb, deep_amber, clamp(edge_band * EDGE_DARKEN + fresnel * 0.5, 0.0, 1.0));
	ALBEDO = body;
	EMISSION = honey_color.rgb * (0.25 + fresnel * rim_strength) + shine_color * shine * shine_strength;
	ROUGHNESS = roughness_value;
	SPECULAR = 1.0;
	METALLIC = 0.0;
	CLEARCOAT = clearcoat_amount;
	CLEARCOAT_ROUGHNESS = clearcoat_roughness;
	float alpha = honey_color.a;
	if (ghost_mode) {
		alpha = ghost_alpha;
	}
	if (drip_mesh) {
		alpha = drip_alpha;
	}
	ALPHA = clamp(alpha, 0.0, 1.0) * mask;
}
