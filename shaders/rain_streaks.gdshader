shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, skip_vertex_transform, shadows_disabled, fog_disabled;

// Bontago-22y.5: cel-styled rain (vfx/weather/RainPresentation.gd builds one
// MultiMesh of quads). All motion is computed here from TIME, so there is no
// per-frame script cost besides updating `center` from the camera. The volume
// is a box around `center`; streaks wrap inside it, so rain always surrounds
// the player's view rather than covering the whole map.
//
// INSTANCE_CUSTOM: x,y = horizontal position 0..1 in the box, z = fall phase
// 0..1, w = per-streak random 0..1 (density culling and speed jitter).

uniform vec3 center = vec3(0.0);
uniform float half_size = 32.0;
uniform float box_height = 40.0;
uniform float fall_speed = 38.0;
uniform float streak_length = 1.6;
uniform float streak_width = 0.035;
uniform vec2 slant = vec2(3.0, 0.0);
uniform vec3 streak_color : source_color = vec3(0.78, 0.88, 1.0);
uniform float streak_alpha = 0.55;
uniform float fade_far = 30.0;
uniform float density = 0.0;

varying float fade;

uniform float near_fade = 5.0;
uniform float min_screen_length = 0.02;

varying float tip;

void vertex() {
	float rnd = INSTANCE_CUSTOM.w;
	float fall = fall_speed * (0.85 + 0.3 * rnd);
	float drop = mod(INSTANCE_CUSTOM.z * box_height + TIME * fall, box_height);
	vec3 base = vec3((INSTANCE_CUSTOM.x * 2.0 - 1.0) * half_size, 0.0, (INSTANCE_CUSTOM.y * 2.0 - 1.0) * half_size);
	base.xz += slant * TIME;
	// Wrap horizontally relative to the camera-following center.
	vec2 rel = mod(base.xz - center.xz + vec2(half_size), vec2(half_size * 2.0)) - vec2(half_size);
	vec3 world = vec3(center.x + rel.x, center.y + box_height * 0.5 - drop, center.z + rel.y);
	vec3 dir = normalize(vec3(slant.x, -fall, slant.y));
	// Velocity-aligned billboard: both ends go to view space, the width is
	// taken perpendicular to the view ray, so it never collapses to a dot.
	vec3 v_top = (VIEW_MATRIX * vec4(world - dir * streak_length * 0.5, 1.0)).xyz;
	vec3 v_bot = (VIEW_MATRIX * vec4(world + dir * streak_length * 0.5, 1.0)).xyz;
	vec3 along = v_top - v_bot;
	vec3 v_mid = 0.5 * (v_top + v_bot);
	vec3 side = normalize(cross(along, v_mid) + vec3(1e-6));
	float t = VERTEX.y + 0.5;
	tip = t;
	vec3 view_pos = mix(v_bot, v_top, t) + side * VERTEX.x * streak_width;
	// Behind the camera or edge-on: collapse the streak instead of a dot.
	float in_front = step(v_mid.z, -0.1);
	vec2 s_top = v_top.xy / max(-v_top.z, 0.1);
	vec2 s_bot = v_bot.xy / max(-v_bot.z, 0.1);
	float screen_len = length(s_top - s_bot);
	float dist = length(v_mid);
	fade = (1.0 - smoothstep(fade_far * 0.5, fade_far, dist))
		* smoothstep(near_fade * 0.5, near_fade, dist)
		* smoothstep(min_screen_length, min_screen_length * 2.5, screen_len)
		* in_front * step(rnd, density)
		* smoothstep(0.0, 0.08, drop / box_height) * (1.0 - smoothstep(0.92, 1.0, drop / box_height));
	VERTEX = view_pos;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	// Crisp cel edge with a tapered tail (top of the streak fades out).
	float core = 1.0;
	float tail = tip;
	ALBEDO = streak_color;
	ALPHA = streak_alpha * fade * core * mix(0.35, 1.0, tail);
	if (ALPHA < 0.01) {
		discard;
	}
}
