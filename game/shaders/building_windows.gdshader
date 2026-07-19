shader_type spatial;
render_mode cull_back;

global uniform float night_amount;

varying vec3 wpos;
varying vec3 wnormal;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// tile vertex colors are authored sRGB; COLOR arrives raw, so linearize
	vec3 base = pow(COLOR.rgb, vec3(2.2));
	float vertical = 1.0 - smoothstep(0.25, 0.4, abs(wnormal.y));
	float u = abs(wnormal.x) > abs(wnormal.z) ? wpos.z : wpos.x;
	float v = wpos.y;
	vec2 cell = vec2(floor(u / 3.6), floor(v / 3.2));
	vec2 f = vec2(fract(u / 3.6), fract(v / 3.2));
	float win = step(0.25, f.x) * step(f.x, 0.75) * step(0.3, f.y) * step(f.y, 0.8);
	win *= vertical;
	float lit = step(0.62, hash21(cell));
	// emission only kicks in well past dusk, so daytime facades stay matte
	float night = smoothstep(0.45, 0.9, night_amount);
	vec3 glass_day = base * 0.55 + vec3(0.05, 0.06, 0.08);
	ALBEDO = mix(base, glass_day, win * 0.6);
	ROUGHNESS = mix(1.0, 0.35, win);
	// dim windows seen edge-on so glancing walls don't merge into bright stripes
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	EMISSION = vec3(1.0, 0.72, 0.35) * (win * lit * night * 1.6 * (0.2 + 0.8 * facing));
}
