shader_type sky;

uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.62;
uniform float cloud_speed = 0.005;
uniform float cloud_scale = 0.8;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.3, 9.1);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = EYEDIR;
	vec3 sun = normalize(vec3(0.3, 0.6, 0.2));
	if (LIGHT0_ENABLED) {
		sun = LIGHT0_DIRECTION;
	}
	float sun_h = sun.y;
	// sun path never crosses the horizon (elevation pins at ~6 deg night, ~23 deg at the
	// harness dusk time), so day/twilight bands are centered on this project's sun_h range
	float daylight = clamp((sun_h - 0.12) * 1.9, 0.0, 1.0);
	float twilight = clamp(1.0 - abs(sun_h - 0.35) * 4.5, 0.0, 1.0);
	vec2 flat_dir = normalize(dir.xz + vec2(1e-5));
	vec2 flat_sun = normalize(sun.xz + vec2(1e-5));
	float toward_sun = dot(flat_dir, flat_sun) * 0.5 + 0.5;

	// atmosphere gradient
	float h = clamp(dir.y, 0.0, 1.0);
	float grad = pow(1.0 - h, 3.0);
	vec3 zen = mix(vec3(0.008, 0.012, 0.035), vec3(0.11, 0.28, 0.62), daylight);
	vec3 hor = mix(vec3(0.045, 0.06, 0.11), vec3(0.68, 0.78, 0.88), daylight);
	vec3 col = mix(zen, hor, grad);

	// dawn/dusk warm wash, strongest toward the sun azimuth
	col = mix(col, vec3(0.95, 0.45, 0.18), twilight * grad * (0.25 + 0.75 * toward_sun));

	// sun disc + halo
	float cs = dot(dir, sun);
	float disc = smoothstep(0.9993, 0.9998, cs);
	float halo = pow(clamp(cs, 0.0, 1.0), 350.0) * 0.5 + pow(clamp(cs, 0.0, 1.0), 24.0) * 0.12;
	vec3 sun_tint = mix(vec3(1.0, 0.55, 0.25), vec3(1.0, 0.97, 0.9), daylight);
	// gate on daylight, not raw elevation: this sun never dips below ~6 deg,
	// so an elevation gate leaves a warm disc burning in the night sky
	col += (disc * 12.0 + halo) * sun_tint * smoothstep(0.05, 0.25, daylight);

	// stars
	float night = 1.0 - daylight;
	if (night > 0.55 && dir.y > 0.0) {
		vec2 sp = dir.xz / (dir.y + 0.6);
		float star = step(0.9985, hash12(floor(sp * 380.0)));
		col += vec3(star) * 0.7 * smoothstep(0.55, 0.9, night);
	}

	// clouds
	if (dir.y > 0.015) {
		vec2 cuv = dir.xz / (dir.y * 3.0 + 0.35) * cloud_scale + vec2(TIME * cloud_speed);
		float d = fbm(cuv) * 1.15;
		float cov = smoothstep(1.0 - cloud_coverage, 1.0 - cloud_coverage + 0.18, d);
		cov *= smoothstep(0.015, 0.12, dir.y);
		vec3 cloud_lit = mix(vec3(0.03, 0.035, 0.06), vec3(1.0, 0.99, 0.96), daylight);
		cloud_lit = mix(cloud_lit, vec3(1.0, 0.55, 0.3), twilight * 0.7);
		float shade = mix(0.35, 1.0, smoothstep(0.2, 0.9, d));
		col = mix(col, cloud_lit * shade, cov * 0.92);
	}

	COLOR = col;
}
