shader_type spatial;
// Distant city blocks around the slice: dark stone mass with a grid of
// windows, a hashed fraction lit warm. Cheap, no textures.
render_mode diffuse_burley;

uniform float night = 1.0;

varying vec3 wpos;
varying vec3 wnrm;

float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(wnrm);
	float along = abs(n.x) > 0.5 ? wpos.z : wpos.x;
	vec2 g = vec2(along / 2.8, (wpos.y - 1.0) / 3.3);
	vec2 cell = floor(g);
	vec2 f = fract(g);
	float win = step(0.3, f.x) * step(f.x, 0.72) * step(0.25, f.y) * step(f.y, 0.85) * step(0.5, wpos.y);
	win *= 1.0 - step(0.5, abs(n.y));
	float lit = step(0.62, hash(vec3(cell, floor(dot(n, vec3(1.0, 3.0, 7.0))) + floor(wpos.x * 0.07) * 13.0 + floor(wpos.z * 0.07) * 7.0)));
	vec3 base = vec3(0.16, 0.15, 0.14) * (0.8 + 0.4 * hash(floor(wpos * 0.07)));
	ALBEDO = mix(base, vec3(0.03), win);
	ROUGHNESS = mix(0.9, 0.1, win);
	EMISSION = vec3(1.0, 0.7, 0.42) * win * lit * 0.9 * night;
}
