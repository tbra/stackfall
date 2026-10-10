shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;
// Honey look A (Bontago-lv2): jelly shell. Each cell is a subdivided cube pushed toward a ball
// (corners rounded, faces shared with a glued neighbour cell stay flat so blobs merge), with a
// moving noise bulge and a down-hanging sag lobe on the lower half. Translucent so the block
// colour shows through. CUSTOM0 = (cell centre xyz, neighbour bitmask).
#include "res://shaders/include/honey_shading.gdshaderinc"

uniform float alpha = 0.72;
uniform float roundness = 0.5;
uniform float ball_radius = 0.7;
uniform float inflate = 0.04;
uniform float bulge = 0.05;
uniform float bulge_freq = 4.0;
uniform float wobble_speed = 1.2;
uniform float sag = 0.18;

// Wobble speed multipliers, per-axis frequency mix, gradient step and sag shaping are fixed shader math.
const float FREQ_Y = 1.3;
const float FREQ_Z = 0.9;
const float TIME_Y = 0.8;
const float TIME_Z = 1.1;
const float GRAD_EPS = 0.02;
const float SAG_FREQ = 5.0;
const float CELL_PHASE = 7.3;
const float NORMAL_ROUND_BOOST = 1.8;

float wob(vec3 p) {
	float t = TIME * wobble_speed;
	return sin(p.x * bulge_freq + t) * sin(p.y * bulge_freq * FREQ_Y - t * TIME_Y) * sin(p.z * bulge_freq * FREQ_Z + t * TIME_Z);
}

// How much of this vertex touches a glued neighbour cell (0 = free surface, 1 = on the shared face).
float closed_amount(vec3 d, float mask) {
	int m = int(mask + 0.5);
	float closed = 0.0;
	for (int axis = 0; axis < 3; axis++) {
		bool pos_set = (m & (1 << (axis * 2))) != 0;
		bool neg_set = (m & (1 << (axis * 2 + 1))) != 0;
		float v = d[axis] * 2.0;
		closed = max(closed, pos_set ? clamp(v, 0.0, 1.0) : 0.0);
		closed = max(closed, neg_set ? clamp(-v, 0.0, 1.0) : 0.0);
	}
	return closed;
}

void vertex() {
	vec3 c = CUSTOM0.xyz;
	float mask = CUSTOM0.w;
	vec3 d = VERTEX - c;
	vec3 n = NORMAL;
	float round_amount = roundness * (1.0 - closed_amount(d, mask));
	vec3 dir = normalize(d);
	vec3 p = mix(d, dir * ball_radius, round_amount);
	n = normalize(mix(n, dir, clamp(round_amount * NORMAL_ROUND_BOOST, 0.0, 1.0)));
	vec3 noise_pos = (c + d) * 1.0 + c * CELL_PHASE;
	float w = wob(noise_pos);
	p += n * (inflate + w * bulge);
	// Gradient of the bulge nudges the normal so highlights ripple.
	vec3 g = vec3(wob(noise_pos + vec3(GRAD_EPS, 0.0, 0.0)) - w, wob(noise_pos + vec3(0.0, GRAD_EPS, 0.0)) - w, wob(noise_pos + vec3(0.0, 0.0, GRAD_EPS)) - w) / GRAD_EPS;
	n = normalize(n - g * bulge);
	// Drip lobes: the lower half sags where a slow noise is high (not on faces glued to a cell below).
	float lower = clamp(-d.y * 2.0, 0.0, 1.0);
	float lobe = max(sin(d.x * SAG_FREQ + c.x * CELL_PHASE) * sin(d.z * SAG_FREQ + c.z * CELL_PHASE + c.y), 0.0);
	p.y -= sag * lower * lower * lobe * (1.0 - closed_amount(d, mask));
	VERTEX = c + p;
	NORMAL = n;
}

void fragment() {
	vec3 albedo;
	vec3 emission;
	honey_surface(dot(normalize(NORMAL), normalize(VIEW)), albedo, emission);
	ALBEDO = albedo;
	EMISSION = emission;
	ROUGHNESS = 0.1;
	SPECULAR = 0.0;
	ALPHA = alpha;
}
