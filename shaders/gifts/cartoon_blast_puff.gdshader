shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;
// Bontago-a3z: one cartoon-blast fireball puff or debris chunk (game/gifts/specials/fx/
// CartoonBlast.gd). Flat cel bands from a fixed view-space key light, a dark rim
// outline, and a per-instance `heat` (1 white-hot, 0.5 flame, 0 smoke) that
// CartoonBlast lowers as the puff cools. Hot puffs push past 1.0 so they bloom.

uniform vec4 hot_color : source_color = vec4(1.0, 0.96, 0.6, 1.0);
uniform vec4 fire_color : source_color = vec4(1.0, 0.5, 0.1, 1.0);
uniform vec4 smoke_color : source_color = vec4(0.36, 0.33, 0.36, 1.0);
uniform vec4 outline_color : source_color = vec4(0.16, 0.08, 0.05, 1.0);
uniform float outline_width = 0.24;
uniform vec3 light_dir_view = vec3(-0.45, 0.75, 0.5);
uniform float hot_glow = 0.8;
instance uniform float heat = 1.0;

void fragment() {
	vec3 n = normalize(NORMAL);
	float lambert = dot(n, normalize(light_dir_view));
	float band = lambert > 0.55 ? 1.0 : (lambert > -0.1 ? 0.84 : 0.66);
	vec3 base = heat > 0.5
		? mix(fire_color.rgb, hot_color.rgb, (heat - 0.5) * 2.0)
		: mix(smoke_color.rgb, fire_color.rgb, heat * 2.0);
	vec3 colour = base * band;
	// A small hard highlight on hot puffs, the classic toon "shine".
	colour = mix(colour, vec3(1.0), step(0.92, lambert) * step(0.5, heat) * 0.6);
	colour *= 1.0 + hot_glow * max(heat - 0.5, 0.0) * 2.0;
	float rim = 1.0 - clamp(dot(n, VIEW), 0.0, 1.0);
	float line = smoothstep(1.0 - outline_width - 0.03, 1.0 - outline_width, rim);
	ALBEDO = mix(colour, outline_color.rgb, line);
}
