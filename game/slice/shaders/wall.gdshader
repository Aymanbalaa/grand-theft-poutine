shader_type spatial;
// World-space triplanar PBR for procedurally built facades (no UVs needed).
// Whiteout-blended normals (Golus), per-building tint/offset via instance
// uniforms, plus weathering: rain streaks, ground grime, splash-zone wetness.
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D alb_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nrm_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile = 2.0;            // metres per texture repeat
uniform float normal_strength = 1.0;
uniform float grime = 0.5;
uniform float wetness = 0.6;         // global rain wetness 0..1
uniform float rough_mul = 1.0;
uniform float metallic = 0.0;

instance uniform vec3 tint = vec3(1.0);
instance uniform vec2 uv_offset = vec2(0.0);

varying vec3 wpos;
varying vec3 wnrm;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(wnrm);
	vec3 w = pow(abs(n), vec3(6.0));
	w /= (w.x + w.y + w.z);
	vec3 p = wpos / tile;
	vec2 uvx = vec2(-p.z * sign(n.x), -p.y) + uv_offset;
	vec2 uvy = vec2(p.x, p.z) + uv_offset;
	vec2 uvz = vec2(p.x * sign(n.z), -p.y) + uv_offset;

	vec3 alb = texture(alb_tex, uvx).rgb * w.x + texture(alb_tex, uvy).rgb * w.y + texture(alb_tex, uvz).rgb * w.z;
	vec3 arm = texture(arm_tex, uvx).rgb * w.x + texture(arm_tex, uvy).rgb * w.y + texture(arm_tex, uvz).rgb * w.z;

	vec3 tx = texture(nrm_tex, uvx).xyz * 2.0 - 1.0;
	vec3 ty = texture(nrm_tex, uvy).xyz * 2.0 - 1.0;
	vec3 tz = texture(nrm_tex, uvz).xyz * 2.0 - 1.0;
	tx.xy *= normal_strength; ty.xy *= normal_strength; tz.xy *= normal_strength;
	// Map each tangent-space sample into world space for its projection axis.
	// GL normal maps: +green is "up" in the texture, i.e. toward decreasing v.
	vec3 nx = vec3(tx.z * sign(n.x), tx.y, -tx.x * sign(n.x));
	vec3 ny = vec3(ty.x, ty.z * sign(n.y), -ty.y);
	vec3 nz = vec3(tz.x * sign(n.z), tz.y, tz.z * sign(n.z));
	vec3 wn = normalize(n + (nx - n * dot(nx, n)) * w.x + (ny - n * dot(ny, n)) * w.y + (nz - n * dot(nz, n)) * w.z);

	// Weathering: vertical rain streaks, darker base, damp splash zone.
	float streak = vnoise(vec2((wpos.x + wpos.z) * 2.3, wpos.y * 0.12)) * vnoise(vec2((wpos.x - wpos.z) * 0.7, wpos.y * 0.5));
	float base = 1.0 - smoothstep(0.0, 1.6, wpos.y);
	alb *= tint;
	alb *= 1.0 - grime * (0.35 * streak + 0.35 * base);
	float wet = wetness * (0.35 + 0.65 * (1.0 - smoothstep(0.1, 0.9, wpos.y)) + 0.25 * streak);
	alb *= mix(1.0, 0.62, clamp(wet, 0.0, 1.0));

	ALBEDO = alb;
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.4;
	ROUGHNESS = clamp(arm.g * rough_mul * (1.0 - 0.55 * clamp(wet, 0.0, 1.0)), 0.04, 1.0);
	METALLIC = metallic;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}
