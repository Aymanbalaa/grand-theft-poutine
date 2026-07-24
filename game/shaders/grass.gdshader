shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

global uniform float night_amount;
uniform float wind_amp = 0.06;

void vertex() {
	// sway the top of the card; VERTEX.y in [0..~0.6], base stays anchored
	float top = clamp(VERTEX.y / 0.6, 0.0, 1.0);
	float phase = NODE_POSITION_WORLD.x * 0.7 + NODE_POSITION_WORLD.z * 0.9 + TIME * 1.6;
	VERTEX.x += sin(phase) * wind_amp * top;
	VERTEX.z += cos(phase * 0.9) * wind_amp * 0.6 * top;
}

void fragment() {
	float top = clamp((UV.y < 0.5) ? 1.0 : 0.0, 0.0, 1.0); // UV.y small = top of card in QuadMesh
	// blade gradient: darker at root, brighter at tip
	vec3 root = vec3(0.11, 0.22, 0.09);
	vec3 tip  = vec3(0.22, 0.42, 0.16);
	vec3 col = mix(root, tip, top);
	col *= mix(0.35, 1.0, 1.0 - night_amount);  // dim at night like the rest of the scene
	ALBEDO = col;
	ROUGHNESS = 1.0;
	// alpha taper to hide the hard quad edges a little
	float edge = smoothstep(0.0, 0.12, UV.x) * (1.0 - smoothstep(0.88, 1.0, UV.x));
	ALPHA = edge;
}
