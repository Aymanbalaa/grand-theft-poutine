shader_type spatial;
render_mode cull_back;

global uniform float night_amount;

uniform sampler2D brick_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D stone_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D concrete_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D roof_tex : source_color, filter_linear_mipmap, repeat_enable;

varying vec3 wpos;
varying vec3 wnormal;
varying vec4 vcol;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float bhash(vec3 c) {
	return fract(sin(dot(floor(c * 255.0 + 0.5), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

// interior mapping: g = fragment pos within aperture in [0,1]^2 on the glass plane;
// rl = view ray in the window-local basis (x along-wall, y up, z into the room).
// analytic nearest-plane hit against a unit box (walls x=0/1, floor/ceil y=0/1,
// back wall z=depth); shaded procedurally per room. No loop, no texture.
vec3 interior_room(vec2 g, vec3 rl, float room_seed) {
	float depth = 0.85;                       // room depth in aperture-heights
	float tz = (rl.z > 1e-4) ? depth / rl.z : 1e9;
	float tx = (rl.x > 1e-4) ? (1.0 - g.x) / rl.x : (rl.x < -1e-4 ? -g.x / rl.x : 1e9);
	float ty = (rl.y > 1e-4) ? (1.0 - g.y) / rl.y : (rl.y < -1e-4 ? -g.y / rl.y : 1e9);
	float t = min(tz, min(tx, ty));
	vec3 hit = vec3(g, 0.0) + rl * t;
	// per-room base palette (warm office / cool office / dim), hashed
	vec3 warm = vec3(0.55, 0.47, 0.36);
	vec3 cool = vec3(0.42, 0.48, 0.55);
	vec3 dim  = vec3(0.14, 0.15, 0.17);
	float pick = fract(room_seed * 3.11);
	vec3 room = (pick < 0.4) ? warm : (pick < 0.75 ? cool : dim);
	// depth shade: back wall darkest, side walls mid, ceiling brightest (fake ceiling light)
	float shade = 1.0 - 0.55 * (hit.z / depth);
	shade *= (t == ty && rl.y < 0.0) ? 1.25 : 1.0;   // looking up -> ceiling, brighter
	shade *= (t == ty && rl.y > 0.0) ? 0.7  : 1.0;    // floor, darker
	// a back-wall furniture band (single horizontal stripe) for readable depth
	float band = (t == tz) ? smoothstep(0.28, 0.30, hit.y) * (1.0 - smoothstep(0.5, 0.52, hit.y)) : 0.0;
	room = mix(room, room * 0.55, band * 0.7);
	return room * clamp(shade, 0.15, 1.35);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vcol = COLOR;
}

// two-axis world triplanar for near-vertical surfaces
vec3 tri_wall(sampler2D tex, vec3 p, vec3 n, float s) {
	float wx = abs(n.x);
	float wz = abs(n.z);
	vec3 tx = texture(tex, p.zy * s).rgb;
	vec3 tz = texture(tex, p.xy * s).rgb;
	return (tx * wx + tz * wz) / max(wx + wz, 1e-4);
}

void fragment() {
	// tile vertex colors are authored sRGB; COLOR arrives raw, so linearize
	vec3 tint = pow(vcol.rgb, vec3(2.2));
	int acode = int(round(vcol.a * 255.0));
	int cat = acode / 40;
	float base_y = float(acode % 40) * 2.0;
	float seed = bhash(vcol.rgb);   // stable per building: vertex color is constant per building
	float roofness = smoothstep(0.45, 0.6, wnormal.y);   // caps + gables; walls ~0

	// sample everything unconditionally (texture() inside branches breaks mips)
	float ws = 0.22;   // wall texture world scale (~4.5 m period)
	vec3 brick = tri_wall(brick_tex, wpos, wnormal, ws);
	vec3 stone = tri_wall(stone_tex, wpos, wnormal, ws);
	vec3 concr = tri_wall(concrete_tex, wpos, wnormal, ws);
	vec3 rooft = texture(roof_tex, wpos.xz * 0.10).rgb;

	float w_brick = (cat == 0) ? 1.0 : 0.0;
	float w_stone = (cat == 2 || cat == 4) ? 1.0 : 0.0;
	float w_concr = 1.0 - min(w_brick + w_stone, 1.0);   // com/ind/default/legacy
	vec3 wall_tex = brick * w_brick + stone * w_stone + concr * w_concr;
	vec3 base = wall_tex * tint * 2.1;                   // tint is mid-dark; renormalize

	// --- window grid v2 (world-space, like v1) ---
	float vertical = 1.0 - smoothstep(0.25, 0.4, abs(wnormal.y));
	float u = abs(wnormal.x) > abs(wnormal.z) ? wpos.z : wpos.x;
	float v = wpos.y - base_y;
	float cw = ((cat == 1) ? 2.4 : 3.6) * mix(0.85, 1.2, fract(seed * 7.31));
	float rh = 3.2 * mix(0.92, 1.12, fract(seed * 3.77));
	vec2 cell = vec2(floor(u / cw), floor(v / rh));
	vec2 f = vec2(fract(u / cw), fract(v / rh));
	float floor_idx = floor(v / rh);

	vec2 lo = (cat == 1) ? vec2(0.08, 0.12) : vec2(0.26, 0.32);
	vec2 hi = (cat == 1) ? vec2(0.92, 0.90) : vec2(0.74, 0.84);
	float storefront = (floor_idx == 0.0 && (cat == 0 || cat == 1 || cat == 5)) ? 1.0 : 0.0;
	lo = mix(lo, vec2(0.06, 0.05), storefront);
	hi = mix(hi, vec2(0.94, 0.72), storefront);

	// residential/default ground-floor doors: ~1 cell in 5 punches through the band
	float door_pick = fract(sin(cell.x * 91.7 + seed * 47.0) * 43758.5453);
	float is_door = (floor_idx == 0.0 && (cat == 0 || cat == 5))
			? step(0.8, door_pick) : 0.0;
	float door_mask = is_door * step(0.30, f.x) * step(f.x, 0.70)
			* step(f.y, 2.2 / rh) * vertical;
	float door_rim = is_door * step(0.26, f.x) * step(f.x, 0.74)
			* step(f.y, 2.35 / rh) * vertical - door_mask;

	float inwin = step(lo.x, f.x) * step(f.x, hi.x) * step(lo.y, f.y) * step(f.y, hi.y) * vertical;
	vec2 fb = vec2(0.045, 0.05);
	float inner = step(lo.x + fb.x, f.x) * step(f.x, hi.x - fb.x)
			* step(lo.y + fb.y, f.y) * step(f.y, hi.y - fb.y) * vertical;
	float frame = inwin - inner;
	float sill = step(lo.y - 0.06, f.y) * step(f.y, lo.y)
			* step(lo.x, f.x) * step(f.x, hi.x) * vertical * (1.0 - storefront);

	inwin *= 1.0 - is_door;
	inner *= 1.0 - is_door;
	frame *= 1.0 - is_door;
	sill *= 1.0 - is_door;

	// inset illusion: glass darkens toward the top of the aperture (fake overhang)
	float glass_grad = mix(0.85, 0.35, smoothstep(lo.y, hi.y, f.y));
	vec3 glass = mix(vec3(0.30, 0.36, 0.42), vec3(0.15, 0.17, 0.19) + tint * 0.08, storefront)
			* glass_grad;

	vec3 col = base;
	col = mix(col, base * 0.5, frame);
	col = mix(col, glass, inner);
	col = mix(col, base * 1.3 + vec3(0.03), sill);

	// --- fake interior depth: commercial (cat 1) floors >= 1, inside the glass ---
	if (cat == 1 && floor_idx >= 1.0) {
		vec3 nrm = normalize(wnormal);
		vec3 up_ref = (abs(nrm.y) > 0.999) ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
		vec3 tang = normalize(cross(up_ref, nrm));  // along-wall horizontal
		vec3 rd = normalize(wpos - CAMERA_POSITION_WORLD);       // camera -> fragment
		// window-local ray: x along wall, y up, z into the room (-nrm)
		vec3 rl = normalize(vec3(dot(rd, tang), rd.y, dot(rd, -nrm)));
		// aperture-normalized fragment coords in [0,1]
		vec2 g = clamp(vec2((f.x - lo.x) / max(hi.x - lo.x, 1e-3),
				(f.y - lo.y) / max(hi.y - lo.y, 1e-3)), 0.0, 1.0);
		float room_seed = fract(sin(dot(cell, vec2(19.19, 71.7)) + seed * 23.0) * 43758.5453);
		vec3 room = interior_room(g, rl, room_seed);
		// only where we're actually seeing into the room (rl.z>0) and inside the glass
		col = mix(col, room, inner * step(1e-3, rl.z));
	}

	col = mix(col, base * 1.15, clamp(door_rim, 0.0, 1.0));
	col = mix(col, vec3(0.13, 0.09, 0.06), door_mask);
	col = mix(col, rooft * tint * 2.4, roofness);

	ALBEDO = col;
	ROUGHNESS = mix(mix(0.92, 0.14, inner), 0.95, roofness);
	METALLIC = inner * 0.55 * (1.0 - roofness);

	float lit = step(mix(0.5, 0.74, fract(seed * 5.13)), hash21(cell + vec2(seed * 31.0, 0.0)));
	float night = smoothstep(0.45, 0.9, night_amount);
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float glow = max(lit, storefront * 0.55);
	vec3 glow_col = mix(vec3(1.0, 0.72, 0.35), vec3(0.78, 0.86, 1.0),
			step(0.85, fract(seed * 9.73)) * storefront);
	EMISSION = glow_col
			* (inner * glow * night * 1.6 * (0.2 + 0.8 * facing) * (1.0 - roofness));
}
