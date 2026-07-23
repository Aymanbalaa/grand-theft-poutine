shader_type spatial;

uniform sampler2D asphalt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float uv_scale = 0.08;
uniform float brighten = 3.2;

varying vec3 wpos;
varying vec3 vtint;

float rhash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float rnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(rhash(i), rhash(i + vec2(1.0, 0.0)), u.x),
			mix(rhash(i + vec2(0.0, 1.0)), rhash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec3 asph = texture(asphalt_tex, wpos.xz * uv_scale).rgb;
	// patchy wear: broad tonal drift + finer repair blotches
	float wear = rnoise(wpos.xz * 0.013) * 0.7 + rnoise(wpos.xz * 0.06) * 0.3;
	vec3 col = asph * vtint * brighten * mix(0.78, 1.12, wear);
	ALBEDO = col;
	ROUGHNESS = 0.92;
	METALLIC = 0.0;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vtint = pow(COLOR.rgb, vec3(2.2));
}
