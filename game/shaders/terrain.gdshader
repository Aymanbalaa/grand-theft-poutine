shader_type spatial;

uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float uv_scale = 0.025;

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 vcol;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vcol = COLOR;
}

void fragment() {
	vec3 painted = pow(vcol.rgb, vec3(2.2));
	vec2 uv = wpos.xz * uv_scale;
	vec3 grass = texture(grass_tex, uv).rgb;
	vec3 dirt = texture(dirt_tex, uv * 1.9).rgb;
	// rock is triplanar: steep faces (road cuts, berms) stretch a pure xz projection into smears
	vec3 an = abs(wnrm);
	vec3 tw = an / (an.x + an.y + an.z);
	vec3 rock = tw.y * texture(rock_tex, uv * 0.7).rgb
		+ tw.x * texture(rock_tex, wpos.zy * uv_scale * 0.7).rgb
		+ tw.z * texture(rock_tex, wpos.xy * uv_scale * 0.7).rgb;

	float wet = smoothstep(0.02, 0.06, vcol.b - vcol.g);
	float greenness = smoothstep(0.03, 0.10, vcol.g - vcol.r) * (1.0 - wet);
	vec3 flat_col = mix(dirt, grass, greenness);
	float rockiness = smoothstep(0.18, 0.40, 1.0 - wnrm.y);
	vec3 col = mix(flat_col, rock, rockiness);

	// keep the baked large-scale tint so elevation/district variation survives
	col *= mix(vec3(1.0), painted * 2.6, 0.35);
	col = min(col * 1.6, vec3(1.0));
	ALBEDO = mix(col, painted, wet);
	ROUGHNESS = 1.0;
}
