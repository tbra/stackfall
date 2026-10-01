// Bontago-1pi.11.42: shared by block_cell_grid.gdshader and
// block_outline.gdshader so both passes eat the same pixels. 3D value noise in
// block-local space; a pixel is gone while its noise is below the threshold.

float dissolve_hash(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float dissolve_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = dissolve_hash(i);
	float n100 = dissolve_hash(i + vec3(1.0, 0.0, 0.0));
	float n010 = dissolve_hash(i + vec3(0.0, 1.0, 0.0));
	float n110 = dissolve_hash(i + vec3(1.0, 1.0, 0.0));
	float n001 = dissolve_hash(i + vec3(0.0, 0.0, 1.0));
	float n101 = dissolve_hash(i + vec3(1.0, 0.0, 1.0));
	float n011 = dissolve_hash(i + vec3(0.0, 1.0, 1.0));
	float n111 = dissolve_hash(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

// Noise threshold for a dissolve progress 0..1: -edge at 0 (nothing eaten),
// 1 at 1 (everything eaten, including the glowing edge band).
float dissolve_threshold(float amount, float edge) {
	return mix(-edge, 1.0 + edge, amount);
}
