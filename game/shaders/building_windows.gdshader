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
	int cat = int(round(vcol.a * 255.0));
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
	float v = wpos.y;
	float cw = (cat == 1) ? 2.4 : 3.6;                   // commercial mullions are finer
	vec2 cell = vec2(floor(u / cw), floor(v / 3.2));
	vec2 f = vec2(fract(u / cw), fract(v / 3.2));
	float floor_idx = floor(v / 3.2);

	vec2 lo = (cat == 1) ? vec2(0.08, 0.12) : vec2(0.26, 0.32);
	vec2 hi = (cat == 1) ? vec2(0.92, 0.90) : vec2(0.74, 0.84);
	float storefront = (floor_idx == 0.0 && (cat == 0 || cat == 1 || cat == 5)) ? 1.0 : 0.0;
	lo = mix(lo, vec2(0.06, 0.05), storefront);
	hi = mix(hi, vec2(0.94, 0.72), storefront);

	float inwin = step(lo.x, f.x) * step(f.x, hi.x) * step(lo.y, f.y) * step(f.y, hi.y) * vertical;
	vec2 fb = vec2(0.045, 0.05);
	float inner = step(lo.x + fb.x, f.x) * step(f.x, hi.x - fb.x)
			* step(lo.y + fb.y, f.y) * step(f.y, hi.y - fb.y) * vertical;
	float frame = inwin - inner;
	float sill = step(lo.y - 0.06, f.y) * step(f.y, lo.y)
			* step(lo.x, f.x) * step(f.x, hi.x) * vertical * (1.0 - storefront);

	// inset illusion: glass darkens toward the top of the aperture (fake overhang)
	float glass_grad = mix(0.85, 0.35, smoothstep(lo.y, hi.y, f.y));
	vec3 glass = mix(vec3(0.30, 0.36, 0.42), vec3(0.15, 0.17, 0.19) + tint * 0.08, storefront)
			* glass_grad;

	vec3 col = base;
	col = mix(col, base * 0.5, frame);
	col = mix(col, glass, inner);
	col = mix(col, base * 1.3 + vec3(0.03), sill);
	col = mix(col, rooft * tint * 2.4, roofness);

	ALBEDO = col;
	ROUGHNESS = mix(mix(0.92, 0.18, inner), 0.95, roofness);
	METALLIC = inner * 0.2 * (1.0 - roofness);

	float lit = step(0.62, hash21(cell));
	float night = smoothstep(0.45, 0.9, night_amount);
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float glow = max(lit, storefront * 0.9);
	EMISSION = vec3(1.0, 0.72, 0.35)
			* (inner * glow * night * 1.6 * (0.2 + 0.8 * facing) * (1.0 - roofness));
}
