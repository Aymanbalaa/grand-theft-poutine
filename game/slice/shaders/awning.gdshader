shader_type spatial;
// Canvas awning: stripes across the width (UV.x * UV2.x metres), damp fabric.
render_mode cull_disabled, diffuse_burley;

uniform vec3 base_col : source_color = vec3(0.1, 0.25, 0.15);
uniform float stripe_w = 0.32;

void fragment() {
	float m = UV.x * UV2.x;
	float s = step(0.5, fract(m / (stripe_w * 2.0)));
	vec3 c = mix(base_col, vec3(0.86, 0.83, 0.76), s * 0.85);
	float weave = 0.92 + 0.08 * sin(m * 600.0) * sin(UV.y * UV2.y * 600.0);
	ALBEDO = c * weave * 0.75;
	ROUGHNESS = 0.7;
	BACKLIGHT = c * 0.25;
}
