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
	vec3 base = COLOR.rgb;
	float vertical = 1.0 - smoothstep(0.25, 0.4, abs(wnormal.y));
	float u = abs(wnormal.x) > abs(wnormal.z) ? wpos.z : wpos.x;
	float v = wpos.y;
	vec2 cell = vec2(floor(u / 3.6), floor(v / 3.2));
	vec2 f = vec2(fract(u / 3.6), fract(v / 3.2));
	float win = step(0.2, f.x) * step(f.x, 0.8) * step(0.25, f.y) * step(f.y, 0.85);
	win *= vertical;
	float lit = step(0.55, hash21(cell));
	vec3 glass_day = base * 0.5 + vec3(0.07, 0.09, 0.12);
	ALBEDO = mix(base, glass_day, win * 0.85);
	ROUGHNESS = mix(1.0, 0.3, win);
	EMISSION = vec3(1.0, 0.72, 0.35) * (win * lit * night_amount * 2.4);
}
