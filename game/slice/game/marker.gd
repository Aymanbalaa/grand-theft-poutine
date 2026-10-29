class_name SliceMarker
extends Node3D
# Objective marker: a soft column of light rising from a pulsing ground ring,
# tinted per objective (pickup amber, drop-off cyan). Readable through rain
# and fog without looking like a UI element pasted into the street.

var color := Color(1.0, 0.7, 0.25)
var _beam_mat: ShaderMaterial
var _ring_mat: ShaderMaterial
var _light: OmniLight3D

const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.7, 0.25, 1.0);
uniform float strength = 1.0;
varying float h;
void vertex() { h = VERTEX.y + 7.0; }   // mesh is centred: 0..14 m
void fragment() {
	float fade = (1.0 - smoothstep(0.0, 14.0, h)) * smoothstep(0.0, 0.3, h);
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 1.5);
	float flicker = 0.85 + 0.15 * sin(TIME * 3.0 + h * 0.8);
	ALBEDO = col.rgb * (0.35 + 1.4 * rim) * fade * flicker * strength * 2.0;
}
"""

const RING_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 col : source_color = vec4(1.0, 0.7, 0.25, 1.0);
uniform float strength = 1.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float pulse = fract(TIME * 0.6);
	float ring = smoothstep(0.08, 0.0, abs(r - 0.82)) + 0.8 * smoothstep(0.07, 0.0, abs(r - pulse)) * (1.0 - pulse);
	float fill = smoothstep(0.85, 0.3, r) * 0.12;
	ALBEDO = col.rgb * (ring + fill) * strength * 2.5;
}
"""

func _ready() -> void:
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.6
	cyl.bottom_radius = 0.6
	cyl.height = 14.0
	cyl.radial_segments = 20
	cyl.cap_top = false
	cyl.cap_bottom = false
	beam.mesh = cyl
	beam.position.y = 7.0
	_beam_mat = ShaderMaterial.new()
	var bs := Shader.new()
	bs.code = BEAM_SHADER
	_beam_mat.shader = bs
	beam.material_override = _beam_mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	var ring := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.2, 2.2)
	q.orientation = PlaneMesh.FACE_Y
	ring.mesh = q
	ring.position.y = 0.03
	_ring_mat = ShaderMaterial.new()
	var rs := Shader.new()
	rs.code = RING_SHADER
	_ring_mat.shader = rs
	ring.material_override = _ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	_light = OmniLight3D.new()
	_light.omni_range = 4.0
	_light.light_energy = 2.0
	_light.position.y = 1.0
	_light.light_volumetric_fog_energy = 2.0
	add_child(_light)
	set_color(color)

func set_color(c: Color) -> void:
	color = c
	if _beam_mat == null:
		return
	_beam_mat.set_shader_parameter("col", c)
	_ring_mat.set_shader_parameter("col", c)
	_light.light_color = c

# The beam fades out as the player arrives so it never blocks the doorway.
func set_proximity(dist: float) -> void:
	var k := clampf((dist - 2.0) / 10.0, 0.25, 1.0)
	_beam_mat.set_shader_parameter("strength", k)
