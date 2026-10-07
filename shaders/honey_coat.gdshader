shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
// Honey coat (Bontago-1pi.85.51): thick golden glossy honey. One shader, two
// uses via drip_mesh: false = a coat laid over a block mesh (material_overlay),
// true = the hanging drip lobes HoneyCoatTuning builds under bottom edges
// (vertex-stretched downward, slowly sagging). Tunables come from
// config/honey_coat_tuning.tres via HoneyCoatTuning.

uniform vec4 honey_color : source_color = vec4(0.98, 0.7, 0.06, 0.93);
uniform float thickness = 0.03;
uniform float drip_scale = 6.0;
uniform float drip_speed = 0.35;
uniform float drip_depth = 0.25;
uniform float roughness_value = 0.05;
uniform float rim_power = 2.5;
uniform float rim_strength = 1.2;
uniform float drip_length = 0.35;
uniform bool drip_mesh = false;
uniform float lump_swell = 0.6;
uniform float lump_tilt = 0.45;
uniform vec3 deep_amber : source_color = vec3(0.62, 0.28, 0.0);
uniform float rim_darken = 0.55;
uniform float clearcoat_amount = 1.0;
uniform float clearcoat_roughness = 0.03;
uniform float base_glow = 0.04;
uniform float body_darken = 0.7;
uniform float shine_power = 28.0;
uniform float shine_strength = 1.6;
uniform vec3 shine_color : source_color = vec3(1.0, 0.96, 0.75);
uniform float sag_base = 0.35;
uniform float tear_narrow = 0.55;
uniform float reach_variation = 2.0;

// DECISION: the constants below are pure shader math (hash seeds, base frequencies), not looks.
const float LUMP_FREQUENCY = 5.0;
// DECISION: rim glow stays a shader constant; rim_strength scales it.
const float RIM_GLOW = 0.35;
const vec3 SHINE_DIR = vec3(-0.35, 0.75, 0.55);
const float TAU_VALUE = 6.2831;
const float PHASE_HASH = 12.9898;
const float PHASE_HASH_Y = 78.233;
const float PHASE_HASH_Z = 37.719;
const float PHASE_SCALE = 43758.5453;
const float LUMP_DRIFT = 3.0;
const float LUMP_SPREAD = 0.2;
const float REACH_BASE = 0.5;
const float SAG_ROOT = 3.0;

varying float v_lump;
varying float v_lump_y;

float lump(vec3 p) {
	return 0.5 + 0.5 * sin(p.x * LUMP_FREQUENCY * drip_scale * LUMP_SPREAD + sin(p.z * LUMP_FREQUENCY) + p.y * LUMP_DRIFT);
}

void vertex() {
	v_lump = lump(VERTEX);
	v_lump_y = lump(VERTEX.zyx);
	if (drip_mesh) {
		// Sphere lobe centred on its anchor: the lower half sags into a teardrop.
		float seed = fract(sin(dot(MODEL_MATRIX[3].xyz, vec3(PHASE_HASH, PHASE_HASH_Y, PHASE_HASH_Z))) * PHASE_SCALE);
		float sag = sag_base + (1.0 - sag_base) * (0.5 + 0.5 * sin(TIME * drip_speed * TAU_VALUE + seed * TAU_VALUE));
		float below = max(-VERTEX.y, 0.0);
		float reach = drip_length * sag * (REACH_BASE + drip_depth * reach_variation * seed);
		float lower = step(0.0, -VERTEX.y);
		VERTEX.y -= lower * reach * smoothstep(0.0, 1.0, below / max(thickness * SAG_ROOT, 0.001));
		float taper = mix(1.0, tear_narrow, lower * clamp(below / max(reach, 0.001), 0.0, 1.0));
		VERTEX.x *= taper;
		VERTEX.z *= taper;
	} else {
		VERTEX += NORMAL * thickness * (1.0 + drip_depth * lump_swell * 2.0 * v_lump);
	}
}

void fragment() {
	// Lumpy surface: tilt the normal so a wet highlight rolls across flat faces.
	NORMAL = normalize(NORMAL + vec3(v_lump - 0.5, v_lump_y - 0.5, 0.0) * lump_tilt);
	float shine = pow(max(dot(NORMAL, normalize(SHINE_DIR)), 0.0), shine_power);
	float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - ndv, rim_power);
	// Thick honey: golden face, deeper amber where the coat pools and at grazing edges.
	vec3 pooled = mix(honey_color.rgb, deep_amber, v_lump * drip_depth * 2.0);
	ALBEDO = mix(pooled, deep_amber, fresnel * rim_darken) * body_darken;
	EMISSION = honey_color.rgb * (base_glow + fresnel * RIM_GLOW * rim_strength) + shine_color * shine * shine_strength;
	ROUGHNESS = roughness_value;
	SPECULAR = 1.0;
	METALLIC = 0.0;
	CLEARCOAT = clearcoat_amount;
	CLEARCOAT_ROUGHNESS = clearcoat_roughness;
	ALPHA = clamp(honey_color.a + fresnel * (1.0 - honey_color.a), 0.0, 1.0);
}
