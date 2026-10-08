shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Honey glaze (Bontago-1pi.128, owner mockup): a glossy yellow pool across the top
// faces with a thin lip and a few rounded drip tongues hanging down each side; the
// rest of the side stays clean player colour. ghost_mode = true is the same honey at
// ghost_alpha on the held ghost so its validity colour shows through.
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
uniform bool ghost_mode = false;
uniform float ghost_alpha = 0.22;
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

// DECISION: hash seeds, the highlight direction, the top/side split angle, slot count and
// jitter, lip wobble and edge darkening are fixed shader math, not player-facing looks.
const vec3 SHINE_DIR = vec3(-0.35, 0.75, 0.55);
const vec3 PHASE_HASH = vec3(12.9898, 78.233, 37.719);
const float PHASE_SCALE = 43758.5453;
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
	// A thin swell keeps the glaze off the block surface (no z-fight); tops bulge a bit more.
	VERTEX += NORMAL * (thickness + top_swell * step(TOP_NORMAL_Y, NORMAL.y));
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
	// Derivatives must run in uniform control flow, so take them before any branch.
	vec2 uv = UV;
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 duv_dx = dFdx(uv);
	vec2 duv_dy = dFdy(uv);
	vec2 dy_screen = vec2(dFdx(wp.y), dFdy(wp.y));
	vec3 world_n = normalize((INV_VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float mask = 0.0;
	float edge_band = 0.0;
	if (world_n.y > TOP_NORMAL_Y) {
		// Pool across the top: wobbly cut so it covers most of the face.
		float field = value_noise(local_pos * patch_scale);
		float cut = 1.0 - patch_coverage;
		mask = smoothstep(cut - patch_edge, cut + patch_edge, field);
		edge_band = 1.0 - smoothstep(cut + patch_edge, cut + patch_edge * 4.0, field);
	} else if (world_n.y > -TOP_NORMAL_Y) {
		// Side face: which uv axis points up in the world (solve the 2x2 screen/uv
		// Jacobian for the gradient of world y), then depth d below this face's top
		// edge and position h along it.
		float det = duv_dx.x * duv_dy.y - duv_dx.y * duv_dy.x;
		float safe_det = abs(det) < 1e-12 ? 1e-12 : det;
		vec2 g = vec2(dy_screen.x * duv_dy.y - dy_screen.y * duv_dx.y, dy_screen.y * duv_dx.x - dy_screen.x * duv_dy.x) / safe_det;
		bool up_is_u = abs(g.x) > abs(g.y);
		float up_sign = up_is_u ? g.x : g.y;
		float along_up = up_is_u ? uv.x : uv.y;
		float d = up_sign > 0.0 ? 1.0 - along_up : along_up;
		float h = up_is_u ? uv.y : uv.x;
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
			float centre = (fi + 0.5) / TONGUE_SLOTS + (ls - 0.5) * 2.0 * SLOT_JITTER;
			float len = mix(tongue_min_len, tongue_max_len, ls);
			float radius = tongue_width * (0.7 + 0.6 * ws) * 0.5;
			float t = tongue_sdf(vec2(h, d), centre, len, radius);
			sdf = hs >= 1.0 - tongue_chance ? min(sdf, t) : sdf;
		}
		mask = 1.0 - smoothstep(-patch_edge * 0.25, patch_edge * 0.25, sdf);
		edge_band = 1.0 - smoothstep(0.0, -patch_edge, sdf);
	}
	if (mask < 0.01) {
		discard;
	}
	ALBEDO = mix(honey_color.rgb, deep_amber, clamp(edge_band * EDGE_DARKEN + fresnel * 0.5, 0.0, 1.0));
	EMISSION = honey_color.rgb * (0.25 + fresnel * rim_strength) + shine_color * shine * shine_strength;
	ROUGHNESS = roughness_value;
	SPECULAR = 1.0;
	METALLIC = 0.0;
	CLEARCOAT = clearcoat_amount;
	CLEARCOAT_ROUGHNESS = clearcoat_roughness;
	ALPHA = clamp(ghost_mode ? ghost_alpha : honey_color.a, 0.0, 1.0) * mask;
}
