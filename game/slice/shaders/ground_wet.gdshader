shader_type spatial;
// Rain-soaked paving: world-XZ PBR, darkened wet albedo, puddles that pool in
// the low gaps of the height map (and in gutters via vertex COLOR.r), with
// animated rain ripples. SSR does the rest.
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D alb_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nrm_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D hgt_tex : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_height = false;
uniform float tile = 2.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform float wetness = 0.85;
uniform float puddles = 0.55;
uniform float rain = 1.0;
uniform float normal_strength = 1.0;

varying vec3 wpos;
varying vec3 wnrm;
varying float gutter;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec2 hash2(vec2 p) { return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { return 0.5 * vnoise(p) + 0.3 * vnoise(p * 2.13) + 0.2 * vnoise(p * 4.37); }

// Expanding rain-drop rings; returns a normal offset (xz).
vec2 ripples(vec2 p, float t) {
	vec2 acc = vec2(0.0);
	for (int layer = 0; layer < 2; layer++) {
		vec2 q = p * (layer == 0 ? 2.2 : 3.1) + float(layer) * 17.3;
		vec2 cell = floor(q);
		for (int j = -1; j <= 1; j++) {
			for (int i = -1; i <= 1; i++) {
				vec2 c = cell + vec2(float(i), float(j));
				vec2 o = hash2(c);
				float phase = fract(t * 0.9 + o.x * 7.0 + float(layer) * 0.37);
				vec2 d = q - (c + o);
				float r = length(d);
				float ring = sin((r - phase * 0.9) * 40.0) * (1.0 - phase) * (1.0 - phase);
				float mask = smoothstep(phase * 0.9 + 0.12, phase * 0.9, r) * smoothstep(0.0, 0.05, r);
				acc += (d / max(r, 1e-3)) * ring * mask;
			}
		}
	}
	return acc * 0.18;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	gutter = COLOR.r;
}

void fragment() {
	vec2 uv = wpos.xz / tile;
	vec3 alb = texture(alb_tex, uv).rgb * tint;
	vec3 arm = texture(arm_tex, uv).rgb;
	vec3 tn = texture(nrm_tex, uv).xyz * 2.0 - 1.0;
	tn.xy *= normal_strength;
	float h = has_height ? texture(hgt_tex, uv).r : 0.5;

	// Puddle level: patchy large-scale noise, raised along gutters.
	float patch = fbm(wpos.xz * 0.11 + 3.7);
	float level = puddles * (smoothstep(0.42, 0.78, patch) * 0.75 + gutter * 0.9) - 0.05;
	float puddle = 1.0 - smoothstep(level - 0.06, level + 0.02, h);
	puddle = clamp(puddle, 0.0, 1.0);
	// Damp gaps even outside puddles.
	float damp = clamp(wetness * (0.65 + 0.35 * (1.0 - h)), 0.0, 1.0);

	vec3 n = normalize(wnrm);
	vec3 base_n = normalize(vec3(tn.x, tn.z, -tn.y));   // tangent frame: U=+X, up-in-texture=-Z
	base_n = normalize(n + vec3(base_n.x, 0.0, base_n.z));
	vec2 rip = rain > 0.0 ? ripples(wpos.xz, TIME) * rain : vec2(0.0);
	vec3 water_n = normalize(n + vec3(rip.x, 0.0, rip.y));
	vec3 wn = normalize(mix(base_n, water_n, puddle));

	alb *= mix(1.0, 0.55, damp);
	alb *= mix(1.0, 0.7, puddle);
	ALBEDO = alb;
	AO = mix(arm.r, 1.0, puddle);
	ROUGHNESS = mix(clamp(arm.g * (1.0 - 0.6 * damp), 0.08, 1.0), 0.02, puddle);
	SPECULAR = mix(0.5, 0.65, puddle);
	METALLIC = 0.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}
