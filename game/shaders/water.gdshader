shader_type spatial;
render_mode cull_back;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float w1 = sin(p.x * 0.09 + TIME * 0.8) + sin(p.y * 0.07 - TIME * 0.6);
	float w2 = sin((p.x + p.y) * 0.05 + TIME * 0.45);
	vec3 n = normalize(vec3(
		0.06 * cos(p.x * 0.09 + TIME * 0.8),
		1.0,
		0.07 * cos(p.y * 0.07 - TIME * 0.6) + 0.04 * cos((p.x + p.y) * 0.05 + TIME * 0.45)
	));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ALBEDO = COLOR.rgb * (0.92 + 0.05 * (w1 + w2));
	ROUGHNESS = 0.12;
	SPECULAR = 0.6;
	METALLIC = 0.15;
}
