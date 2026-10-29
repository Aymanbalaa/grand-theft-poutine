shader_type sky;
// Blue-hour sky: the HDRI supplies the cloud deck above ~12 degrees (clamped
// so its stadium floodlights never flare); below that a smooth city-glow
// gradient replaces the photographed parking lot. `day` cross-fades to a
// procedural overcast sky.

uniform sampler2D pano : filter_linear_mipmap, repeat_enable;
uniform float energy = 1.0;
uniform float clamp_max = 1.4;
uniform vec3 glow_col = vec3(0.42, 0.26, 0.3);
uniform vec3 ground_col = vec3(0.025, 0.025, 0.035);
uniform float day = 0.0;

vec2 equirect(vec3 d) {
	return vec2(atan(d.x, -d.z) / TAU + 0.5, acos(clamp(d.y, -1.0, 1.0)) / PI);
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 hdr = min(textureLod(pano, equirect(d), 0.0).rgb, vec3(clamp_max));
	// horizon colour taken from the HDRI just above the masked band, heavily blurred
	vec3 up = normalize(vec3(d.x, 0.6, d.z));
	vec3 hz = min(textureLod(pano, equirect(up), 6.0).rgb, vec3(clamp_max));
	float w = smoothstep(0.3, 0.55, d.y);
	vec3 band = mix(glow_col, hz, smoothstep(-0.02, 0.2, d.y));
	vec3 night = mix(band, hdr, w);
	night = mix(ground_col, night, smoothstep(-0.12, 0.02, d.y));

	// overcast day
	vec2 cp = d.xz / max(d.y, 0.05) * 1.5;
	float cl = vnoise(cp) * 0.6 + vnoise(cp * 2.3) * 0.3 + vnoise(cp * 5.1) * 0.1;
	vec3 dsky = mix(vec3(0.78, 0.8, 0.83), vec3(0.6, 0.66, 0.75), smoothstep(0.0, 0.8, d.y));
	dsky = mix(dsky, vec3(0.86, 0.87, 0.88), smoothstep(0.45, 0.8, cl) * smoothstep(0.0, 0.2, d.y));
	dsky = mix(vec3(0.3, 0.31, 0.33), dsky, smoothstep(-0.1, 0.02, d.y));

	COLOR = mix(night * energy, dsky * 1.6, day);
}
