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

// DECISION: hash seeds, the highlight direction and the sag root are shader math, not looks.
const vec3 SHINE_DIR = vec3(-0.35, 0.75, 0.55);
const float TAU_VALUE = 6.2831;
const vec3 PHASE_HASH = vec3(12.9898, 78.233, 37.719);
const float PHASE_SCALE = 43758.5453;
const float SAG_ROOT = 0.06;

void vertex() {
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
		VERTEX += NORMAL * thickness;
	}
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float ndv = clamp(dot(n, normalize(VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - ndv, rim_power);
	float shine = pow(max(dot(n, normalize(SHINE_DIR)), 0.0), shine_power);
	ALBEDO = mix(honey_color.rgb, deep_amber, fresnel);
	EMISSION = honey_color.rgb * fresnel * rim_strength + shine_color * shine * shine_strength;
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
	ALPHA = clamp(alpha + fresnel * (1.0 - alpha), 0.0, 1.0);
}
