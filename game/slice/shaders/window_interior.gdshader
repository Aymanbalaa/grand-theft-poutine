shader_type spatial;
// Glass with a fake room behind it (interior mapping). Ray-box intersection in
// window space gives parallax-correct walls/floor/ceiling; per-window seed
// (COLOR.r) picks palette, lit state, curtains; COLOR.g = 1 marks a shop.
// UV: 0..1 across the pane (v=0 at top); UV2: pane size in metres.
render_mode specular_schlick_ggx;

uniform float night = 1.0;        // 0 day .. 1 night: how much rooms glow
uniform float lit_ratio = 0.62;
uniform float room_depth = 4.0;
uniform float energy = 1.0;

varying vec3 wpos;
varying vec3 wnrm;

float hash(float n) { return fract(sin(n * 91.3458) * 47453.5453); }

vec3 wall_palette(float s) {
	vec3 c[6] = vec3[](vec3(0.82, 0.74, 0.62), vec3(0.75, 0.70, 0.66), vec3(0.62, 0.68, 0.72),
		vec3(0.70, 0.74, 0.62), vec3(0.85, 0.62, 0.48), vec3(0.78, 0.78, 0.76));
	return c[int(floor(s * 5.999))];
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float seed = COLOR.r;
	bool shop = COLOR.g > 0.5;
	vec2 size = UV2;
	vec3 N = normalize(wnrm);
	vec3 U = normalize(cross(vec3(0.0, 1.0, 0.0), N));
	vec3 rd_w = normalize(wpos - CAMERA_POSITION_WORLD);
	vec3 rd = vec3(dot(rd_w, U), dot(rd_w, vec3(0.0, 1.0, 0.0)), dot(rd_w, -N));
	rd.z = max(rd.z, 1e-3);

	float sill = shop ? 0.4 : 0.9;
	float ceil_h = shop ? size.y + 0.6 : size.y + 0.55;
	vec3 p = vec3(UV.x * size.x, (1.0 - UV.y) * size.y, 0.0);
	vec3 bmin = vec3(-0.9 - hash(seed * 7.0), -sill, 0.0);
	vec3 bmax = vec3(size.x + 0.9 + hash(seed * 9.0), ceil_h, room_depth * (shop ? 1.6 : 0.8 + 0.5 * hash(seed * 3.0)));
	vec3 tmax = max((bmax - p) / rd, (bmin - p) / rd);
	float t = min(min(tmax.x, tmax.y), tmax.z);
	vec3 hit = p + rd * t;

	vec3 wallc = wall_palette(hash(seed * 13.0)) * 0.8;
	if (shop) {
		vec3 sp[4] = vec3[](vec3(0.32, 0.18, 0.1), vec3(0.14, 0.24, 0.18), vec3(0.42, 0.14, 0.1), vec3(0.75, 0.7, 0.6));
		wallc = sp[int(floor(hash(seed * 61.0) * 3.999))];
	}
	vec3 col;
	if (t == tmax.z) {
		col = wallc;
		// pictures / shelves on the back wall
		if (shop) {
			// wall shelving: dark wood boards every 0.45 m, stocked with goods of
			// varied width/height in a muted palette (loaves, jars, bottles, boxes)
			float sy = (hit.y - 0.1) / 0.45;
			float row = floor(sy);
			float fy = fract(sy);
			bool in_unit = hit.y > 0.1 && hit.y < ceil_h - 0.7 && abs(hit.x - (bmin.x + bmax.x) * 0.5) < (bmax.x - bmin.x) * 0.42;
			if (in_unit) {
				vec3 wood = vec3(0.2, 0.12, 0.07);
				float cw = 0.11 + 0.1 * hash(row * 7.0 + seed * 3.0);
				float cell = floor(hit.x / cw);
				float fx = fract(hit.x / cw);
				float h = hash(cell * 13.0 + row * 71.0 + seed * 101.0);
				float k = hash(cell * 5.0 + row * 17.0 + seed * 19.0);
				vec3 goods[5] = vec3[](vec3(0.55, 0.32, 0.14), vec3(0.7, 0.45, 0.12), vec3(0.18, 0.32, 0.2), vec3(0.75, 0.68, 0.55), vec3(0.45, 0.12, 0.1));
				vec3 g = goods[int(floor(k * 4.999))] * (0.75 + 0.5 * h);
				float item_h = 0.35 + 0.5 * h;
				bool has = h > 0.18 && fx > 0.08 && fx < 0.92 && fy > 0.08 && fy < 0.08 + item_h * 0.85;
				col = fy < 0.08 ? wood * 1.3 : (has ? g : wood * 0.8);
			}
		} else {
			vec2 fc = vec2(hit.x - (bmin.x + bmax.x) * 0.5 + hash(seed) - 0.5, hit.y - 1.5);
			float frame = step(abs(fc.x), 0.45) * step(abs(fc.y), 0.32) * step(0.4, hash(seed * 5.0));
			col = mix(col, vec3(0.25, 0.18, 0.12) * (0.5 + hash(seed * 17.0)), frame);
		}
	} else if (t == tmax.y) {
		if (rd.y < 0.0) {
			float plank = hash(floor(hit.x * 5.0 + floor(hit.z * 0.8) * 3.0));
			col = shop ? vec3(0.2, 0.16, 0.12) * (0.85 + 0.15 * step(0.5, fract(hit.x * 2.0 + 0.5 * step(0.5, fract(hit.z * 2.0)))))
				: vec3(0.34, 0.2, 0.11) * (0.8 + 0.4 * plank);
		} else {
			col = vec3(0.9, 0.88, 0.84);
		}
	} else {
		col = wallc * 0.85;
	}

	// Lighting: ceiling lamp falloff + slight depth darkening.
	vec3 lamp = vec3((bmin.x + bmax.x) * 0.5, ceil_h - 0.2, bmax.z * 0.45);
	float d = length(hit - lamp);
	float lamp_k = 1.0 / (1.0 + d * d * 0.35);
	bool lit = hash(seed * 23.0) < (shop ? 0.95 : lit_ratio);
	vec3 light_col = mix(vec3(1.0, 0.72, 0.42), vec3(1.0, 0.86, 0.7), hash(seed * 29.0));
	float glow = lit ? (shop ? 1.25 : 0.85) : 0.0;
	// soft contact darkening into room corners and with depth
	vec3 rc = (hit - bmin) / (bmax - bmin);
	float corner = smoothstep(0.0, 0.12, min(min(rc.x, 1.0 - rc.x), min(rc.y, 1.0 - rc.y)));
	float ao = mix(0.55, 1.0, corner) * mix(1.0, 0.6, rc.z);
	vec3 interior = col * light_col * lamp_k * glow * ao;
	float t_eff = t;
	if (shop) {
		// display table / counter in the middle ground (occludes the room)
		float cx0 = bmin.x + 0.6 + hash(seed * 51.0) * 0.6;
		float cx1 = bmax.x - 0.6 - hash(seed * 53.0) * 0.6;
		float ty = 0.5 - 0.3 * hash(seed * 57.0);
		float z0 = 1.1;
		float z1 = 2.0 + hash(seed * 59.0);
		if (rd.y < 0.0) {
			float tt = (ty - p.y) / rd.y;
			vec3 q = p + rd * tt;
			if (tt > 0.0 && tt < t_eff && q.x > cx0 && q.x < cx1 && q.z > z0 && q.z < z1) {
				// dark wood top with a few goods laid out (round loaves / boxes)
				vec2 gq = q.xz * vec2(3.2, 3.2);
				vec2 gc = floor(gq);
				vec2 gf = fract(gq) - 0.5;
				float item = hash(gc.x * 7.0 + gc.y * 13.0 + seed * 11.0);
				float blob = step(length(gf * vec2(1.0, 1.6)), 0.3) * step(0.5, item);
				vec3 tc = mix(vec3(0.17, 0.1, 0.055), mix(vec3(0.62, 0.38, 0.16), vec3(0.7, 0.62, 0.48), step(0.8, item)), blob);
				interior = tc * light_col * glow * 0.7;
				t_eff = tt;
			}
		}
		float tf = (z0 - p.z) / rd.z;
		vec3 qf = p + rd * tf;
		if (tf > 0.0 && tf < t_eff && qf.x > cx0 && qf.x < cx1 && qf.y < ty && qf.y > bmin.y) {
			interior = vec3(0.16, 0.09, 0.05) * light_col * glow * 0.5;
			t_eff = tf;
		}
	}
	// pendant lamps hanging from the ceiling: glowing bulbs + cords
	if (lit) {
		int np = shop ? 3 : 1;
		for (int k = 0; k < np; k++) {
			float fx = shop ? (float(k) + 0.5) / 3.0 : 0.5;
			vec3 L = vec3(mix(bmin.x, bmax.x, fx), ceil_h - (shop ? 0.75 : 0.55), shop ? 1.6 : bmax.z * 0.45);
			vec3 v = L - p;
			float tp = dot(v, rd);
			if (tp > 0.0 && tp < t_eff) {
				float dist = length(v - rd * tp);
				interior += light_col * (smoothstep(0.09, 0.03, dist) * 5.0 + exp(-dist * 9.0) * 0.6);
			}
			// cord: vertical segment above the bulb
			vec2 cxz = vec2(L.x, L.z);
			float tc2 = (L.z - p.z) / rd.z;
			vec3 qc = p + rd * tc2;
			if (tc2 > 0.0 && tc2 < t_eff && qc.y > L.y && abs(qc.x - L.x) < 0.012) {
				interior *= 0.2;
			}
		}
	}
	// TV flicker in a few dark rooms
	if (!lit && hash(seed * 31.0) > 0.85) {
		float f = 0.6 + 0.4 * sin(TIME * 7.0 + seed * 50.0) * sin(TIME * 3.1);
		interior = col * vec3(0.25, 0.45, 1.0) * 0.35 * f / (1.0 + hit.z);
	}
	// Curtains / sheers close to the glass.
	float c = hash(seed * 37.0);
	float cw = c > 0.35 ? 0.12 + 0.18 * hash(seed * 41.0) : 0.0;
	float curtain = max(step(UV.x, cw), step(1.0 - cw, UV.x));
	vec3 cloth = mix(vec3(0.85, 0.8, 0.7), vec3(0.6, 0.15, 0.12), step(0.8, hash(seed * 43.0)));
	float folds = 0.75 + 0.25 * sin(UV.x * 90.0);
	if (!shop) {
		interior = mix(interior, cloth * light_col * folds * (lit ? 0.9 : 0.0) + cloth * 0.01, curtain);
		// sheer net over lower pane on some windows
		float sheer = step(0.7, hash(seed * 47.0)) * step(0.45, UV.y);
		interior = mix(interior, interior * 0.6 + cloth * light_col * (lit ? 0.35 : 0.0), sheer * 0.6);
	}
	interior *= night * energy;
	vec3 day_room = col * 0.04 * (1.0 - night);

	ALBEDO = vec3(0.01) + day_room;
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.35;
	EMISSION = interior;
}
