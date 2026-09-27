shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
// Bontago-mp0.3.4 fix round (owner: the previous particle-burst trail read
// as "dashed/dotted... not attached to the falling piece"): one continuous
// mesh per streak (see BlockEffectsManager._build_trail_streak_mesh() for
// the geometry -- a single quad running from the mesh's own local origin,
// UV.y = 0, the "head" nearest the block, out to local -Z, UV.y = 1, the
// "tail"), so there is no gap by construction. This shader only fades alpha
// along that UV.y from head to tail; BlockEffectsManager re-orients and
// re-scales the mesh's own transform every frame to track the block and its
// fall speed, rather than this shader doing anything positional.

uniform vec4 trail_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float emission_energy = 1.2;
uniform float max_alpha = 0.8;

void fragment() {
	float fade = 1.0 - smoothstep(0.0, 1.0, UV.y);
	ALBEDO = trail_color.rgb;
	EMISSION = trail_color.rgb * emission_energy * fade;
	ALPHA = fade * max_alpha;
}
