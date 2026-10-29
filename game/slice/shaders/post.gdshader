shader_type canvas_item;
// Lens finish: vignette, faint chromatic fringe toward the edges, film grain.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float vignette = 0.32;
uniform float fringe = 0.0006;
uniform float grain = 0.035;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - 0.5;
	float r2 = dot(d, d);
	vec3 col;
	col.r = texture(screen_tex, uv + d * fringe * r2 * 8.0).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - d * fringe * r2 * 8.0).b;
	col *= 1.0 - vignette * smoothstep(0.08, 0.6, r2 * 1.6);
	float g = hash(uv * 1000.0 + fract(TIME * 13.0)) - 0.5;
	col += g * grain * (1.0 - dot(col, vec3(0.33)));
	COLOR = vec4(col, 1.0);
}
