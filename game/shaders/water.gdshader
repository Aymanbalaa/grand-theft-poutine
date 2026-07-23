shader_type spatial;
render_mode cull_back;

uniform sampler2D depth_tex : hint_depth_texture, filter_linear;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 wave_normal(vec2 p, float t) {
	float dx = 0.055 * cos(p.x * 0.11 + t * 0.9)
		+ 0.035 * cos((p.x * 0.7 + p.y * 0.4) * 0.23 + t * 1.7)
		+ 0.018 * cos((p.x + p.y * 1.7) * 0.53 + t * 2.6);
	float dz = 0.065 * cos(p.y * 0.09 - t * 0.7)
		+ 0.030 * cos((p.x * -0.3 + p.y * 0.8) * 0.19 + t * 1.3)
		+ 0.015 * cos((p.x * 1.4 - p.y) * 0.47 + t * 2.2);
	return normalize(vec3(-dx, 1.0, -dz));
}

void fragment() {
	vec3 n = wave_normal(wpos.xz, TIME);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	// scene depth behind the surface -> shore fade + foam
	float depth_raw = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	vec4 vpos = INV_PROJECTION_MATRIX * ndc;
	float scene_depth = -(vpos.xyz / vpos.w).z;
	float water_depth = clamp(scene_depth + VERTEX.z, 0.0, 60.0);

	vec3 deep = vec3(0.016, 0.045, 0.07);
	vec3 shallow = vec3(0.06, 0.13, 0.14);
	vec3 col = mix(shallow, deep, smoothstep(0.0, 12.0, water_depth));

	float foam = 1.0 - smoothstep(0.0, 2.2, water_depth);
	col = mix(col, vec3(0.85), foam * 0.55);

	ALBEDO = col;
	METALLIC = 0.0;
	SPECULAR = 0.7;
	ROUGHNESS = mix(0.04, 0.12, foam);
}
