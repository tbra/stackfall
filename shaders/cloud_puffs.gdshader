shader_type spatial;
render_mode unshaded, world_vertex_coords, cull_back, depth_draw_always, fog_disabled, shadows_disabled;
#include "res://shaders/include/cloud_common.gdshaderinc"

// Bontago-adt.1: stylized cumulus puffs below the floating disc
// (vfx/CloudSea.gd builds one MultiMesh of flat-bottomed low-poly spheres
// clustered into cumulus clumps). Opaque and toon-lit in the shader itself
// (no scene lights, shadows or fog), so the same material works at sunset
// and at night from theme colours alone.
//
// Per-pixel shape: the mesh is only an inflated bounding hull. Each fragment
// intersects its view ray with the puff's ellipsoid, whose radius is pushed
// out by round cauliflower domes (cellular noise, triplanar on the unit
// sphere) and a slow billow wave, and discards rays that miss -- so
// silhouettes are round and lumpy at any distance with no mesh facets, and
// shading uses the true entry point and ellipsoid normal.
//
// Motion is all here, driven by TIME and per-instance custom data, so it
// runs in the game, the editor and the baked demo with no script:
//  - drift: every puff orbits the disc's vertical axis at its clump's own
//    angular speed (INSTANCE_CUSTOM.x), so clumps slide past each other;
//  - billow/boil: the silhouette breathes and the dome pattern slides slowly.
// Shading: wrap-lit N.L against the (elevation-lifted) sun/moon plus a
// height-in-clump term and the dome pattern, split into three flat cel tones
// (shadow/mid/lit) with pixel-crisp edges; a sun-side and backlit fresnel
// rim; darker flat undersides.
// Seamless far fade: with distance (and depth below the disc) the colour
// blends into exactly the sky colour behind the puff -- the theme's
// panorama sampled along the view ray (moonlit-graded at night) -- so
// distant clumps melt into the painted far cloud sea with no seam or edge.
// Near fade: fragments close to the camera dissolve (ordered dither) so a
// camera orbiting under the disc is never blocked by a puff.
//
// DECISION (Bontago-adt.1): drawn in the transparent pass (writes ALPHA = 1,
// still writes depth, vfx/CloudSea.gd gives it the lowest render_priority so
// every other transparent draws over it). In the opaque pass the puffs' depth
// fed the disc's screen-space reflections, which then "hit" puffs below the
// disc and painted cloud patches onto the disc surface; the transparent pass
// is not part of the SSR/SSAO depth, and it also skips the depth prepass that
// a discarding opaque shader pays for twice.

// Shared with the sky material (vfx/CloudSea.gd copies these from it).
uniform sampler2D panorama : source_color, filter_linear_mipmap, repeat_enable;
uniform float exposure = 0.8;
uniform float seam_blend_width = 0.025;
uniform float sky_yaw_offset_deg = 0.0;
uniform float sky_pitch_offset_deg = 0.0;
uniform float grade_amount = 0.0;
uniform vec3 grade_dark : source_color = vec3(0.02, 0.03, 0.08);
uniform vec3 grade_mid : source_color = vec3(0.12, 0.17, 0.33);
uniform vec3 grade_light : source_color = vec3(0.55, 0.64, 0.82);
uniform float grade_gamma = 1.2;

// Bontago-59o.16 (procedural sky P4): when procedural_sea_mix > 0 the far fade
// targets the shared procedural sky/sea (cloud_common.gdshaderinc) instead of
// the panorama. vfx/CloudSea.gd copies every uniform below from the sky
// material; all are inert at procedural_sea_mix == 0.
uniform float procedural_sea_mix = 0.0;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 sun_direction = vec3(0.963087, 0.069011, -0.260192);
uniform vec4 proc_zenith_color : source_color = vec4(0.161, 0.2, 0.333, 1.0);
uniform vec4 proc_mid_color : source_color = vec4(0.55, 0.36, 0.5, 1.0);
uniform vec4 proc_horizon_color : source_color = vec4(0.98, 0.64, 0.38, 1.0);
uniform float proc_gradient_mid_height = 0.35;
uniform float proc_gradient_power = 1.5;
uniform float proc_gradient_bands = 8.0;
uniform float proc_gradient_band_edge = 0.12;
uniform vec4 proc_horizon_glow_color : source_color = vec4(1.0, 0.62, 0.28, 1.0);
uniform float proc_horizon_glow_width = 0.18;
uniform float proc_horizon_glow_strength = 0.45;
uniform float proc_horizon_glow_sun_bias = 3.0;
uniform vec4 proc_sea_color_near : source_color = vec4(0.85, 0.5, 0.42, 1.0);
uniform vec4 proc_sea_color_far : source_color = vec4(0.34, 0.27, 0.47, 1.0);
uniform float proc_sea_horizon_fade = 0.12;
uniform vec4 proc_sea_params = vec4(0.5, 0.9, 0.004, 4.0);
uniform vec2 proc_sea_heights = vec2(1.0, 0.6);
uniform vec2 proc_sea_wind = vec2(1.0, 0.35);
uniform float proc_sea_coverage = 0.5;
uniform float proc_sea_softness = 0.06;
uniform float proc_sea_band_edge = 0.08;
uniform vec3 cloud_shadow_color : source_color = vec3(0.34, 0.27, 0.47);
uniform vec3 cloud_mid_color : source_color = vec3(0.86, 0.55, 0.52);
uniform vec3 cloud_lit_color : source_color = vec3(1.0, 0.82, 0.52);
uniform vec3 cloud_rim_color : source_color = vec3(1.0, 0.9, 0.66);
// Copied from SkyThemeDef.cloud_flat_base: the mesh's flat base plane, in
// unit-sphere space below each puff's centre.
uniform float flat_base = 0.15;

// Direction toward the sun / moon.
uniform vec3 light_direction = vec3(0.963087, 0.069011, -0.260192);
// Shading light is lifted to at least this elevation so tops read lit even
// with the sun on the horizon.
uniform float min_light_elevation = 0.3;
uniform vec3 shadow_color : source_color = vec3(0.27, 0.32, 0.48);
uniform vec3 mid_color : source_color = vec3(0.57, 0.41, 0.49);
uniform vec3 lit_color : source_color = vec3(1.0, 0.6, 0.3);
uniform vec3 rim_color : source_color = vec3(1.0, 0.78, 0.42);
// Shade value thresholds between the three flat tones (shadow | mid | lit)
// and their anti-aliased edge width in pixels.
uniform float mid_threshold = 0.38;
uniform float lit_threshold = 0.64;
uniform float band_edge_px = 1.0;
uniform float light_weight = 0.7;
uniform float height_weight = 0.2;
uniform float ambient_shade = -0.05;
uniform float underside_shade = 0.25;
// Bontago-mp0.93 (cloud undersides, seen from below by the upper layer): the flat
// base's normal eases from straight down to the side normal over the outer part
// of the base, starting at this share of the lumpy radius.
uniform float base_rim_start = 0.55;
// Shade lift at the base's centre (light bounced up from the sea), fading out
// toward the rim, so the domes read as soft mid-tone mottling on the underbelly
// instead of one flat shadow tone.
uniform float base_bounce = 0.5;
// A clump's bases lie in one plane: each puff lifts its own base by up to this
// many metres so overlapping bases do not z-fight into stripes.
uniform float base_stagger_m = 0.4;
// Bontago-mp0.93: the upper layer is seen from below, where a flat base is one huge
// featureless slab. vfx/CloudSea.gd gives that layer its own base plane height through
// flat_base_override (< 0 = this material's flat_base, the sea's cumulus bottoms);
// at or above round_base_from there is no plane at all: the puffs are whole ellipsoids
// whose lower half is the (lumpy) underside. Their down-facing surfaces get the
// underbelly bounce by how far the normal points down, from round_under_start.
uniform float round_base_from = 0.9;
uniform float round_under_start = 0.3;
// Upper layer only (floor_on): surfaces less than base_clear_start_m above the camera dither
// away, solid from base_clear_end_m up, so a camera just under the layer never sees a
// razor-flat cloud bottom edge-on. 0 end = off.
uniform float base_clear_start_m = 0.0;
uniform float base_clear_end_m = 0.0;
uniform float rim_power = 4.0;
uniform float rim_sun_side = 0.9;
uniform float rim_backlight = 1.4;
uniform float rim_threshold = 0.5;
uniform float rim_softness = 0.08;
// Bontago-mp0.93: upper puffs (floor_on) lose their rim on side faces, not only on down-facing
// ones: the thin yellow slivers along the cloud's lower and side edges. The cut-off normal.y
// moves up by this much there (0 = the sea's rule).
uniform float upper_rim_down_shift = 0.1;

// Cauliflower domes from a cellular (F1 distance) noise texture
// (config/sky_themes/puff_noise.tres). The silhouette octave is
// lump_vertex_scale x the shading frequency and pushes the radius out by up
// to lump_height (fraction of radius, centred on lump_bias); the shading
// uses the base frequency plus a finer octave (lump_detail_scale, lump_detail_weight) that scallops
// the band edges (lump_shade). The pattern slides slowly (lump_speed).
uniform sampler2D puff_noise : filter_linear_mipmap, repeat_enable;
uniform float lump_frequency = 0.4;
uniform float lump_cell_radius = 1.0;
uniform float lump_height = 0.35;
uniform float lump_vertex_scale = 0.7;
uniform float lump_detail_scale = 2.3;
uniform float lump_detail_weight = 0.4;
uniform float lump_shade = 0.35;
uniform float lump_bias = 0.6;
uniform float lump_speed = 0.004;
// The fine octave is skipped beyond this camera distance (faded out from 60%).
uniform float detail_lod_m = 260.0;
// Silhouette breathing: amplitude (fraction of radius), speed, and how many
// wave crests run around a puff.
uniform float billow_amount = 0.03;
uniform float billow_speed = 0.35;
uniform float billow_frequency = 2.0;
// Extra hull inflation (fraction of radius) covering the low-poly chord error.
uniform float hull_margin = 0.04;
// Bontago-mp0.93: the hull's flat faces dip below the sphere between vertices (the High preset's
// 80-face puff by about 6%), more than hull_margin covers, so the tops of the largest lumps were
// sliced off along straight face edges (vertical and diagonal razor edges on big overhead clumps).
// Vertex stage only, on top of hull_margin; the carved silhouette itself does not change.
uniform float hull_chord_margin = 0.05;

// Bontago-470.3: weather fog for a fog_disabled shader (see
// vfx/weather/WeatherFogShader.gd). Nothing closer than wfog_begin metres from
// the camera, wfog_strength at wfog_end; 0 strength = off.
uniform float wfog_strength : hint_range(0.0, 1.0) = 0.0;
uniform float wfog_begin = 25.0;
uniform float wfog_end = 110.0;
uniform vec4 wfog_color : source_color = vec4(0.72, 0.8, 0.88, 1.0);
uniform float fade_start_m = 160.0;
uniform float fade_end_m = 500.0;
uniform float depth_fade_start_m = 40.0;
uniform float depth_fade_end_m = 140.0;
uniform float depth_fade_amount = 0.45;
// Bontago-59o.19: cap on the combined distance/depth fade into the sky (1 = none,
// the painted look; the procedural look sets <1 so far puffs stay shaded cumulus).
uniform float far_fade_cap = 1.0;
uniform float near_fade_start_m = 5.0;
uniform float near_fade_end_m = 16.0;

// Bontago-mp0.29: weather grade shared with the weather cloud ceiling
// (CloudLighting.grade): desaturate toward luminance, then darken.
uniform float weather_dim : hint_range(0.0, 1.0) = 0.0;
uniform float weather_desaturate : hint_range(0.0, 1.0) = 0.0;

// Bontago-mp0.34: per-tone brightness floor after the weather grade (lit tone
// colour; the shadow / mid tones use these shares of it) so night and storm
// puffs fade to deep slate, never black. (0,0,0) = off.
uniform vec3 weather_floor : source_color = vec3(0.0);
uniform float floor_shadow_ratio = 0.55;
uniform float floor_mid_ratio = 0.8;
// Soft silhouette width in pixels (upper puffs); 0 keeps the hard cut.
instance uniform float edge_soft_px : hint_range(0.0, 8.0) = 0.0;
// 1 on the upper puff layer (the floor above applies there only), 0 on the sea.
instance uniform float floor_on : hint_range(0.0, 1.0) = 0.0;
instance uniform float flat_base_override : hint_range(-1.0, 1.0) = -1.0;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 puff_centre;
varying vec2 puff_axes;
varying float puff_seed;
varying float base_y;
varying float clump_height;
// The puff's base plane height (flat_base or flat_base_override).
varying float base_flat;

// Round dome (1 at a cell centre, 0 on the crease between cells); 0..1.
// lump_cell_radius is the normalized F1 distance treated as a cell's edge.
float dome(vec2 p) {
	float f1 = clamp(texture(puff_noise, p).r / lump_cell_radius, 0.0, 1.0);
	return 1.0 - f1 * f1;
}

// Triplanar domes on a unit-sphere direction, `scale` x the base frequency.
// `to_sides` 1 = the plain triplanar mix; toward 0 the weights move to a
// top-down map over `under_xz` (the point's own horizontal position in unit
// space; pass u.xz when to_sides is 1). The flat base needs that: its
// direction is nearly horizontal with a constant y and a saturated u.xz, so the
// triplanar weights switch along the 45-degree diagonals and the maps streak
// (wedge-shaped shards on the underside).
float lumps(vec3 u, float seed, float t, float scale, float to_sides, vec2 under_xz) {
	vec3 w = abs(u);
	w = w * w * w;
	w /= max(w.x + w.y + w.z, 0.0001);
	w = mix(vec3(0.0, 1.0, 0.0), w, to_sides);
	vec2 o = vec2(seed * 0.137 + t, seed * 0.291 - t * 0.7);
	float f = lump_frequency * scale;
	vec2 top_down = mix(under_xz, u.xz, to_sides);
	return dome(u.yz * f + o) * w.x + dome(top_down * f + o) * w.y + dome(u.xy * f + o) * w.z;
}

mat2 rot2(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}

void vertex() {
	// world_vertex_coords: VERTEX and NORMAL arrive in world space.
	vec3 centre = MODEL_MATRIX[3].xyz;
	vec2 axes = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
	// Inflate the hull to the largest silhouette the fragment stage can carve
	// (the flat base stays put).
	float inflate = lump_height * (1.0 - lump_bias) + billow_amount + hull_margin + hull_chord_margin;
	// NORMAL is not unit length under the instance scale: normalize first.
	vec3 hull_normal = normalize(NORMAL);
	float plane = flat_base_override < 0.0 ? flat_base : flat_base_override;
	bool round_bottom = plane >= round_base_from;
	// A round-bottomed puff inflates all the way round, its underside included.
	VERTEX += hull_normal * inflate * max(axes.x, axes.y) * (round_bottom ? 1.0 : smoothstep(-0.3, 0.3, hull_normal.y));
	// The flat base polygon is widened to cover the lumpy silhouette too (the
	// fragment stage clips it to the same radius as the sides), so the underside
	// joins the body instead of ending at the bare chord polygon.
	if (hull_normal.y < -0.7 && !round_bottom) {
		VERTEX.xz = centre.xz + (VERTEX.xz - centre.xz) * (1.0 + 2.0 * inflate);
		// INSTANCE_CUSTOM.y is the puff's seed in 0..TAU: its own share of the stagger.
		VERTEX.y += base_stagger_m * INSTANCE_CUSTOM.y / TAU;
	}
	mat2 r = rot2(TIME * INSTANCE_CUSTOM.x);
	VERTEX.xz = r * VERTEX.xz;
	NORMAL = hull_normal;
	NORMAL.xz = r * NORMAL.xz;
	centre.xz = r * centre.xz;
	world_pos = VERTEX;
	world_normal = NORMAL;
	puff_centre = centre;
	puff_axes = axes;
	puff_seed = INSTANCE_CUSTOM.y;
	base_y = INSTANCE_CUSTOM.z;
	clump_height = max(INSTANCE_CUSTOM.w, 0.001);
	base_flat = plane;
}

// 4x4 ordered dither threshold in 0..1.
float bayer4(vec2 frag) {
	ivec2 p = ivec2(mod(frag, 4.0));
	int i = p.x + p.y * 4;
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[i]) + 0.5) / 16.0;
}

void fragment() {
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 to_frag = world_pos - cam;
	float dist = length(to_frag);
	float near = smoothstep(near_fade_start_m, near_fade_end_m, dist);
	if (near < bayer4(FRAGCOORD.xy)) {
		discard;
	}
	vec3 view_dir = to_frag / max(dist, 0.001);
	vec3 axes = vec3(puff_axes.x, puff_axes.y, puff_axes.x);
	float t_boil = TIME * lump_speed;
	vec3 mesh_n = normalize(world_normal);
	bool round_bottom = base_flat >= round_base_from;
	bool on_base = mesh_n.y < -0.7 && !round_bottom;
	float edge_alpha = 1.0;
	// Bontago-mp0.93: share of the side shading on a base fragment (1 on every
	// other fragment); see base_rim_start.
	float base_ramp = 1.0;

	// Ray against the lumpy ellipsoid, in the puff's unit-sphere space.
	vec3 o = (cam - puff_centre) / axes;
	vec3 v = view_dir / axes;
	float vv = dot(v, v);
	float t_close = -dot(o, v) / vv;
	vec3 closest = o + v * t_close;
	float closest_sq = dot(closest, closest);
	vec3 unit = (world_pos - puff_centre) / axes;
	// Silhouette: the dome radius in the ray's closest-approach direction.
	// Rays that cannot reach even the largest possible puff skip the fetches.
	if (!on_base) {
		float max_radius = 1.0 + (1.0 - lump_bias) * lump_height + billow_amount;
		if (closest_sq > max_radius * max_radius) {
			discard;
		}
		vec3 dir = normalize(closest);
		float coarse = lumps(dir, puff_seed, t_boil, lump_vertex_scale, 1.0, dir.xz);
		float wave = sin(TIME * billow_speed + puff_seed + dot(dir, vec3(1.0, 0.7, 1.3)) * billow_frequency);
		float radius = 1.0 + (coarse - lump_bias) * lump_height + wave * billow_amount;
		float miss = closest_sq - radius * radius;
		float soft = fwidth(miss) * edge_soft_px;
		if (miss > soft) {
			discard;
		}
		if (soft > 0.0) {
			edge_alpha = 1.0 - smoothstep(0.0, soft, miss);
		}
		vec3 entry = o + v * (t_close - sqrt(max(-miss, 0.0) / vv));
		// The part of the ellipsoid below the flat base does not exist.
		if (!round_bottom && entry.y < -base_flat) {
			discard;
		}
		if (t_close > 0.0) {
			unit = entry;
		}
	} else {
		// Flat base: clip to the very same lumpy radius the sides use in this
		// direction, so side and base meet along one continuous edge.
		vec3 dir = normalize(unit);
		float coarse = lumps(dir, puff_seed, t_boil, lump_vertex_scale, 1.0, dir.xz);
		float wave = sin(TIME * billow_speed + puff_seed + dot(dir, vec3(1.0, 0.7, 1.3)) * billow_frequency);
		float radius = 1.0 + (coarse - lump_bias) * lump_height + wave * billow_amount;
		float base_sq = dot(unit, unit);
		if (base_sq > radius * radius) {
			discard;
		}
		// 0 at the base's centre, 1 at its lumpy rim: how far the shading has
		// moved from the underside to the side surface it joins.
		base_ramp = smoothstep(min(base_rim_start, 0.99), 1.0, sqrt(base_sq) / max(radius, 0.0001));
	}
	vec3 surface = puff_centre + unit * axes;
	// Upper layer, camera close beneath it: fade out what is within reach of the camera's own height.
	if (floor_on > 0.5 && base_clear_end_m > 0.0) {
		float clearance = smoothstep(base_clear_start_m, max(base_clear_end_m, base_clear_start_m + 0.001), surface.y - cam.y);
		if (clearance < bayer4(FRAGCOORD.xy)) {
			discard;
		}
	}

	// Ellipsoid normal at the surface point. The flat base uses the same formula
	// (its point is inside the ellipsoid), so at its rim the normal is the side
	// normal and the shading meets the sides without a step.
	vec3 n = normalize(unit / axes);
	if (on_base) {
		// Bontago-mp0.93: inside the rim the normal eases to straight down (the
		// base faces the ground, not outward: the old ratio left it radial almost
		// everywhere, so the cel bands cut the underside into sun-side wedges and
		// lit slivers). Seen from below it is now one dark underbelly with a soft
		// lit ring toward the sun.
		n = normalize(mix(vec3(0.0, -1.0, 0.0), n, base_ramp));
	} else if (round_bottom) {
		// A round bottom has no plane: the underbelly share follows the normal itself.
		base_ramp = 1.0 - smoothstep(min(round_under_start, 0.99), 1.0, -n.y);
	}
	vec3 sun = normalize(light_direction);
	vec3 light = normalize(vec3(sun.x, max(sun.y, min_light_elevation), sun.z));

	// Shading domes at the surface point (base included); the fine
	// octave is dropped with distance. The base eases from a top-down map to
	// the triplanar one toward its rim (see lumps()).
	vec3 unit_dir = normalize(unit);
	float lump = lumps(unit_dir, puff_seed, t_boil, 1.0, base_ramp, unit.xz);
	if (dist < detail_lod_m && lump_detail_weight > 0.0) {
		float detail = lumps(unit_dir, puff_seed + 3.1, t_boil, lump_detail_scale, base_ramp, unit.xz);
		lump = mix(lump, detail, lump_detail_weight * (1.0 - smoothstep(detail_lod_m * 0.6, detail_lod_m, dist)));
	}
	float wrap = dot(n, light) * 0.5 + 0.5;
	float height_rel = clamp((surface.y - base_y) / clump_height, 0.0, 1.0);
	float shade = wrap * light_weight + height_rel * height_weight + ambient_shade + (lump - lump_bias) * lump_shade;
	shade -= underside_shade * clamp(-n.y, 0.0, 1.0);
	shade += base_bounce * (1.0 - base_ramp);
	float edge = max(fwidth(shade) * band_edge_px, 0.0001);
	float to_mid = smoothstep(mid_threshold - edge, mid_threshold + edge, shade);
	float to_lit = smoothstep(lit_threshold - edge, lit_threshold + edge, shade);
	vec3 col = mix(shadow_color, mid_color, to_mid);
	col = mix(col, lit_color, to_lit);

	// Rim: silhouette edges facing the sun, much stronger looking toward it.
	float fresnel = pow(1.0 - clamp(dot(n, -view_dir), 0.0, 1.0), rim_power);
	float toward_sun = clamp(dot(view_dir, sun), 0.0, 1.0);
	float sun_side = clamp(dot(n, light), 0.0, 1.0);
	float rim = fresnel * (sun_side * rim_sun_side + toward_sun * toward_sun * rim_backlight);
	// The distance fade below would leave bright rim outlines around puffs
	// whose bodies already match the sky, so the rim fades out first.
	float fade = smoothstep(fade_start_m, fade_end_m, dist);
	rim *= (1.0 - fade) * (1.0 - fade);
	// Down-facing surfaces (the underside seen at a grazing angle) get no rim: a
	// flat base has a near-constant fresnel, so the rim would paint it as one
	// pale band cut off from the shaded body. Continuous in n.y, no step.
	rim *= 1.0 - smoothstep(-0.25 - upper_rim_down_shift * floor_on, 0.25 - upper_rim_down_shift * floor_on, -n.y);
	col = mix(col, rim_color, smoothstep(rim_threshold, rim_threshold + rim_softness, rim));
	float weather_luma = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(col, vec3(weather_luma), weather_desaturate) * (1.0 - weather_dim);
	vec3 tone_floor = weather_floor * mix(mix(floor_shadow_ratio, floor_mid_ratio, to_mid), 1.0, to_lit);
	col = max(col, tone_floor * floor_on);
	// Same exposure as the sky, so theme colours can be picked straight from
	// the painted panorama.
	col *= exposure;

	// Blend into the sky drawn behind: distance haze plus depth below the disc.
	float depth = smoothstep(depth_fade_start_m, depth_fade_end_m, -surface.y) * depth_fade_amount;
	fade = min(1.0 - (1.0 - fade) * (1.0 - depth), far_fade_cap);
	if (fade > 0.001) {
		vec2 sky_uv = sky_panorama_uv(view_dir, sky_yaw_offset_deg, sky_pitch_offset_deg);
		vec3 sky = panorama_lod(panorama, sky_uv, seam_blend_width) * exposure;
		if (procedural_sea_mix > 0.0) {
			// Same composition as sunset_clouds.gdshader's procedural branch, so
			// the puff fades into exactly the sea/gradient drawn behind it.
			vec3 sun_dir = normalize(sun_direction);
			vec3 pcol = sky_gradient(view_dir.y, proc_horizon_color.rgb, proc_mid_color.rgb, proc_zenith_color.rgb,
				proc_gradient_mid_height, proc_gradient_power, proc_gradient_bands, proc_gradient_band_edge);
			if (view_dir.y < 0.0) {
				float below = smoothstep(0.0, max(proc_sea_horizon_fade, 0.001), -view_dir.y);
				pcol = mix(pcol, proc_sea_color_near.rgb, below);
				pcol = mix(pcol, proc_sea_color_far.rgb, smoothstep(0.0, 1.0, -view_dir.y) * below);
				pcol = procedural_sea_color(noise_tex, view_dir, sun_dir, TIME, proc_sea_params, proc_sea_heights,
					proc_sea_wind, proc_sea_coverage, proc_sea_softness, proc_sea_band_edge, proc_sea_horizon_fade,
					proc_sea_color_near.rgb, proc_sea_color_far.rgb, cloud_shadow_color, cloud_mid_color,
					cloud_lit_color, cloud_rim_color, pcol);
			}
			float sun_side = pow(max(dot(view_dir, sun_dir), 0.0), max(proc_horizon_glow_sun_bias, 0.001));
			float glow = (1.0 - smoothstep(0.0, max(proc_horizon_glow_width, 0.001), abs(view_dir.y)))
				* mix(0.35, 1.0, sun_side) * proc_horizon_glow_strength;
			pcol = mix(pcol, proc_horizon_glow_color.rgb, clamp(glow, 0.0, 1.0));
			sky = mix(sky, pcol * exposure, clamp(procedural_sea_mix, 0.0, 1.0));
		}
		sky = moonlit_grade(sky, grade_amount, grade_dark, grade_mid, grade_light, grade_gamma);
		col = mix(col, sky, fade);
	}
	col = mix(col, wfog_color.rgb, clamp((dist - wfog_begin) / max(wfog_end - wfog_begin, 0.001), 0.0, 1.0) * wfog_strength);
	ALBEDO = col;
	ALPHA = edge_alpha;
}
